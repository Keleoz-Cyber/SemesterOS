"""Resolve bell-period references from the semester, never from today's classes."""
from copy import deepcopy
import re

from .auth import error
from .reminder_rules import SHANGHAI, instant

NUMBER = r'[0-9一二两三四五六七八九十]+'
RELATIVE = re.compile(rf'(上午|早上|下午|晚上|晚间)\s*(?:的)?\s*第\s*({NUMBER})\s*(大节|小节|节课|节)')
LESSON = re.compile(rf'第\s*({NUMBER})\s*(?:大节(?:课)?|节课|堂课)')
ABSOLUTE = re.compile(rf'第?\s*({NUMBER})\s*(?:到|至|—|-|、|和)\s*第?\s*({NUMBER})\s*节|第\s*({NUMBER})\s*节')
CLOCK = re.compile(r'\d{1,2}[:：]\d{2}|[0-9一二两三四五六七八九十]+\s*点')


def number(text):
    if text.isdigit():
        return int(text) if len(text) <= 4 else None
    digits = {'一': 1, '二': 2, '两': 2, '三': 3, '四': 4, '五': 5,
              '六': 6, '七': 7, '八': 8, '九': 9}
    if '十' in text:
        before, after = text.split('十', 1)
        return digits.get(before, 1) * 10 + digits.get(after, 0)
    return digits.get(text)


def minutes(clock):
    hour, minute = map(int, clock.split(':'))
    return hour * 60 + minute


def timetable(periods):
    rows = sorted((dict(p) for p in periods), key=lambda p: minutes(p['start']))
    sessions = {'上午': [], '下午': [], '晚上': []}
    for row in rows:
        start = minutes(row['start'])
        sessions['上午' if start < 12 * 60 else '下午' if start < 18 * 60 + 30 else '晚上'].append(row)
    return rows, sessions


def class_blocks(periods):
    """Short breaks suggest joined periods; this is evidence, not a saved setting."""
    blocks = []
    for row in periods:
        if (blocks and row['number'] == blocks[-1][-1]['number'] + 1
                and 0 <= minutes(row['start']) - minutes(blocks[-1][-1]['end']) <= 10):
            blocks[-1].append(row)
        else:
            blocks.append([row])
    return blocks


def candidate(rows, interpretation):
    return {'interpretation': interpretation, 'period_numbers': [p['number'] for p in rows],
            'start': rows[0]['start'], 'last_period_end': rows[-1]['end']}


def resolve_period_reference(periods, expression):
    rows, sessions = timetable(periods)
    relatives = list(RELATIVE.finditer(expression))
    # An explicit correction ("下午第二节不是7到8节吗") outranks the relative phrase.
    rest = RELATIVE.sub('', expression)
    lessons = list(LESSON.finditer(rest))
    rest = LESSON.sub('', rest)
    absolute = [m for m in ABSOLUTE.finditer(rest)
        if not re.search(r'(?:不是|并非|不要|别用|不按)\s*$', rest[:m.start()])
        or re.match(r'[吗么？?]', rest[m.end():])]
    result = {'expression': expression, 'periods': rows,
              'basis': '当前学期保存的每日节次；与当天是否有课无关',
              'usage': '日常“第几节课”或“下午第几节”按连上的整节课计数；明确7到8节等编号按课表编号查询，不追问大小节。',
              'end_time_rule': '节次末尾不是会议结束时间；未说明会议结束就留空'}
    if absolute:
        match = absolute[-1]
        begin = number(match[1] or match[3]); end = number(match[2] or match[3])
        maximum = max((p['number'] for p in rows), default=0)
        wanted = list(range(begin, end + 1)) if begin is not None and end is not None and 1 <= begin <= end <= maximum else []
        selected = [p for p in rows if p['number'] in wanted]
        if wanted and sorted(p['number'] for p in selected) == wanted:
            return {**result, 'status': 'resolved', **candidate(selected, '明确的全日节次编号')}
        return {**result, 'status': 'unavailable', 'message': '当前节次表没有这些完整编号，请核对编号或直接给开始时间。'}
    if lessons:
        ordinal = number(lessons[-1][1])
        blocks = [block for session in sessions.values() for block in class_blocks(session)]
        if ordinal and ordinal <= len(blocks):
            return {**result, 'status': 'resolved', **candidate(blocks[ordinal - 1], f'当天第{ordinal}节课')}
        return {**result, 'status': 'unavailable', 'message': '当前节次表中没有这节课对应的时段，请提供开始时间。'}
    if not relatives:
        return {**result, 'status': 'unavailable', 'message': '请提供节次原话，如第7节或下午第二节课。'}
    match = relatives[-1]
    session = {'早上': '上午', '晚间': '晚上'}.get(match[1], match[1])
    ordinal = number(match[2]); unit = match[3]
    selected = sessions[session]
    # Students count lessons, not individual bell periods. Only explicit
    # "小节" overrides that everyday meaning; never ask about the distinction.
    if unit == '小节' and ordinal and ordinal <= len(selected):
        return {**result, 'status': 'resolved', **candidate([selected[ordinal - 1]], f'{session}第{ordinal}小节')}
    blocks = class_blocks(selected)
    if ordinal and ordinal <= len(blocks) and unit != '小节':
        return {**result, 'status': 'resolved', **candidate(blocks[ordinal - 1], f'{session}第{ordinal}节课')}
    return {**result, 'status': 'unavailable', 'message': '当前节次表不足以确定这个时刻，请核对编号或直接给开始时间。'}


def reference_evidence(text, source):
    if RELATIVE.search(text) or ABSOLUTE.search(text) or CLOCK.search(text):
        return text
    unit = re.search(r'(?:按|指|是|算|用|说的)\s*(?:第?[一二两三四五六七八九十0-9]+)?(大节|小节)', text)
    if unit and RELATIVE.search(source):
        return RELATIVE.sub(lambda m: m[1]+'第'+m[2]+unit[1], source)
    return source


def guard_event_class_time(fields, periods, text):
    """Reject unsupported precise times, while allowing an unresolved date draft."""
    time = fields.get('time') or {}
    if time.get('precision') != 'exact' or not time.get('at'):
        return fields
    expression = time.get('expression') or ''
    # Explicit clock corrections do not need a second period interpretation.
    if CLOCK.search(text):
        return fields
    evidence = text if RELATIVE.search(text) or ABSOLUTE.search(text) else ''
    if not evidence:
        return fields
    resolution = resolve_period_reference(periods, evidence)
    if resolution['status'] != 'resolved':
        error(422, 'CLASS_TIME_UNAVAILABLE', resolution['message'] +
              ' 可调用resolve_class_time查看真实节次；也可以先保留日期和时间原话，不编造时刻。')
    at = instant(time['at']).astimezone(SHANGHAI)
    if at.strftime('%H:%M') != resolution['start']:
        error(422, 'CLASS_TIME_MISMATCH',
              f"当前节次表中第{'、'.join(map(str, resolution['period_numbers']))}节从{resolution['start']}开始，请修正预览时间。")
    result = deepcopy(fields)
    # A class is a start reference here, not evidence of meeting duration.
    unknown_end = re.search(r'(?:结束|散会)(?:时间|时刻)?[，,:：\s]*(?:还|暂|先)?(?:没|未|不|待)|其他.{0,4}不确定', text)
    if time.get('end_at') and (unknown_end or not re.search(r'占用|持续|整[节段]|从.{0,20}(?:到|至)|下课(?:结束|为止)|结束', text)):
        result['time']['end_at'] = None
    if not expression:
        result['time']['expression'] = evidence[:200]
    return result
