"""Small typed tool surface. All identity and revision values come from the server."""
from copy import deepcopy
from collections import Counter
from datetime import date, datetime, timedelta
import re
from typing import Literal, Annotated
from pydantic import Field, model_validator
from sqlalchemy import select
from .schemas import Input
from .academics import owned_semester, fingerprint
from .auth import error
from .models import StudyItem, CourseMeeting
from .event_schemas import EventFields, EventEdit, EventCancel
from .item_schemas import ItemCreate, ItemEdit, ItemTime, ReminderInput, NoticeDetails, LifecycleInput
from . import calendar_events as events
from .event_store import event_rows, event_value
from .items import serialize_item, create_item_command, edit_item_command
from .capacity import local_day, merge, subtract, iso, uncertainty_affects_window
from .reminder_rules import instant, SHANGHAI
from .operation_schemas import TaskPatch, OperationSuggestion, OperationResolve, OperationAction
from .agent_planning import PlanRequest, prepare_agent_plan, apply_agent_plan
from .agent_education import OccurrenceQuery, CourseChange, ExamChange, query_occurrences, prepare_course, prepare_exam, apply_education
from .agent_cards import append_card


class Range(Input):
    from_date: date
    to_date: date

    @model_validator(mode='after')
    def bounded(self):
        if not 0 <= (self.to_date - self.from_date).days < 366:
            raise ValueError('请检查日期范围，每次可查询最多一年')
        return self


class Find(Input):
    query: str = Field(default='', max_length=120)
    resource_type: Literal['event', 'item', 'course', 'exam'] | None = None
    on_date: date | None = Field(default=None, description='用户明确提供的日期，用于同名事项消歧。')
    location: str | None = Field(default=None, max_length=120, description='用户明确提供的地点，用于同名事项消歧。')
    lifecycle: Literal['active', 'completed', 'cancelled', 'all'] = 'active'


class EventPatch(Input):
    title: str | None = Field(default=None, min_length=1, max_length=120)
    time: ItemTime | None = None
    certainty: Literal['formal', 'tentative', 'unknown'] | None = None
    reserve_time: bool | None = None
    location: str | None = Field(default=None, max_length=120)
    notes: str | None = Field(default=None, max_length=3000)
    details: NoticeDetails | None = None
    category_id: Literal['study', 'research', 'affairs', 'life'] | None = None
    tags: list[str] | None = Field(default=None, max_length=12)
    reminder_minutes: list[int] | None = Field(default=None, max_length=12,
        description='提前提醒分钟数数组，例如提前30分钟为[30]，提前一天和两小时为[1440,120]；不修改提醒时省略。')


class EventChange(Input):
    action: Literal['create', 'update', 'cancel','restore'] = Field(description='create新增，update修改，cancel取消，restore恢复已取消的个人日程；恢复仅传event_id，不同时修改字段。')
    event_id: str | None = Field(default=None, max_length=36)
    fields: EventPatch = Field(default_factory=EventPatch)


class ItemDraft(Input):
    kind: Literal['assignment', 'task', 'exam']
    title: str = Field(min_length=1, max_length=120)
    time: ItemTime = Field(default_factory=ItemTime)
    details: NoticeDetails = Field(default_factory=NoticeDetails)
    course_id: str | None = Field(default=None, max_length=36)
    certainty: Literal['formal', 'tentative', 'unknown'] = Field(default='formal',
        description='明确要做的行动默认formal，与有没有截止或钟点无关。来源明确暂定/预计等不确定时填写tentative；确实无法判断事实时unknown。')
    remaining_minutes: int | None = Field(default=None, ge=1, le=525600)
    priority: Literal['normal', 'high', 'low'] = 'normal'
    notes: str = Field(default='', max_length=3000)
    category_id: Literal['study', 'research', 'affairs', 'life'] | None = None
    tags: list[str] = Field(default_factory=list, max_length=12)
    reminders: list[ReminderInput] = Field(default_factory=list, max_length=20)

    location: str = Field(default='', max_length=120)
    reserve_time: bool = True
    start_policy: Literal['unconfirmed', 'now', 'at'] = 'unconfirmed'
    earliest_start_at: datetime | None = None


class ItemNew(Input):
    fields: ItemDraft


class ItemPatch(Input):
    title: str | None = Field(default=None, min_length=1, max_length=120)
    time: ItemTime | None = None
    certainty: Literal['formal', 'tentative', 'unknown'] | None = None
    reserve_time: bool | None = None
    location: str | None = Field(default=None, max_length=120)
    notes: str | None = Field(default=None, max_length=3000)
    details: NoticeDetails | None = None
    category_id: Literal['study', 'research', 'affairs', 'life'] | None = None
    tags: list[str] | None = Field(default=None, max_length=12)
    start_policy: Literal['unconfirmed', 'now', 'at'] | None = None
    earliest_start_at: datetime | None = None


