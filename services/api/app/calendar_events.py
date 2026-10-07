from datetime import date, timedelta
from fastapi import APIRouter, Depends, Header, Query
from sqlalchemy import select
from sqlalchemy.orm import Session
from .academics import owned_semester, replay, remember
from .auth import current_user, error
from .database import get_db
from .event_schemas import EventFields, EventEdit, EventCancel
from .event_store import CATEGORIES, tag_ids, event_rows, event_value, classification_value, classification_request
from .models import CalendarEvent, CalendarEventRevision, CalendarTag, StudyItem, TextCandidate, User
from .reminder_rules import utcnow, instant, notice_arrival_at, reservation_enabled
from .course_participation import course_requires_attendance, course_attendance_label

router = APIRouter()


def owned_event(db, user, eid):
    row = db.scalar(select(CalendarEvent).where(CalendarEvent.user_id == user.id, CalendarEvent.id == eid))
    if row is None: error(404, 'NOT_FOUND', '找不到这条日程')
    return row


def guard(s, expected_revision, row=None, version=None):
    if s.revision != expected_revision or (row is not None and row.version != version):
        error(409, 'SNAPSHOT_STALE', '安排已更新，请重新打开后核对')


def payload(db, user, s, body):
    if body.semester_id != s.id: error(404, 'NOT_FOUND', '日程不属于这个学期')
    if body.time.week and body.time.week > s.total_weeks:
        error(422, 'INVALID_TIME', '周次超出当前学期')
    data = body.model_dump(mode='json', exclude={'expected_revision', 'expected_version', 'change_reason', 'tags', 'semester_id'})
    data['tag_ids'] = tag_ids(db, user, body.tags)
    return data


def record(db, row, reason):
    result = event_value(db, row)
    db.add(CalendarEventRevision(user_id=row.user_id, event_id=row.id, version=row.version,
        snapshot=result, reason=reason, created_at=row.updated_at))
    return result


def receipt(db, user, s, row, reason):
    from .schedule_api import snapshot
    from .capacity import calendar_context
    from .plan_rules import classify
    source = snapshot(db, user, s)
    c = calendar_context(*source[:4], utcnow())
    _, issues = classify(source[4], source[3], c['free'].spans, c['begin'])
    return {'event': record(db, row, reason), 'semester_id': s.id, 'revision': s.revision,
            'affected_plan_ids': sorted({i['block_id'] for i in issues}), 'fixed_conflicts': c['conflicts']}


