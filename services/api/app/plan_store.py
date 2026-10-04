from datetime import timezone
from sqlalchemy import select
from .models import PlanBlock, PlanRevision
from .auth import error
from .plan_rules import future_minutes


def block_value(b,title=''):
    return {k:getattr(b,k) for k in ('id','item_id','proposal_id','start_at','end_at','minutes','locked','status','version')}|{'title':title}


def plan_rows(db,user,sid):
    return list(db.scalars(select(PlanBlock).where(PlanBlock.user_id==user.id,PlanBlock.semester_id==sid,PlanBlock.status=='active').order_by(PlanBlock.start_at,PlanBlock.id)))


def future_for_item(db,item,now):
    return list(db.scalars(select(PlanBlock).where(PlanBlock.user_id==item.user_id,PlanBlock.item_id==item.id,
        PlanBlock.status=='active',PlanBlock.end_at>now.astimezone(timezone.utc).isoformat()).order_by(PlanBlock.start_at,PlanBlock.id)))


def preview_blocks(db,item,now):
    return [block_value(b,item.payload['title'])|{'future_minutes':future_minutes(block_value(b),now.timestamp())} for b in future_for_item(db,item,now)]


def record(db,user,sid,kind,payload,now):
    db.add(PlanRevision(user_id=user.id,semester_id=sid,kind=kind,payload=payload,created_at=now.isoformat()))


def cancel_for_change(db,user,item,now,ids,confirm_locked,remaining=None,all_required=False):
    blocks=future_for_item(db,item,now);selected=set(ids)
    if not selected.issubset({b.id for b in blocks}):error(409,'PLAN_SELECTION_STALE','所选计划已变化，请重新核对')
    if all_required and selected!={b.id for b in blocks}:error(409,'PLAN_CONFIRMATION_REQUIRED','请通过预览明确取消这条事项的未来计划')
    if any(b.locked and b.id in selected for b in blocks) and not confirm_locked:
        error(422,'LOCKED_CONFIRMATION','包含锁定计划，需明确确认解锁并取消')
    kept=sum(future_minutes(block_value(b),now.timestamp()) for b in blocks if b.id not in selected)
    if remaining is not None and kept>remaining:error(422,'PLAN_OVER_COVERAGE','保留计划的总时长超过了任务还需要的时间，请再取消几段计划')
    before=[block_value(b) for b in blocks if b.id in selected]
    for b in blocks:
        if b.id in selected:b.status='cancelled';b.locked=False;b.version+=1;b.updated_at=now.isoformat()
    if before:record(db,user,item.semester_id,'cancel_for_item_change',{'before':before,'item_id':item.id},now)
