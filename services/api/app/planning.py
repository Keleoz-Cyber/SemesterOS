from .event_store import calendar_snapshot
from fastapi import APIRouter, Depends, Header, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from .academics import owned_semester, replay, remember
from .auth import current_user, error
from .capacity import analyze
from .database import get_db
from .items import owned_item, check_version, audit, serialize_item, rules_for
from .models import AvailabilityRevision, ProgressEntry, StudyAvailability, StudyItem, User
from .planning_schemas import AvailabilityApply, AvailabilityInput, ProgressApply, ProgressInput
from .reminder_rules import utcnow
from .capacity import calendar_context
from .plan_rules import classify
from .plan_store import plan_rows,block_value,preview_blocks,cancel_for_change

router=APIRouter()


def schedule_setup_value(db,user,s,task_ids=None):
    from .task_readiness import start_policy
    rows=list(db.scalars(select(StudyItem).where(StudyItem.user_id==user.id,
        StudyItem.semester_id==s.id,StudyItem.lifecycle=='active').order_by(StudyItem.created_at,StudyItem.id)))
    rows=[r for r in rows if r.payload.get('kind') in ('task','assignment')]
    if task_ids:
        if not set(task_ids).issubset(r.id for r in rows):error(404,'NOT_FOUND','所选任务不属于当前学期或已完成')
        rows=[r for r in rows if r.id in task_ids]
    preferences=availability_value(availability_row(db,user,s.id),s.revision)
    # A small starting template, never a claimed personal preference or saved value.
    candidate={'weekly':[{'weekday':d,'start':'19:00','end':'21:00'} for d in range(1,6)]+
        [{'weekday':d,'start':'10:00','end':'12:00'} for d in (6,7)],'exclusions':[]}
    tasks=[];unresolved=[]
    for row in rows[:100]:
        payload=row.payload;policy=start_policy(payload);remaining=payload.get('remaining_minutes')
        # Simple proposed starting effort. It is explicitly editable and never
        # written to the task without the user's normal save confirmation.
        title=payload.get('title','')
        suggestion=120 if any(word in title for word in ('报告','论文','实验','项目')) else 45
        tasks.append({'id':row.id,'version':row.version,'title':title,'remaining_minutes':remaining,
            'start_policy':policy,'earliest_start_at':payload.get('earliest_start_at'),
            'can_schedule':policy!='unconfirmed',
            'waiting_reason':('；'.join((payload.get('details') or {}).get('conditions') or []) or
                '任务仍有明确等待条件，请核对后再安排') if policy=='unconfirmed' else '',
            'duration_suggestion_minutes':suggestion if remaining is None else None,
            'duration_suggestion_label':'起步建议，可按实际修改；尚未计入任务耗时' if remaining is None else '',
            'details':payload.get('details',{}),'time':payload.get('time',{})})
        missing=(['remaining_minutes'] if remaining is None else [])+(['start_condition'] if policy=='unconfirmed' else [])
        if missing:unresolved.append({'item_id':row.id,'fields':missing})
    return {'semester_id':s.id,'revision':s.revision,'settings_version':preferences['version'],
        'availability':{'current':preferences,'candidate':candidate,
            'candidate_label':'候选学习时间，请按作息修改后确认','needs_confirmation':not preferences['configured']},
        'tasks':tasks,'unresolved':unresolved}


@router.get('/semesters/{sid}/schedule/setup')
def get_schedule_setup(sid:str,task_ids:list[str]=Query(default=[]),user:User=Depends(current_user),db:Session=Depends(get_db)):
    s=owned_semester(db,user,sid,lock=True)
    return schedule_setup_value(db,user,s,task_ids)


def availability_row(db,user,sid):
    return db.scalar(select(StudyAvailability).where(StudyAvailability.user_id==user.id,StudyAvailability.semester_id==sid))


def availability_value(row,revision):
    return {**(row.payload if row else {'weekly':[],'exclusions':[]}), 'configured':row is not None,
            'version':row.version if row else 0,'revision':revision,'timezone':'Asia/Shanghai'}


def validate_preferences(db,user,sid,body):
    s=owned_semester(db,user,sid,lock=True)
    row=availability_row(db,user,sid)
    if (row.version if row else 0)!=body.expected_version:
        error(409,'SNAPSHOT_STALE','学习时间已经更新，请重新打开设置核对')
    return s,row


