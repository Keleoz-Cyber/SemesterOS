"""Small typed tool surface. All identity and revision values come from the server."""
from copy import deepcopy
from collections import Counter
from datetime import date, timedelta
from typing import Literal
from pydantic import Field, model_validator
from sqlalchemy import select
from .schemas import Input
from .academics import owned_semester, fingerprint
from .auth import error
from .models import StudyItem, CourseMeeting
from .event_schemas import EventFields, EventEdit, EventCancel
from .item_schemas import ItemCreate, ItemTime, ReminderInput
from . import calendar_events as events
from .event_store import event_rows, event_value, CATEGORIES
from .items import serialize_item, create_item_command
from .capacity import local_day, merge, subtract, iso
from .reminder_rules import instant
from .operation_schemas import TaskPatch, OperationSuggestion, OperationResolve, OperationAction


class Range(Input):
    from_date: date
    to_date: date

    @model_validator(mode='after')
    def bounded(self):
        if not 0 <= (self.to_date - self.from_date).days <= 31:
            raise ValueError('每次最多查询32天，请缩小范围')
        return self


class Find(Input):
    query: str = Field(min_length=1, max_length=120)


class EventPatch(Input):
    title: str | None = Field(default=None, min_length=1, max_length=120)
    time: ItemTime | None = None
    certainty: Literal['formal', 'tentative', 'unknown'] | None = None
    location: str | None = Field(default=None, max_length=120)
    notes: str | None = Field(default=None, max_length=3000)
    category_id: Literal['study', 'research', 'affairs', 'life'] | None = None
    tags: list[str] | None = Field(default=None, max_length=12)
    reminder_minutes: list[int] | None = Field(default=None, max_length=12,
        description='提前提醒分钟数数组，例如提前30分钟为[30]，提前一天和两小时为[1440,120]；不修改提醒时省略。')


class EventChange(Input):
    action: Literal['create', 'update', 'cancel']
    event_id: str | None = Field(default=None, max_length=36)
    fields: EventPatch = Field(default_factory=EventPatch)


class ItemDraft(Input):
    kind: Literal['assignment', 'task']
    title: str = Field(min_length=1, max_length=120)
    time: ItemTime = Field(default_factory=ItemTime)
    course_id: str | None = Field(default=None, max_length=36)
    certainty: Literal['formal', 'tentative', 'unknown'] = 'unknown'
    remaining_minutes: int | None = Field(default=None, ge=1, le=525600)
    priority: Literal['normal', 'high', 'low'] = 'normal'
    notes: str = Field(default='', max_length=3000)
    reminders: list[ReminderInput] = Field(default_factory=list, max_length=20)


class ItemNew(Input):
    fields: ItemDraft


class FreeWindows(Range):
    duration_minutes: int = Field(ge=15, le=480)


class TaskChange(Input):
    item_id: str = Field(min_length=1, max_length=36)
    intent: Literal['update_task', 'update_reminder']
    task_patch: TaskPatch | None = None
    reminder_action: Literal['add', 'edit', 'disable'] = 'edit'
    reminder_id: str | None = Field(default=None, max_length=36)
    reminder: ReminderInput | None = None


SCHEMAS = {
    'query_calendar': (Range, '查询日期范围内的真实课程、日程、截止事项和个人计划；返回事实与数据版本。'),
    'find_records': (Find, '按名称搜索当前学期的日程、任务、考试与课程。修改前先搜索，不猜ID；同名时询问用户。'),
    'analyze_schedule': (Range, '计算安排数量、已安排时长、重叠时间的并集、截止事项和缺失信息；不是实际投入或效率评分。'),
    'find_free_windows': (FreeWindows, '查找用户学习时间设置内的连续空闲时段，扣除固定安排与个人计划。信息不完整时返回待补充。'),
    'prepare_event': (EventChange, '仅准备一般固定日程的新增/修改/取消预览。fields可含title,time,certainty,location,notes,category_id,tags,reminder_minutes。time遵循precision=exact/date/week/range/unknown；exact用含时区的at,end_at，不猜结束时间。修改时仅传需要改变的完整字段。分类study/research/affairs/life；建议1到3标签。不能改课程或考试；不能擅自移动固定安排。'),
    'prepare_item': (ItemNew, '准备新增作业或任务的确认预览。fields含kind(task或assignment),title,time，可含course_id,remaining_minutes,priority,notes,reminders。日期只有天时precision=date，勿推断23:59；未说耗时不猜。'),
    'prepare_task_change': (TaskChange, '准备任务标题/剩余分钟/是否拆分，或任务考试提醒的修改预览。先find_records定位item_id；同名先问。update_task使用task_patch；update_reminder使用reminder_action和reminder(mode/lead_minutes/trigger_at/purpose)。有多条提醒时提供reminder_id。不更改课程或考试时间，不自行取消已有计划。'),
}


