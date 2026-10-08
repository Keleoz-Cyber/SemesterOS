"""Versioned semester correction and account-scoped removal."""

from fastapi import APIRouter, Depends, Header, Query, Request
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from .academics import owned_semester, remember, replay, serialize_semester
from .auth import current_user, error
from .database import get_db
from .media_files import path_for
from .reminder_rules import utcnow
from .models import (
    AgentRun, AgentThread, AvailabilityRevision, CalendarEvent,
    CalendarEventRevision, CourseMeeting, ImportBatch, ItemRevision,
    MediaCleanupJob, MediaSource, OperationProposal, PlanBlock, PlanProposal, PlanRevision,
    ProgressEntry, RealityChange, ReminderRule, StudyAvailability,
    StudyItem, TextCandidate, User,
)
from .schemas import SemesterUpdate

router = APIRouter()


def drain_media_cleanup(db, media_root, user_id=None):
    """Retry persisted deletes; a failed unlink never loses its cleanup job."""
    query = select(MediaCleanupJob)
    if user_id is not None:
        query = query.where(MediaCleanupJob.user_id == user_id)
    pending = 0
    for job in db.scalars(query).all():
        try:
            path_for(media_root, job.storage_key).unlink(missing_ok=True)
        except OSError:
            pending += 1
        else:
            db.delete(job)
    db.commit()
    return pending


def _count(db, model, user_id, semester_id):
    return db.scalar(select(func.count()).select_from(model).where(
        model.user_id == user_id, model.semester_id == semester_id)) or 0


def _overview(db, user, semester):
    sid = semester.id
    return {
        'semester_id': sid,
        'name': semester.name,
        'revision': semester.revision,
        'courses': _count(db, CourseMeeting, user.id, sid),
        'items': _count(db, StudyItem, user.id, sid),
        'events': _count(db, CalendarEvent, user.id, sid),
        'plans': _count(db, PlanBlock, user.id, sid),
        'sources': _count(db, MediaSource, user.id, sid),
        'conversations': _count(db, AgentThread, user.id, sid),
    }


@router.put('/semesters/{sid}')
def update_semester(sid: str, body: SemesterUpdate,
                    user: User = Depends(current_user), db: Session = Depends(get_db),
                    idempotency_key: str | None = Header(default=None)):
    semester = owned_semester(db, user, sid, lock=True)
    request = body.model_dump(mode='json')
    cached = replay(db, user, f'update-semester:{sid}', idempotency_key, request)
    if cached is not None:
        return cached
    if semester.revision != body.expected_revision:
        error(409, 'SNAPSHOT_STALE', '学期或课表已变化，请重新打开设置后再保存')
    before = serialize_semester(semester)
    changed_time = (
        before['first_monday'] != request['first_monday'] or
        before['total_weeks'] != request['total_weeks'] or
        before['periods'] != request['periods']
    )
    if changed_time:
        known = {period.number for period in body.periods}
        for course in db.scalars(select(CourseMeeting).where(
                CourseMeeting.user_id == user.id, CourseMeeting.semester_id == sid)):
            maximum = max(course.payload['weeks'])
            if maximum > body.total_weeks:
                error(422, 'CALENDAR_MISMATCH',
                      f'课表使用到第{maximum}周，请把学期周数设为至少{maximum}周')
            missing = set(course.payload['sections']) - known
            if missing and not course.payload.get('start_time'):
                section = min(missing)
                error(422, 'CALENDAR_MISMATCH', f'课表使用第{section}节，请补上该节时间')
        applied_changes = list(db.scalars(select(RealityChange).where(
            RealityChange.user_id == user.id, RealityChange.semester_id == sid,
            RealityChange.applied_revision.is_not(None))))
        # Legacy releases forbade calendar corrections once an exception was
        # saved. Their unchanged calendar is therefore the original anchor.
        for change in applied_changes:
            if 'base_calendar' not in change.payload:
                change.payload = {**change.payload, 'base_calendar': {'first_monday': before['first_monday']}}
    if before['name'] != body.name or changed_time:
        semester.name = body.name
        semester.first_monday = request['first_monday']
        semester.total_weeks = body.total_weeks
        semester.periods = request['periods']
        semester.revision += 1
    response = serialize_semester(semester)
    if changed_time:
        db.flush()
        from .schedule_api import snapshot
        from .capacity import calendar_context
        from .plan_rules import classify
        source = snapshot(db, user, semester)
        context = calendar_context(*source[:4], utcnow())
        _, issues = classify(source[4], source[3], context['free'].spans, context['begin'],
            obligation_points=context['obligation_points'])
        response['affected_plan_count'] = len({i['block_id'] for i in issues})
    remember(db, user, f'update-semester:{sid}', idempotency_key, request, response)
    db.commit()
    return response


@router.get('/semesters/{sid}/delete-preview')
def delete_preview(sid: str, user: User = Depends(current_user),
                   db: Session = Depends(get_db)):
    semester = owned_semester(db, user, sid)
    return _overview(db, user, semester)


@router.delete('/semesters/{sid}')
def delete_semester(sid: str, request: Request,
                    expected_revision: int = Query(ge=0),
                    user: User = Depends(current_user), db: Session = Depends(get_db),
                    idempotency_key: str | None = Header(default=None)):
    operation = f'delete-semester:{sid}'
    payload = {'expected_revision': expected_revision}
    cached = replay(db, user, operation, idempotency_key, payload)
    if cached is not None:
        return {**cached, 'media_files_pending_cleanup':
                drain_media_cleanup(db, request.app.state.media_root, user.id)}
    semester = owned_semester(db, user, sid, lock=True)
    if semester.revision != expected_revision:
        error(409, 'SNAPSHOT_STALE', '学期内容已变化，请重新查看删除范围')
    overview = _overview(db, user, semester)
    user_id = user.id
    item_ids = select(StudyItem.id).where(StudyItem.user_id == user_id, StudyItem.semester_id == sid)
    event_ids = select(CalendarEvent.id).where(CalendarEvent.user_id == user_id, CalendarEvent.semester_id == sid)
    thread_ids = select(AgentThread.id).where(AgentThread.user_id == user_id, AgentThread.semester_id == sid)
    media_keys = list(db.scalars(select(MediaSource.storage_key).where(
        MediaSource.user_id == user_id, MediaSource.semester_id == sid,
        MediaSource.file_deleted.is_(False))))
    for model, column, ids in (
        (AgentRun, AgentRun.thread_id, thread_ids),
        (CalendarEventRevision, CalendarEventRevision.event_id, event_ids),
        (ReminderRule, ReminderRule.item_id, item_ids),
        (ItemRevision, ItemRevision.item_id, item_ids),
        (ProgressEntry, ProgressEntry.item_id, item_ids),
    ):
        db.execute(delete(model).where(model.user_id == user_id, column.in_(ids)))
    for model in (
        TextCandidate, PlanBlock, CourseMeeting, MediaSource,
        OperationProposal, AvailabilityRevision, StudyAvailability,
        PlanRevision, PlanProposal, RealityChange, ImportBatch,
        CalendarEvent, StudyItem, AgentThread,
    ):
        db.execute(delete(model).where(model.user_id == user_id, model.semester_id == sid))
    db.delete(semester)
    for key in media_keys:
        db.add(MediaCleanupJob(user_id=user_id, storage_key=key,
                               created_at=utcnow().isoformat()))
    response = {'deleted_semester_id': sid, 'deleted_counts': overview}
    remember(db, user, operation, idempotency_key, payload, response)
    db.commit()
    return {**response, 'media_files_pending_cleanup':
            drain_media_cleanup(db, request.app.state.media_root, user.id)}
