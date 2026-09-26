"""Authenticated conversation API. Model tools never receive confirmation authority."""
from datetime import timedelta
from typing import Literal
from fastapi import APIRouter, Depends, Request
from pydantic import Field, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session
from .academics import owned_semester
from .auth import current_user, error
from .database import get_db
from .models import AgentThread, AgentRun, User, OperationProposal
from .schemas import Input
from .reminder_rules import utcnow, instant

router = APIRouter(prefix='/agent')


class ThreadInput(Input):
    semester_id: str = Field(min_length=1, max_length=36)


class TurnInput(Input):
    text: str = Field(min_length=1, max_length=10000)
    request_id: str = Field(min_length=1, max_length=100)

    @field_validator('text')
    @classmethod
    def nonblank(cls, value):
        if not value.strip(): raise ValueError('请输入内容')
        return value.strip()


class Decision(Input):
    decision: Literal['confirm', 'reject']
    token: str = Field(min_length=1, max_length=64)


def owned_thread(db, user, tid, lock=False):
    query = select(AgentThread).where(AgentThread.id == tid, AgentThread.user_id == user.id)
    row = db.scalar(query.with_for_update() if lock else query)
    if row is None: error(404, 'NOT_FOUND', '找不到这段对话')
    return row


def owned_run(db, user, rid, lock=False):
    query = select(AgentRun).where(AgentRun.id == rid, AgentRun.user_id == user.id)
    row = db.scalar(query.with_for_update() if lock else query)
    if row is None: error(404, 'NOT_FOUND', '找不到这条请求')
    return row


def public_run(row):
    state = row.state
    return {'id': row.id, 'thread_id': row.thread_id, 'text': row.text, 'status': row.status,
            'created_at': row.created_at, 'answer': state.get('answer', ''),
            'stage': state.get('stage', '等待处理'), 'cards': state.get('cards', []),
            'preview': state.get('preview'), 'receipt': state.get('receipt'),
            'error': state.get('error'), 'sequence': state.get('sequence', 0)}


def invalidate_preview(db, row):
    preview = row.state.get('preview') or {}
    if preview.get('kind') == 'operation':
        # Legacy operation endpoints serialize on the semester before touching
        # the proposal. Use the same order when rejecting via the agent.
        owned_semester(db, db.get(User, row.user_id), preview['semester_id'], lock=True)
        p = db.scalar(select(OperationProposal).where(OperationProposal.id == preview['operation_id'],
            OperationProposal.user_id == row.user_id).with_for_update())
        if p is not None and p.phase not in ('applied', 'rejected'):
            p.phase = 'rejected'; p.version += 1
    row.state = {**row.state, 'sequence': row.state.get('sequence', 0) + 1}


@router.post('/threads', status_code=201)
def new_thread(body: ThreadInput, user: User = Depends(current_user), db: Session = Depends(get_db)):
    owned_semester(db, user, body.semester_id)
    now = utcnow().isoformat()
    row = AgentThread(user_id=user.id, semester_id=body.semester_id, created_at=now, updated_at=now)
    db.add(row); db.flush(); db.commit()
    return {'id': row.id, 'semester_id': row.semester_id, 'title': row.title}


@router.get('/threads')
def threads(semester_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    owned_semester(db, user, semester_id)
    return [{'id': r.id, 'title': r.title, 'updated_at': r.updated_at} for r in db.scalars(
        select(AgentThread).where(AgentThread.user_id == user.id, AgentThread.semester_id == semester_id)
        .order_by(AgentThread.updated_at.desc(), AgentThread.id).limit(40))]


@router.get('/threads/{tid}')
def get_thread(tid: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = owned_thread(db, user, tid)
    runs = list(db.scalars(select(AgentRun).where(AgentRun.thread_id == tid, AgentRun.user_id == user.id)
                          .order_by(AgentRun.created_at.desc(), AgentRun.id.desc()).limit(50)))
    return {'id': tid, 'title': row.title, 'semester_id': row.semester_id, 'runs': [public_run(r) for r in reversed(runs)]}


@router.post('/threads/{tid}/turns', status_code=202)
def submit(tid: str, body: TurnInput, request: Request, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = owned_thread(db, user, tid, True)
    existing = db.scalar(select(AgentRun).where(AgentRun.thread_id == tid, AgentRun.request_id == body.request_id))
    if existing:
        if existing.text != body.text: error(409, 'IDEMPOTENCY_CONFLICT', '这次发送的内容已变化，请重新发送')
        return public_run(existing)
    from .capture import admission
    admission(request, user)
    busy = db.scalar(select(AgentRun).where(AgentRun.thread_id == tid, AgentRun.status.in_(['queued', 'running'])))
    if busy: error(409, 'RUN_BUSY', '请等待当前回复，或先停止处理')
    pending_count = list(db.scalars(select(AgentRun.id).where(AgentRun.user_id == user.id,
        AgentRun.status.in_(['queued', 'running'])).limit(3)))
    if len(pending_count) >= 3: error(429, 'RUN_LIMIT', '已有几条请求正在处理，请稍后再发')
    # One pending preview per conversation: a follow-up supersedes it, but never applies it.
    for pending in db.scalars(select(AgentRun).where(AgentRun.thread_id == tid, AgentRun.status == 'needs_confirmation').with_for_update()):
        invalidate_preview(db, pending)
        pending.status = 'superseded'
    now = utcnow().isoformat()
    from .agent_runtime import initial_state
    state = initial_state(db, user, row, body.text, now)
    run = AgentRun(user_id=user.id, thread_id=tid, request_id=body.request_id,
                   text=body.text, state=state, created_at=now)
    row.updated_at = now
    if row.title == '新对话': row.title = body.text[:80]
    db.add(run); db.flush(); run.state = {**state, 'run_id': run.id}; db.commit()
    return public_run(run)


@router.get('/runs/{rid}')
def get_run(rid: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return public_run(owned_run(db, user, rid))


@router.post('/runs/{rid}/cancel')
def cancel(rid: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = owned_run(db, user, rid, True)
    if row.status in ('queued', 'running', 'needs_confirmation'):
        invalidate_preview(db, row)
        row.status = 'cancelled'; row.lease_token = None
        row.state = {**row.state, 'stage': '已停止', 'sequence': row.state.get('sequence', 0) + 1}
        db.commit()
    return public_run(row)


@router.post('/runs/{rid}/decision')
def decide(rid: str, body: Decision, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = owned_run(db, user, rid, True)
    preview = row.state.get('preview')
    if not preview or body.token != preview['token']: error(409, 'PREVIEW_STALE', '请重新打开当前修改预览')
    if row.status == 'applied' and body.decision == 'confirm': return public_run(row)
    if row.status == 'cancelled' and body.decision == 'reject': return public_run(row)
    if row.status != 'needs_confirmation': error(409, 'PREVIEW_STALE', '这次预览已失效，请重新描述修改')
    if body.decision == 'reject':
        invalidate_preview(db, row)
        row.status = 'cancelled'; db.commit(); return public_run(row)
    if utcnow() - instant(row.created_at) > timedelta(hours=24):
        error(409, 'PREVIEW_EXPIRED', '这份预览已经超过一天，请重新核对安排')
    from .agent_tools import apply_preview
    # Command and agent receipt share a transaction: no commit gap on process failure.
    receipt = apply_preview(db, user, preview)
    row.state = {**row.state, 'receipt': receipt, 'stage': '已保存', 'answer': '已保存。',
                 'sequence': row.state.get('sequence', 0) + 1}
    row.status = 'applied'; db.commit()
    return public_run(row)
