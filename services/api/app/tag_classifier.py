"""Small, deterministic campus vocabulary. No model, network, or DB mutation."""
import json
import re
import unicodedata
from collections import Counter
from functools import lru_cache
from pathlib import Path

RULES = json.loads((Path(__file__).parent / 'data/tag_rules.json').read_text(encoding='utf-8'))
GROUPS = RULES['groups']

def normalized(text):
    return ' '.join(unicodedata.normalize('NFKC', str(text or '')).casefold().split())

def positive(text):
    text = normalized(text)
    text = re.sub(r'(?:不是|并非)([^，。；;\n]{0,40}?)而是', '', text)
    return re.sub(r'(?:不是|并非|不涉及)[^，。；;\n]*', '', text)

@lru_cache(maxsize=256)
def pattern(term):
    term = normalized(term)
    # English words may touch Chinese text, but Java must not match JavaScript.
    left = r'(?<![a-z0-9])' if term[0].isascii() and term[0].isalnum() else ''
    right = r'(?![a-z0-9])' if term[-1].isascii() else ''
    return re.compile(left + re.escape(term) + right)

def matches(text, rule):
    return any(pattern(term).search(text) for term in [rule['name'], *rule['aliases'],
        *RULES['equivalents'].get(rule['name'], [])])

def canonical_name(name):
    value = normalized(name)
    for canonical, aliases in RULES['equivalents'].items():
        if value in {normalized(s) for s in [canonical, *aliases]}:
            return canonical
    for rule in RULES['rules']:
        if value == normalized(rule['name']):
            return rule['name']
    return value

def standard_name(name):
    canonical = canonical_name(name)
    if canonical in {r['name'] for r in RULES['rules']}:
        return canonical
    return ' '.join(unicodedata.normalize('NFKC', name).split())

def infer(title='', *, notes='', kind='', course_title='', source=''):
    primary = positive(title + ' ' + course_title)
    # Long/multi-item source text is not evidence that every topic belongs here.
    context = positive(notes + ' ' + (source if len(source) <= 500 else ''))
    found = [r for r in RULES['rules'] if matches(primary, r)]
    suppressed = {name for r in found for name in r.get('suppresses', [])}
    found = [r for r in found if r['name'] not in suppressed]
    found.sort(key=lambda r: (-r['priority'], r['name']))
    tags = list(dict.fromkeys(standard_name(r['name']) for r in found))[:3]
    if kind == 'exam' and '考试' not in tags:
        tags = [*tags[:2], '考试']
    if kind == 'assignment' and not {'作业', '实验作业', '课程设计', '毕业设计'}.intersection(tags):
        tags = [*tags[:2], '作业']
    category = None
    if kind in ('assignment', 'exam') or course_title:
        category = 'study'
    else:
        votes = Counter()
        for r in found:
            if r['category']:
                votes[r['category']] += r['priority']
        if votes:
            ranked = votes.most_common()
            if len(ranked) == 1 or ranked[0][1] > ranked[1][1]:
                category = ranked[0][0]
        # Context can disambiguate a general meeting; it cannot overturn a
        # specific title such as a choir rehearsal or Python assignment.
        contextual_meeting = (any(r['group'] == 'meetings' for r in found)
            and all(r['group'] == 'campus' or r['name'] in ('会议', '组会', '座谈会') for r in found))
        if category is None or contextual_meeting:
            hints = {cat: sum(h in primary for h in words) * 4 + sum(h in context for h in words)
                     for cat, words in RULES['category_hints'].items()}
            best = max(hints.values(), default=0)
            winners = [cat for cat, score in hints.items() if score == best and score]
            if len(winners) == 1:
                category = winners[0]
    return {'category_id': category, 'tags': tags}

def group_for(name, contexts=()):
    value = normalized(name)
    exact = next((r for r in RULES['rules']
                  if value in {normalized(s) for s in [r['name'], *r['aliases']]}), None)
    if exact:
        return exact['group']
    own = [r for r in RULES['rules'] if matches(value, r)]
    if own:
        own.sort(key=lambda r: (-r['priority'], -len(r['name']), r['name']))
        return own[0]['group']
    votes = Counter()
    for title in contexts:
        groups = {r['group'] for r in RULES['rules'] if matches(positive(title), r)}
        if len(groups) == 1:
            votes[next(iter(groups))] += 1
    ranked = votes.most_common()
    if ranked and (len(ranked) == 1 or ranked[0][1] >= 2 * ranked[1][1]):
        return ranked[0][0]
    return 'other'

def automatic_fields(fields, source='', *, course_title=''):
    """Ignore model-created labels; keep directly requested user labels instead."""
    result = dict(fields)
    labels = infer(result.get('title', ''), notes=result.get('notes', ''),
                   kind=result.get('kind', ''), course_title=course_title, source=source)
    requests = list(re.finditer(r'标签(?:设为|设成|改为|改成|用|为|是|叫|加上|添加|[：:])[：:\s“"\']*([^。；;\n]{1,80})', source))
    explicit = requests[-1] if requests else None
    if explicit:
        names = [s.strip(' 、,，“”"\'') for s in re.split(r'[、,，]', explicit.group(1))]
        labels['tags'] = list(dict.fromkeys(s for s in names if 0 < len(s) <= 24
            and not re.match(r'(?:分类|时间|地点|提醒|截止)(?:设|改|为|是)', s)))[:12]
    categories = list(re.finditer(r'分类(?:设为|设成|改为|改成|为|是|[：:])[：:\s]*(学业|科研|校园事务|生活)', source))
    if categories:
        labels['category_id'] = {'学业': 'study', '科研': 'research', '校园事务': 'affairs', '生活': 'life'}[categories[-1][1]]
    if re.search(r'(?:不需要|不用|不要|清空|移除所有|删除所有)标签', source):
        labels['tags'] = []
    return {**result, **labels}
