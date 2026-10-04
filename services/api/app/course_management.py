"""Basic course corrections without discarding the whole semester."""

from fastapi import APIRouter, Depends, Header, Query
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .academics import course_payload, identity, owned_semester, remember, replay
from .auth import current_user, error
from .database import get_db
from .items import audit
from .models import CourseMeeting, StudyItem, User
from .reminder_rules import utcnow
from .schemas import CourseUpdate

router = APIRouter()


def _owned_course(db, user, course_id):
    course = db.scalar(select(CourseMeeting).where(
        CourseMeeting.id == course_id, CourseMeeting.user_id == user.id))
    if course is None:
        error(404, 'NOT_FOUND', '找不到这门课程')
    return course


def _family(db, user, course):
    rows = list(db.scalars(select(CourseMeeting).where(
        CourseMeeting.user_id == user.id,
        CourseMeeting.semester_id == course.semester_id)))
    source = course.payload.get('source_id')
    return [row for row in rows if row.id == course.id or
            source and row.payload.get('source_id') == source]


def _linked_items(db, user, semester_id, course_ids):
    return [item for item in db.scalars(select(StudyItem).where(
        StudyItem.user_id == user.id, StudyItem.semester_id == semester_id))
        if item.payload.get('course_id') in course_ids]


@router.get('/courses/{course_id}')
def course_details(course_id: str, user: User = Depends(current_user),
                   db: Session = Depends(get_db)):
    course = _owned_course(db, user, course_id)
    semester = owned_semester(db, user, course.semester_id)
    return {'id': course.id, 'semester_id': semester.id,
            'revision': semester.revision, 'course': course.payload}


@router.patch('/courses/{course_id}')
def update_course(course_id: str, body: CourseUpdate,
                  user: User = Depends(current_user), db: Session = Depends(get_db),
                  idempotency_key: str | None = Header(default=None)):
    course = _owned_course(db, user, course_id)
    semester = owned_semester(db, user, course.semester_id, lock=True)
    request = {**course_payload(body), 'expected_revision': body.expected_revision}
    cached = replay(db, user, f'update-course:{course_id}', idempotency_key, request)
    if cached is not None:
        return cached
    if semester.revision != body.expected_revision:
        error(409, 'SNAPSHOT_STALE', '课表已变化，请重新打开课程后再保存')
    if max(body.weeks) > semester.total_weeks:
        error(422, 'CALENDAR_MISMATCH', '课程周次超出学期范围，请先修改学期周数')
    data = course_payload(body)
    slot_changed = (body.weekday != course.payload['weekday'] or body.sections != course.payload['sections'])
    if not {'start_time', 'end_time'} & body.model_fields_set and not slot_changed:
        for key in ('start_time', 'end_time'):
            if key in course.payload:
                data[key] = course.payload[key]
    if 'attendance_exempt' not in body.model_fields_set and course.payload.get('attendance_exempt'):
        data['attendance_exempt'] = True
    missing = set(body.sections) - {p['number'] for p in semester.periods}
    if missing and not data.get('start_time'):
        error(422, 'CALENDAR_MISMATCH', f'学期作息缺少第{min(missing)}节，请先补充节次')
    if course.payload.get('source_id') and not data.get('source_id'):
        data['source_id'] = course.payload['source_id']
    new_key = identity(data)
    duplicate = db.scalar(select(CourseMeeting.id).where(
        CourseMeeting.user_id == user.id,
        CourseMeeting.semester_id == semester.id,
        CourseMeeting.identity_key == new_key,
        CourseMeeting.id != course.id))
    if duplicate is not None:
        error(422, 'DUPLICATE_COURSE', '已有相同周次、星期和节次的课程记录')
    if data != course.payload:
        old_title = course.payload['title']
        course.payload = data
        course.identity_key = new_key
        course.manually_edited = True
        if data['title'] != old_title:
            for item in _linked_items(db, user, semester.id, {course.id}):
                item.payload = {**item.payload, 'course_title': data['title']}
                item.version += 1
                item.updated_at = utcnow().isoformat()
                audit(db, item, '关联课程名称已修改')
        semester.revision += 1
    response = {'id': course.id, 'semester_id': semester.id,
                'revision': semester.revision, 'course': course.payload}
    remember(db, user, f'update-course:{course_id}', idempotency_key, request, response)
    db.commit()
    return response


@router.get('/courses/{course_id}/delete-preview')
def delete_preview(course_id: str, user: User = Depends(current_user),
                   db: Session = Depends(get_db)):
    course = _owned_course(db, user, course_id)
    semester = owned_semester(db, user, course.semester_id)
    family = _family(db, user, course)
    ids = {row.id for row in family}
    return {'course_id': course.id, 'semester_id': semester.id,
            'title': course.payload['title'], 'revision': semester.revision,
            'meetings': len(family),
            'linked_items': len(_linked_items(db, user, semester.id, ids))}


@router.delete('/courses/{course_id}')
def delete_course(course_id: str, expected_revision: int = Query(ge=0),
                  user: User = Depends(current_user), db: Session = Depends(get_db),
                  idempotency_key: str | None = Header(default=None)):
    operation = f'delete-course:{course_id}'
    request = {'expected_revision': expected_revision}
    cached = replay(db, user, operation, idempotency_key, request)
    if cached is not None:
        return cached
    course = _owned_course(db, user, course_id)
    semester = owned_semester(db, user, course.semester_id, lock=True)
    if semester.revision != expected_revision:
        error(409, 'SNAPSHOT_STALE', '课表已变化，请重新查看删除范围')
    family = _family(db, user, course)
    ids = {row.id for row in family}
    linked = _linked_items(db, user, semester.id, ids)
    for item in linked:
        old_title = item.payload.get('course_title') or course.payload['title']
        item.payload = {**item.payload, 'course_id': None, 'course_title': ''}
        item.version += 1
        item.updated_at = utcnow().isoformat()
        audit(db, item, f'关联课程“{old_title}”已删除，事项保留')
    db.execute(delete(CourseMeeting).where(
        CourseMeeting.user_id == user.id, CourseMeeting.id.in_(ids)))
    semester.revision += 1
    response = {'semester_id': semester.id, 'revision': semester.revision,
                'deleted_count': len(family), 'detached_items': len(linked)}
    remember(db, user, operation, idempotency_key, request, response)
    db.commit()
    return response
