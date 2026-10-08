"""Fixed event persistence helpers, shared by every scheduling entry point."""
from datetime import timedelta
from sqlalchemy import select
from .models import CalendarEvent, CalendarTag, CalendarTagAlias, User
from .reminder_rules import utcnow

CATEGORIES = [{'id': key, 'name': name} for key, name in (
    ('study', '学业'), ('research', '科研'), ('affairs', '校园事务'), ('life', '生活'))]


def without_default_confirmation_fields(data, *, optional_revision=False):
    """Keep pre-conflict request hashes stable without dropping real choices."""
    result = dict(data)
    if result.get('confirm_fixed_conflicts') is False:
        result.pop('confirm_fixed_conflicts', None)
    if result.get('course_leave_targets') == []:
        result.pop('course_leave_targets', None)
    if optional_revision and result.get('expected_revision') is None:
        result.pop('expected_revision', None)
    return result


def classification_request(body):
    # Edit omissions preserve stored choices; explicitly supplied empty values
    # can clear them. The idempotency signature must retain that distinction.
    editing = 'expected_version' in type(body).model_fields
    sensitive = {'category_id', 'tags'} | ({'reserve_time', 'details'} if editing else set())
    data = body.model_dump(mode='json', exclude=sensitive - body.model_fields_set)
    if editing:
        if 'details' in data:
            data['details'] = body.details.model_dump(mode='json', exclude_unset=True)
        for key in ('expression', 'meaning', 'candidate_dates', 'course_anchor', 'end_at'):
            if key not in body.time.model_fields_set:
                data['time'].pop(key, None)
    from .item_schemas import ItemFields
    return without_default_confirmation_fields(data, optional_revision=isinstance(body, ItemFields))


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
        row = tag_by_name(db, user.id, name)
        if row is None:
            row = CalendarTag(user_id=user.id, name=name, normalized=name.casefold()); db.add(row); db.flush()
        if row.id not in ids:
            ids.append(row.id)
    return ids


def canonical_tag(db, user_id, tag_id):
    seen = set()
    while tag_id and tag_id not in seen:
        seen.add(tag_id)
        row = db.scalar(select(CalendarTag).where(CalendarTag.user_id == user_id, CalendarTag.id == tag_id))
        if row is None or row.merged_into is None:
            return row
        tag_id = row.merged_into
    return None


def tag_by_name(db, user_id, name):
    row = db.scalar(select(CalendarTag).where(CalendarTag.user_id == user_id,
        CalendarTag.normalized == name.casefold(), CalendarTag.merged_into.is_(None)))
    if row is not None:
        return row
    alias = db.get(CalendarTagAlias, (user_id, name.casefold()))
    return canonical_tag(db, user_id, alias.tag_id) if alias else None


def canonical_tag_ids(db, user_id, ids):
    result = []
    for tag_id in ids:
        tag = canonical_tag(db, user_id, tag_id)
        if tag is not None and tag.id not in result:
            result.append(tag.id)
    return result


def reminder_values(row):
    from .reminder_rules import anchor_at
    anchor = anchor_at({**row.payload, 'kind': 'exam'})
    result = []
    for lead in row.payload.get('reminder_minutes', []):
        trigger = anchor - timedelta(minutes=lead) if anchor else None
        status = ('disabled' if row.lifecycle != 'active' else 'pending_anchor' if trigger is None
                  else 'expired' if trigger <= utcnow() else 'scheduled')
        result.append({'id': f'{row.id}:before:{lead}', 'item_id': 'event:' + row.id, 'resource_type': 'event',
                       'resource_id': row.id, 'version': row.version, 'item_version': row.version,
                       'start_at': row.payload.get('time', {}).get('at'),
                       'place': row.payload.get('location', row.payload.get('place', '')), 'can_complete': False,
                       'time_meaning': row.payload.get('time', {}).get('meaning'),
                       'title': row.payload['title'], 'semester_id': row.semester_id, 'purpose': 'item',
                       'mode': 'relative', 'lead_minutes': lead, 'enabled': row.lifecycle == 'active',
                       'trigger_at': trigger.isoformat() if trigger else None, 'schedule_state': status})
    return result


def classification_value(db, row):
    ids = canonical_tag_ids(db, row.user_id, row.payload.get('tag_ids', []))
    by_id = {t.id: {'id': t.id, 'name': t.name} for t in db.scalars(select(CalendarTag).where(
        CalendarTag.user_id == row.user_id, CalendarTag.id.in_(ids)))} if ids else {}
    default = 'study' if row.payload.get('kind') in ('assignment', 'exam') else None
    return {'category_id': row.payload.get('category_id', default),
            'tags': [by_id[i] for i in ids if i in by_id]}


def event_value(db, row):
    from .reminder_rules import notice_arrival_at
    arrival = notice_arrival_at(row.payload)
    return {**{k: v for k, v in row.payload.items() if k != 'tag_ids'}, 'id': row.id,
            'semester_id': row.semester_id, 'version': row.version, 'lifecycle': row.lifecycle,
            'control': 'fixed', **classification_value(db, row),
            'reserve_time': row.payload.get('reserve_time', True),
            'reminders': reminder_values(row), 'created_at': row.created_at, 'updated_at': row.updated_at,
            'arrival_at': arrival.isoformat() if arrival else None}
