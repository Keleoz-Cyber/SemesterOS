from copy import deepcopy
from fastapi import APIRouter,Depends,Request,HTTPException
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session
from .database import get_db
from .auth import current_user,error
from .models import OperationProposal,StudyItem,User,ProgressEntry
from .academics import owned_semester,fingerprint
from .items import owned_item,rules_for,serialize_item,serialize_rule,validate_rule,add_rule,audit
from .plan_store import preview_blocks,cancel_for_change
from .item_schemas import ReminderInput
from .reminder_rules import utcnow
from .capture import admission
from .operation_schemas import OperationParse,OperationResolve,OperationAction
from .operation_parser import PROMPT,validate_suggestion
from .text_model import deepseek_text
from .schedule_schemas import ScheduleInput,ReplanInput

router=APIRouter()


def source_guard(db,user,source,sid,lock=False):
    if not source:return
    from .media import owned_source,version
    row=owned_source(db,user,source['id'],lock)
    if row.semester_id!=sid:error(404,'NOT_FOUND','来源不属于当前学期')
    version(row,source['version'])


def eligible(db,user,sid,intent):
    rows=list(db.scalars(select(StudyItem).where(StudyItem.user_id==user.id,StudyItem.semester_id==sid,StudyItem.lifecycle=='active').order_by(StudyItem.id).limit(201)))
    if len(rows)>200:error(422,'INPUT_LIMIT','当前自然语言入口最多检索200条活跃事项，请使用事项详情的手工入口')
    return [r for r in rows if intent not in ('update_task','request_plan') or r.payload['kind']!='exam']


def choices(rows):
    return [{'id':r.id,'version':r.version,**{k:r.payload.get(k) for k in ('title','kind','course_title','time','remaining_minutes','splittable')}} for r in rows]


def own(db,user,id):
    p=db.scalar(select(OperationProposal).where(OperationProposal.id==id,OperationProposal.user_id==user.id))
    if p is None:error(404,'NOT_FOUND','找不到这条修改请求')
    s=owned_semester(db,user,p.semester_id,lock=True);db.refresh(p)
    return p,s


def dependencies(db,user,p,s):
    selected=p.payload.get('selection',{});intent=p.payload['suggestion']['intent']
    ids=[selected['target_item_id']] if selected.get('target_item_id') else [t['item_id'] for t in selected.get('tasks',[])]
    rows=[]
    for id in ids:
        item=owned_item(db,user,id)
        rows.append({'id':id,'version':item.version,'lifecycle':item.lifecycle,
            'rules':[{'id':r.id,'version':r.version,'payload':r.payload} for r in rules_for(db,item)] if intent=='update_reminder' else []})
    return fingerprint({'revision':s.revision if intent!='update_reminder' else None,'targets':rows})


def output(db,user,p,s):
    phase=p.phase
    if phase=='ready':
        try:
            source_guard(db,user,p.payload.get('source'),s.id)
            if dependencies(db,user,p,s)!=p.payload.get('dependency'):phase='stale'
        except HTTPException:phase='stale'
    return {'id':p.id,'semester_id':p.semester_id,'version':p.version,'phase':phase,'base_revision':p.base_revision,
        'source_text':p.source_text,'reference_at':p.reference_at,'created_at':p.created_at,'receipt':p.receipt,**p.payload}


