"""Keep an explicit arrival/start pair from becoming a fabricated event end."""
from copy import deepcopy
import re
from .reminder_rules import instant, SHANGHAI

PAIR = re.compile(r'(?=(\d{1,2}[:：]\d{2})[^。\n]{0,120}?(?:候场|到场|集合)[^。\n]{0,100}?(\d{1,2}[:：]\d{2})\s*(?:正式)?(?:开始|开场))')
FULL_DAY = re.compile(r'全天(?!候)|一整天|整天')
NEGATED_DAY = re.compile(r'(?:不是|并非|非|不用|不需要|无需|不必|不要|不会|不想|不能|没(?:有)?|未)(?:持续|参加|占用|都|要|是|用|需要|一)?\s*$')


def declared_full_day(text):
    # Evaluate each clause so "不用上课，全天外出" keeps the positive
    # declaration, while "不是全天，只有半天" never reserves a whole date.
    for clause in re.split(r'[，,。；;\n]', text or ''):
        if re.search(r'只(?:有|需|要|参加|占用)?(?:.{0,2})半天|仅(?:.{0,2})半天', clause):
            continue
        for match in FULL_DAY.finditer(clause):
            if not NEGATED_DAY.search(clause[:match.start()]):
                return True
    return False


def normalize_explicit_all_day(fields, source):
    time = fields.get('time') or {}
    expression = time.get('expression') or ''
    if (time.get('precision') not in ('date', 'range') or not time.get('date')
            or time.get('meaning') in ('window', 'candidate', 'course_anchor')):
        return fields
    if not declared_full_day(expression) or not declared_full_day(source):
        if time.get('meaning') != 'all_day':
            return fields
        # Model-supplied meaning cannot override a user's negation.
        result = deepcopy(fields)
        result['time'] = {**time, 'meaning': 'unspecified'}
        return result
    # A stated whole date has date-level occupancy, never an invented clock.
    result = deepcopy(fields)
    result['time'] = {**time, 'meaning': 'all_day'}
    return result


def normalize_notice_event_time(fields, source):
    fields = normalize_explicit_all_day(fields, source)
    time = fields.get('time') or {}
    if time.get('precision') != 'exact' or not time.get('at') or not time.get('end_at'):
        return fields
    title = fields.get('title', '')
    if '候场' in title and not any(word in title for word in ('彩排', '排练', '联排', '演出', '活动')):
        return fields  # A separately requested waiting interval is a real interval.
    begin, end = instant(time['at']).astimezone(SHANGHAI), instant(time['end_at']).astimezone(SHANGHAI)
    if begin.date() != end.date():
        return fields
    for arrival, start in PAIR.findall(source):
        def clock(value):
            hour, minute = value.replace('：', ':').split(':')
            return f'{int(hour):02}:{minute}'
        arrival, start = clock(arrival), clock(start)
        if arrival != begin.strftime('%H:%M') or start != end.strftime('%H:%M'):
            continue
        minutes = int((end - begin).total_seconds() // 60)
        if not 0 < minutes <= 240:
            continue
        result = deepcopy(fields)
        result['time'] = {**time, 'at': time['end_at'], 'end_at': None,
                          'expression': f'{arrival}到场，{start}开始；结束时间未说明'}
        result['details'] = {**result.get('details', {}), 'early_arrival_minutes': minutes}
        return result
    return fields
