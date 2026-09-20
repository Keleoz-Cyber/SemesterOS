from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

SHANGHAI = ZoneInfo('Asia/Shanghai')


def utcnow():
    return datetime.now(timezone.utc)


def instant(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(timezone.utc)


def anchor_at(payload):
    time = payload['time']
    if time['precision'] == 'exact':
        return instant(time['at'])
    if time['precision'] == 'date' and time.get('day_end_confirmed') and payload['kind'] != 'exam':
        day = datetime.fromisoformat(time['date']).replace(tzinfo=SHANGHAI)
        return (day + timedelta(days=1)).astimezone(timezone.utc)
    return None


def evaluate(rule, item_payload, lifecycle, now=None):
    now = now or utcnow()
    anchor = anchor_at(item_payload)
    trigger = (anchor - timedelta(minutes=rule['lead_minutes']) if anchor else None) \
        if rule['mode'] == 'relative' else instant(rule['trigger_at'])
    if not rule['enabled'] or lifecycle != 'active':
        state = 'disabled'
    elif item_payload['kind'] == 'exam' and anchor is None and rule['purpose'] != 'check_notice':
        state = 'pending_anchor'
    elif trigger is None:
        state = 'pending_anchor'
    elif rule['mode'] == 'absolute' and rule['purpose'] != 'check_notice' and anchor and trigger > anchor:
        state = 'needs_review'
    elif trigger <= now:
        state = 'expired'
    else:
        state = 'scheduled'
    return {'trigger_at': trigger.isoformat() if trigger else None, 'schedule_state': state}
