from copy import deepcopy
from fastapi import APIRouter,Depends,Header
from sqlalchemy import select
from sqlalchemy.orm import Session
from pydantic import ValidationError
from .database import get_db
from .models import StudyItem,User,CourseMeeting
from .auth import current_user,error
from .academics import owned_semester,replay,remember,fingerprint
from .items import owned_item,check_version,serialize_item,audit,rules_for,serialize_rule
from .item_schemas import ItemFields,ItemTime
from .exam_schemas import ReviewInput,ExamChangeInput,ExamChangeApply
from .reminder_rules import utcnow,anchor_at,notice_arrival_at
from .capacity import analyze,calendar_context
from .plan_rules import classify

router=APIRouter()


def owned_exam(db,user,id):
    e=owned_item(db,user,id,lock=True)
    if e.payload['kind']!='exam':error(422,'NOT_EXAM','这条事项不是考试')
    return e


def reviews(db,user,e):
    return [r for r in db.scalars(select(StudyItem).where(StudyItem.user_id==user.id,StudyItem.semester_id==e.semester_id))
        if r.payload.get('review_exam_id')==e.id]


def update_payload(db,item,data,reason,now):
    changed=item.payload['time']!=data['time'];item.payload=data;item.version+=1;item.updated_at=now.isoformat()
    if changed:
        for rule in rules_for(db,item):rule.version+=1;rule.updated_at=item.updated_at
    audit(db,item,reason)


@router.post('/exams/{id}/reviews',status_code=201)
def create_review(id:str,body:ReviewInput,user:User=Depends(current_user),db:Session=Depends(get_db),idempotency_key:str|None=Header(default=None)):
    e=owned_exam(db,user,id);data=body.model_dump(mode='json');op='exam-review/'+id
    cached=replay(db,user,op,idempotency_key,data)
    if cached is not None:return cached
    check_version(e,body.expected_exam_version)
    if e.lifecycle!='active':error(422,'INACTIVE_EXAM','已取消的考试不能新增复习，请先核对考试状态')
    if any(r.lifecycle=='active' for r in reviews(db,user,e)):error(409,'REVIEW_EXISTS','已有未完成复习任务，请更新它的进度或工作量')
    s=owned_semester(db,user,e.semester_id);now=utcnow()
    if body.task_id:
        task=owned_item(db,user,body.task_id)
        check_version(task,body.expected_task_version)
        if task.semester_id!=s.id or task.payload['kind']!='task' or task.lifecycle!='active' or task.payload.get('review_exam_id'):
            error(422,'INVALID_REVIEW_TASK','请选择本学期尚未关联考试的活跃个人任务')
        task.payload={**task.payload,'review_exam_id':e.id};task.version+=1;task.updated_at=now.isoformat()
        audit(db,task,'用户关联考试复习：'+e.payload['title'])
    else:
        due=anchor_at(e.payload)
        if body.deadline_mode=='exam' and (not due or e.payload['certainty']!='formal' or e.payload['time']['precision']!='exact'):
            error(422,'EXAM_TIME_UNKNOWN','考试正式开始时间未明确，请选择自定义复习截止或保持待确认')
        at=due if body.deadline_mode=='exam' else body.deadline_at
        fields=ItemFields(semester_id=s.id,kind='task',title=e.payload['title'][:115]+'复习',course_id=e.payload.get('course_id'),
            time={'precision':'exact','at':at} if at else {'precision':'unknown'},certainty='formal' if at else 'unknown',
            remaining_minutes=body.remaining_minutes,start_policy=body.start_policy)
        payload={**fields.model_dump(mode='json'),'course_title':e.payload.get('course_title',''),'review_exam_id':e.id}
        task=StudyItem(user_id=user.id,semester_id=s.id,payload=payload,created_at=now.isoformat(),updated_at=now.isoformat())
        db.add(task);db.flush();audit(db,task,'用户确认考试复习目标')
    s.revision+=1;result=serialize_item(db,task);remember(db,user,op,idempotency_key,data,result);db.commit();return result


