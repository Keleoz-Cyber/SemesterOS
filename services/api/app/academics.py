from datetime import date, datetime, time, timedelta
from hashlib import sha256
import json
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Header, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from .auth import current_user, error
from .database import get_db
from .models import CourseMeeting, IdempotencyRecord, ImportBatch, Semester, User
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


def summarize(db, batch):
    existing = {r.identity_key: r.payload for r in db.scalars(select(CourseMeeting).where(
        CourseMeeting.user_id == batch.user_id, CourseMeeting.semester_id == batch.semester_id))}
    def same_course(a, b):
        if a.get('source_id') and b.get('source_id'):
            return a['source_id'] == b['source_id']
        return a['title'] == b['title']

    def suspected_change(c):
        key = identity(c)
        if key in existing:
            return existing[key] != c
        if batch.source == 'manual':
            return False
        return any(same_course(c, old) for old in existing.values())

    changed = sum(suspected_change(c) for c in batch.courses)
    new_count = sum(identity(c) not in existing and not suspected_change(c) for c in batch.courses)
    return {"id": batch.id, "semester_id": batch.semester_id, "base_revision": batch.base_revision,
            "source": batch.source, "source_term": batch.source_term, "courses": batch.courses, "new_count": new_count,
            "unchanged_count": len(batch.courses) - new_count - changed, "changed_count": changed,
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
        if max(c.weeks) > s.total_weeks or not set(c.sections).issubset(known):
            error(422, "CALENDAR_MISMATCH", "课表周次或节次超出本学期设置，请先核对校历")
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
    if summarize(db, batch)["changed_count"]:
        error(409, "CHANGE_REQUIRES_REVIEW", "存在与已保存课次不同的信息，本批请先核对，不能直接覆盖")
    existing = set(db.scalars(select(CourseMeeting.identity_key).where(CourseMeeting.user_id == user.id, CourseMeeting.semester_id == s.id)))
    count = 0
    for c in batch.courses:
        key = identity(c)
        if key not in existing:
            db.add(CourseMeeting(user_id=user.id, semester_id=s.id, identity_key=key, payload=c, source_batch_id=batch.id))
            existing.add(key)
            count += 1
    if count:
        s.revision += 1
    response = {"semester_id": s.id, "revision": s.revision, "imported_count": count, "batch_id": batch.id}
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
    periods = {p["number"]: p for p in s.periods}
    events = []
    for row in db.scalars(select(CourseMeeting).where(CourseMeeting.user_id == user.id, CourseMeeting.semester_id == sid)):
        c = row.payload
        if week not in c["weeks"]:
            continue
        groups = []
        for section in c["sections"]:
            if not groups or groups[-1][-1] + 1 != section:
                groups.append([])
            groups[-1].append(section)
        day = date.fromisoformat(s.first_monday) + timedelta(days=(week - 1) * 7 + c["weekday"] - 1)
        for group in groups:
            start = datetime.combine(day, time.fromisoformat(periods[group[0]]["start"]), ZoneInfo("Asia/Shanghai"))
            end = datetime.combine(day, time.fromisoformat(periods[group[-1]]["end"]), ZoneInfo("Asia/Shanghai"))
            events.append({**c, "id": f"{row.id}:{day}:{group[0]}", "start_at": start.isoformat(),
                           "end_at": end.isoformat(), "sections": group, "source_batch_id": row.source_batch_id})
    events.sort(key=lambda e: (e["start_at"], e["title"], e["id"]))
    for e in events:
        e["conflict"] = any(o["id"] != e["id"] and o["start_at"] < e["end_at"] and e["start_at"] < o["end_at"] for o in events)
    return {"semester_id": sid, "week": week, "revision": s.revision, "events": events}
