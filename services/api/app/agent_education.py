"""Educational notices use the same reality and exam rules as manual editing."""
from copy import deepcopy
from datetime import date, datetime
from typing import Literal
from collections import Counter
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
            'next_step': '用户肯定陈述这个范围没课/停课时准备scope停课预览；用户已请假/自行确认不上课用leave，打算申请用plan_leave，恢复出席用attend。出席调整保留学校课次时间地点；只提问时回答结论。'}


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