@router.get('/taxonomy')
def taxonomy(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return {'categories': CATEGORIES, 'tags': [{'id': t.id, 'name': t.name} for t in db.scalars(
        select(CalendarTag).where(CalendarTag.user_id == user.id, CalendarTag.merged_into.is_(None)).order_by(CalendarTag.name))]}


@router.post('/events', status_code=201)
def create_event(body: EventFields, user: User = Depends(current_user), db: Session = Depends(get_db),
                 idempotency_key: str | None = Header(default=None)):
    result = create_event_command(db, user, body, idempotency_key)
    db.commit()
    return result


def create_event_command(db, user, body, idempotency_key=None):
    s = owned_semester(db, user, body.semester_id, lock=True); data = body.model_dump(mode='json')
    cached = replay(db, user, 'event-create', idempotency_key, data)
    if cached is not None: return cached
    candidate = None
    if body.candidate_id:
        candidate = db.scalar(select(TextCandidate).where(TextCandidate.id == body.candidate_id,
            TextCandidate.user_id == user.id, TextCandidate.semester_id == s.id).with_for_update())
        if candidate is None or candidate.payload.get('intent') != 'create_event':
            error(404, 'NOT_FOUND', '找不到这条日程候选，请重新解析')
        if candidate.payload.get('applied_event_id'):
            error(409, 'CANDIDATE_APPLIED', '这条通知已经添加为日程，请返回查看')
        media_ref = candidate.payload.get('media_source')
        if media_ref:
            from .media import owned_source, version
            source = owned_source(db, user, media_ref['id'])
            db.refresh(source, with_for_update=True)
            version(source, media_ref['version'])
    guard(s, body.expected_revision)
    now = utcnow().isoformat()
    row = CalendarEvent(user_id=user.id, semester_id=s.id, payload=payload(db, user, s, body),
        version=1, lifecycle='active', created_at=now, updated_at=now)
    db.add(row); s.revision += 1; db.flush()
    if candidate is not None:
        row.payload = {**row.payload, 'source_text': candidate.source_text,
                       'source_id': candidate.payload.get('media_source', {}).get('id')}
        candidate.payload = {**candidate.payload, 'applied_event_id': row.id}
    response = receipt(db, user, s, row, '创建日程')
    remember(db, user, 'event-create', idempotency_key, data, response)
    return response


@router.get('/events/{eid}')
def get_event(eid: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = owned_event(db, user, eid)
    return event_value(db, row)


@router.get('/events/{eid}/history')
def history(eid: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    owned_event(db, user, eid)
    return {'entries': [{'version': r.version, 'event': r.snapshot, 'reason': r.reason, 'at': r.created_at}
        for r in db.scalars(select(CalendarEventRevision).where(CalendarEventRevision.user_id == user.id,
            CalendarEventRevision.event_id == eid).order_by(CalendarEventRevision.version))]}


@router.patch('/events/{eid}')
def edit_event(eid: str, body: EventEdit, user: User = Depends(current_user), db: Session = Depends(get_db),
               idempotency_key: str | None = Header(default=None)):
    result = edit_event_command(db, user, eid, body, idempotency_key)
    db.commit()
    return result


def edit_event_command(db, user, eid, body, idempotency_key=None):
    row = owned_event(db, user, eid); s = owned_semester(db, user, row.semester_id, lock=True); db.refresh(row)
    data = classification_request(body); operation = 'event-edit/' + eid
    cached = replay(db, user, operation, idempotency_key, data)
    if cached is not None: return cached
    guard(s, body.expected_revision, row, body.expected_version)
    if row.lifecycle != 'active': error(409, 'EVENT_CANCELLED', '日程已取消，不能继续修改')
    if body.candidate_id not in (None, row.payload.get('candidate_id')):
        error(422, 'SOURCE_IMMUTABLE', '不能更换日程的原始来源')
    updated = payload(db, user, s, body)
    for field, stored in (('category_id', 'category_id'), ('tags', 'tag_ids'), ('details', 'details')):
        if field not in body.model_fields_set and stored in row.payload:
            updated[stored] = row.payload[stored]
    if 'details' in body.model_fields_set:
        updated['details'] = {**row.payload.get('details', {}),
                              **body.details.model_dump(mode='json', exclude_unset=True)}
    if 'reserve_time' not in body.model_fields_set:
        status_changed = ('details' in body.model_fields_set
            and 'participation_status' in body.details.model_fields_set
            and body.details.participation_status != row.payload.get('details', {}).get('participation_status', 'unspecified'))
        updated['reserve_time'] = body.reserve_time if status_changed else row.payload.get('reserve_time', True)
    from .items import preserve_notice_time
    preserve_notice_time(row.payload['time'], body.time, updated['time'])
    updated['source_text'] = row.payload.get('source_text', '')
    if 'import_origin' in row.payload:
        updated['import_origin'] = row.payload['import_origin']
    if row.payload.get('candidate_id'):
        updated.update({k: row.payload.get(k) for k in ('candidate_id', 'source_id', 'source_text')})
    row.payload = updated; row.version += 1; row.updated_at = utcnow().isoformat(); s.revision += 1
    db.flush(); response = receipt(db, user, s, row, body.change_reason)
    remember(db, user, operation, idempotency_key, data, response)
    return response


@router.post('/events/{eid}/cancel')
def cancel_event(eid: str, body: EventCancel, user: User = Depends(current_user), db: Session = Depends(get_db),
                 idempotency_key: str | None = Header(default=None)):
    result = cancel_event_command(db, user, eid, body, idempotency_key)
    db.commit()
    return result


def cancel_event_command(db, user, eid, body, idempotency_key=None):
    row = owned_event(db, user, eid); s = owned_semester(db, user, row.semester_id, lock=True); db.refresh(row)
    data = body.model_dump(mode='json'); operation = 'event-cancel/' + eid
    cached = replay(db, user, operation, idempotency_key, data)
    if cached is not None: return cached
    guard(s, body.expected_revision, row, body.expected_version)
    if row.lifecycle != 'active': error(409, 'EVENT_CANCELLED', '日程已经取消')
    row.lifecycle = 'cancelled'; row.version += 1; row.updated_at = utcnow().isoformat(); s.revision += 1
    db.flush(); response = receipt(db, user, s, row, '取消日程')
    remember(db, user, operation, idempotency_key, data, response)
    return response


def restore_impact(db,user,s,row):
    from copy import deepcopy
    from .schedule_api import snapshot
    from .capacity import calendar_context
    from .plan_rules import classify
    from .conflict_changes import introduced_conflicts
    from .academics import fingerprint
    source=snapshot(db,user,s);now=utcnow()
    before=calendar_context(*source[:4],now)
    before_issues=classify(source[4],source[3],before['free'].spans,before['begin'])[1]
    restored=deepcopy(source[0])
    restored['fixed_events'].append({**row.payload,'id':row.id,'version':row.version})
    after=calendar_context(restored,*source[1:4],now)
    after_issues=classify(source[4],source[3],after['free'].spans,after['begin'])[1]
    old={fingerprint(issue) for issue in before_issues}
    affected={issue['block_id'] for issue in after_issues if fingerprint(issue) not in old}
    return {'fixed_conflicts':after['conflicts'],
        'new_fixed_conflicts':introduced_conflicts(before['conflicts'],after['conflicts']),
        'affected_plan_count':len(affected),'affected_blocks':[block for block in source[4] if block['id'] in affected]}


def restore_event_command(db,user,eid,body,*,confirm_fixed_conflicts=False):
    row=owned_event(db,user,eid);s=owned_semester(db,user,row.semester_id,lock=True);db.refresh(row)
    guard(s,body.expected_revision,row,body.expected_version)
    if row.lifecycle!='cancelled':error(409,'EVENT_ACTIVE','这条日程已经恢复，无需重复操作')
    impact=restore_impact(db,user,s,row)
    if impact['new_fixed_conflicts'] and not confirm_fixed_conflicts:
        error(422,'CONFIRM_FIXED_CONFLICTS','恢复后存在时间冲突，请核对后勾选确认')
    row.lifecycle='active';row.version+=1;row.updated_at=utcnow().isoformat();s.revision+=1
    db.flush()
    return {**receipt(db,user,s,row,'用户确认恢复日程'),'impact':impact}


@router.get('/semesters/{sid}/calendar')
def calendar(sid: str, from_date: date = Query(), to_date: date = Query(),
             user: User = Depends(current_user), db: Session = Depends(get_db)):
    from .schedule_api import snapshot
    from .occurrences import expand
    from .capacity import local_day, exam_window, calendar_context
    s = owned_semester(db, user, sid, lock=True)
    if to_date < from_date or (to_date - from_date).days > 366:
        error(422, 'INVALID_RANGE', '请核对查询日期，范围不能超过一年')
    begin = local_day(from_date.isoformat()).timestamp(); end = local_day((to_date + timedelta(days=1)).isoformat()).timestamp()
    source = snapshot(db, user, s); result = []; undated = []
    def add(entry, a, b):
        if a < end and b > begin: result.append(entry)
    for e in expand(source[0], source[2]):
        add({'id': e['id'], 'resource_id': e.get('course_id'), 'resource_type': 'course', 'title': e['title'],
             'start_at': e['start_at'], 'end_at': e['end_at'], 'location': e.get('location', ''),
             'category_id': 'study', 'tags': [], 'time_precision': 'exact',
             'attendance_exempt': bool(e.get('attendance_exempt')), 'fixed': course_requires_attendance(e),
             'attendance_status': e.get('attendance_status'), 'attendance_reason': e.get('attendance_reason', ''),
             'attendance_label': course_attendance_label(e)},
            instant(e['start_at']).timestamp(), instant(e['end_at']).timestamp())
    term_start = local_day(s.first_monday).timestamp(); term_end = term_start + s.total_weeks * 7 * 86400
    facts = [('event', event_value(db, r)) for r in event_rows(db, user, sid)]
    facts += [('exam' if r.payload['kind'] == 'exam' else 'deadline', {**r.payload, **classification_value(db, r), 'id': r.id, 'version': r.version})
              for r in db.scalars(select(StudyItem).where(StudyItem.user_id == user.id, StudyItem.semester_id == sid, StudyItem.lifecycle == 'active'))]
    for kind, e in facts:
        t = e['time']; exact = t['precision'] == 'exact'
        fixed_time = kind in ('event', 'exam') and t.get('meaning') not in ('window', 'candidate', 'course_anchor')
        reserved = reservation_enabled(e, kind)
        fixed = fixed_time and reserved
        deadline = kind == 'deadline' and t.get('meaning') not in ('window', 'candidate', 'course_anchor', 'start')
        arrival = notice_arrival_at(e) if fixed_time else None
        entry = {'id': kind + ':' + e['id'], 'resource_id': e['id'], 'resource_type': kind, 'title': e['title'],
                 'start_at': t.get('at') if exact and fixed_time else None, 'end_at': t.get('end_at') if exact and fixed_time else None,
                 'due_at': t.get('at') if exact and deadline else None, 'date': t.get('date'), 'week': t.get('week'),
                 'end_date': t.get('end_date'), 'time_precision': t['precision'], 'certainty': e['certainty'],
                 'location': e.get('location', ''), 'category_id': e.get('category_id'),
                 'tags': e.get('tags', []), 'fixed': fixed, 'version': e['version'],
                 'time': t, 'details': e.get('details', {}), 'reserve_time': reserved if kind in ('event','exam') else e.get('reserve_time', True)}
        entry['arrival_at'] = arrival.isoformat() if arrival else None
        entry['occupancy_start_at'] = (entry['arrival_at'] or entry['start_at']) if fixed else None
        if t['precision'] == 'unknown': undated.append(entry); continue
        a, b = exam_window(e, term_start, term_end)
        if arrival: a = arrival.timestamp()
        if exact and ((not fixed_time and t.get('meaning') != 'window') or not t.get('end_at')):
            b = instant(t['at']).timestamp() + .000001
        add(entry, a, b)
    item_labels = {r.id: classification_value(db, r) for r in db.scalars(select(StudyItem).where(
        StudyItem.user_id == user.id, StudyItem.semester_id == sid))}
    for p in source[4]:
        if p['status'] != 'active': continue
        add({'id': 'plan:' + p['id'], 'resource_id': p['item_id'], 'plan_id': p['id'], 'resource_type': 'plan',
             'title': p.get('title', '个人计划'), 'start_at': p['start_at'], 'end_at': p['end_at'], 'location': '',
             'fixed': False, **item_labels.get(p['item_id'], {'category_id': None, 'tags': []}), 'time_precision': 'exact'},
            instant(p['start_at']).timestamp(), instant(p['end_at']).timestamp())
    context = calendar_context(*source[:4], utcnow())
    def ordering(entry):
        timestamp = entry.get('start_at') or entry.get('due_at') or entry.get('time', {}).get('at')
        if timestamp:
            return instant(timestamp).timestamp(), entry['id']
        if entry.get('date'):
            return local_day(entry['date']).timestamp(), entry['id']
        return term_start + ((entry.get('week') or 1) - 1) * 7 * 86400, entry['id']
    result.sort(key=ordering)
    return {'semester_id': sid, 'revision': s.revision, 'from_date': from_date.isoformat(), 'to_date': to_date.isoformat(),
            'entries': result, 'undated': undated,
            'fixed_conflicts': [c for c in context['conflicts'] if instant(c['start_at']).timestamp() < end
                                and instant(c['end_at']).timestamp() > begin], 'categories': CATEGORIES}
