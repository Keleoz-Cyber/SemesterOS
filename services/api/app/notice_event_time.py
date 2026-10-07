"""Keep an explicit arrival/start pair from becoming a fabricated event end."""
from copy import deepcopy
import re
from .reminder_rules import instant, SHANGHAI

PAIR = re.compile(r'(?=(\d{1,2}[:：]\d{2})[^。\n]{0,120}?(?:候场|到场|集合)[^。\n]{0,100}?(\d{1,2}[:：]\d{2})\s*(?:正式)?(?:开始|开场))')


def normalize_notice_event_time(fields, source):
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
