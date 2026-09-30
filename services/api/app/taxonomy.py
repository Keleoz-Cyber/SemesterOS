"""Owner-scoped tag maintenance with a persisted, single-use confirmation preview."""
from typing import Literal

from fastapi import APIRouter, Depends
from pydantic import Field, field_validator, model_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from .academics import fingerprint
from .auth import current_user, error
from .database import get_db
from .event_schemas import EventFields
from .event_store import canonical_tag, canonical_tag_ids, tag_by_name
from .models import (CalendarEvent, CalendarTag, CalendarTagAlias, CalendarTagChange,
                     PlanBlock, ProgressEntry, Semester, StudyItem, User)
from .reminder_rules import utcnow
from .schemas import Input

router = APIRouter()


class TagChangeInput(Input):
    operation: Literal['rename', 'merge']
    source_id: str = Field(min_length=1, max_length=36)
    name: str | None = None
    target_id: str | None = Field(default=None, min_length=1, max_length=36)

    @field_validator('name')
    @classmethod
    def normalize_name(cls, value):
        return EventFields.normalize_tags([value])[0] if value is not None else None

    @model_validator(mode='after')
    def correct_operation(self):
        if self.operation == 'rename' and (self.name is None or self.target_id is not None):
            raise ValueError('重命名需要填写新名称')
        if self.operation == 'merge' and (self.target_id is None or self.name is not None):
            raise ValueError('合并需要明确选择保留的标签')
        return self


def tag_value(row):
    return {'id': row.id, 'name': row.name, 'version': row.version}


def lock_scope(db, user):
    # Item/event writes already lock their semester before tag_ids locks User.
    # Use this same order globally; re-read identity-map rows after waiting.
    semesters = list(db.scalars(select(Semester).where(Semester.user_id == user.id)
        .order_by(Semester.id).with_for_update().execution_options(populate_existing=True)))
    db.scalar(select(User).where(User.id == user.id).with_for_update())
    ids = list(db.scalars(select(Semester.id).where(Semester.user_id == user.id).order_by(Semester.id)))
    if ids != [s.id for s in semesters]:
        error(409, 'SNAPSHOT_STALE', '学期列表已更新，请重新核对标签')
    return semesters


def state(db, user, semesters):
    tags = list(db.scalars(select(CalendarTag).where(CalendarTag.user_id == user.id)
        .order_by(CalendarTag.id).execution_options(populate_existing=True)))
    aliases = list(db.scalars(select(CalendarTagAlias).where(CalendarTagAlias.user_id == user.id)
        .order_by(CalendarTagAlias.normalized).execution_options(populate_existing=True)))
    resources = []
    for model in (StudyItem, CalendarEvent):
        resources.extend(db.scalars(select(model).where(model.user_id == user.id)
            .order_by(model.id).execution_options(populate_existing=True)))
    snapshot = {'tags': [[t.id, t.name, t.version, t.merged_into] for t in tags],
        'aliases': [[a.normalized, a.tag_id] for a in aliases],
        'semesters': [[s.id, s.revision] for s in semesters],
        'resources': [[type(r).__name__, r.id, r.version, r.payload.get('tag_ids', [])] for r in resources]}
    return resources, fingerprint(snapshot)


def checked_tags(db, user, body):
    source = canonical_tag(db, user.id, body.source_id)
    if source is None or source.id != body.source_id:
        error(404, 'NOT_FOUND', '标签已合并或不存在，请刷新后选择')
    if body.operation == 'rename':
        existing = tag_by_name(db, user.id, body.name)
        if existing is not None and existing.id != source.id:
            error(409, 'TAG_NAME_EXISTS', '此名称已属于其他标签，请选择合并并核对影响')
        if source.name == body.name:
            error(422, 'NO_CHANGE', '新名称与当前名称相同')
        return source, None
    target = canonical_tag(db, user.id, body.target_id)
    if target is None or target.id != body.target_id:
        error(404, 'NOT_FOUND', '保留的标签已合并或不存在，请刷新后选择')
    if target.id == source.id:
        error(422, 'NO_CHANGE', '请选择两个不同的标签')
    return source, target


@router.get('/tags')
def list_tags(user: User = Depends(current_user), db: Session = Depends(get_db)):
    tags = db.scalars(select(CalendarTag).where(CalendarTag.user_id == user.id,
        CalendarTag.merged_into.is_(None)).order_by(CalendarTag.name, CalendarTag.id))
    return {'owner_id': user.id, 'tags': [tag_value(t) for t in tags]}