def prepare(db,user,p,s,selection):
    data=deepcopy(p.payload);suggestion=data['suggestion'];intent=suggestion['intent']
    source_guard(db,user,data.get('source'),s.id,True)
    if data.get('source',{}).get('kind')=='image' and not selection.confirm_direct_request:
        error(422,'DIRECT_REQUEST_REQUIRED','请先勾选确认：你希望按图片中的内容修改自己的安排')
    if intent in ('clarify','unsupported'):error(422,'UNSUPPORTED_OPERATION','请重新描述修改请求，或使用对应的手工入口')
    selected=selection.model_dump(mode='json');preview={'intent':intent,'affected_blocks':[]}
    if intent=='request_plan':
        if not selection.tasks:error(422,'CHOOSE_TASKS','请先选择任务，并确认每项还需要多久')
        tasks=[]
        for target in selection.tasks:
            item=owned_item(db,user,target.item_id)
            if item.semester_id!=s.id or item.lifecycle!='active' or item.payload['kind']=='exam':error(422,'INVALID_TARGET','只能选择本学期活跃的个人任务或作业')
            if item.payload.get('remaining_minutes') is None or item.payload.get('start_policy','unconfirmed')=='unconfirmed':error(422,'PLAN_INPUT_INCOMPLETE','请先到任务详情填写还需要多久，以及最早什么时候能开始')
            if target.target_minutes is not None and target.target_minutes>item.payload['remaining_minutes']:error(422,'TARGET_EXCEEDS_WORK','安排时长不能超过任务还需要的时间。如果工作增加了，请先更新任务进度')
            tasks.append(serialize_item(db,item))
        mode=selection.plan_mode or suggestion['plan_mode'];selected['plan_mode']=mode
        if mode=='replan':
            if selection.window_start_at or selection.window_end_at or (suggestion['needs_window'] and not selection.use_default_window):
                error(422,'REPLAN_WINDOW_UNSUPPORTED','调整已有计划会使用你设置的学习时间。想指定新时段，请改选“安排还没排好的任务”')
            request=ReplanInput(task_ids=[i['id'] for i in tasks],lead_minutes=selection.lead_minutes).model_dump(mode='json')
        else:
            if suggestion['needs_window'] and not selection.window_start_at and not selection.use_default_window:error(422,'CHOOSE_WINDOW','请选择开始和结束时间，或勾选使用已设置的学习时间')
            try:request=ScheduleInput(days=selection.days,chunk_minutes=selection.chunk_minutes,lead_minutes=selection.lead_minutes,tasks=selection.tasks,
                window_start_at=selection.window_start_at,window_end_at=selection.window_end_at).model_dump(mode='json')
            except ValidationError:error(422,'INVALID_WINDOW','请检查任务时长、开始和结束时间，安排范围不能超过28天')
        preview.update(tasks=tasks,planning_request=request)
    else:
        if not selection.target_item_id:error(422,'CHOOSE_TARGET','请明确选择要修改的事项')
        item=owned_item(db,user,selection.target_item_id)
        if item.semester_id!=s.id or item.lifecycle!='active':error(422,'INVALID_TARGET','请选择当前学期的活跃事项')
        before=serialize_item(db,item);preview['before']=before
        if intent=='update_task':
            if item.payload['kind']=='exam':error(422,'AUTHORITATIVE_ITEM','考试安排不能通过个人任务修改入口改变')
            patch=selection.task_patch.model_dump(mode='json',exclude_none=True) if selection.task_patch else {k:v for k,v in suggestion['task_patch'].items() if v is not None}
            patch={k:v for k,v in patch.items() if item.payload.get(k)!=v}
            if not patch:error(422,'NO_CHANGES','请补全需要修改的标题、剩余分钟或拆分设置')
            preview.update(after={**before,**patch},task_patch=patch)
            if 'remaining_minutes' in patch or 'splittable' in patch:
                preview['affected_blocks']=preview_blocks(db,item,utcnow())
        else:
            action=selection.reminder_action or suggestion['reminder_action'];selected['reminder_action']=action
            rules=rules_for(db,item);rule=None
            if action!='add':
                if selection.reminder_id:rule=next((r for r in rules if r.id==selection.reminder_id),None)
                elif len(rules)==1:rule=rules[0]
                if rule is None:error(422,'CHOOSE_REMINDER','请选择一条已有提醒；没有提醒时可明确改为新增')
                selected['reminder_id']=rule.id
            payload=deepcopy(rule.payload) if rule else {'purpose':'item','enabled':True}
            if action=='disable':payload['enabled']=False
            elif selection.reminder:
                if selection.expected_item_version!=item.version or (rule is not None and selection.expected_reminder_version!=rule.version):
                    error(409,'REMINDER_EDITOR_STALE','提醒或事项已有更新，请刷新后重新设置')
                payload=selection.reminder.model_dump(mode='json')
            else:
                requested=suggestion['reminder_patch']
                if (requested['mode']=='absolute' and requested['trigger_at'] is None) or (requested['mode']=='relative' and requested['lead_minutes'] is None):
                    error(422,'REMINDER_INCOMPLETE','请设置新的提醒时间，或填写希望提前多久提醒')
                payload.update({k:v for k,v in suggestion['reminder_patch'].items() if v is not None})
                if payload.get('mode')=='absolute':payload['lead_minutes']=None
                if payload.get('mode')=='relative':payload['trigger_at']=None
            try:payload=ReminderInput.model_validate(payload).model_dump(mode='json')
            except ValidationError:error(422,'REMINDER_INCOMPLETE','请明确提醒模式、提前量或具体时刻')
            if action=='add' and len(rules)>=20:error(422,'LIMIT_REACHED','每条事项最多20条提醒')
            validate_rule(db,item,payload,skip=rule.id if rule else None)
            if rule and rule.payload==payload:error(422,'NO_CHANGES','这条提醒没有变化。你可以调整时间、用途，或关闭提醒')
            from types import SimpleNamespace
            after=serialize_rule(SimpleNamespace(id=rule.id if rule else 'new',version=rule.version if rule else 0,payload=payload),item)
            preview.update(reminder_action=action,reminder_before=serialize_rule(rule,item,rules) if rule else None,reminder_after=after,reminder_payload=payload)
    data.update(selection=selected,preview=preview);p.payload=data;p.base_revision=s.revision;p.phase='ready'
    p.payload={**data,'dependency':dependencies(db,user,p,s)}