@router.get('/semesters/{sid}/availability')
def get_availability(sid:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    s=owned_semester(db,user,sid,lock=True)
    return availability_value(availability_row(db,user,sid),s.revision)


@router.post('/semesters/{sid}/availability/preview')
def preview_availability(sid:str,body:AvailabilityInput,user:User=Depends(current_user),db:Session=Depends(get_db)):
    s,row=validate_preferences(db,user,sid,body)
    conflicts=preference_conflicts(db,user,s,body.normalized())
    return {'before':availability_value(row,s.revision),'after':body.normalized(),'base_revision':s.revision,
            'settings_version':body.expected_version,'affected_plan_count':len(conflicts),'affected_blocks':conflicts}


def preference_conflicts(db,user,s,payload):
    calendar=calendar_snapshot(db,user,s)
    from .occurrences import effective_courses
    courses=effective_courses(db,user,s)
    items=[{**i.payload,'id':i.id,'lifecycle':i.lifecycle} for i in db.scalars(select(StudyItem).where(StudyItem.user_id==user.id,StudyItem.semester_id==s.id))]
    plans=[block_value(b) for b in plan_rows(db,user,s.id)]
    context=calendar_context(calendar,{**payload,'configured':True},courses,items,utcnow())
    _,issues=classify(plans,items,context['free'].spans,context['begin'],obligation_points=context['obligation_points'])
    bad={i['block_id'] for i in issues}
    return [b for b in plans if b['id'] in bad]


@router.put('/semesters/{sid}/availability')
def put_availability(sid:str,body:AvailabilityApply,user:User=Depends(current_user),db:Session=Depends(get_db),
                     idempotency_key:str|None=Header(default=None)):
    s=owned_semester(db,user,sid,lock=True)
    data=body.model_dump(mode='json')
    operation='availability/'+sid
    cached=replay(db,user,operation,idempotency_key,data)
    if cached is not None:return cached
    s,row=validate_preferences(db,user,sid,body)
    if s.revision!=body.expected_revision:
        error(409,'SNAPSHOT_STALE','学期安排已变化，请重新核对学习时间')
    if preference_conflicts(db,user,s,body.normalized()) and not body.confirm_plan_conflicts:
        error(422,'CONFIRM_PLAN_CONFLICTS','新设置会使已有计划冲突，请明确确认；计划不会自动移动')
    before=availability_value(row,s.revision)
    now=utcnow().isoformat()
    if row is None:
        row=StudyAvailability(user_id=user.id,semester_id=sid,payload=body.normalized(),version=1,updated_at=now)
        db.add(row)
    else:
        row.payload=body.normalized();row.version+=1;row.updated_at=now
    s.revision+=1
    result=availability_value(row,s.revision)
    db.add(AvailabilityRevision(user_id=user.id,semester_id=sid,payload={'before':before,'after':result},created_at=now))
    remember(db,user,operation,idempotency_key,data,result)
    db.commit()
    return result


@router.get('/semesters/{sid}/risk')
def get_risk(sid:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    # All writers lock this semester. Copy one consistent view, release the short
    # database lock, then run calculations without holding a transaction open.
    s=owned_semester(db,user,sid,lock=True)
    revision=s.revision
    calendar=calendar_snapshot(db,user,s)
    preferences=availability_value(availability_row(db,user,sid),revision)
    from .occurrences import effective_courses
    courses=effective_courses(db,user,s)
    items=[{**r.payload,'id':r.id,'version':r.version,'lifecycle':r.lifecycle} for r in db.scalars(select(StudyItem).where(StudyItem.user_id==user.id,StudyItem.semester_id==sid).order_by(StudyItem.created_at,StudyItem.id))]
    plans=[block_value(b) for b in plan_rows(db,user,sid)]
    db.commit()
    return {**analyze(calendar,preferences,courses,items,utcnow(),plans),'semester_id':sid,'revision':revision,
            'settings_version':preferences['version']}


def progress_target(db,user,item_id,body):
    item=owned_item(db,user,item_id,lock=True)
    check_version(item,body.expected_version)
    if item.payload['kind']=='exam' or item.lifecycle!='active':
        error(422,'INVALID_PROGRESS','只能更新进行中的作业或个人任务')
    return item,owned_semester(db,user,item.semester_id)


@router.post('/items/{item_id}/progress/preview')
def preview_progress(item_id:str,body:ProgressInput,user:User=Depends(current_user),db:Session=Depends(get_db)):
    item,s=progress_target(db,user,item_id,body)
    blocks=preview_blocks(db,item,utcnow())
    return {'item_id':item.id,'item_version':item.version,'base_revision':s.revision,
            'before_remaining_minutes':item.payload.get('remaining_minutes'),'after_remaining_minutes':body.remaining_minutes,
            'actual_minutes':body.actual_minutes,'will_complete':body.remaining_minutes==0,'affected_plan_count':len(blocks),'affected_blocks':blocks}


@router.post('/items/{item_id}/progress')
def apply_progress(item_id:str,body:ProgressApply,user:User=Depends(current_user),db:Session=Depends(get_db),
                   idempotency_key:str|None=Header(default=None)):
    item=owned_item(db,user,item_id,lock=True)
    request=body.model_dump(mode='json');operation='progress/'+item_id
    cached=replay(db,user,operation,idempotency_key,request)
    if cached is not None:return cached
    item,s=progress_target(db,user,item_id,body)
    if s.revision!=body.expected_revision:
        error(409,'SNAPSHOT_STALE','预览后学期安排已变化，请重新核对进度')
    if (body.remaining_minutes==0)!=body.confirm_complete:
        error(422,'CONFIRM_COMPLETION','剩余为0时需明确确认完成并停用提醒')
    cancel_for_change(db,user,item,utcnow(),body.cancel_plan_ids,body.confirm_locked_cancellation,
        remaining=body.remaining_minutes,all_required=body.confirm_complete)
    before=item.payload.get('remaining_minutes')
    item.payload={**item.payload,'remaining_minutes':body.remaining_minutes}
    item.version+=1;item.updated_at=utcnow().isoformat()
    if body.confirm_complete:
        item.lifecycle='completed'
        for rule in rules_for(db,item):
            rule.payload={**rule.payload,'enabled':False};rule.version+=1;rule.updated_at=item.updated_at
    s.revision+=1
    db.add(ProgressEntry(user_id=user.id,item_id=item.id,payload={'before_remaining_minutes':before,
        'remaining_minutes':body.remaining_minutes,'actual_minutes':body.actual_minutes,'note':body.note,'item_version':item.version},created_at=item.updated_at))
    audit(db,item,'用户确认完成并更新进度' if body.confirm_complete else '用户更新剩余工作量')
    result=serialize_item(db,item)
    remember(db,user,operation,idempotency_key,request,result)
    db.commit()
    return result


@router.get('/items/{item_id}/progress')
def progress_history(item_id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    item=owned_item(db,user,item_id)
    return [{**r.payload,'created_at':r.created_at} for r in db.scalars(select(ProgressEntry).where(
        ProgressEntry.user_id==user.id,ProgressEntry.item_id==item.id).order_by(ProgressEntry.created_at,ProgressEntry.id))]