class ItemState(Input):
    item_id: str = Field(min_length=1, max_length=36)
    lifecycle: Literal['active', 'completed', 'cancelled']


class ItemChange(Input):
    item_id: str = Field(min_length=1, max_length=36)
    fields: ItemPatch


class FreeWindows(Range):
    duration_minutes: int = Field(ge=15, le=480)
    scope: Literal['calendar', 'study'] = Field(default='calendar', description='普通空闲、约时间、哪天有空用calendar；用户明确在学习时段内找学习时间用study。')
    answer_style: Literal['summary','detail'] = Field(default='summary', description='普通哪天有空用summary，App按结构化结果显示简短结论。用户明确要求比较、解释原因、详细文字列表时用detail保留完整回复。')
    day_start_minutes: int = Field(default=480, ge=0, le=1439, description='calendar每天查询开始分钟；未指定按08:00起查并说明范围，全天用0。study忽略。')
    day_end_minutes: int = Field(default=1320, ge=1, le=1440, description='calendar每天查询结束分钟；未指定按22:00止查并说明范围，全天用1440。study忽略。')

    @model_validator(mode='after')
    def day_window(self):
        if self.scope == 'calendar' and self.day_end_minutes <= self.day_start_minutes:
            raise ValueError('请检查每日查询时段')
        return self


class InsightQuery(Input):
    scope: Literal['range','semester'] = 'range'
    from_date: date | None = None
    to_date: date | None = None
    category_id: Literal['study','research','affairs','life','unclassified'] | None = None
    tag_ids: list[str] = Field(default_factory=list, max_length=12)

    @model_validator(mode='after')
    def valid_dates(self):
        if self.scope=='range' and (self.from_date is None or self.to_date is None):
            raise ValueError('请明确查询起止日期，或用semester查询整个学期')
        if self.scope=='semester' and (self.from_date is not None or self.to_date is not None):
            raise ValueError('整个学期范围由校历决定，不另指定日期')
        return self


class TaskChange(Input):
    item_id: str = Field(min_length=1, max_length=36)
    intent: Literal['update_task', 'update_reminder']
    task_patch: TaskPatch | None = None
    reminder_action: Literal['add', 'edit', 'disable'] = 'edit'
    reminder_id: str | None = Field(default=None, max_length=36)
    reminder: ReminderInput | None = None


class BatchEvent(Input):
    tool: Literal['prepare_event']
    arguments: EventChange


class BatchItem(Input):
    tool: Literal['prepare_item']
    arguments: ItemNew


class BatchTask(Input):
    tool: Literal['prepare_task_change']
    arguments: TaskChange


class BatchItemChange(Input):
    tool: Literal['prepare_item_change']
    arguments: ItemChange


class BatchItemState(Input):
    tool: Literal['prepare_item_state']
    arguments: ItemState


class BatchCourse(Input):
    tool: Literal['prepare_course_change']
    arguments: CourseChange


class BatchExam(Input):
    tool: Literal['prepare_exam_change']
    arguments: ExamChange


class BatchGroup(Input):
    title: str = Field(min_length=1, max_length=120)
    operations: list[Annotated[BatchEvent | BatchItem | BatchTask | BatchItemChange | BatchItemState | BatchCourse | BatchExam,
                               Field(discriminator='tool')]] = Field(min_length=1, max_length=8)


class BatchRequest(Input):
    groups: list[BatchGroup] = Field(min_length=1, max_length=8)

    @model_validator(mode='after')
    def bounded(self):
        if sum(len(g.operations) for g in self.groups)>8:
            raise ValueError('每次最多整理8项，请分批处理')
        return self


class RecentActions(Input):
    pass


class UndoAction(Input):
    run_id: str = Field(min_length=1,max_length=36)


class ScheduleSetup(Input):
    task_ids:list[str]=Field(default_factory=list,max_length=100)


class ForwardingDraft(Input):
    text:str=Field(min_length=1,max_length=3000,
        description='用户要求的简短转发文案；只包含通知真实动作、对象、期限和渠道，保留未确定信息。')
    title:str=Field(default='转发文案',min_length=1,max_length=120)


