"""Fixed event persistence helpers, shared by every scheduling entry point."""
from datetime import timedelta
from sqlalchemy import select
from .models import CalendarEvent, CalendarTag, User
from .reminder_rules import utcnow, instant

CATEGORIES = [{'id': key, 'name': name} for key, name in (
    ('study', '学业'), ('research', '科研'), ('affairs', '校园事务'), ('life', '生活'))]


def event_rows(db, user, sid=None, active=True):
    q = select(CalendarEvent).where(CalendarEvent.user_id == user.id)
    if sid is not None: q = q.where(CalendarEvent.semester_id == sid)
    if active: q = q.where(CalendarEvent.lifecycle == 'active')
    return list(db.scalars(q.order_by(CalendarEvent.created_at, CalendarEvent.id)))


def calendar_snapshot(db, user, s):
    return {'first_monday': s.first_monday, 'total_weeks': s.total_weeks, 'periods': s.periods,
            'fixed_events': [{**r.payload, 'id': r.id, 'version': r.version} for r in event_rows(db, user, s.id)]}


def tag_ids(db, user, names):
    # Shared owner lock serializes label creation across distinct semesters.
    db.scalar(select(User).where(User.id == user.id).with_for_update())
    ids = []
    for name in names:
        row = db.scalar(select(CalendarTag).where(CalendarTag.user_id == user.id, CalendarTag.normalized == name.casefold()))
        if row is None:
            row = CalendarTag(user_id=user.id, name=name, normalized=name.casefold()); db.add(row); db.flush()
        ids.append(row.id)
    return ids


def reminder_values(row):
    anchor = instant(row.payload['time']['at']) if row.payload['time']['precision'] == 'exact' else None
    result = []
    for lead in row.payload.get('reminder_minutes', []):
        trigger = anchor - timedelta(minutes=lead) if anchor else None
        status = ('disabled' if row.lifecycle != 'active' else 'pending_anchor' if trigger is None
                  else 'expired' if trigger <= utcnow() else 'scheduled')
        result.append({'id': f'{row.id}:before:{lead}', 'item_id': 'event:' + row.id, 'resource_type': 'event',
                       'resource_id': row.id, 'version': row.version, 'item_version': row.version,
                       'title': row.payload['title'], 'semester_id': row.semester_id, 'purpose': 'item',
                       'mode': 'relative', 'lead_minutes': lead, 'enabled': row.lifecycle == 'active',
                       'trigger_at': trigger.isoformat() if trigger else None, 'schedule_state': status})
    return result


def event_value(db, row):
    ids = row.payload.get('tag_ids', [])
    by_id = {t.id: {'id': t.id, 'name': t.name} for t in db.scalars(select(CalendarTag).where(
        CalendarTag.user_id == row.user_id, CalendarTag.id.in_(ids)))} if ids else {}
    return {**{k: v for k, v in row.payload.items() if k != 'tag_ids'}, 'id': row.id,
            'semester_id': row.semester_id, 'version': row.version, 'lifecycle': row.lifecycle,
            'control': 'fixed', 'tags': [by_id[i] for i in ids if i in by_id],
            'reminders': reminder_values(row), 'created_at': row.created_at, 'updated_at': row.updated_at}
