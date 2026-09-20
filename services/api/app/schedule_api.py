from datetime import timedelta
from math import floor
from fastapi import APIRouter,Depends,Header,Request
from contextlib import contextmanager
from sqlalchemy import select
from sqlalchemy.orm import Session

from .academics import owned_semester,replay,remember,fingerprint
from .auth import current_user,error
from .database import get_db
from .models import CourseMeeting,StudyItem,PlanBlock,PlanProposal,User
from .planning import availability_row,availability_value
from .plan_store import block_value,plan_rows,record
from .plan_rules import classify
from .capacity import calendar_context
from .scheduler import generate,prepare,validate_result
from .schedule_schemas import ScheduleInput,ProposalAction,BlockLock,BlockCancel
from .reminder_rules import utcnow,instant

router=APIRouter()


@contextmanager
def solver_slot(app,user_id):
    with app.state.planner_lock:
        if user_id in app.state.planner_users or not app.state.planner_slots.acquire(blocking=False):
            error(429,'PLANNER_BUSY','已有排程请求正在处理，请稍后查看最近候选或重试')
        app.state.planner_users.add(user_id)
    try:yield
    finally:
        with app.state.planner_lock:
            app.state.planner_users.discard(user_id);app.state.planner_slots.release()


def snapshot(db,user,s):
    calendar={'first_monday':s.first_monday,'total_weeks':s.total_weeks,'periods':s.periods}
    preferences=availability_value(availability_row(db,user,s.id),s.revision)
    courses=[{**r.payload,'id':r.id} for r in db.scalars(select(CourseMeeting).where(CourseMeeting.user_id==user.id,CourseMeeting.semester_id==s.id))]
    items=[{**r.payload,'id':r.id,'version':r.version,'lifecycle':r.lifecycle} for r in db.scalars(select(StudyItem).where(StudyItem.user_id==user.id,StudyItem.semester_id==s.id))]
    titles={i['id']:i['title'] for i in items}
    plans=[block_value(b,titles.get(b.item_id,'')) for b in plan_rows(db,user,s.id)]
    return calendar,preferences,courses,items,plans


def proposal_value(p):
    phase='expired' if p.phase=='ready' and p.payload['result'].get('valid_until') and instant(p.payload['result']['valid_until'])<=utcnow() else p.phase
    return {**p.payload['result'],'id':p.id,'version':p.version,'phase':phase,'base_revision':p.base_revision,
            'semester_id':p.semester_id,
            'created_at':p.created_at,'request':p.payload['request'],'receipt':p.receipt,
            'can_apply':phase=='ready' and p.payload['result'].get('can_apply',False)}


def owned_proposal(db,user,id):
    p=db.scalar(select(PlanProposal).where(PlanProposal.id==id,PlanProposal.user_id==user.id))
    if not p:error(404,'NOT_FOUND','找不到这个候选计划')
    return p


@router.post('/semesters/{sid}/plan-proposals',status_code=201)
def create_proposal(sid:str,body:ScheduleInput,request:Request,user:User=Depends(current_user),db:Session=Depends(get_db),idempotency_key:str|None=Header(default=None)):
    s=owned_semester(db,user,sid,lock=True);data=body.model_dump(mode='json');operation='generate-plan/'+sid
    cached=replay(db,user,operation,idempotency_key,data)
    if cached is not None:return cached
    source=snapshot(db,user,s);revision=s.revision
    if not {t.item_id for t in body.tasks}.issubset({i['id'] for i in source[3]}):error(404,'NOT_FOUND','所选事项不属于本学期')
    source_hash=fingerprint(source);db.commit()
    with solver_slot(request.app,user.id):result=generate(*source,data,utcnow())
    db.expire_all();s=owned_semester(db,user,sid,lock=True)
    cached=replay(db,user,operation,idempotency_key,data)
    if cached is not None:return cached
    phase='stale' if s.revision!=revision else 'ready' if result['status'].startswith('FEASIBLE_') else 'failed'
    p=PlanProposal(user_id=user.id,semester_id=sid,base_revision=revision,phase=phase,
        payload={'request':data,'result':result,'input_hash':source_hash},created_at=utcnow().isoformat())
    db.add(p);db.flush();response=proposal_value(p)
    remember(db,user,operation,idempotency_key,data,response);db.commit();return response


