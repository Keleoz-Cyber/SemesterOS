from fastapi import APIRouter, Depends, Header
from sqlalchemy import select
from sqlalchemy.orm import Session

from .academics import owned_semester, replay, remember
from .auth import current_user, error
from .database import get_db
from .item_schemas import ItemCreate, ItemEdit, LifecycleInput, ReminderCreate, ReminderEdit, ReminderInput
from .models import CourseMeeting, ItemRevision, ReminderRule, StudyItem, TextCandidate, User
from .reminder_rules import anchor_at, evaluate, utcnow
from .plan_store import preview_blocks,cancel_for_change

router = APIRouter()


def owned_item(db, user, item_id, lock=False):
    item = db.scalar(select(StudyItem).where(StudyItem.id == item_id, StudyItem.user_id == user.id))
    if not item:
        error(404, 'NOT_FOUND', '找不到这条事项')
    if lock:
        owned_semester(db, user, item.semester_id, lock=True)
        db.refresh(item)
    return item


def check_version(item, expected):
    if item.version != expected:
        error(409, 'SNAPSHOT_STALE', '事项已被修改，请重新打开后核对')


def rules_for(db, item):
    return list(db.scalars(select(ReminderRule).where(ReminderRule.item_id == item.id,
        ReminderRule.user_id == item.user_id).order_by(ReminderRule.created_at, ReminderRule.id)))


def serialize_rule(rule, item, peers=()):
    calculated = evaluate(rule.payload, item.payload, item.lifecycle)
    if calculated['schedule_state'] == 'scheduled':
        for peer in peers:
            other = evaluate(peer.payload, item.payload, item.lifecycle)
            if peer.id != rule.id and peer.payload['purpose'] == rule.payload['purpose'] and other == calculated:
                calculated = {**calculated, 'schedule_state': 'needs_review', 'review_reason': 'duplicate_trigger'}
                break
    return {**rule.payload, 'id': rule.id, 'item_id': item.id, 'version': rule.version,
            'item_version': item.version, 'title': item.payload['title'], 'semester_id': item.semester_id,
            **calculated}


def serialize_item(db, item):
    anchor = anchor_at(item.payload)
    rules = rules_for(db, item)
    return {**item.payload, 'id': item.id, 'semester_id': item.semester_id, 'version': item.version,
            'lifecycle': item.lifecycle, 'review_state': 'confirmed',
            'control': 'authoritative' if item.payload['kind'] == 'exam' else 'plannable',
            'anchor_at': anchor.isoformat() if anchor else None, 'created_at': item.created_at,
            'updated_at': item.updated_at, 'reminders': [serialize_rule(r, item, rules) for r in rules]}


def audit(db, item, reason):
    db.add(ItemRevision(user_id=item.user_id, item_id=item.id, version=item.version,
        snapshot=serialize_item(db, item), reason=reason, created_at=utcnow().isoformat()))


def checked_payload(db, user, body):
    s = owned_semester(db, user, body.semester_id, lock=True)
    if body.time.week and body.time.week > s.total_weeks:
        error(422, 'INVALID_WEEK', '周次超出当前学期，请核对')
    data = body.model_dump(mode='json', exclude={'reminders', 'expected_version', 'change_reason'})
    data['course_title'] = ''
    if body.course_id:
        course = db.scalar(select(CourseMeeting).where(CourseMeeting.id == body.course_id,
            CourseMeeting.user_id == user.id, CourseMeeting.semester_id == s.id))
        if not course:
            error(422, 'INVALID_COURSE', '关联课程不属于当前账号和学期')
        data['course_title'] = course.payload['title']
    return data, s