def tool_definitions():
    return [{'type': 'function', 'function': {'name': name, 'description': description,
            'parameters': cls.model_json_schema()}} for name, (cls, description) in SCHEMAS.items()]


def facts(db, user, sid, args):
    value = events.calendar(sid, args.from_date, args.to_date, user, db)
    if len(value['entries']) + len(value['undated']) > 300:
        error(422, 'TOO_MANY_RESULTS', '这个范围的安排较多，请缩小日期范围')
    return value


def analyze(value):
    begin = local_day(value['from_date']).timestamp()
    end = local_day((date.fromisoformat(value['to_date']) + timedelta(days=1)).isoformat()).timestamp()
    intervals = []; planned = 0; fixed = 0; unknown = []; counts = {}
    for e in value['entries']:
        counts[e['resource_type']] = counts.get(e['resource_type'], 0) + 1
        a, b = e.get('start_at'), e.get('end_at')
        if a and b:
            a, b = max(begin, instant(a).timestamp()), min(end, instant(b).timestamp())
            minutes = max(0, b - a) / 60
            intervals.append((a, b))
            if e['resource_type'] == 'plan': planned += minutes
            else: fixed += minutes
        elif e['resource_type'] != 'deadline': unknown.append(e['id'])
    return {'from_date': value['from_date'], 'to_date': value['to_date'], 'revision': value['revision'],
            'counts': counts, 'fixed_scheduled_minutes': round(fixed, 1), 'personal_planned_minutes': round(planned, 1),
            'occupied_union_minutes': round(sum(b-a for a,b in merge(intervals))/60, 1),
            'actual_minutes': None, 'unknown_duration_ids': unknown,
            'undated_count': len(value['undated']), 'conflicts': value['fixed_conflicts'],
            'basis_ids': [e['id'] for e in value['entries']],
            'definition': '时长按查询日期裁剪；占用时长按区间并集去重。课表和计划不等于实际投入。'}