@router.get('/plan-proposals/{id}')
def get_proposal(id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    p=owned_proposal(db,user,id);s=owned_semester(db,user,p.semester_id)
    result=proposal_value(p)
    if p.phase=='ready' and p.base_revision!=s.revision:result.update(phase='stale',can_apply=False)
    return result


@router.post('/plan-proposals/{id}/accept')
def accept_proposal(id:str,body:ProposalAction,user:User=Depends(current_user),db:Session=Depends(get_db)):
    p=owned_proposal(db,user,id);s=owned_semester(db,user,p.semester_id,lock=True);db.refresh(p)
    if p.phase=='applied':return p.receipt
    if p.phase!='ready' or p.version!=body.expected_version or s.revision!=p.base_revision or s.revision!=body.expected_revision:
        error(409,'SNAPSHOT_STALE','候选或学期安排已变化，请重新生成')
    result=p.payload['result']
    if result.get('valid_until') and instant(result['valid_until'])<=utcnow():error(409,'PLAN_EXPIRED','候选已过有效时刻，请重新生成')
    if result['status']=='FEASIBLE_PARTIAL' and (not body.confirm_partial or body.unarranged_minutes!=result['unarranged_minutes']):
        error(422,'CONFIRM_PARTIAL','这是部分方案，请明确确认仍有多少分钟未安排')
    if not result['can_apply']:error(422,'NOTHING_TO_APPLY','本轮没有需要新增的时间块')
    request={**p.payload['request'],'_window_start':floor(instant(result['window_start']).timestamp()/60),
             '_window_end':floor(instant(result['window_end']).timestamp()/60)}
    now=utcnow();_,context=prepare(*snapshot(db,user,s),request,now)
    if context is None or not validate_result(context,result,p.payload['request']['allow_partial']):
        error(409,'PLAN_EXPIRED','候选已过期或不再满足最新约束，请重新生成')
    ids=[]
    for block in result['blocks']:
        row=PlanBlock(user_id=user.id,semester_id=s.id,item_id=block['item_id'],proposal_id=p.id,
            start_at=block['start_at'],end_at=block['end_at'],minutes=block['minutes'],updated_at=now.isoformat())
        db.add(row);db.flush();ids.append(row.id)
    s.revision+=1;p.phase='applied';p.version+=1;p.applied_at=now.isoformat()
    p.receipt={'proposal_id':p.id,'proposal_version':p.version,'semester_id':s.id,'revision':s.revision,
               'block_ids':ids,'unarranged_minutes':result['unarranged_minutes']}
    record(db,user,s.id,'apply_proposal',p.receipt,now);db.commit();return p.receipt


@router.post('/plan-proposals/{id}/undo')
def undo_proposal(id:str,body:ProposalAction,user:User=Depends(current_user),db:Session=Depends(get_db)):
    p=owned_proposal(db,user,id);s=owned_semester(db,user,p.semester_id,lock=True);db.refresh(p)
    if p.phase=='undone':return p.receipt
    latest=db.scalar(select(PlanProposal).where(PlanProposal.user_id==user.id,PlanProposal.semester_id==s.id,
        PlanProposal.phase=='applied').order_by(PlanProposal.applied_at.desc(),PlanProposal.id.desc()))
    if latest is None or latest.id!=p.id or p.phase!='applied' or p.version!=body.expected_version or s.revision!=body.expected_revision:
        error(409,'UNDO_STALE','仅能撤销最近一次应用且未被后续操作改变的方案')
    blocks=list(db.scalars(select(PlanBlock).where(PlanBlock.user_id==user.id,PlanBlock.proposal_id==p.id)))
    now=utcnow()
    if any(b.version!=1 or b.status!='active' or b.locked or instant(b.start_at)<now for b in blocks):
        error(409,'UNDO_BLOCK_CHANGED','相关计划已修改、锁定或开始，不能整批撤销，请逐项核对')
    for b in blocks:b.status='cancelled';b.version+=1;b.updated_at=now.isoformat()
    s.revision+=1;p.phase='undone';p.version+=1
    p.receipt={'proposal_id':p.id,'proposal_version':p.version,'semester_id':s.id,'revision':s.revision,'undone':True}
    record(db,user,s.id,'undo_proposal',p.receipt,now);db.commit();return p.receipt


@router.get('/semesters/{sid}/plans')
def list_plans(sid:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    s=owned_semester(db,user,sid,lock=True);source=snapshot(db,user,s);now=utcnow()
    context=calendar_context(*source[:4],now)
    _,issues=classify(source[4],source[3],context['free'].spans,context['begin'])
    latest=db.scalar(select(PlanProposal).where(PlanProposal.user_id==user.id,PlanProposal.semester_id==sid).order_by(PlanProposal.created_at.desc(),PlanProposal.id.desc()))
    applied=db.scalar(select(PlanProposal).where(PlanProposal.user_id==user.id,PlanProposal.semester_id==sid,PlanProposal.phase=='applied').order_by(PlanProposal.applied_at.desc(),PlanProposal.id.desc()))
    latest_data=proposal_value(latest) if latest else None
    if latest_data and latest.phase=='ready' and latest.base_revision!=s.revision:latest_data.update(phase='stale',can_apply=False)
    return {'revision':s.revision,'semester_id':sid,'blocks':[b for b in source[4] if instant(b['end_at'])>now-timedelta(days=7)],
            'invalid_blocks':issues,'history_days':7,'latest_proposal':latest_data,
            'latest_applied':{'id':applied.id,'version':applied.version} if applied else None}


def owned_block(db,user,id):
    row=db.scalar(select(PlanBlock).where(PlanBlock.id==id,PlanBlock.user_id==user.id))
    if not row:error(404,'NOT_FOUND','找不到这段计划')
    s=owned_semester(db,user,row.semester_id,lock=True);db.refresh(row)
    return row,s


@router.patch('/plan-blocks/{id}/lock')
def lock_block(id:str,body:BlockLock,user:User=Depends(current_user),db:Session=Depends(get_db)):
    row,s=owned_block(db,user,id);now=utcnow()
    if row.version!=body.expected_version or row.status!='active' or instant(row.end_at)<=now:error(409,'BLOCK_STALE','计划已改变或结束，请刷新')
    before=block_value(row);row.locked=body.locked;row.version+=1;row.updated_at=now.isoformat();s.revision+=1
    record(db,user,s.id,'lock_block',{'before':before,'after':block_value(row)},now);db.commit();return {'semester_id':s.id,'revision':s.revision,'block':block_value(row)}


@router.post('/plan-blocks/{id}/cancel')
def cancel_block(id:str,body:BlockCancel,user:User=Depends(current_user),db:Session=Depends(get_db)):
    row,s=owned_block(db,user,id);now=utcnow()
    if row.version!=body.expected_version or row.status!='active' or instant(row.end_at)<=now:error(409,'BLOCK_STALE','计划已改变或结束，请刷新')
    if row.locked and not body.confirm_locked:error(422,'LOCKED_CONFIRMATION','需明确确认解锁并取消')
    before=block_value(row);row.status='cancelled';row.locked=False;row.version+=1;row.updated_at=now.isoformat();s.revision+=1
    record(db,user,s.id,'cancel_block',{'before':before},now);db.commit();return {'semester_id':s.id,'revision':s.revision,'block':block_value(row)}