@router.post('/tags/preview')
def preview_change(body: TagChangeInput, user: User = Depends(current_user), db: Session = Depends(get_db)):
    semesters = lock_scope(db, user)
    resources, snapshot_hash = state(db, user, semesters)
    source, target = checked_tags(db, user, body)
    relevant = {source.id} | ({target.id} if target else set())
    affected = [r for r in resources if relevant.intersection(canonical_tag_ids(db, user.id, r.payload.get('tag_ids', [])))]
    item_ids = [r.id for r in affected if isinstance(r, StudyItem)]
    plans = list(db.scalars(select(PlanBlock.id).where(PlanBlock.user_id == user.id, PlanBlock.item_id.in_(item_ids))))
    progress = list(db.scalars(select(ProgressEntry.id).where(ProgressEntry.user_id == user.id, ProgressEntry.item_id.in_(item_ids))))
    sids = {r.semester_id for r in affected}
    summary = {'owner_id': user.id, 'operation': body.operation, 'source': tag_value(source),
        'target': tag_value(target) if target else {'id': source.id, 'name': body.name},
        'affected': {'items': len(item_ids), 'events': len(affected) - len(item_ids),
            'plans': len(plans), 'progress': len(progress)},
        'semesters': [{'id': s.id, 'name': s.name, 'revision': s.revision} for s in semesters if s.id in sids]}
    change = CalendarTagChange(user_id=user.id, payload=body.model_dump(), snapshot_hash=snapshot_hash,
        preview=summary, created_at=utcnow().isoformat())
    db.add(change); db.flush()
    response = {**summary, 'token': change.id}
    db.commit()
    return response


def save_alias(db, user, normalized, target):
    alias = db.get(CalendarTagAlias, (user.id, normalized))
    if alias is None:
        db.add(CalendarTagAlias(user_id=user.id, normalized=normalized, tag_id=target.id))
    else:
        alias.tag_id = target.id


@router.post('/tags/changes/{token}/apply')
def apply_change(token: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    semesters = lock_scope(db, user)
    change = db.scalar(select(CalendarTagChange).where(CalendarTagChange.id == token,
        CalendarTagChange.user_id == user.id).with_for_update().execution_options(populate_existing=True))
    if change is None:
        error(404, 'NOT_FOUND', '找不到这次标签预览')
    if change.receipt is not None:
        return change.receipt
    resources, snapshot_hash = state(db, user, semesters)
    if snapshot_hash != change.snapshot_hash:
        error(409, 'SNAPSHOT_STALE', '标签或相关安排已变化，请重新预览后确认')
    body = TagChangeInput.model_validate(change.payload)
    source, target = checked_tags(db, user, body)
    before = {id(r): canonical_tag_ids(db, user.id, r.payload.get('tag_ids', [])) for r in resources}
    if target is None:
        save_alias(db, user, source.normalized, source)
        source.name = body.name
        source.normalized = body.name.casefold()
        source.version += 1
        target = source
    else:
        save_alias(db, user, source.normalized, target)
        for alias in db.scalars(select(CalendarTagAlias).where(CalendarTagAlias.user_id == user.id,
                CalendarTagAlias.tag_id == source.id)):
            alias.tag_id = target.id
        source.merged_into = target.id
        source.normalized = '~merged:' + source.id
        source.version += 1
        target.version += 1
    db.flush()
    changed_semesters = {s['id'] for s in change.preview['semesters']}
    if body.operation == 'merge':
        from .items import audit
        from .calendar_events import record
        for row in resources:
            if source.id not in before[id(row)]:
                continue
            ids = canonical_tag_ids(db, user.id, row.payload.get('tag_ids', []))
            row.payload = {**row.payload, 'tag_ids': ids}
            row.version += 1
            row.updated_at = utcnow().isoformat()
            if isinstance(row, StudyItem):
                audit(db, row, '用户确认合并标签')
            else:
                record(db, row, '用户确认合并标签')
    for semester in semesters:
        if semester.id in changed_semesters:
            semester.revision += 1
    response = {'owner_id': user.id, 'token': token, 'operation': body.operation, 'tag': tag_value(target),
        'affected': change.preview['affected'],
        'semesters': [{'id': s.id, 'revision': s.revision} for s in semesters if s.id in changed_semesters]}
    change.receipt = response
    db.commit()
    return response