SCHEMAS = {
    'get_schedule_setup':(ScheduleSetup,'读取排程确认项和可修改建议：普通任务无等待条件可立即开始；未设置学习时间提供候选模板，未知耗时提供起步建议，均需用户确认后保存。返回排程设置卡，不能声称已经设置或安排。'),
    'prepare_forwarding_draft':(ForwardingDraft,'仅用户要求转达、发群文案或转发时生成可编辑草稿。按已查询事实或当前通知提炼对象、动作、日期、材料和渠道；不猜身份，不自动发送，不把别人分工写成用户已承接。'),
    'list_recent_actions': (RecentActions, '查询当前学期最近由助手确认保存的操作及是否已撤销。撤销前先查询，不猜run_id。'),
    'prepare_undo': (UndoAction, '准备撤销已保存操作的预览。先list_recent_actions定位run_id；有多条可能匹配的操作时请明确时间和内容再继续。后续修改或依赖冲突会拒绝，不强行覆盖。'),
    'prepare_batch': (BatchRequest, '把一份通知里的多项安排一次生成分组预览。groups每组title和operations，operation含tool和arguments，参数与单项prepare工具一致。最多8项，可选组保存。同一对象不能重复修改；修改前先查询。课程/考试/会议事实与个人重排分开，不包含prepare_plan或撤销。点名给其他人的任务不能擅自录为用户任务。'),
    'query_course_occurrences': (OccurrenceQuery, '按原上课日期范围和课程名称查询真实课次；返回课次ID、原时间与地点。调课/停课前必须查询；课程ID不等于课次ID。'),
    'prepare_course_change': (CourseChange, '按当前用户的明确要求更正自己的课表：调课(move)、单次停课(cancel)、范围停课(suspend)、补课(add)。不要求学校通知证明，也不因日期已过拒绝。先query_course_occurrences；范围全部停课传scope=query_scope包含全部查到的课次，不需逐条选择或罗列ID。单次用targets课次ID。新开始时刻明确而未改变时长时保留原课次时长。不自动移动个人计划。'),
    'prepare_exam_change': (ExamChange, '按用户要求更正自己记录的考试改期/地点/确定性/是否预留时间或details，不要求学校通知证明；先find_records查考试。正式确定的参考考试也可reserve_time=false，无需改变certainty。details仅传修改值，省略或null保留；未改时间使用原time与certainty，允许exact/date/week/range/unknown。align_review_deadlines默认false，用户要求同步才true。'),
    'query_calendar': (Range, '查询日期范围内的真实课程、日程、截止事项和个人计划；返回事实与数据版本。'),
    'find_records': (Find, '搜索本学期日程、任务、考试与课程。用户已给日期或地点时用on_date/location定位，同名但范围唯一不必再点选。恢复事项时可指定lifecycle=cancelled/completed/all。修改前先搜索，不猜ID。'),
    'prepare_item_state': (ItemState, '按用户请求将个人任务/作业标记完成、取消事项/考试，或恢复取消完成的事项。先find_records定位；查询完成取消记录用对应lifecycle。生成含关联未来个人计划与提醒影响的预览，一次确认后保存，不修改学校系统。'),
    'prepare_plan': (PlanRequest, '用求解器准备个人计划，确认前不写入时间块。先find_records查询任务。新增用schedule；重排用replan，只传mode/task_ids/lead_minutes。普通任务可立即开始，明确等待条件或未来开始保持原样；缺耗时或学习时间用get_schedule_setup给可修改建议并确认，不猜成事实，不要求没有截止的任务先补精确期限。不改固定课程考试活动。'),
    'analyze_schedule': (Range, '计算安排数量、已安排时长、重叠时间的并集、截止事项和缺失信息；不是实际投入或效率评分。'),
    'query_insights': (InsightQuery, '读取与统计页面一致的汇总。全学期使用scope=semester，指定日期用scope=range+from_date/to_date；可按主分类、已查到的稳定标签ID筛选。明确区分安排时长、重叠去重占用、实际进度记录和未知值，不能生成效率评分。'),
    'find_free_windows': (FreeWindows, '查询连续空闲。普通日程问题默认calendar，扣除课程、考试、已预留活动、个人计划和临时不可用时段，不限于学习偏好；默认08:00—22:00，用户指定全天/其他钟点时改每日查询范围。明确查询可学习时间才用study，遵循已保存学习时段。按天返回真实空档，未知结束保留核对提示。'),
    'prepare_event': (EventChange, '准备一般日程或参考通知的新增/修改/取消预览。fields可含title,time,certainty,reserve_time,details,location,notes,category_id,tags,reminder_minutes。仅作参考、自愿尚未报名、条件未确定或另选他人时reserve_time=false；details.participation_status用optional/conditional/other。本人已确定参加时confirmed及reserve_time=true，不从formal或时间完整推断参加。time遵循precision=exact/date/week/range/unknown；exact用含时区的at,end_at，不猜结束时间。修改时仅传需要改变的完整字段。分类study/research/affairs/life；建议1到3标签。不能改课程或考试；不能擅自移动固定安排。'),
    'prepare_item': (ItemNew, '准备新增作业、个人任务或学校考试通知的确认预览。fields含kind(task或assignment或exam),title,time，可含course_id,remaining_minutes,priority,notes,reminders。日期只有天时precision=date，勿推断23:59；未说耗时不猜。'),
    'prepare_item_change': (ItemChange, '按用户请求更新已有任务/作业的截止、地点、材料、渠道、条件，以及start_policy/earliest_start_at。明确“从现在可以安排”用now，指定最早时刻用at。先find_records定位；fields只传修改字段，details合并其余细节。考试走prepare_exam_change，课程走prepare_course_change。'),
    'prepare_task_change': (TaskChange, '准备任务标题/剩余分钟/是否拆分，或任务考试提醒的修改预览。先find_records定位item_id；同名先问。update_task使用task_patch；update_reminder使用reminder_action和reminder(mode/lead_minutes/trigger_at/purpose)。有多条提醒时提供reminder_id。不更改课程或考试时间，不自行取消已有计划。'),
}


