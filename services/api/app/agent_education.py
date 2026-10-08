"""Educational notices use the same reality and exam rules as manual editing."""
from copy import deepcopy
from datetime import date, datetime
from typing import Literal
from collections import Counter
import json
import re
from pydantic import Field, field_validator, model_validator
from .schemas import Input
from .item_schemas import ItemTime, NoticeDetails
from .change_schemas import ChangeInput, ChangeApply
from .exam_schemas import ExamChangeInput, ExamChangeApply
from .auth import error
from .academics import fingerprint
from .reminder_rules import instant, SHANGHAI
from . import changes, exam_planning
from .occurrences import effective_courses, expand
from .course_participation import course_requires_attendance, course_attendance_label


class OccurrenceQuery(Input):
    from_date: date
    to_date: date
    query: str = Field(default='', max_length=120)
    course_id: str | None = Field(default=None, max_length=36)

    @model_validator(mode='after')
    def bounded(self):
        if not 0 <= (self.to_date-self.from_date).days < 210:
            raise ValueError('请检查日期范围，每次可查询最多30周')
        return self


class CourseChange(Input):
    kind: Literal['move', 'cancel', 'suspend', 'add', 'leave', 'plan_leave', 'attend']
    targets: list[str] = Field(default_factory=list, max_length=1000)
    scope: OccurrenceQuery | None = Field(default=None,
        description='范围停课或个人出席调整可直接传已查询的from_date/to_date/query/course_id，包含该查询的全部课次，不必列出targets。')
    title: str | None = Field(default=None, min_length=1, max_length=120)
    start_at: datetime | None = None
    end_at: datetime | None = None
    location: str | None = Field(default=None, max_length=120)

    @field_validator('start_at', 'end_at')
    @classmethod
    def aware(cls, value):
        return ItemTime.aware(value)

    @model_validator(mode='after')
    def range_scope(self):
        if self.scope is not None and (self.kind == 'add' or self.targets):
            raise ValueError('课次修改使用scope或targets其中一种，补课不指定原课次范围')
        if self.kind in ('leave', 'plan_leave', 'attend') and self.scope is None and not self.targets:
            raise ValueError('请明确选择需要调整出席的课次或已查询范围')
        return self


class ExamChange(Input):
    exam_id: str = Field(min_length=1, max_length=36)
    time: ItemTime
    certainty: Literal['formal','tentative','unknown']
    location: str | None = Field(default=None, max_length=120)
    reserve_time: bool | None = None
    align_review_deadlines: bool = False
    details: NoticeDetails | None = None


def query_occurrences(db,user,s,state,args):
    courses=expand({'first_monday':s.first_monday,'periods':s.periods},effective_courses(db,user,s))
    q=''.join(args.query.casefold().split())
    found=[e for e in courses if e.get('reality_kind')=='course' and
           args.from_date <= instant(e['start_at']).astimezone(SHANGHAI).date() <= args.to_date and
           (not args.course_id or e.get('course_id')==args.course_id) and q in ''.join(e['title'].casefold().split())]
    if len(found)>1000:error(422,'TOO_MANY_RESULTS','课次超过1000条，请缩小日期范围或补充课程名称')
    records=[{**e,'resource_type':'course_occurrence','resource_id':e['id'],'queried_revision':s.revision,
        'attendance_status':e.get('attendance_status'),'attendance_reason':e.get('attendance_reason',''),
        'attendance_label':course_attendance_label(e),'fixed':course_requires_attendance(e)} for e in found]
    known={**state.get('occurrence_records',{}),**{e['id']:e for e in records}}
    state['occurrence_records']=known
    state['occurrence_queries']=[*state.get('occurrence_queries',[]),[e['id'] for e in records]][-8:]
    scopes = dict(state.get('occurrence_query_scopes', {}))
    scopes[fingerprint(args.model_dump(mode='json'))] = {'ids': [e['id'] for e in records], 'revision': s.revision}
    state['occurrence_query_scopes'] = dict(list(scopes.items())[-8:])
    counts=Counter(e['title'].casefold() for e in records)
    ambiguous=set(state.get('ambiguous_ids',[]))
    for e in records:
        if counts[e['title'].casefold()]>1 and e['id'] not in state.get('selected_record_ids',[]):ambiguous.add(e['id'])
    state['ambiguous_ids']=sorted(ambiguous)
    value={'occurrences':records,'revision':s.revision,'from_date':str(args.from_date),'to_date':str(args.to_date)}
    from .agent_cards import append_card
    append_card(state, 'course_occurrences', {**value, 'total_count':len(records),
        'navigation_query':{'semester_id':s.id, **args.model_dump(mode='json')}})
    return {**value, 'occurrences': records[:100], 'total_count': len(records),
            'truncated': len(records) > 100, 'query_scope': args.model_dump(mode='json'),
            'next_step': '用户肯定陈述这个范围没课/停课时准备scope停课预览；用户明确已请假或直接要求记录已请假状态才用leave，打算申请用plan_leave。外出、开会、不能上课本身不代表已请假；要求记录活动时先prepare_event再核对实际冲突，不擅自修改出勤。恢复出席用attend。出席调整保留学校课次时间地点；只提问时回答结论。'}