def exam_change_context(db,user,e,body):
    from .schedule_api import snapshot
    check_version(e,body.expected_version)
    if e.lifecycle!='active':error(422,'INACTIVE_EXAM','请先核对考试状态')
    s=owned_semester(db,user,e.semester_id);source=snapshot(db,user,s);now=utcnow()
    updated={**e.payload,'time':body.time.model_dump(mode='json'),'certainty':body.certainty,'location':body.location,'reserve_time':body.reserve_time}
    if body.details is not None:
        updated['details']={**e.payload.get('details',{}),
                            **body.details.model_dump(mode='json',exclude_unset=True)}
    for key in ('title','notes'):
        if getattr(body,key) is not None:updated[key]=getattr(body,key)
    if 'course_id' in body.model_fields_set:
        updated.update(course_id=body.course_id,course_title='')
        if body.course_id:
            course=db.scalar(select(CourseMeeting).where(CourseMeeting.id==body.course_id,CourseMeeting.user_id==user.id,CourseMeeting.semester_id==s.id))
            if course is None:error(422,'INVALID_COURSE','关联课程不属于当前账号和学期')
            updated['course_title']=course.payload['title']
    fields={k:v for k,v in updated.items() if k in ItemFields.model_fields}
    try:ItemFields.model_validate(fields)
    except ValidationError:error(422,'INVALID_EXAM','请检查考试日期、开始和结束时间，确认是否已正式通知')
    if body.time.week and body.time.week>s.total_weeks:error(422,'INVALID_WEEK','周次超出当前学期')
    active=[r for r in reviews(db,user,e) if r.lifecycle=='active']
    after_tasks={}
    if body.align_review_deadlines:
        due=anchor_at(updated)
        if not due or updated['certainty']!='formal' or updated['time']['precision']!='exact':
            error(422,'EXAM_TIME_UNKNOWN','只有正式明确的考试开始时刻才能同步复习截止')
        for r in active:after_tasks[r.id]={**r.payload,'time':ItemTime(precision='exact',at=due).model_dump(mode='json'),'certainty':'formal'}
    after=deepcopy(source[3])
    for i,row in enumerate(after):
        if row['id']==e.id:after[i]={**row,**updated}
        elif row['id'] in after_tasks:after[i]={**row,**after_tasks[row['id']]}
    c=calendar_context(*source[:3],after,now);_,issues=classify(source[4],after,c['free'].spans,c['begin'])
    before_context=calendar_context(*source[:4],now)
    from .conflict_changes import introduced_conflicts
    new_conflicts=introduced_conflicts(before_context['conflicts'],c['conflicts'])
    ids={r['block_id'] for r in issues}
    before_risk=analyze(*source[:4],now,source[4]);after_risk=analyze(*source[:3],after,now,source[4])
    old={r['item_id']:r for r in before_risk['items']}
    risk_changes=[{'title':r['title'],'item_id':r['item_id'],'before_slack':old[r['item_id']]['task_slack_minutes'],'after_slack':r['task_slack_minutes']}
        for r in after_risk['items'] if (r['task_slack_minutes'],r['level'])!=(old[r['item_id']]['task_slack_minutes'],old[r['item_id']]['level'])]
    from types import SimpleNamespace
    preview_item=SimpleNamespace(payload=updated,lifecycle=e.lifecycle,id=e.id,version=e.version,semester_id=e.semester_id)
    peers=rules_for(db,e)
    changed_reminders=[serialize_rule(r,preview_item,peers) for r in peers]
    review_reminders=[]
    dependencies=[{'item_id':e.id,'rules':[{'id':r.id,'version':r.version,'payload':r.payload} for r in peers]}]
    for task in active:
        task_rules=rules_for(db,task)
        dependencies.append({'item_id':task.id,'rules':[{'id':r.id,'version':r.version,'payload':r.payload} for r in task_rules]})
        view=SimpleNamespace(payload=after_tasks.get(task.id,task.payload),lifecycle=task.lifecycle,id=task.id,version=task.version,semester_id=task.semester_id)
        review_reminders.extend(serialize_rule(r,view,task_rules) for r in task_rules)
    token=fingerprint({'revision':s.revision,'exam_version':e.version,'payload_after':updated,'request':body.model_dump(mode='json',include=set(ExamChangeInput.model_fields)),
        'reminder_dependencies':sorted(dependencies,key=lambda r:r['item_id'])})
    arrival=notice_arrival_at(updated)
    result={'base_revision':s.revision,'item_version':e.version,'before':serialize_item(db,e),
        'preview_token':token,
        'after':{**serialize_item(db,e),**updated,'anchor_at':anchor_at(updated).isoformat() if anchor_at(updated) else None,
            'arrival_at':arrival.isoformat() if arrival else None,'reminders':changed_reminders},
        'reminders_after':changed_reminders,'review_reminders_after':review_reminders,
        'reviews':[{'id':r.id,'title':r.payload['title'],'version':r.version,'before_time':r.payload['time'],
            'after_time':after_tasks.get(r.id,r.payload)['time'],'will_align':r.id in after_tasks} for r in active],
        'affected_blocks':[b for b in source[4] if b['id'] in ids],'risk_changes':risk_changes,
        'fixed_conflicts':c['conflicts'],'fixed_conflict_count':len(c['conflicts']),
        'new_fixed_conflicts':new_conflicts,'new_fixed_conflict_count':len(new_conflicts)}
    return s,updated,after_tasks,result,now


@router.post('/exams/{id}/reschedule/preview')
def preview_exam(id:str,body:ExamChangeInput,user:User=Depends(current_user),db:Session=Depends(get_db)):
    e=owned_exam(db,user,id)
    return exam_change_context(db,user,e,body)[3]


@router.post('/exams/{id}/reschedule')
def apply_exam(id:str,body:ExamChangeApply,user:User=Depends(current_user),db:Session=Depends(get_db),idempotency_key:str|None=Header(default=None)):
    result=apply_exam_command(db,user,id,body,idempotency_key)
    db.commit();return result


def apply_exam_command(db,user,id,body,idempotency_key=None):
    e=owned_exam(db,user,id);data=body.model_dump(mode='json');op='exam-change/'+id
    cached=replay(db,user,op,idempotency_key,data)
    if cached is not None:return cached
    s,updated,tasks,preview,now=exam_change_context(db,user,e,body)
    if s.revision!=body.expected_revision:error(409,'SNAPSHOT_STALE','核对后学期安排已变化，请重新预览')
    if preview['preview_token']!=body.preview_token:error(409,'PREVIEW_STALE','核对后提醒或输入已变化，请重新预览考试影响')
    if preview['new_fixed_conflict_count'] and not body.confirm_fixed_conflicts:error(422,'CONFIRM_FIXED_CONFLICTS','修改后新增了时间冲突，请核对后保存')
    update_payload(db,e,updated,body.reason,now)
    for task_id,payload in tasks.items():update_payload(db,owned_item(db,user,task_id),payload,('用户随考试改期同步复习截止：'+body.reason)[:500],now)
    s.revision+=1
    result={'semester_id':s.id,'revision':s.revision,'item':serialize_item(db,e),
        'changed_items':[serialize_item(db,e)]+[serialize_item(db,owned_item(db,user,id)) for id in tasks],'impact':preview}
    remember(db,user,op,idempotency_key,data,result);return result
