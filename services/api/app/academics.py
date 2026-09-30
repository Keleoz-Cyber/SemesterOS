from datetime import date, datetime, time, timedelta
from hashlib import sha256
import json
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Header, Query
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .auth import current_user, error
from .database import get_db
from .models import CourseMeeting, IdempotencyRecord, ImportBatch, RealityChange, Semester, StudyItem, User
from .schemas import ApplyInput, ImportInput, SemesterInput

router = APIRouter()


def fingerprint(value):
    return sha256(json.dumps(value, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def identity(course):
    return fingerprint([course.get("source_id") or course["title"], course["weekday"], course["weeks"], course["sections"]])


def owned_semester(db, user, sid, lock=False):
    query = select(Semester).where(Semester.id == sid, Semester.user_id == user.id)
    item = db.scalar(query.with_for_update() if lock else query)
    if item is None:
        error(404, "NOT_FOUND", "找不到这个学期")
    return item


def serialize_semester(s):
    return {"id": s.id, "name": s.name, "first_monday": s.first_monday, "total_weeks": s.total_weeks,
            "periods": s.periods, "revision": s.revision}


def replay(db, user, operation, key, body):
    if not key:
        return None
    if len(key) > 120:
        error(422, "INVALID_KEY", "请求标识过长")
    record = db.scalar(select(IdempotencyRecord).where(IdempotencyRecord.user_id == user.id,
                         IdempotencyRecord.operation == operation, IdempotencyRecord.key == key))
    if record and record.request_hash != fingerprint(body):
        error(409, "IDEMPOTENCY_CONFLICT", "该请求标识已用于其他内容")
    return record.response if record else None


def remember(db, user, operation, key, body, response):
    if key:
        db.add(IdempotencyRecord(user_id=user.id, operation=operation, key=key,
                                request_hash=fingerprint(body), response=response))


@router.get("/semesters")
def semesters(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return [serialize_semester(s) for s in db.scalars(select(Semester).where(Semester.user_id == user.id).order_by(Semester.first_monday.desc(), Semester.id))]


@router.post("/semesters", status_code=201)
def create_semester(body: SemesterInput, user: User = Depends(current_user), db: Session = Depends(get_db),
                    idempotency_key: str | None = Header(default=None)):
    db.scalar(select(User).where(User.id == user.id).with_for_update())
    data = body.model_dump(mode="json")
    cached = replay(db, user, "create-semester", idempotency_key, data)
    if cached is not None:
        return cached
    item = Semester(user_id=user.id, **data)
    db.add(item)
    db.flush()
    response = serialize_semester(item)
    remember(db, user, "create-semester", idempotency_key, data, response)
    db.commit()
    return response


def classify_import(db, batch):
    existing = list(db.scalars(select(CourseMeeting).where(
        CourseMeeting.user_id == batch.user_id, CourseMeeting.semester_id == batch.semester_id)))
    by_key = {row.identity_key: row for row in existing}
    reserved_exact = {by_key[identity(course)].id for course in batch.courses
                      if identity(course) in by_key}
    used = set()
    changes, new_count, unchanged = [], 0, 0
    for course in batch.courses:
        key = identity(course)
        exact = by_key.get(key)
        if exact is not None:
            used.add(exact.id)
            if exact.payload == course:
                unchanged += 1
            else:
                changes.append({'course_id': exact.id, 'before': exact.payload, 'after': course})
            continue
        if batch.source == 'manual':
            new_count += 1
            continue
        matches = [row for row in existing if row.id not in used and row.id not in reserved_exact and (
            row.payload.get('source_id') and course.get('source_id') and
            row.payload['source_id'] == course['source_id'] or
            (not row.payload.get('source_id') or not course.get('source_id')) and
            row.payload['title'] == course['title'])]
        if len(matches) > 1:
            error(422, 'AMBIGUOUS_COURSE',
                  f"“{course['title']}”对应多条已有课程，暂不能自动替换，请先核对旧课表")
        if matches:
            old = matches[0]
            used.add(old.id)
            changes.append({'course_id': old.id, 'before': old.payload, 'after': course})
        else:
            new_count += 1
    missing_school = []
    if batch.source == 'haut_webview' and batch.source_term:
        source_batches = {row.id: row for row in db.scalars(select(ImportBatch).where(
            ImportBatch.user_id == batch.user_id,
            ImportBatch.semester_id == batch.semester_id))}
        missing_school = [
            {'course_id': row.id, 'before': row.payload}
            for row in existing
            if row.id not in used and not row.manually_edited and
            row.source_batch_id in source_batches and
            source_batches[row.source_batch_id].source == 'haut_webview' and
            source_batches[row.source_batch_id].source_term == batch.source_term
        ]
    return changes, new_count, unchanged, missing_school


def summarize(db, batch):
    changes, new_count, unchanged, missing_school = classify_import(db, batch)
    return {"id": batch.id, "semester_id": batch.semester_id, "base_revision": batch.base_revision,
            "source": batch.source, "source_term": batch.source_term, "courses": batch.courses, "new_count": new_count,
            "unchanged_count": unchanged, "changed_count": len(changes), "changed_courses": changes,
            "missing_count": len(missing_school), "missing_courses": missing_school,
            "applied": batch.receipt is not None}


@router.post("/imports", status_code=201)
def preview_import(body: ImportInput, user: User = Depends(current_user), db: Session = Depends(get_db),
                   idempotency_key: str | None = Header(default=None)):
    s = owned_semester(db, user, body.semester_id, lock=True)
    request = body.model_dump(mode="json")
    cached = replay(db, user, "preview-import", idempotency_key, request)
    if cached is not None:
        return cached
    known = {p["number"] for p in s.periods}
    courses = {}
    for c in body.courses:
        maximum = max(c.weeks)
        if maximum > s.total_weeks:
            error(422, "CALENDAR_MISMATCH",
                  f"教务课表包含第{maximum}周，当前学期只设了{s.total_weeks}周。请修改学期周数后重试")
        missing = set(c.sections) - known
        if missing:
            section = min(missing)
            error(422, "CALENDAR_MISMATCH",
                  f"教务课表使用第{section}节，当前学期没有这节的时间。请补充节次后重试")
        data = c.model_dump()
        key = identity(data)
        if key in courses and courses[key] != data:
            error(422, "AMBIGUOUS_COURSE", "同一课次有不同信息，请先核对")
        courses[key] = data
    batch = ImportBatch(user_id=user.id, semester_id=s.id, source=body.source, source_term=body.source_term,
                        courses=list(courses.values()), base_revision=s.revision)
    db.add(batch)
    db.flush()
    response = summarize(db, batch)
    remember(db, user, "preview-import", idempotency_key, request, response)
    db.commit()
    return response


@router.post("/imports/{batch_id}/apply")
def apply_import(batch_id: str, body: ApplyInput, user: User = Depends(current_user),
                 db: Session = Depends(get_db), idempotency_key: str | None = Header(default=None)):
    batch = db.scalar(select(ImportBatch).where(ImportBatch.id == batch_id, ImportBatch.user_id == user.id))
    if batch is None:
        error(404, "NOT_FOUND", "找不到这个导入预览")
    s = owned_semester(db, user, batch.semester_id, lock=True)
    db.refresh(batch)
    request = body.model_dump()
    operation = f"apply-import:{batch.id}"
    cached = replay(db, user, operation, idempotency_key, request)
    if cached is not None:
        return cached
    if body.expected_revision != batch.base_revision:
        error(409, "SNAPSHOT_STALE", "请重新读取课表并核对预览")
    if batch.receipt is not None:
        return batch.receipt
    if s.revision != batch.base_revision:
        error(409, "SNAPSHOT_STALE", "课表已有更新，请重新核对导入内容")
    changes, _, _, missing_school = classify_import(db, batch)
    if changes and not body.replace_changed:
        error(409, "CHANGE_REQUIRES_REVIEW", "存在与已保存课次不同的信息，本批请先核对，不能直接覆盖")
    if body.remove_missing and batch.source != 'haut_webview':
        error(422, 'INVALID_IMPORT', '只有完整的教务课表可移除未出现的旧教务课程')
    removed_count = 0
    if body.remove_missing and missing_school:
        if db.scalar(select(RealityChange.id).where(
                RealityChange.user_id == user.id, RealityChange.semester_id == s.id,
                RealityChange.applied_revision.is_not(None)).limit(1)) is not None:
            error(409, 'APPLIED_CHANGE', '已有确认的调课或停课，请先核对变化，暂不能移除原课程')
        from .items import audit
        from .reminder_rules import utcnow
        missing_ids = {row['course_id'] for row in missing_school}
        for item in db.scalars(select(StudyItem).where(
                StudyItem.user_id == user.id, StudyItem.semester_id == s.id)):
            if item.payload.get('course_id') in missing_ids:
                title = item.payload.get('course_title', '')
                item.payload = {**item.payload, 'course_id': None, 'course_title': ''}
                item.version += 1
                item.updated_at = utcnow().isoformat()
                audit(db, item, f'旧教务课程“{title}”已移除，事项保留')
        db.execute(delete(CourseMeeting).where(CourseMeeting.user_id == user.id,
            CourseMeeting.semester_id == s.id, CourseMeeting.id.in_(missing_ids)))
        removed_count = len(missing_ids)
    occupied_keys = {row.identity_key: row.id for row in db.scalars(select(CourseMeeting).where(
        CourseMeeting.user_id == user.id, CourseMeeting.semester_id == s.id))}
    for change in changes:
        course_id = change['course_id']
        new_key = identity(change['after'])
        if new_key in occupied_keys and occupied_keys[new_key] != course_id:
            error(422, 'AMBIGUOUS_COURSE', '两条课程会变成相同课次，请返回学校课表核对')
        if db.scalar(select(RealityChange.id).where(
                RealityChange.user_id == user.id, RealityChange.semester_id == s.id,
                RealityChange.applied_revision.is_not(None)).limit(1)) is not None:
            error(409, 'APPLIED_CHANGE', '已有确认的调课或停课，请先核对变化，暂不能替换原课程')
        linked = any(item.payload.get('course_id') == course_id for item in db.scalars(
            select(StudyItem).where(StudyItem.user_id == user.id, StudyItem.semester_id == s.id)))
        if change['before']['title'] != change['after']['title'] and linked:
            error(409, 'LINKED_ITEM', '课程名称变化且本学期有事项，请先核对关联事项')
        old = db.scalar(select(CourseMeeting).where(CourseMeeting.id == course_id,
            CourseMeeting.user_id == user.id, CourseMeeting.semester_id == s.id))
        old.identity_key = new_key
        old.payload = change['after']
        old.source_batch_id = batch.id
        old.manually_edited = False
    existing = set(db.scalars(select(CourseMeeting.identity_key).where(CourseMeeting.user_id == user.id, CourseMeeting.semester_id == s.id)))
    existing.update(identity(change['after']) for change in changes)
    count = 0
    for c in batch.courses:
        key = identity(c)
        if key not in existing:
            db.add(CourseMeeting(user_id=user.id, semester_id=s.id, identity_key=key, payload=c, source_batch_id=batch.id))
            existing.add(key)
            count += 1
    if count or changes or removed_count:
        s.revision += 1
    response = {"semester_id": s.id, "revision": s.revision, "imported_count": count,
                "replaced_count": len(changes), "removed_count": removed_count,
                "batch_id": batch.id}
    batch.receipt = response
    remember(db, user, operation, idempotency_key, request, response)
    db.commit()
    return response


@router.get("/semesters/{sid}/timetable")
def timetable(sid: str, week: int = Query(ge=1, le=30), user: User = Depends(current_user), db: Session = Depends(get_db)):
    # Keep revision and rows in the same view while an import could commit.
    s = owned_semester(db, user, sid, lock=True)
    if week > s.total_weeks:
        error(422, "OUTSIDE_SEMESTER", "该周不在当前学期内")
    from .occurrences import effective_courses,expand
    from .reminder_rules import instant,SHANGHAI
    begin=datetime.combine(date.fromisoformat(s.first_monday)+timedelta(weeks=week-1),time(),SHANGHAI)
    finish=begin+timedelta(days=7)
    events=[e for e in expand({'first_monday':s.first_monday,'periods':s.periods},effective_courses(db,user,s))
        if instant(e['start_at'])<finish and instant(e['end_at'])>begin]
    events.sort(key=lambda e: (e["start_at"], e["title"], e["id"]))
    for e in events:
        e["conflict"] = any(o["id"] != e["id"] and o["start_at"] < e["end_at"] and e["start_at"] < o["end_at"] for o in events)
    return {"semester_id": sid, "week": week, "revision": s.revision, "events": events}