@router.post('/operations/parse',status_code=201)
def parse_operation(body:OperationParse,request:Request,user:User=Depends(current_user),db:Session=Depends(get_db)):
    s=owned_semester(db,user,body.semester_id);source=None
    if body.context_item_id:
        context=owned_item(db,user,body.context_item_id)
        if context.semester_id!=s.id:error(404,'NOT_FOUND','事项不属于当前学期')
    if body.source_id:
        from .media import owned_source,version
        origin=owned_source(db,user,body.source_id);version(origin,body.source_version)
        if origin.semester_id!=s.id:error(404,'NOT_FOUND','来源不属于当前学期')
        if origin.status in ('queued','running') or origin.text!=body.text or origin.reference_at!=body.reference_at.isoformat():
            error(409,'SOURCE_STALE','请先在来源页保存并核对当前文稿，或明确移除媒体关联后重新描述修改')
        source={'id':origin.id,'version':origin.version,'kind':origin.kind,'original_text':origin.original_text,'reviewed_text':origin.text}
    admission(request,user)
    model=getattr(request.app.state,'operation_model',None)
    raw,metadata=model(body.text,body.reference_at.isoformat(),[]) if model else deepseek_text(body.text,body.reference_at.isoformat(),[],system_prompt=PROMPT,prompt_version='operation-v2')
    suggestion=validate_suggestion(raw,body.text)
    db.expire_all();s=owned_semester(db,user,body.semester_id,lock=True);source_guard(db,user,source,s.id,True)
    rows=eligible(db,user,s.id,suggestion['intent']);q=''.join(suggestion['target_query'].casefold().split()).strip('“”"\'')
    matches=[r for r in rows if q and any(q in ''.join(str(r.payload.get(k,'')).casefold().split()) for k in ('title','course_title'))]
    if not q and body.context_item_id:matches=[r for r in rows if r.id==body.context_item_id]
    data={'suggestion':suggestion,'choices':choices(matches or rows),'suggested_target_id':matches[0].id if len(matches)==1 else None,'metadata':{**metadata,'schema_version':'operation-v1'}}
    if source:data['source']=source
    p=OperationProposal(user_id=user.id,semester_id=s.id,base_revision=s.revision,source_text=body.text,reference_at=body.reference_at.isoformat(),payload=data,created_at=utcnow().isoformat())
    db.add(p);db.flush()
    if len(matches)==1 and suggestion['intent'] in ('update_task','update_reminder') and not (source and source['kind']=='image'):
        try:prepare(db,user,p,s,OperationResolve(expected_version=1,target_item_id=matches[0].id))
        except HTTPException as exc:
            if exc.status_code!=422:raise
            p.payload={**data,'clarification':exc.detail['message']}
    result=output(db,user,p,s);db.commit();return result