def tool_definitions():
    return [{'type': 'function', 'function': {'name': name, 'description': description,
            'parameters': cls.model_json_schema()}} for name, (cls, description) in SCHEMAS.items()]


def normalize_notice_task_time(fields,state,source):
    """Do not borrow another notice action's time for a new personal task."""
    if state.get('input_kind')!='notice' or fields.get('kind')=='exam':return fields
    t=fields.get('time') or {};expression=t.get('expression','').strip()
    if not expression or not re.search(r'前|截止|截至|尽快|尽早|抓紧|马上',expression):return fields
    compact=lambda value:re.sub(r'\s+','',value)
    if compact(expression) in compact(source):return fields
    deadline_cue=re.search(r'截止|截至|最迟|不晚于|(?:下课|上课|课|开会|会)(?:之)?前|(?<!提)前(?:请|需|须|务必)?(?:提交|填报|填写|申请|完成|发送|上交|交)',source)
    if deadline_cue:return fields
    return {**fields,'time':ItemTime().model_dump(mode='json')}


def source_guard(db, user, sid, ref, lock=False):
    if not ref: return
    from .media import owned_source, version
    row = owned_source(db, user, ref['id'], lock)
    if row.semester_id != sid: error(404, 'NOT_FOUND', '来源不属于当前学期')
    version(row, ref['version'])


def facts(db, user, sid, args):
    value = events.calendar(sid, args.from_date, args.to_date, user, db)
    if len(value['entries']) + len(value['undated']) > 1000:
        error(422, 'TOO_MANY_RESULTS', '这个范围的安排较多，请缩小日期范围')
    return value


