"""Transaction-only Agent adapter for the existing scheduling solvers.

The caller owns the semester/AgentRun transaction, confirmation token and receipt.
No business plan blocks are written until apply_agent_plan is called.
"""
from datetime import datetime
from typing import Annotated, Literal

from pydantic import Field, model_validator
from sqlalchemy import select

from .schemas import Input
from .schedule_schemas import ScheduleInput, TaskTarget, ReplanInput, ProposalAction
from .models import StudyItem, PlanProposal
from .academics import fingerprint
from .auth import error
from . import schedule_api, replanner


class PlanRequest(Input):
    mode: Literal['schedule', 'replan']
    task_ids: list[Annotated[str, Field(min_length=1, max_length=36)]] = Field(min_length=1, max_length=100)
    targets: list[TaskTarget] = Field(default_factory=list, max_length=100,
        description='仅排程使用。用户明确给出的本次目标分钟数；不确定时留空并询问，不猜剩余工作量。')
    days: Literal[7, 14, 28] = 7
    lead_minutes: int = Field(default=5, ge=0, le=60)
    chunk_minutes: int = Field(default=45, ge=15, le=120)
    allow_partial: bool = False
    window_start_at: datetime | None = None
    window_end_at: datetime | None = None

    @model_validator(mode='after')
    def valid_request(self):
        if len(set(self.task_ids)) != len(self.task_ids):
            raise ValueError('不能重复选择任务')
        targets = [target.item_id for target in self.targets]
        if len(set(targets)) != len(targets) or not set(targets).issubset(self.task_ids):
            raise ValueError('目标时长必须对应已选择的唯一任务')
        if self.mode == 'replan' and self.model_fields_set & {
            'targets', 'days', 'chunk_minutes', 'allow_partial', 'window_start_at', 'window_end_at'
        }:
            raise ValueError('重排仅调整所选任务已有的个人计划，不能同时新增工作量或指定排程窗口')
        if self.mode == 'schedule':
            # Reuse the route's timezone/window bounds and task input contract.
            self.schedule_input()
        return self

    def schedule_input(self):
        targets = {target.item_id: target for target in self.targets}
        return ScheduleInput(days=self.days, lead_minutes=self.lead_minutes,
            chunk_minutes=self.chunk_minutes, allow_partial=self.allow_partial,
            window_start_at=self.window_start_at, window_end_at=self.window_end_at,
            tasks=[targets.get(id, TaskTarget(item_id=id)) for id in self.task_ids])


def prepare_agent_plan(db, user, semester, state, args: PlanRequest):
    """Return a raw confirmation preview or useful solver data, never commit."""
    if semester.user_id != user.id:
        error(404, 'NOT_FOUND', '找不到这个学期')
    rows = list(db.scalars(select(StudyItem).where(StudyItem.user_id == user.id,
        StudyItem.semester_id == semester.id, StudyItem.id.in_(args.task_ids))))
    if len(rows) != len(args.task_ids) or any(
        row.lifecycle != 'active' or row.payload.get('kind') not in ('task', 'assignment') for row in rows
    ):
        error(404, 'NOT_FOUND', '所选任务不属于本学期、已不活跃或不支持排程')
    if set(args.task_ids) & set(state.get('ambiguous_ids', [])):
        error(422, 'AMBIGUOUS_TARGET', '查到了多条同名事项，请先列出名称和时间，确认具体要安排哪一条')
    if not set(args.task_ids).issubset(state.get('known_ids', [])):
        error(422, 'READ_FIRST', '请先查询并核对要安排的任务，不要猜测任务编号')
    source = schedule_api.snapshot(db, user, semester)
    now = schedule_api.utcnow()
    request = (args.schedule_input() if args.mode == 'schedule' else
        ReplanInput(task_ids=args.task_ids, lead_minutes=args.lead_minutes)).model_dump(mode='json')
    solver = schedule_api.generate if args.mode == 'schedule' else replanner.generate
    result = solver(*source, request, now)
    if not result.get('can_apply') or not result['status'].startswith('FEASIBLE_'):
        return {'status': 'needs_input' if result['status'].startswith('INPUT_') else 'not_applicable',
            'result': result, 'messages': result.get('messages') or ['当前没有需要保存的新安排。'],
            'semester_id': semester.id, 'revision': semester.revision}
    proposal = PlanProposal(user_id=user.id, semester_id=semester.id,
        base_revision=semester.revision, phase='ready', created_at=now.isoformat(),
        payload={'request': request, 'result': result, 'input_hash': fingerprint(source),
            'agent_run_id': state['run_id']})
    db.add(proposal); db.flush()
    return {'kind': 'plan', 'action': args.mode, 'target_id': proposal.id,
        'before': {'tasks': [item for item in source[3] if item['id'] in args.task_ids],
            'blocks': source[4]},
        'after': result, 'semester_id': semester.id, 'expected_revision': semester.revision,
        'body': ProposalAction(expected_version=proposal.version, expected_revision=semester.revision,
            confirm_partial=result['status'] == 'FEASIBLE_PARTIAL',
            unarranged_minutes=result['unarranged_minutes']).model_dump(mode='json')}


def apply_agent_plan(db, user, preview):
    proposal = schedule_api.owned_proposal(db, user, preview['target_id'])
    if proposal.semester_id != preview['semester_id'] or not proposal.payload.get('agent_run_id'):
        error(409, 'PREVIEW_STALE', '这份方案不属于当前助手预览，请重新生成')
    return schedule_api.accept_proposal_command(db, user, proposal.id,
        ProposalAction.model_validate(preview['body']))


def invalidate_agent_plan(db, user, preview):
    """Reject only a still-pending Agent proposal; safe to call repeatedly."""
    proposal = db.scalar(select(PlanProposal).where(PlanProposal.id == preview['target_id'],
        PlanProposal.user_id == user.id, PlanProposal.semester_id == preview['semester_id']).with_for_update())
    if proposal and proposal.payload.get('agent_run_id') and proposal.phase == 'ready':
        proposal.phase = 'rejected'
        proposal.version += 1