@router.get('/semesters/{sid}/operations')
def list_operations(sid:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    s=owned_semester(db,user,sid,lock=True)
    return [output(db,user,p,s) for p in db.scalars(select(OperationProposal).where(OperationProposal.user_id==user.id,OperationProposal.semester_id==sid).order_by(OperationProposal.created_at.desc()).limit(50))]


@router.get('/operations/{id}')
def get_operation(id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    p,s=own(db,user,id);return output(db,user,p,s)


@router.post('/operations/{id}/resolve')
def resolve(id:str,body:OperationResolve,user:User=Depends(current_user),db:Session=Depends(get_db)):
    p,s=own(db,user,id)
    if p.phase in ('applied','rejected') or p.version!=body.expected_version:error(409,'OPERATION_STALE','请求已变化，请重新打开')
    prepare(db,user,p,s,body);p.version+=1;result=output(db,user,p,s);db.commit();return result


@router.post('/operations/{id}/reject')
def reject(id:str,body:OperationAction,user:User=Depends(current_user),db:Session=Depends(get_db)):
    p,s=own(db,user,id)
    if p.phase=='rejected':return output(db,user,p,s)
    if p.phase=='applied' or p.version!=body.expected_version:error(409,'OPERATION_STALE','这次修改已经保存。如果还想调整，请发起一次新的修改')
    p.phase='rejected';p.version+=1;db.commit();return output(db,user,p,s)


@router.post('/operations/{id}/apply')
def apply(id:str,body:OperationAction,user:User=Depends(current_user),db:Session=Depends(get_db)):
    p,_=own(db,user,id)
    if p.payload.get('agent_run_id'):
        error(409,'AGENT_CONFIRMATION_REQUIRED','请在日程助手中核对并确认这次修改')
    result=apply_command(db,user,id,body)
    db.commit()
    return result


def apply_command(db,user,id,body):
    p,s=own(db,user,id)
    if p.phase=='applied':return p.receipt
    if p.phase!='ready' or p.version!=body.expected_version or output(db,user,p,s)['phase']!='ready':error(409,'OPERATION_STALE','事项、提醒或安排已有变化，请重新核对')
    source_guard(db,user,p.payload.get('source'),s.id,True)
    preview=p.payload['preview'];intent=preview['intent'];changed=[];now=utcnow();planning=None
    if intent=='request_plan':
        if body.cancel_plan_ids:error(422,'INVALID_OPERATION','规划请求不直接取消时间块')
        planning=preview['planning_request']
    else:
        item=owned_item(db,user,p.payload['selection']['target_item_id'])
        if intent=='update_task':
            patch=preview['task_patch']
            if not set(body.cancel_plan_ids).issubset({b['id'] for b in preview['affected_blocks']}):error(422,'INVALID_PLAN_SELECTION','不能取消未在本次预览中列出的计划')
            cancel_for_change(db,user,item,now,body.cancel_plan_ids,body.confirm_locked_cancellation,remaining=patch.get('remaining_minutes'))
            remaining_blocks=preview_blocks(db,item,now)
            if patch.get('splittable') is False and len(remaining_blocks)>1:error(422,'SPLIT_CONFLICT','改为不可拆分前，请明确取消多余未来块或保留原设置')
            old_remaining=item.payload.get('remaining_minutes');item.payload={**item.payload,**patch};item.version+=1;item.updated_at=now.isoformat();s.revision+=1
            if 'remaining_minutes' in patch:db.add(ProgressEntry(user_id=user.id,item_id=item.id,payload={'before_remaining_minutes':old_remaining,
                'remaining_minutes':patch['remaining_minutes'],'actual_minutes':None,'note':p.source_text[:500],'item_version':item.version},created_at=item.updated_at))
        else:
            if body.cancel_plan_ids:error(422,'INVALID_OPERATION','修改提醒不取消个人计划')
            payload=preview['reminder_payload'];action=preview['reminder_action']
            if action=='add':add_rule(db,item,payload)
            else:
                rule=next(r for r in rules_for(db,item) if r.id==p.payload['selection']['reminder_id'])
                validate_rule(db,item,payload,skip=rule.id);rule.payload=payload;rule.version+=1;rule.updated_at=now.isoformat()
        audit(db,item,('自然语言修改：'+p.source_text)[:500]);changed=[serialize_item(db,item)]
    p.phase='applied';p.version+=1
    p.receipt={'operation_id':p.id,'operation_version':p.version,'semester_id':s.id,'revision':s.revision,'changed_items':changed,'planning_request':planning}
    return p.receipt