def analyze(value):
    begin = local_day(value['from_date']).timestamp()
    end = local_day((date.fromisoformat(value['to_date']) + timedelta(days=1)).isoformat()).timestamp()
    intervals = []; planned = 0; fixed = 0; unknown = []; counts = {}
    for e in value['entries']:
        counts[e['resource_type']] = counts.get(e['resource_type'], 0) + 1
        a, b = e.get('occupancy_start_at') or e.get('start_at'), e.get('end_at')
        if a and b and (e.get('fixed') or e['resource_type'] == 'plan'):
            a, b = max(begin, instant(a).timestamp()), min(end, instant(b).timestamp())
            minutes = max(0, b - a) / 60
            intervals.append((a, b))
            if e['resource_type'] == 'plan': planned += minutes
            else: fixed += minutes
        elif e.get('fixed'): unknown.append(e['id'])
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
    source_guard(db, user, sid, state.get('source'))
    if name=='get_schedule_setup':
        from .planning import schedule_setup_value
        result=schedule_setup_value(db,user,s,args.task_ids)
        state['known_ids']=list(set(state.get('known_ids',[])+[i['id'] for i in result['tasks']]))
        append_card(state,'schedule_setup',{**result,'total_count':len(result['tasks'])})
        return result
    if name=='prepare_forwarding_draft':
        result={'title':args.title,'text':args.text,'editable':True,'sent':False}
        append_card(state,'forwarding_draft',result)
        return result
    if name=='list_recent_actions':
        from .models import AgentRun, AgentThread
        rows=list(db.scalars(select(AgentRun).join(AgentThread,AgentThread.id==AgentRun.thread_id).where(
            AgentRun.user_id==user.id,AgentThread.semester_id==sid,AgentRun.status=='applied').order_by(AgentRun.created_at.desc()).limit(20)))
        actions=[{'id':r.id,'text':r.text,'created_at':r.created_at,'undone':bool(r.state.get('undone_by')),
                  'has_undo_record':bool(r.state.get('undo_data')),'kind':(r.state.get('preview') or {}).get('kind')} for r in rows]
        state['known_action_ids']=[r.id for r in rows]
        append_card(state, 'recent_actions', {'actions':actions, 'total_count':len(actions),
            'navigation_query': {'semester_id':sid, 'kind':'recent_actions'}})
        return {'actions':actions}
    if name == 'query_course_occurrences': return query_occurrences(db,user,s,state,args)
    if name == 'query_insights':
        from .insights import insights
        begin=date.fromisoformat(s.first_monday) if args.scope=='semester' else args.from_date
        end=begin+timedelta(days=s.total_weeks*7-1) if args.scope=='semester' else args.to_date
        value=insights(sid,begin,end,args.category_id,','.join(args.tag_ids) or None,user,db)
        # Aggregates are complete. Bound source details sent to the model.
        count = len(value['records']) + len(value['undated'])
        append_card(state, 'insights', {**value, 'records_total':len(value['records']), 'total_count':count,
            'navigation_query': {'semester_id':sid, **args.model_dump(mode='json')}})
        return {**value,'records_total':len(value['records']),'records_truncated':len(value['records'])>60,
                'records':value['records'][:60],'undated':value['undated'][:30]}
    if name in ('query_calendar', 'analyze_schedule'):
        value = facts(db, user, sid, args)
        data = {**value,
                'total_count': len(value['entries']) + len(value['undated']),
                'navigation_query': {'semester_id': sid, **args.model_dump(mode='json')}}
        card = append_card(state, 'calendar', data) if name == 'query_calendar' else append_card(state, 'analysis', analyze(value))
        state['known_ids'] = list(set(state.get('known_ids', []) + [e['resource_id'] for e in value['entries'] if e.get('resource_id')]))
        return {**value, 'presentation': '明细已经显示在App结果卡片，回复只给问题结论，默认80字以内，不再列举所有课程。'} if name == 'query_calendar' else card['data']
    if name == 'find_records':
        q = ''.join(args.query.casefold().split())
        if not q and args.resource_type is None: error(422,'SEARCH_SCOPE_REQUIRED','请提供名称，或指定要查询的事项类型')
        event_records=event_rows(db,user,sid,active=False)
        if args.lifecycle!='all':event_records=[r for r in event_records if r.lifecycle==args.lifecycle]
        rows = [{'resource_type': 'event', **event_value(db, r)} for r in event_records]
        items = select(StudyItem).where(StudyItem.user_id==user.id, StudyItem.semester_id==sid)
        if args.lifecycle != 'all': items = items.where(StudyItem.lifecycle == args.lifecycle)
        rows += [{'resource_type': 'exam' if r.payload['kind']=='exam' else 'item', **serialize_item(db,r)} for r in db.scalars(items)]
        rows += [{'resource_type': 'course', 'id': r.id, **r.payload} for r in db.scalars(select(CourseMeeting).where(
            CourseMeeting.user_id==user.id, CourseMeeting.semester_id==sid))]
        found = [r for r in rows if q in ''.join(r['title'].casefold().split()) and (args.resource_type is None or r['resource_type']==args.resource_type)]
        if args.on_date is not None:
            def on_date(r):
                t = r.get('time', {})
                if t.get('at'): return instant(t['at']).astimezone(SHANGHAI).date() == args.on_date
                if t.get('date'): return date.fromisoformat(t['date']) <= args.on_date <= date.fromisoformat(t.get('end_date') or t['date'])
                week = ((args.on_date - date.fromisoformat(s.first_monday)).days // 7) + 1
                if t.get('week'): return week == t['week']
                return r.get('resource_type') == 'course' and week in r.get('weeks', []) and r.get('weekday') == args.on_date.isoweekday()
            found = [r for r in found if on_date(r)]
        if args.location is not None:
            found = [r for r in found if args.location.strip().casefold() in r.get('location', '').casefold()]
        counts=Counter(''.join(r['title'].casefold().split()) for r in found)
        state['ambiguous_ids']=list(set(state.get('ambiguous_ids',[])) | {
            r['id'] for r in found if q and counts[''.join(r['title'].casefold().split())]>1})
        state['ambiguous_ids']=[id for id in state['ambiguous_ids'] if id not in state.get('selected_record_ids',[])]
        if len(found) == 1 and (args.on_date is not None or args.location is not None):
            state['ambiguous_ids'] = [id for id in state['ambiguous_ids'] if id != found[0]['id']]
        state['known_ids'] = list(set(state.get('known_ids', []) + [r['id'] for r in found]))
        append_card(state, 'records', {'records': found, 'total_count': len(found),
            'navigation_query': {'semester_id': sid, **args.model_dump(mode='json')}})
        return {'records': found[:100], 'total_count': len(found), 'truncated': len(found)>100, 'revision': s.revision}
    if name == 'find_free_windows':
        from .schedule_api import snapshot
        from .capacity import calendar_context
        from .reminder_rules import utcnow
        snap = snapshot(db,user,s)
        availability=snap[1]
        if args.scope == 'calendar':
            def clock(minutes):return f'{minutes//60:02d}:{minutes%60:02d}'
            availability={**availability,'weekly':[{'weekday':day,'start':clock(args.day_start_minutes),
                'end':clock(args.day_end_minutes)} for day in range(1,8)]}
        context=calendar_context(snap[0],availability,snap[2],snap[3],utcnow())
        range_start=local_day(args.from_date.isoformat()).timestamp()
        range_end=local_day((args.to_date+timedelta(days=1)).isoformat()).timestamp()
        begin=max(range_start,utcnow().timestamp());end=range_end
        occupied=[(instant(p['start_at']).timestamp(),instant(p['end_at']).timestamp()) for p in snap[4] if p['status']=='active']
        windows=subtract(context['free'].spans,merge(occupied))
        spans=[]
        for day in range((args.to_date-args.from_date).days+1):
            start=local_day((args.from_date+timedelta(days=day)).isoformat()).timestamp()
            stop=start+86400
            for a,b in windows:
                left,right=max(a,begin,start),min(b,end,stop)
                if right-left>=args.duration_minutes*60:spans.append((left,right))
        warnings=[w for w in context['uncertainty_warnings'] if uncertainty_affects_window(w,begin,end)]
        result={'windows':[{'start_at':iso(a),'end_at':iso(b)} for a,b in spans[:30]],'truncated':len(spans)>30,
                'revision':s.revision,'uncertainty_warnings':warnings,'needs_input':[],
                'scope':args.scope,
                'daily_search':None if args.scope=='study' else {'start':clock(args.day_start_minutes),'end':clock(args.day_end_minutes)},
                'basis':'按已保存的学习时段查询' if args.scope=='study' else f'按已记录日程查询，每天{clock(args.day_start_minutes)}—{clock(args.day_end_minutes)}；已避开固定安排、个人计划与临时不可用时段'}
        days=sorted({datetime.fromtimestamp(a,SHANGHAI).date() for a,b in spans})
        hours,minutes=divmod(args.duration_minutes,60)
        duration=(f'{hours}小时' if hours else '')+(f'{minutes}分钟' if minutes else '')
        if args.scope=='study' and not snap[1].get('configured'):
            overview='还没有保存每周学习时段，暂时无法按学习偏好查询。'
        elif not days:
            overview=f'在本次查询范围内，没有找到**{duration}**的连续'+('日程空档。' if args.scope=='calendar' else '学习空闲。')
        else:
            year=utcnow().astimezone(SHANGHAI).year
            def label(day):return (f'{day.year}年' if day.year!=year else '')+f'{day.month}月{day.day}日'
            if (days[-1]-days[0]).days+1==len(days) and len(days)>1:
                date_label=((f'{days[0].year}年' if days[0].year!=year else '')+f'{days[0].month}月{days[0].day}—{days[-1].day}日' if days[0].month==days[-1].month and days[0].year==days[-1].year else label(days[0])+'—'+label(days[-1]))
            elif len(days)<=6:date_label='、'.join(label(day) for day in days)
            else:date_label=f'本次查询中有{len(days)}天'
            overview=f'按已记录安排，**{date_label}**有至少**{duration}**'+('日程空档' if args.scope=='calendar' else '学习空闲')+'。时段见下方。'
        if any(w.get('could_affect_occupancy') for w in warnings):overview+='\n有时间不完整的安排，后续时段需核对。'
        result.update(answer_style=args.answer_style,overview_answer=overview,duration_minutes=args.duration_minutes)
        append_card(state, 'windows', {**result, 'total_count':len(result['windows']),
            'navigation_query':{'semester_id':sid, **args.model_dump(mode='json')}})
        return result
    if state.get('preview'): error(422,'ONE_CHANGE','请先确认当前修改，再处理下一项')
    before = None
    fields = args.fields.model_dump(mode='json', exclude_unset=True) if hasattr(args, 'fields') else {}
    if isinstance(args, (EventChange, ItemChange)):
        fields = {k:v for k,v in fields.items() if v is not None}
    provided_fields = sorted(fields)
    if name == 'prepare_undo':
        if args.run_id not in state.get('known_action_ids',[]):error(422,'READ_FIRST','请先查询最近保存的操作')
        from .agent_undo import prepare_undo
        preview=prepare_undo(db,user,s,args.run_id)
        preview['undo_run_id']=state['run_id']
    elif name == 'prepare_item_change':
        from .items import owned_item, checked_payload, preserve_notice_time
        item = owned_item(db, user, args.item_id)
        if item.semester_id != sid: error(404, 'NOT_FOUND', '找不到本学期的事项')
        if item.payload['kind'] == 'exam': error(422, 'USE_EXAM_CHANGE', '这是考试，请用考试修改工具保留关联复习和提醒')
        if item.lifecycle != 'active': error(409, 'ITEM_INACTIVE', '事项已经完成或取消')
        if item.id in state.get('ambiguous_ids', []): error(422, 'AMBIGUOUS_TARGET', '有多条同名事项，请先选择具体记录')
        if item.id not in state.get('known_ids', []): error(422, 'READ_FIRST', '请先查询并核对这条事项')
        if not fields: error(422, 'NO_CHANGES', '请说明需要修改的内容')
        before = serialize_item(db, item)
        existing = {k: v for k, v in item.payload.items() if k in ItemEdit.model_fields}
        existing['tags'] = [t['name'] for t in before['tags']]
        if 'details' in fields and fields['details'] is not None:
            # Detail patches must not erase previously supplied materials/conditions.
            fields['details'] = {**item.payload.get('details', {}),
                **args.fields.details.model_dump(mode='json', exclude_unset=True)}
        if 'start_policy' in fields and fields['start_policy'] != 'at' and 'earliest_start_at' not in fields:
            fields['earliest_start_at'] = None
        if fields.get('earliest_start_at') is not None and 'start_policy' not in fields:
            fields['start_policy'] = 'at'
        body = ItemEdit.model_validate({**existing, **fields, 'semester_id': sid,
            'expected_version': item.version, 'change_reason': source[:500] or '补充通知'})
        merged_time = body.time.model_dump(mode='json')
        preserve_notice_time(item.payload['time'], body.time, merged_time)
        body.time = ItemTime.model_validate(merged_time)
        if body.time.end_at and body.time.meaning != 'window':
            error(422, 'INVALID_TIME', '任务只有办理窗口允许结束时刻')
        checked_payload(db, user, body)
        data = body.model_dump(mode='json')
        preview = {'kind': 'item', 'action': 'update', 'target_id': item.id,
                   'before': before, 'after': data, 'body': data}
    elif name == 'prepare_item_state':
        from .items import owned_item
        from .plan_store import preview_blocks
        from .reminder_rules import utcnow
        item = owned_item(db, user, args.item_id)
        if item.semester_id != sid: error(404, 'NOT_FOUND', '找不到本学期的事项')
        if item.id not in state.get('known_ids', []): error(422, 'READ_FIRST', '请先查询这条事项')
        if item.id in state.get('ambiguous_ids', []): error(422, 'AMBIGUOUS_TARGET', '请补充事项的日期或选择具体记录')
        if item.lifecycle == args.lifecycle: error(422, 'NO_CHANGES', '这条事项已经是所需状态，无需再次修改')
        before = serialize_item(db, item)
        blocks = preview_blocks(db, item, utcnow()) if args.lifecycle != 'active' else []
        body = LifecycleInput(expected_version=item.version, expected_revision=s.revision,
            lifecycle=args.lifecycle, cancel_plan_ids=[b['id'] for b in blocks],
            confirm_locked_cancellation=any(b.get('locked') for b in blocks))
        preview = {'kind': 'item_state', 'action': args.lifecycle, 'target_id': item.id,
            'title': item.payload['title'], 'before': before, 'after': {**before, 'lifecycle': args.lifecycle},
            'affected_blocks': blocks, 'body': body.model_dump(mode='json')}
    elif name == 'prepare_batch':
        from .agent_batches import prepare_batch
        preview=prepare_batch(db,user,thread,s,state,args,source)
    elif name == 'prepare_course_change':
        preview=prepare_course(db,user,s,state,args,source)
    elif name == 'prepare_exam_change':
        preview=prepare_exam(db,user,s,state,args,source)
    elif name == 'prepare_plan':
        preview = prepare_agent_plan(db, user, s, state, args)
        if preview.get('kind') != 'plan':
            append_card(state, 'planning_result', preview)
            return preview
    elif name == 'prepare_task_change':
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
        allowed = {'title','time','certainty','reserve_time','location','notes','details','category_id','tags','reminder_minutes'}
        if set(fields)-allowed: error(422,'INVALID_FIELDS','请只填写日程本身的信息')
        if args.action=='create':
            if args.event_id: error(422,'INVALID_TARGET','新增日程不需要已有日程编号')
            body=EventFields.model_validate({**fields,'semester_id':sid,'expected_revision':s.revision,'source_text':source})
        else:
            row=events.owned_event(db,user,args.event_id)
            if row.semester_id!=sid: error(404,'NOT_FOUND','找不到本学期的这条日程')
            if row.id in state.get('ambiguous_ids',[]):error(422,'AMBIGUOUS_TARGET','查到了多条同名日程，请先向用户列出时间和地点，确认具体是哪一条')
            if row.id not in state.get('known_ids',[]): error(422,'READ_FIRST','请先查询并核对这条日程')
            if args.action=='restore':
                if row.lifecycle!='cancelled':error(409,'EVENT_ACTIVE','这条日程已在安排中，无需恢复')
            elif row.lifecycle!='active': error(409,'EVENT_CANCELLED','日程已经取消；恢复请使用restore')
            before=event_value(db,row)
            existing={k:before[k] for k in allowed if k in before}
            existing['tags']=[t['name'] for t in before['tags']]
            if args.action in ('cancel','restore'):
                if fields: error(422,'INVALID_FIELDS','取消或恢复日程不同时修改其他字段')
                body=EventCancel(expected_revision=s.revision,expected_version=row.version)
            else:
                if not fields: error(422,'NO_CHANGES','请说明需要修改的内容')
                if 'details' in fields and fields['details'] is not None:
                    fields['details'] = {**before.get('details', {}),
                        **args.fields.details.model_dump(mode='json', exclude_unset=True)}
                    if ('reserve_time' not in fields and 'participation_status' in args.fields.details.model_fields_set
                            and args.fields.details.participation_status != before.get('details', {}).get('participation_status', 'unspecified')):
                        existing.pop('reserve_time', None)
                body=EventEdit.model_validate({**existing,**fields,'semester_id':sid,'expected_revision':s.revision,
                    'expected_version':row.version,'change_reason':source[:500]})
        data=body.model_dump(mode='json')
        if data.get('time',{}).get('week',0) and data['time']['week']>s.total_weeks: error(422,'INVALID_TIME','周次超出学期')
        preview={'kind':'event','action':args.action,'target_id':args.event_id,'before':before,
                 'after':None if args.action=='cancel' else data,'body':data}
        if args.action=='restore':
            from types import SimpleNamespace
            from .event_store import reminder_values
            restored=SimpleNamespace(id=row.id,semester_id=sid,payload=row.payload,lifecycle='active',version=row.version+1)
            preview['after']={**before,'lifecycle':'active','version':row.version+1,'reminders':reminder_values(restored)}
            preview['impact']=events.restore_impact(db,user,s,row)
            preview['affected_blocks']=preview['impact']['affected_blocks']
    else:
        fields=normalize_notice_task_time(fields,state,source)
        allowed=set(ItemCreate.model_fields)-{'semester_id','source_id','candidate_id','source_text'}
        if set(fields)-allowed: error(422,'INVALID_FIELDS','请只填写事项本身的信息')
        body=ItemCreate.model_validate({**fields,'certainty':args.fields.certainty,
            'semester_id':sid,'source_text':source})
        if 'category_id' not in fields and body.kind in ('assignment','exam'):
            body.category_id = 'study'
        if body.course_id:
            course=db.scalar(select(CourseMeeting).where(CourseMeeting.id==body.course_id,CourseMeeting.user_id==user.id,CourseMeeting.semester_id==sid))
            if course is None: error(422,'INVALID_COURSE','找不到关联课程，请先查询课程名称')
        data=body.model_dump(mode='json')
        preview={'kind':'item','action':'create','target_id':None,'before':None,'after':data,'body':data}
    ref = state.get('source')
    if ref:
        preview['source'] = ref
        if preview['action'] == 'create' and preview['kind'] in ('event', 'item'):
            from .models import TextCandidate
            from .reminder_rules import utcnow
            candidate = TextCandidate(user_id=user.id, semester_id=sid, source_text=source,
                payload={'intent': 'create_event' if preview['kind']=='event' else 'create_item', 'media_source': ref},
                created_at=utcnow().isoformat())
            db.add(candidate); db.flush()
            preview['body']['candidate_id'] = candidate.id
            if preview['kind']=='item': preview['body']['source_id'] = ref['id']
    preview.update(semester_id=sid,expected_revision=s.revision)
    if preview['kind'] in ('event', 'item'):
        preview['provided_fields'] = provided_fields
    preview['token']=fingerprint({'run_id': state['run_id'], 'preview': preview})
    state['preview']=preview
    return {'status':'needs_confirmation','preview':preview,'message':'尚未保存，请用户核对预览后点击确认。'}


def apply_preview(db,user,preview,*,confirm_fixed_conflicts=False,prepared_base_revision=None,selected_group_ids=None):
    s=owned_semester(db,user,preview['semester_id'],lock=True)
    source_guard(db, user, s.id, preview.get('source'), True)
    if s.revision!=preview['expected_revision']:error(409,'PREVIEW_STALE','安排已有更新，请重新生成修改预览')
    if preview['kind']=='batch':
        from .agent_batches import apply_batch
        return apply_batch(db,user,s,preview,selected_group_ids,confirm_fixed_conflicts)
    if preview['kind']=='undo':
        from .agent_undo import apply_undo
        return apply_undo(db,user,preview)
    data=deepcopy(preview['body'])
    if preview['kind'] in ('course_change','exam_change'):
        return apply_education(db,user,preview,confirm_fixed_conflicts=confirm_fixed_conflicts,prepared_base_revision=prepared_base_revision)
    if preview['kind']=='plan': return apply_agent_plan(db,user,preview)
    if preview['kind']=='operation':
        from .operations import apply_command
        return apply_command(db,user,preview['operation_id'],OperationAction.model_validate(data))
    if preview['kind']=='item':
        item = (edit_item_command(db, user, preview['target_id'], ItemEdit.model_validate(data))
                if preview['action'] == 'update' else create_item_command(db,user,ItemCreate.model_validate(data)))
        return {'semester_id':s.id,'revision':s.revision,'item':item}
    if preview['kind'] == 'item_state':
        from .items import set_lifecycle_command
        item = set_lifecycle_command(db, user, preview['target_id'], LifecycleInput.model_validate(data))
        return {'semester_id': s.id, 'revision': s.revision, 'item': item}
    action=preview['action']
    if action=='create':return events.create_event_command(db,user,EventFields.model_validate(data))
    if action=='update':return events.edit_event_command(db,user,preview['target_id'],EventEdit.model_validate(data))
    if action=='restore':return events.restore_event_command(db,user,preview['target_id'],EventCancel.model_validate(data),
        confirm_fixed_conflicts=confirm_fixed_conflicts)
    return events.cancel_event_command(db,user,preview['target_id'],EventCancel.model_validate(data))