def leave_record_intent(text):
    """Return the latest explicit attendance decision, including a withdrawal."""
    decision = None
    clauses = re.split(r'[，。；;\n]|但是|不过|其实|现在|后来', text)
    for clause in clauses:
        denied = re.search(
            r'(?:不|未|没(?:有)?|尚未|还(?:没|未)|并未|没有).{0,4}'
            r'(?:请.{0,12}假|准假|获准|获批|批准|同意|允许|批|通过)'
            r'|(?:拒绝|驳回|否决|撤销|撤回|收回|取消).{0,12}(?:请假|准假|批准|同意|允许|申请)'
            r'|(?:请假|申请).{0,8}(?:被拒|被驳回|被撤销|已取消|不准确|不算|没通过|未通过)'
            r'|不用请假|无需请假|恢复.{0,6}(?:上课|出席)', clause)
        if denied:
            decision = False
            continue
        if not re.search(r'请[^，。；;\n]{0,20}假|准假|获准|获批|批(?:了|好|准)|批准|同意|允许', clause):
            continue
        uncertain = re.search(r'怎么|如何|是否|能否|可否|是不是|不确定|不清楚|可能|也许|如果|假如|要是', clause)
        status_question = re.search(r'(?:请.{0,20}假|准假|获准|获批|批准|同意|允许).{0,12}(?:吗|么)', clause)
        record_command = re.search(r'(?:标记|记录|登记|设为|改为|记为).{0,12}请.{0,12}假', clause)
        if uncertain or status_question and not record_command:
            decision = False
            continue
        planned = re.search(r'(?:准备|打算|想|需要|要|会|申请)请[^，。；;\n]{0,20}假|请假申请|提交.{0,4}请假|等待.{0,6}(?:批准|审批|同意)|还没|尚未|未获|没批|没请|未请|没有请假|没有批准|不用请假|无需请假', clause)
        completed = re.search(r'已(?:经)?(?:请[^，。；;\n]{0,20}假|获准|获批|批准)|请(?:了|过)[^，。；;\n]{0,20}假|获准|获批|批了|批准了|同意了|允许了|(?:申请|审批|请假).{0,6}(?:已(?:经)?通过|通过了)', clause)
        decision = bool(not planned or completed)
    return decision


def has_leave_record_intent(text):
    """Activities alone never authorize an AI-proposed excused attendance record."""
    return leave_record_intent(text) is True


def leave_target_clarification(text):
    """A target answer can continue the same request, never an unrelated activity."""
    if len(text) > 120 or re.search(r'外出|出差|开会|会议|参会|参加|活动|旅游|申请|准备|打算|撤销|取消|恢复', text):
        return False
    return bool(re.fullmatch(r'\s*(?:对|是的|没错|嗯|好|好的|确认)[，,。.!！\s]*', text)
                or re.search(r'(?:这|那|该).{0,8}(?:节|次|课)|上午|下午|晚上|早上|周[一二三四五六日天]'
                             r'|星期[一二三四五六日天]|第[一二三四五六七八九十0-9]+(?:节|次|个)|全部|都记录', text))


