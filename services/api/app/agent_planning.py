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
    remaining_updates: list['RemainingUpdate'] = Field(default_factory=list, max_length=100,
        description='用户同时明确更正剩余耗时并要求排程时，填写要更正的item_id/remaining_minutes，与新安排一起预览、一次确认保存。只给本次目标时使用targets，不改剩余量。')
    days: int = Field(default=7, ge=1, le=210)
    lead_minutes: int = Field(default=5, ge=0, le=1440)
    chunk_minutes: int = Field(default=45, ge=1, le=1440,
        description='单次学习分钟数，不是总目标。每次只学5分钟用5；明确要求连续3小时用180，不擅自改短或拆开。')
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
        updates=[u.item_id for u in self.remaining_updates]
        if len(set(updates))!=len(updates) or not set(updates).issubset(self.task_ids):
            raise ValueError('剩余量更正需对应所选唯一任务')
        if self.mode == 'replan' and self.model_fields_set & {
            'targets', 'remaining_updates', 'days', 'chunk_minutes', 'allow_partial', 'window_start_at', 'window_end_at'
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


class RemainingUpdate(Input):
    item_id: str = Field(min_length=1, max_length=36)
    remaining_minutes: int = Field(ge=1, le=525600)


def project_remaining(source, updates):
    values={u['item_id']:u['remaining_minutes'] for u in updates}
    return (*source[:3], [{**item, 'remaining_minutes':values.get(item['id'],item.get('remaining_minutes'))}
                         for item in source[3]], source[4])


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
    updates=[{'item_id':u.item_id,'remaining_minutes':u.remaining_minutes,
              'before_remaining_minutes':next(r.payload.get('remaining_minutes') for r in rows if r.id==u.item_id),
              'expected_version':next(r.version for r in rows if r.id==u.item_id)}
             for u in args.remaining_updates]
    now = schedule_api.utcnow()
    request = (args.schedule_input() if args.mode == 'schedule' else
        ReplanInput(task_ids=args.task_ids, lead_minutes=args.lead_minutes)).model_dump(mode='json')
    solver = schedule_api.generate if args.mode == 'schedule' else replanner.generate
    result = solver(*project_remaining(source,updates), request, now)
    if not result.get('can_apply') or not result['status'].startswith('FEASIBLE_'):
        from .capacity import calendar_context, CapacityIndex, subtract, merge
        from .reminder_rules import instant
        projected=project_remaining(source,updates)
        context=calendar_context(*projected[:4],now)
        occupied=merge([(instant(b['start_at']).timestamp(),instant(b['end_at']).timestamp())
                        for b in source[4] if b['status']=='active'])
        available=CapacityIndex(subtract(context['free'].spans,occupied),points=context['obligation_points'])
        longest=available.longest(instant(result['window_start']).timestamp(),instant(result['window_end']).timestamp())
        required=min(args.chunk_minutes,max((i.get('remaining_minutes') or 0 for i in projected[3]
                                            if i['id'] in args.task_ids),default=0))
        overview=(f'按已保存的学习时段，最长连续空档为**{longest}分钟**，放不下这次**{required}分钟**整段。'
                  if longest<required and result['status']=='CHUNKING_LIMITED' else
                  (result.get('messages') or ['当前没有需要保存的新安排。'])[0])
        if updates:overview+='剩余量更正和时间安排**都未保存**。'
        return {'status': 'needs_input' if result['status'].startswith('INPUT_') else 'not_applicable',
            'result': result, 'messages': result.get('messages') or ['当前没有需要保存的新安排。'],
            'overview_answer':overview, 'changes_saved':False,
            'basis':'按已保存的每周学习时段计算，不代表这些日期全天没有空闲。',
            'semester_id': semester.id, 'revision': semester.revision}
    if updates:result['remaining_updates']=updates
    proposal = PlanProposal(user_id=user.id, semester_id=semester.id,
        base_revision=semester.revision, phase='ready', created_at=now.isoformat(),
        payload={'request': request, 'result': result, 'input_hash': fingerprint(source),
            'agent_run_id': state['run_id'], 'remaining_updates':updates,
            'change_reason':str(state.get('draft_source') or '用户更正剩余量并安排时间')[:500]})
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