def validate_rule(db, item, payload, skip=None):
    calculated = evaluate(payload, item.payload, item.lifecycle)
    if payload['enabled']:
        messages = {'pending_anchor': '只有日期或周次时，请先确认具体时间，或改用指定时刻提醒',
                    'expired': '提醒时刻已过去，请选择未来时间或停用此提醒',
                    'needs_review': '该提醒晚于事项时间，请核对时刻或选择核实通知用途',
                    'disabled': '已完成或已取消的事项不能新增有效提醒'}
        if calculated['schedule_state'] in messages:
            error(422, 'INVALID_REMINDER', messages[calculated['schedule_state']])
        for old in rules_for(db, item):
            if old.id == skip or not old.payload['enabled']:
                continue
            when = evaluate(old.payload, item.payload, item.lifecycle)['trigger_at']
            if when == calculated['trigger_at'] and old.payload['purpose'] == payload['purpose']:
                error(422, 'DUPLICATE_REMINDER', '已有相同时刻和用途的提醒，请修改原提醒')


def add_rule(db, item, payload):
    validate_rule(db, item, payload)
    now = utcnow().isoformat()
    rule = ReminderRule(user_id=item.user_id, item_id=item.id, payload=payload, created_at=now, updated_at=now)
    db.add(rule)
    db.flush()
    return rule