def execute_tool(name, raw, db, user, thread, state, source):
    if name not in SCHEMAS: error(422, 'UNKNOWN_TOOL', '此操作暂不支持，请使用已有日程功能')
    args = SCHEMAS[name][0].model_validate(raw)
    sid = thread.semester_id
    s = owned_semester(db, user, sid, lock=True)
    if name in ('query_calendar', 'analyze_schedule'):
        value = facts(db, user, sid, args)
        card = {'kind': 'calendar', 'data': value} if name == 'query_calendar' else {'kind': 'analysis', 'data': analyze(value)}
        state['cards'].append(card)
        state['known_ids'] = list(set(state.get('known_ids', []) + [e['resource_id'] for e in value['entries'] if e.get('resource_id')]))
        return card['data']
    if name == 'find_records':
        q = ''.join(args.query.casefold().split())
        rows = [{'resource_type': 'event', **event_value(db, r)} for r in event_rows(db,user,sid)]
        rows += [{'resource_type': 'exam' if r.payload['kind']=='exam' else 'item', **serialize_item(db,r)} for r in db.scalars(
            select(StudyItem).where(StudyItem.user_id==user.id, StudyItem.semester_id==sid, StudyItem.lifecycle=='active'))]
        rows += [{'resource_type': 'course', 'id': r.id, **r.payload} for r in db.scalars(select(CourseMeeting).where(
            CourseMeeting.user_id==user.id, CourseMeeting.semester_id==sid))]
        found = [r for r in rows if q in ''.join(r['title'].casefold().split())]
        if len(found)>30: error(422,'TOO_MANY_RESULTS','匹配的事项较多，请补充名称或日期')
        counts=Counter(''.join(r['title'].casefold().split()) for r in found)
        state['ambiguous_ids']=list(set(state.get('ambiguous_ids',[])) | {
            r['id'] for r in found if counts[''.join(r['title'].casefold().split())]>1})
        state['known_ids'] = list(set(state.get('known_ids', []) + [r['id'] for r in found]))
        state['cards'].append({'kind':'records','data': {'records': found}})
        return {'records': found, 'revision': s.revision}
    if name == 'find_free_windows':
        from .schedule_api import snapshot
        from .capacity import calendar_context
        from .reminder_rules import utcnow
        snap = snapshot(db,user,s); context=calendar_context(*snap[:4],utcnow())
        range_start=local_day(args.from_date.isoformat()).timestamp()
        range_end=local_day((args.to_date+timedelta(days=1)).isoformat()).timestamp()
        titles={e['id']:e['title'] for e in snap[3]}
        titles.update({'event:'+e['id']:e['title'] for e in snap[0].get('fixed_events',[])})
        incomplete=[{'id':eid,'title':titles.get(eid,'待确认安排')} for a,b,missing,eid in context['uncertain']
                    if missing and a<range_end and b>range_start]
        if incomplete:
            result={'windows':[], 'needs_input':incomplete, 'revision':s.revision}
        else:
            begin=max(local_day(args.from_date.isoformat()).timestamp(),utcnow().timestamp())
            end=local_day((args.to_date+timedelta(days=1)).isoformat()).timestamp()
            occupied=[(instant(p['start_at']).timestamp(),instant(p['end_at']).timestamp()) for p in snap[4] if p['status']=='active']
            windows=subtract(context['free'].spans,merge(occupied))
            spans=[(max(a,begin),min(b,end)) for a,b in windows if min(b,end)-max(a,begin)>=args.duration_minutes*60]
            result={'windows':[{'start_at':iso(a),'end_at':iso(b)} for a,b in spans[:30]],'truncated':len(spans)>30,
                    'revision':s.revision,'basis':'仅使用你设置的可学习时间，已扣除固定安排、个人计划和缓冲'}
        state['cards'].append({'kind':'windows','data':result}); return result
    if state.get('preview'): error(422,'ONE_CHANGE','请先确认当前修改，再处理下一项')
    before = None
    fields = args.fields.model_dump(mode='json', exclude_unset=True) if hasattr(args, 'fields') else {}
    if name == 'prepare_task_change':
        from .items import owned_item, rules_for
        from .models import OperationProposal
        from .operations import prepare
        from .reminder_rules import utcnow
        item=owned_item(db,user,args.item_id)
        if item.semester_id!=sid:error(404,'NOT_FOUND','找不到本学期的这条事项')
        if item.id in state.get('ambiguous_ids',[]):error(422,'AMBIGUOUS_TARGET','查到了多条同名事项，请先向用户列出时间和地点，确认具体是哪一条')
        if item.id not in state.get('known_ids',[]):error(422,'READ_FIRST','请先查找并核对要修改的事项')
        suggestion=OperationSuggestion(intent=args.intent,task_patch=args.task_patch or TaskPatch(),reminder_action=args.reminder_action)
        p=OperationProposal(user_id=user.id,semester_id=sid,base_revision=s.revision,source_text=source,
            reference_at=utcnow().isoformat(),created_at=utcnow().isoformat(),payload={
                'suggestion':suggestion.model_dump(mode='json'), 'agent_run_id':state['run_id']})
        db.add(p);db.flush()
        rules=rules_for(db,item)
        rule=next((r for r in rules if r.id==args.reminder_id),None) if args.reminder_id else (rules[0] if len(rules)==1 else None)
        selection=OperationResolve(expected_version=1,target_item_id=item.id,task_patch=args.task_patch,
            reminder_action=args.reminder_action,reminder_id=args.reminder_id,reminder=args.reminder,
            expected_item_version=item.version,expected_reminder_version=rule.version if rule else None)
        prepare(db,user,p,s,selection)
        detail=p.payload['preview']
        preview={'kind':'operation','action':args.intent,'target_id':item.id,'operation_id':p.id,
                 'before':detail.get('reminder_before') if args.intent=='update_reminder' else detail['before'],
                 'after':detail.get('reminder_after') if args.intent=='update_reminder' else detail['after'],
                 'title':item.payload['title'],'affected_blocks':detail.get('affected_blocks',[]),
                 'body':{'expected_version':p.version}}
    elif name == 'prepare_event':
        allowed = {'title','time','certainty','location','notes','category_id','tags','reminder_minutes'}
        if set(fields)-allowed: error(422,'INVALID_FIELDS','请只填写日程本身的信息')
        if args.action=='create':
            if args.event_id: error(422,'INVALID_TARGET','新增日程不需要已有日程编号')
            body=EventFields.model_validate({**fields,'semester_id':sid,'expected_revision':s.revision,'source_text':source})
        else:
            row=events.owned_event(db,user,args.event_id)
            if row.semester_id!=sid: error(404,'NOT_FOUND','找不到本学期的这条日程')
            if row.id in state.get('ambiguous_ids',[]):error(422,'AMBIGUOUS_TARGET','查到了多条同名日程，请先向用户列出时间和地点，确认具体是哪一条')
            if row.id not in state.get('known_ids',[]): error(422,'READ_FIRST','请先查询并核对这条日程')
            if row.lifecycle!='active': error(409,'EVENT_CANCELLED','日程已经取消')
            before=event_value(db,row)
            existing={k:before[k] for k in allowed if k in before}
            existing['tags']=[t['name'] for t in before['tags']]
            if args.action=='cancel':
                if fields: error(422,'INVALID_FIELDS','取消日程不同时修改其他字段')
                body=EventCancel(expected_revision=s.revision,expected_version=row.version)
            else:
                if not fields: error(422,'NO_CHANGES','请说明需要修改的内容')
                body=EventEdit.model_validate({**existing,**fields,'semester_id':sid,'expected_revision':s.revision,
                    'expected_version':row.version,'change_reason':source[:500]})
        data=body.model_dump(mode='json')
        if data.get('time',{}).get('week',0) and data['time']['week']>s.total_weeks: error(422,'INVALID_TIME','周次超出学期')
        preview={'kind':'event','action':args.action,'target_id':args.event_id,'before':before,
                 'after':None if args.action=='cancel' else data,'body':data}
    else:
        allowed=set(ItemCreate.model_fields)-{'semester_id','source_id','candidate_id','source_text'}
        if set(fields)-allowed: error(422,'INVALID_FIELDS','请只填写事项本身的信息')
        body=ItemCreate.model_validate({**fields,'semester_id':sid,'source_text':source})
        if body.time.day_end_confirmed:
            error(422,'DEADLINE_POLICY_REQUIRED','只有日期时保留日期，不自动设为当天结束；用户明确了时刻才能填具体截止时间')
        if body.kind=='exam': error(422,'AUTHORITATIVE_ITEM','考试请通过考试录入核对学校通知')
        if body.course_id:
            course=db.scalar(select(CourseMeeting).where(CourseMeeting.id==body.course_id,CourseMeeting.user_id==user.id,CourseMeeting.semester_id==sid))
            if course is None: error(422,'INVALID_COURSE','找不到关联课程，请先查询课程名称')
        data=body.model_dump(mode='json')
        preview={'kind':'item','action':'create','target_id':None,'before':None,'after':data,'body':data}
    preview.update(semester_id=sid,expected_revision=s.revision)
    preview['token']=fingerprint({'run_id': state['run_id'], 'preview': preview})
    state['preview']=preview
    return {'status':'needs_confirmation','preview':preview,'message':'尚未保存，请用户核对预览后点击确认。'}


def apply_preview(db,user,preview):
    s=owned_semester(db,user,preview['semester_id'],lock=True)
    if s.revision!=preview['expected_revision']:error(409,'PREVIEW_STALE','安排已有更新，请重新生成修改预览')
    data=deepcopy(preview['body'])
    if preview['kind']=='operation':
        from .operations import apply_command
        return apply_command(db,user,preview['operation_id'],OperationAction.model_validate(data))
    if preview['kind']=='item':
        item=create_item_command(db,user,ItemCreate.model_validate(data))
        return {'semester_id':s.id,'revision':s.revision,'item':item}
    action=preview['action']
    if action=='create':return events.create_event_command(db,user,EventFields.model_validate(data))
    if action=='update':return events.edit_event_command(db,user,preview['target_id'],EventEdit.model_validate(data))
    return events.cancel_event_command(db,user,preview['target_id'],EventCancel.model_validate(data))