def human_request(content):
    """Unwrap the server's request envelope without reading quoted source data."""
    ids = set()
    for _ in range(8):
        if not isinstance(content, str):
            return None
        try:
            value = json.loads(content)
        except (ValueError, TypeError):
            return {'text': content, 'occurrence_ids': ids}
        if not isinstance(value, dict) or not isinstance(value.get('request'), str):
            return None  # Profile and preview-status messages are server context.
        ids.update(value.get('selected_record_ids', []))
        ids.update(e['id'] for e in value.get('context_records', [])
                   if e.get('resource_type') == 'course_occurrence' and e.get('id'))
        content = value['request']
    return None


def leave_record_authorized(state, targets):
    """Only human requests authorize leave; read results can bind their targets."""
    if state.get('input_kind', 'message') != 'message':
        return False
    requests = []
    for message in state.get('messages', []):
        if message.get('role') == 'user':
            request = human_request(message.get('content'))
            if request is not None:
                requests.append(request)
        elif message.get('role') == 'tool' and requests:
            try:
                result = json.loads(message.get('content', ''))
            except (ValueError, TypeError):
                continue
            if isinstance(result, dict):
                requests[-1]['occurrence_ids'].update(e['id'] for e in result.get('occurrences', [])
                                                      if isinstance(e, dict) and e.get('id'))
    current = state.get('current_user_text')
    if current is None:
        current = requests[-1]['text'] if requests else ''
    decision = leave_record_intent(current)
    if decision is not None:
        return decision
    if not leave_target_clarification(current):
        return False
    if requests and requests[-1]['text'] == current:
        requests.pop()
    for request in reversed(requests):
        previous = request['text']
        decision = leave_record_intent(previous)
        if decision is not None:
            return decision and bool(targets) and set(targets).issubset(request['occurrence_ids'])
        if not leave_target_clarification(previous):
            return False
    return False


def prepare_course(db,user,s,state,args,source):
    known=state.get('occurrence_records',{})
    targets = args.targets
    if args.scope is not None:
        query = state.get('occurrence_query_scopes', {}).get(fingerprint(args.scope.model_dump(mode='json')))
        if query is None: error(422, 'READ_FIRST', '请先查询这个范围的课程')
        if query['revision'] != s.revision: error(409, 'COURSE_QUERY_STALE', '课表已更新，请重新查询这个范围')
        targets = query['ids']
        if not targets: error(422, 'NO_OCCURRENCES', '这个范围没有可调整的课次')
        if args.kind in ('move', 'cancel') and len(targets) != 1:
            error(422, 'AMBIGUOUS_TARGET', '这个范围有多次课，请补充原上课日期，或使用范围停课')
    if args.kind == 'leave' and not leave_record_authorized(state, targets):
        error(422, 'ATTENDANCE_INTENT_REQUIRED',
            '这条请求没有已请假或记录请假状态的陈述。外出、开会不代表已请假；请先记录活动并核对实际冲突，打算申请时用plan_leave。无需索取学校证明。')
    if not set(targets).issubset(known):error(422,'READ_FIRST','请先查询并核对具体日期的课次')
    if any(known[id].get('queried_revision')!=s.revision for id in targets):
        error(409,'COURSE_QUERY_STALE','查询后安排已有变化，请重新查询原课次再准备修改')
    whole_group = args.kind in ('suspend', 'leave', 'plan_leave', 'attend') and len(targets) > 1 and any(
        set(targets) == set(group) for group in state.get('occurrence_queries', []))
    if args.scope is None and not whole_group and set(targets)&set(state.get('ambiguous_ids',[])):
        error(422,'AMBIGUOUS_TARGET','同名课程有多个课次，请让用户选择单次课或核对整组课次')
    old=[known[id] for id in targets]
    titles={'suspend':'课程停课','leave':'课程请假','plan_leave':'课程待请假','attend':'恢复课程出席'}
    title=old[0]['title'] if len(old)==1 else args.title or titles.get(args.kind,'')
    if not title:error(422,'TITLE_REQUIRED','新增课程需要明确课程名称')
    location=args.location if args.location is not None else (old[0].get('location','') if len(old)==1 else '')
    end_at = args.end_at
    if args.kind == 'move' and args.start_at is not None and end_at is None and len(old) == 1:
        end_at = args.start_at + (instant(old[0]['end_at']) - instant(old[0]['start_at']))
    body=ChangeInput(kind=args.kind,targets=targets,title=title,source_text=source,
        source_id=(state.get('source') or {}).get('id'),start_at=args.start_at,end_at=end_at,location=location)
    value=changes.preview_change_command(db,user,s.id,body,agent_run_id=state['run_id'])
    patch=value['patch']
    return {'kind':'course_change','action':args.kind,'change_id':value['id'],'target_id':None,
        'title':title,'before':patch['before'],'after':patch['after'],'impact':value['impact'],
        'body':{'expected_revision':s.revision},'agent_run_id':state['run_id']}


