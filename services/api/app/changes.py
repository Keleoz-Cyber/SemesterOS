from datetime import timedelta
from copy import deepcopy
from fastapi import APIRouter,Depends,Header
from sqlalchemy import select
from sqlalchemy.orm import Session
from .academics import owned_semester,replay,remember
from .auth import current_user,error
from .database import get_db
from .models import RealityChange,User,new_id
from .change_schemas import ChangeInput,ChangeApply
from .occurrences import expand,apply_patch,effective_courses
from .capacity import analyze,local_day
from .reminder_rules import utcnow,instant,SHANGHAI

router=APIRouter()


def source_snapshot(db,user,s):
    from .schedule_api import snapshot
    return snapshot(db,user,s)


def make_patch(source,data,now):
    calendar=source[0];events=expand(calendar,source[2]);by_id={e['id']:e for e in events}
    if not set(data['targets']).issubset(by_id):error(409,'TARGET_STALE','课次已改变或不属于本学期，请重新选择')
    before=[deepcopy(by_id[id]) for id in data['targets']]
    after=[]
    if data['kind'] in ('move','add','block'):
        a,b=instant(data['start_at']),instant(data['end_at'])
        begin=local_day(calendar['first_monday']);end=begin+timedelta(weeks=calendar['total_weeks'])
        if a<begin or b>end:error(422,'OUTSIDE_SEMESTER','新安排的日期需在当前学期内')
        e=deepcopy(before[0]) if before else {'id':'extra:'+new_id(),'course_id':None,'teacher':'','sections':[],'weeks':[],
            'weekday':a.isoweekday(),'source_batch_id':None,'reality_kind':'activity' if data['kind']=='block' else 'course'}
        e.update(title=data['title'],start_at=a.astimezone(SHANGHAI).isoformat(),end_at=b.astimezone(SHANGHAI).isoformat(),
            location=data['location'],changed=True,weekday=a.astimezone(SHANGHAI).isoweekday(),sections=[],weeks=[])
        after=[e]
    return {'before':before,'after':after}


def impact(source,patch,now):
    before=analyze(*source[:4],now,source[4]);changed=[{'occurrences':apply_patch(expand(source[0],source[2]),patch)}]
    after=analyze(source[0],source[1],changed,source[3],now,source[4])
    a={r['item_id']:r for r in before['items']};deltas=[]
    for row in after['items']:
        old=a.get(row['item_id'],{})
        if old.get('task_slack_minutes')!=row['task_slack_minutes'] or old.get('level')!=row['level']:
            deltas.append({'item_id':row['item_id'],'title':row['title'],'before_slack':old.get('task_slack_minutes'),
                'after_slack':row['task_slack_minutes'],'before_level':old.get('level'),'after_level':row['level']})
    # Full issues from classify, not the truncated risk details.
    from .capacity import calendar_context
    from .plan_rules import classify
    c=calendar_context(source[0],source[1],changed,source[3],now)
    old_context=calendar_context(*source[:4],now)
    from .conflict_changes import introduced_conflicts
    _,issues=classify(source[4],source[3],c['free'].spans,c['begin']);bad={i['block_id'] for i in issues}
    return {'affected_blocks':[b for b in source[4] if b['id'] in bad],'risk_changes':deltas,
        'before_summary':before['summary'],'after_summary':after['summary'],'fixed_conflicts':c['conflicts'],
        'new_fixed_conflicts':introduced_conflicts(old_context['conflicts'],c['conflicts'])}


def value(row,s):
    return {'id':row.id,'semester_id':row.semester_id,'base_revision':row.base_revision,
        'phase':'applied' if row.receipt else 'stale' if s.revision!=row.base_revision or row.payload.get('agent_invalidated') else 'ready',
        **row.payload,'receipt':row.receipt,'created_at':row.created_at}


@router.get('/semesters/{sid}/changes')
def list_changes(sid:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    s=owned_semester(db,user,sid,lock=True)
    return {'revision':s.revision,'changes':[value(r,s) for r in db.scalars(select(RealityChange).where(
        RealityChange.user_id==user.id,RealityChange.semester_id==sid).order_by(RealityChange.created_at.desc()).limit(50))],
        'occurrences':expand({'first_monday':s.first_monday,'periods':s.periods},effective_courses(db,user,s))}


@router.post('/semesters/{sid}/changes',status_code=201)
def preview_change(sid:str,body:ChangeInput,user:User=Depends(current_user),db:Session=Depends(get_db),idempotency_key:str|None=Header(default=None)):
    result=preview_change_command(db,user,sid,body,idempotency_key)
    db.commit();return result


def preview_change_command(db,user,sid,body,idempotency_key=None,*,agent_run_id=None):
    s=owned_semester(db,user,sid,lock=True);data=body.model_dump(mode='json');op='preview-change/'+sid
    if body.source_id:
        from .media import owned_source
        if owned_source(db,user,body.source_id).semester_id!=sid:error(404,'NOT_FOUND','来源不属于当前学期')
    cached=replay(db,user,op,idempotency_key,data)
    if cached is not None:return cached
    now=utcnow();source=source_snapshot(db,user,s);patch=make_patch(source,data,now)
    row=RealityChange(user_id=user.id,semester_id=sid,base_revision=s.revision,
        payload={'request':data,'patch':patch,'impact':impact(source,patch,now),
            'base_calendar':{'first_monday':s.first_monday},
            **({'agent_run_id':agent_run_id} if agent_run_id else {})},created_at=now.isoformat())
    db.add(row);db.flush();result=value(row,s);remember(db,user,op,idempotency_key,data,result);return result


@router.post('/changes/{id}/apply')
def apply_change(id:str,body:ChangeApply,user:User=Depends(current_user),db:Session=Depends(get_db)):
    result=apply_change_command(db,user,id,body)
    db.commit();return result


def apply_change_command(db,user,id,body,*,agent_run_id=None,prepared_base_revision=None):
    row=db.scalar(select(RealityChange).where(RealityChange.id==id,RealityChange.user_id==user.id))
    if row is None:error(404,'NOT_FOUND','找不到变化预览')
    s=owned_semester(db,user,row.semester_id,lock=True);db.refresh(row)
    if row.payload.get('agent_run_id') != agent_run_id:
        error(409,'AGENT_CONFIRMATION_REQUIRED','请在助手中的当前预览确认这次变更')
    if row.payload.get('agent_invalidated'):error(409,'PREVIEW_STALE','这份变化预览已失效，请重新核对')
    if row.receipt:return row.receipt
    if s.revision!=body.expected_revision or row.base_revision!=(s.revision if prepared_base_revision is None else prepared_base_revision):error(409,'SNAPSHOT_STALE','预览后安排已变化，请重新核对')
    source=source_snapshot(db,user,s);now=utcnow()
    make_patch(source,row.payload['request'],now)
    current=impact(source,row.payload['patch'],now)
    if current['new_fixed_conflicts'] and not body.confirm_fixed_conflicts:
        error(422,'CONFIRM_FIXED_CONFLICTS','修改后新增了时间冲突，请核对后保存')
    s.revision+=1;row.applied_revision=s.revision
    row.receipt={'change_id':row.id,'semester_id':s.id,'revision':s.revision,'impact':current}
    return row.receipt