@router.get('/semesters/{sid}/courses')
def course_choices(sid: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    owned_semester(db, user, sid)
    return [{'id': c.id, 'title': c.payload['title'], 'teacher': c.payload['teacher'],
             'weekday': c.payload['weekday']} for c in db.scalars(select(CourseMeeting).where(
        CourseMeeting.user_id == user.id, CourseMeeting.semester_id == sid).order_by(CourseMeeting.id))]


@router.get('/semesters/{sid}/items')
def list_items(sid: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    s = owned_semester(db, user, sid, lock=True)
    rows = db.scalars(select(StudyItem).where(StudyItem.user_id == user.id,
        StudyItem.semester_id == sid).order_by(StudyItem.created_at.desc(), StudyItem.id))
    return {'revision': s.revision, 'items': [serialize_item(db, i) for i in rows]}


@router.get('/items/{item_id}')
def get_item(item_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return serialize_item(db, owned_item(db, user, item_id))


@router.get('/items/{item_id}/history')
def history(item_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    item = owned_item(db, user, item_id)
    return [{'version': r.version, 'reason': r.reason, 'created_at': r.created_at, 'snapshot': r.snapshot}
            for r in db.scalars(select(ItemRevision).where(ItemRevision.user_id == user.id,
                ItemRevision.item_id == item.id).order_by(ItemRevision.created_at, ItemRevision.id))]


@router.post('/items', status_code=201)
def create_item(body: ItemCreate, user: User = Depends(current_user), db: Session = Depends(get_db),
                idempotency_key: str | None = Header(default=None)):
    data, s = checked_payload(db, user, body)
    request = body.model_dump(mode='json')
    cached = replay(db, user, 'create-item', idempotency_key, request)
    if cached is not None:
        return cached
    candidate = None
    if body.candidate_id:
        candidate = db.scalar(select(TextCandidate).where(TextCandidate.id == body.candidate_id,
            TextCandidate.user_id == user.id, TextCandidate.semester_id == s.id))
        if not candidate:
            error(404, 'NOT_FOUND', '找不到解析草稿')
        if candidate.payload['intent'] != 'create_item':
            error(422, 'INVALID_CANDIDATE', '这份解析不是新增事项草稿')
        if candidate.item_id:
            error(409, 'ALREADY_APPLIED', '这份草稿已经保存，请打开已有事项')
        data['source_text'] = candidate.source_text
        data['parse_evidence'] = candidate.payload
    now = utcnow().isoformat()
    item = StudyItem(user_id=user.id, semester_id=s.id, payload=data, created_at=now, updated_at=now)
    db.add(item)
    db.flush()
    for rule in body.reminders:
        add_rule(db, item, rule.model_dump(mode='json'))
    if candidate:
        candidate.item_id = item.id
    s.revision += 1
    audit(db, item, '用户确认录入')
    result = serialize_item(db, item)
    remember(db, user, 'create-item', idempotency_key, request, result)
    db.commit()
    return result


@router.patch('/items/{item_id}')
def edit_item(item_id: str, body: ItemEdit, user: User = Depends(current_user), db: Session = Depends(get_db),
              idempotency_key: str | None = Header(default=None)):
    item = owned_item(db, user, item_id, lock=True)
    if item.semester_id != body.semester_id or item.payload['kind'] != body.kind:
        error(422, 'IMMUTABLE_KIND', '不能通过编辑改变事项所属学期或类型')
    request = body.model_dump(mode='json')
    operation = 'edit-item/' + item_id
    cached = replay(db, user, operation, idempotency_key, request)
    if cached is not None:
        return cached
    check_version(item, body.expected_version)
    data, s = checked_payload(db, user, body)
    # Older clients do not know the new optional planning fields. Preserve those
    # unless this request explicitly changed them, rather than erasing user choices.
    if not {'start_policy', 'earliest_start_at'} & body.model_fields_set:
        for key in ('start_policy', 'earliest_start_at'):
            if key in item.payload:
                data[key] = item.payload[key]
    if 'reserve_time' not in body.model_fields_set and body.certainty != 'formal' and 'reserve_time' in item.payload:
        data['reserve_time'] = item.payload['reserve_time']
    if ('end_at' not in body.time.model_fields_set and body.kind == 'exam'
            and item.payload['time'].get('at') == data['time'].get('at')
            and item.payload['time']['precision'] == data['time']['precision'] == 'exact'):
        data['time']['end_at'] = item.payload['time'].get('end_at')
    coverage=sum(b['future_minutes'] for b in preview_blocks(db,item,utcnow()))
    if coverage and (data.get('remaining_minutes') is None or data['remaining_minutes']<coverage):
        error(409,'PLAN_CONFIRMATION_REQUIRED','已有未来计划超过新剩余工作量，请通过更新进度选择需取消的块')
    # Original source/candidate evidence is immutable; corrections have their own audit reason.
    for key in ('source_text', 'candidate_id', 'parse_evidence'):
        if key in item.payload:
            data[key] = item.payload[key]
    changed_anchor = item.payload['time'] != data['time']
    item.payload = data
    item.version += 1
    item.updated_at = utcnow().isoformat()
    if changed_anchor:
        for rule in rules_for(db, item):
            rule.version += 1
            rule.updated_at = item.updated_at
    s.revision += 1
    audit(db, item, body.change_reason)
    result = serialize_item(db, item)
    remember(db, user, operation, idempotency_key, request, result)
    db.commit()
    return result


@router.post('/items/{item_id}/lifecycle')
def set_lifecycle(item_id: str, body: LifecycleInput, user: User = Depends(current_user),
                  db: Session = Depends(get_db), idempotency_key: str | None = Header(default=None)):
    item = owned_item(db, user, item_id, lock=True)
    request = body.model_dump()
    operation = 'item-state/' + item_id
    cached = replay(db, user, operation, idempotency_key, request)
    if cached is not None:
        return cached
    check_version(item, body.expected_version)
    if body.lifecycle == 'completed' and item.payload['kind'] == 'exam':
        error(422, 'INVALID_LIFECYCLE', '考试不是可完成的个人任务')
    current=owned_semester(db,user,item.semester_id)
    future=preview_blocks(db,item,utcnow())
    if body.lifecycle!='active' and future:
        if body.expected_revision!=current.revision:error(409,'PLAN_CONFIRMATION_REQUIRED','请先预览并确认如何取消未来计划')
        cancel_for_change(db,user,item,utcnow(),body.cancel_plan_ids,body.confirm_locked_cancellation,all_required=True)
    item.lifecycle = body.lifecycle
    if body.lifecycle == 'active' and item.payload.get('remaining_minutes') == 0:
        item.payload = {**item.payload, 'remaining_minutes': None}
    item.version += 1
    item.updated_at = utcnow().isoformat()
    if body.lifecycle != 'active':
        for rule in rules_for(db, item):
            rule.payload = {**rule.payload, 'enabled': False}
            rule.version += 1
            rule.updated_at = item.updated_at
    s = owned_semester(db, user, item.semester_id)
    s.revision += 1
    audit(db, item, {'active': '用户恢复事项', 'completed': '用户确认完成', 'cancelled': '用户确认取消'}[body.lifecycle])
    result = serialize_item(db, item)
    remember(db, user, operation, idempotency_key, request, result)
    db.commit()
    return result


@router.post('/items/{item_id}/lifecycle/preview')
def preview_lifecycle(item_id:str,body:LifecycleInput,user:User=Depends(current_user),db:Session=Depends(get_db)):
    item=owned_item(db,user,item_id,lock=True);check_version(item,body.expected_version)
    s=owned_semester(db,user,item.semester_id)
    blocks=preview_blocks(db,item,utcnow()) if body.lifecycle!='active' else []
    return {'base_revision':s.revision,'affected_blocks':blocks,'affected_plan_count':len(blocks)}


@router.post('/items/{item_id}/reminders', status_code=201)
def create_reminder(item_id: str, body: ReminderCreate, user: User = Depends(current_user),
                    db: Session = Depends(get_db), idempotency_key: str | None = Header(default=None)):
    item = owned_item(db, user, item_id, lock=True)
    request = body.model_dump(mode='json')
    operation = 'add-reminder/' + item_id
    cached = replay(db, user, operation, idempotency_key, request)
    if cached is not None:
        return cached
    check_version(item, body.expected_item_version)
    if len(rules_for(db, item)) >= 20:
        error(422, 'LIMIT_REACHED', '每条事项最多20条提醒，请修改已有规则')
    rule = add_rule(db, item, body.model_dump(mode='json', exclude={'expected_item_version'}))
    audit(db, item, '用户增加提醒')
    result = serialize_rule(rule, item)
    remember(db, user, operation, idempotency_key, request, result)
    db.commit()
    return result


@router.patch('/reminders/{rule_id}')
def edit_reminder(rule_id: str, body: ReminderEdit, user: User = Depends(current_user),
                  db: Session = Depends(get_db), idempotency_key: str | None = Header(default=None)):
    rule = db.scalar(select(ReminderRule).where(ReminderRule.id == rule_id, ReminderRule.user_id == user.id))
    if not rule:
        error(404, 'NOT_FOUND', '找不到这条提醒')
    item = owned_item(db, user, rule.item_id, lock=True)
    db.refresh(rule)
    request = body.model_dump(mode='json')
    operation = 'edit-reminder/' + rule_id
    cached = replay(db, user, operation, idempotency_key, request)
    if cached is not None:
        return cached
    check_version(item, body.expected_item_version)
    if rule.version != body.expected_version:
        error(409, 'SNAPSHOT_STALE', '提醒已被修改，请重新核对')
    data = body.model_dump(mode='json', exclude={'expected_item_version', 'expected_version'})
    validate_rule(db, item, data, skip=rule.id)
    rule.payload = data
    rule.version += 1
    rule.updated_at = utcnow().isoformat()
    audit(db, item, '用户修改提醒')
    result = serialize_rule(rule, item)
    remember(db, user, operation, idempotency_key, request, result)
    db.commit()
    return result


@router.get('/reminders')
def list_reminders(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = list(db.execute(select(ReminderRule, StudyItem).join(StudyItem, ReminderRule.item_id == StudyItem.id).where(
        ReminderRule.user_id == user.id, StudyItem.user_id == user.id, StudyItem.lifecycle == 'active')))
    peers = {}
    for rule, item in rows:
        peers.setdefault(item.id, []).append(rule)
    return {'owner_id': user.id, 'synced_at': utcnow().isoformat(),
            'reminders': [serialize_rule(r, item, peers[item.id]) for r, item in rows if r.payload['enabled']]}
