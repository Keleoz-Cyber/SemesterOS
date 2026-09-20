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
    if any(instant(e['start_at'])<=now for e in before):error(422,'PAST_OCCURRENCE','仅支持尚未开始的课次，请核对原日期')
    after=[]
    if data['kind'] in ('move','add','block'):
        a,b=instant(data['start_at']),instant(data['end_at'])
        begin=local_day(calendar['first_monday']);end=begin+timedelta(weeks=calendar['total_weeks'])
        if a<=now or a<begin or b>end:error(422,'OUTSIDE_SEMESTER','新安排必须在本学期未来时间内')
        if a.astimezone(SHANGHAI).date()!=(b-timedelta(microseconds=1)).astimezone(SHANGHAI).date():
            error(422,'CROSS_DAY_EVENT','跨天固定安排请按日期分条记录，放假停课请明确选择受影响课次')
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
    _,issues=classify(source[4],source[3],c['free'].spans,c['begin']);bad={i['block_id'] for i in issues}
    return {'affected_blocks':[b for b in source[4] if b['id'] in bad],'risk_changes':deltas,
        'before_summary':before['summary'],'after_summary':after['summary'],'fixed_conflicts':after['fixed_conflicts']}


def value(row,s):
    return {'id':row.id,'semester_id':row.semester_id,'base_revision':row.base_revision,
        'phase':'applied' if row.receipt else 'stale' if s.revision!=row.base_revision else 'ready',
        **row.payload,'receipt':row.receipt,'created_at':row.created_at}


@router.get('/semesters/{sid}/changes')
def list_changes(sid:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    s=owned_semester(db,user,sid,lock=True)
    return {'revision':s.revision,'changes':[value(r,s) for r in db.scalars(select(RealityChange).where(
        RealityChange.user_id==user.id,RealityChange.semester_id==sid).order_by(RealityChange.created_at.desc()).limit(50))],
        'occurrences':[e for e in expand({'first_monday':s.first_monday,'periods':s.periods},effective_courses(db,user,s)) if instant(e['start_at'])>utcnow()]}


@router.post('/semesters/{sid}/changes',status_code=201)
def preview_change(sid:str,body:ChangeInput,user:User=Depends(current_user),db:Session=Depends(get_db),idempotency_key:str|None=Header(default=None)):
    s=owned_semester(db,user,sid,lock=True);data=body.model_dump(mode='json');op='preview-change/'+sid
    if body.source_id:
        from .media import owned_source
        if owned_source(db,user,body.source_id).semester_id!=sid:error(404,'NOT_FOUND','来源不属于当前学期')
    cached=replay(db,user,op,idempotency_key,data)
    if cached is not None:return cached
    now=utcnow();source=source_snapshot(db,user,s);patch=make_patch(source,data,now)
    row=RealityChange(user_id=user.id,semester_id=sid,base_revision=s.revision,
        payload={'request':data,'patch':patch,'impact':impact(source,patch,now)},created_at=now.isoformat())
    db.add(row);db.flush();result=value(row,s);remember(db,user,op,idempotency_key,data,result);db.commit();return result


@router.post('/changes/{id}/apply')
def apply_change(id:str,body:ChangeApply,user:User=Depends(current_user),db:Session=Depends(get_db)):
    row=db.scalar(select(RealityChange).where(RealityChange.id==id,RealityChange.user_id==user.id))
    if row is None:error(404,'NOT_FOUND','找不到变化预览')
    s=owned_semester(db,user,row.semester_id,lock=True);db.refresh(row)
    if row.receipt:return row.receipt
    if s.revision!=body.expected_revision or row.base_revision!=s.revision:error(409,'SNAPSHOT_STALE','预览后安排已变化，请重新核对')
    source=source_snapshot(db,user,s);now=utcnow()
    make_patch(source,row.payload['request'],now)
    current=impact(source,row.payload['patch'],now)
    if current['after_summary']['fixed_conflict_count'] and not body.confirm_fixed_conflicts:
        error(422,'CONFIRM_FIXED_CONFLICTS','学校固定安排存在冲突，需明确确认记录现实情况')
    s.revision+=1;row.applied_revision=s.revision
    row.receipt={'change_id':row.id,'semester_id':s.id,'revision':s.revision,'impact':current}
    db.commit();return row.receipt
