from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

SHANGHAI = ZoneInfo('Asia/Shanghai')


def utcnow():
    return datetime.now(timezone.utc)


def instant(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(timezone.utc)


def anchor_at(payload):
    time = payload['time']
    if time.get('meaning') in ('window', 'candidate', 'course_anchor'):
        return None
    if time.get('meaning') == 'start' and payload.get('kind') != 'exam':
        return None
    if time['precision'] == 'exact':
        return instant(time['at'])
    if time['precision'] == 'date' and time.get('day_end_confirmed') and payload['kind'] != 'exam':
        day = datetime.fromisoformat(time['date']).replace(tzinfo=SHANGHAI)
        return (day + timedelta(days=1)).astimezone(timezone.utc)
    return None


def reminder_anchor_at(payload):
    """A known start is a reminder anchor, while only a deadline constrains work."""
    time = payload['time']
    if time.get('meaning') == 'start' and time['precision'] == 'exact' and time.get('at'):
        return instant(time['at'])
    return anchor_at(payload)


def notice_arrival_at(payload):
    """Only an explicitly supplied arrival lead defines this extra obligation."""
    lead = payload.get('details', {}).get('early_arrival_minutes')
    t = payload['time']
    if (lead is None or t['precision'] != 'exact' or not t.get('at')
            or t.get('meaning') in ('window', 'candidate', 'course_anchor')
            or payload.get('kind') in ('task', 'assignment')):
        return None
    return instant(t['at']) - timedelta(minutes=lead)


def reservation_enabled(payload, resource_type):
    """Use the same reservation choice for feeds, statistics and the solver."""
    return resource_type in ('exam', 'event') and payload.get('reserve_time', True)


def evaluate(rule, item_payload, lifecycle, now=None):
    now = now or utcnow()
    anchor = reminder_anchor_at(item_payload)
    trigger = (anchor - timedelta(minutes=rule['lead_minutes']) if anchor else None) \
        if rule['mode'] == 'relative' else instant(rule['trigger_at'])
    if not rule['enabled'] or lifecycle != 'active':
        state = 'disabled'
    elif trigger is None:
        state = 'pending_anchor'
    elif rule['mode'] == 'absolute' and rule['purpose'] != 'check_notice' and anchor and trigger > anchor:
        state = 'needs_review'
    elif trigger <= now:
        state = 'expired'
    else:
        state = 'scheduled'
    return {'trigger_at': trigger.isoformat() if trigger else None, 'schedule_state': state}