def prepare_exam(db,user,s,state,args,source):
    if args.exam_id not in state.get('known_ids',[]):error(422,'READ_FIRST','请先查找并核对考试')
    if args.exam_id in state.get('ambiguous_ids',[]):error(422,'AMBIGUOUS_TARGET','有多条同名考试，请先明确要修改哪一条')
    exam=exam_planning.owned_exam(db,user,args.exam_id)
    if exam.semester_id!=s.id:error(404,'NOT_FOUND','找不到本学期的考试')
    body=ExamChangeInput(expected_version=exam.version,time=args.time,certainty=args.certainty,
        details=args.details,
        location=exam.payload.get('location','') if args.location is None else args.location,
        reserve_time=exam.payload.get('reserve_time',True) if args.reserve_time is None else args.reserve_time,
        align_review_deadlines=args.align_review_deadlines,reason=source[:500])
    detail=exam_planning.exam_change_context(db,user,exam,body)[3]
    token=fingerprint({'agent_run_id':state['run_id'],'exam_preview':detail['preview_token']})
    return {'kind':'exam_change','action':'update','target_id':exam.id,'before':detail['before'],'agent_run_id':state['run_id'],
        'after':detail['after'],'title':exam.payload['title'],'reviews':detail['reviews'],
        'impact':{k:v for k,v in detail.items() if k!='preview_token'},
        'body':{**body.model_dump(mode='json',exclude_unset=True),'expected_revision':s.revision,'preview_token':token}}


def apply_education(db,user,preview,*,confirm_fixed_conflicts=False,prepared_base_revision=None):
    data=deepcopy(preview['body']);data['confirm_fixed_conflicts']=confirm_fixed_conflicts
    if preview['kind']=='course_change':
        return changes.apply_change_command(db,user,preview['change_id'],ChangeApply.model_validate(data),
            agent_run_id=preview['agent_run_id'],prepared_base_revision=prepared_base_revision)
    # Agent-bound tokens cannot be replayed through the legacy manual endpoint.
    # Batch caller already validated original dependencies before rebasing.
    exam=exam_planning.owned_exam(db,user,preview['target_id'])
    request=ExamChangeInput.model_validate({k:v for k,v in data.items() if k in ExamChangeInput.model_fields})
    current_token=exam_planning.exam_change_context(db,user,exam,request)[3]['preview_token']
    if prepared_base_revision is None and fingerprint({'agent_run_id':preview['agent_run_id'],'exam_preview':current_token})!=data['preview_token']:
        error(409,'PREVIEW_STALE','考试或关联提醒已有更新，请重新核对')
    data['preview_token']=current_token
    return exam_planning.apply_exam_command(db,user,preview['target_id'],ExamChangeApply.model_validate(data))
