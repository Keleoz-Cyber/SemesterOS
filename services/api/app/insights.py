"""Deterministic statistics from the user's saved semester records."""
from datetime import date, datetime, time, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from .academics import owned_semester
from .auth import current_user, error
from .capacity import merge
from .database import get_db
from .event_store import CATEGORIES, classification_value, event_rows, canonical_tag, canonical_tag_ids
from .models import CalendarTag, CourseMeeting, ItemRevision, PlanBlock, ProgressEntry, StudyItem, User
from .occurrences import effective_courses, expand
from .reminder_rules import SHANGHAI, instant, utcnow, notice_arrival_at, reservation_enabled
from .course_participation import course_requires_attendance, course_attendance_label

router = APIRouter()

BUCKETS = [*CATEGORIES, {'id': 'unclassified', 'name': '未分类'}]
DEFINITIONS = {
    'scheduled': '固定安排和个人计划分别按明确起止时间计算，明确要求的提前到场计入占用开始，裁剪到所选日期；各记录的时长相加，重叠仍分别计入。包括已预留的暂定安排，参考安排不计时长，不代表实际出席。',
    'occupied': '所选记录的明确时间区间取并集；重叠只计一次。筛选后按所选记录重新计算。',
    'actual': '仅累计进度记录中用户填写的实际分钟数，归入记录创建日（Asia/Shanghai），并非实际工作发生日。没有填写为未知，明确填写0保留为0；已完成任务的进度仍计入。',
    'classification': '使用当前分类与标签；计划和进度继承当前事项，课程固定为学业。作业及考试未指定分类时默认为学业，其他未指定为未分类。修改分类会重新归类历史记录。',
    'entry_count': '范围内来源记录数：每次课程、日程、事项截止、计划块、进度记录各算一条；同一记录命中多个标签只计一次。不是任务数，也不是天数。',
    'undated': '时间未知的事项和日程单列为当前学期上下文，不分配到任何日期，也不计入范围内条数和分钟数。',
    'unknown_duration': '范围内缺少明确起止区间的固定日程或考试数；截止、进度和未定日期上下文不计入此数。',
    'task_activity': '期间完成按事项审计中最近进入完成状态的记录时间（Asia/Shanghai）统计，且事项当前仍须完成；当前待办、逾期及无日期待办统计本学期当前状态。均使用当前分类和标签筛选，完成记录时间不作为任务截止日期。',
}
LIMITATIONS = [
    '计划时长不等于实际投入；剩余预计耗时不作为已完成时长。',
    '普通日期、周次或日期范围不推定全天占用；明确全天按日期另计，不补造钟点时长。',
    '实际分钟数未记录工作起止时间，无法与日程计算真实投入的重叠或效率。',
    '取消的日程、事项和计划不计安排；历史进度记录仍保留。分类按当前状态回溯，不是历史分类快照。',
]


def midnight(day):
    return datetime.combine(day, time.min, SHANGHAI)


def record(kind, source_id, title, **fields):
    return {'id': f'{kind}:{source_id}', 'resource_type': kind, 'resource_id': source_id,
            'title': title, 'category_id': 'unclassified', 'tags': [],
            'start_at': None, 'end_at': None, 'due_at': None, 'date': None,
            'week': None, 'end_date': None, 'time_precision': 'unknown',
            'scheduled_minutes': None, 'actual_minutes': None, 'fixed': False,
            'classification_basis': 'current', **fields}


def source_records(db, user, semester):
    """Keep source identities unique; do not join tags into duration rows."""
    courses = expand({'first_monday': semester.first_monday, 'periods': semester.periods},
                     effective_courses(db, user, semester))
    records = [record('course', c['id'], c['title'], resource_id=c.get('course_id'),
                      start_at=c['start_at'], end_at=c['end_at'], time_precision='exact',
                      category_id='study', fixed=course_requires_attendance(c),
                      attendance_exempt=bool(c.get('attendance_exempt')),
                      attendance_status=c.get('attendance_status'), attendance_reason=c.get('attendance_reason', ''),
                      attendance_label=course_attendance_label(c),
                      classification_basis='course_default') for c in courses]
    items = list(db.scalars(select(StudyItem).where(StudyItem.user_id == user.id,
        StudyItem.semester_id == semester.id)))
    by_id = {i.id: i for i in items}
    labels = {i.id: classification_value(db, i) for i in items}
    facts = [('event', e) for e in event_rows(db, user, semester.id)]
    facts += [('exam' if i.payload['kind'] == 'exam' else 'deadline', i)
              for i in items if i.lifecycle != 'cancelled']
    for kind, row in facts:
        p = row.payload; t = p['time']
        fixed_time = kind in ('event', 'exam') and t.get('meaning') not in ('window', 'candidate', 'course_anchor')
        reserved = reservation_enabled(p, kind)
        fixed = fixed_time and reserved
        deadline = kind == 'deadline' and t.get('meaning') not in ('window', 'candidate', 'course_anchor', 'start')
        arrival = notice_arrival_at(p) if fixed_time else None
        records.append(record(kind, row.id, p['title'], **classification_value(db, row),
            start_at=t.get('at') if fixed_time else None, end_at=t.get('end_at') if fixed_time else None,
            due_at=t.get('at') if deadline else None, date=t.get('date'), week=t.get('week'),
            end_date=t.get('end_date'), time_precision=t['precision'], fixed=fixed,
            certainty=p.get('certainty'), lifecycle=row.lifecycle, version=row.version, time=t,
            course_id=p.get('course_id'),item_kind=p.get('kind'),
            reserve_time=reserved if kind in ('event','exam') else p.get('reserve_time', True),
            arrival_at=arrival.isoformat() if arrival else None,
            occupancy_start_at=(arrival.isoformat() if arrival else t.get('at')) if fixed else None,
            all_day=t.get('meaning')=='all_day'))
    for p in db.scalars(select(PlanBlock).where(PlanBlock.user_id == user.id,
            PlanBlock.semester_id == semester.id, PlanBlock.status == 'active')):
        if p.item_id not in by_id or by_id[p.item_id].lifecycle == 'cancelled':
            continue
        records.append(record('plan', p.id, by_id[p.item_id].payload['title'],
            resource_id=p.item_id, plan_id=p.id, start_at=p.start_at, end_at=p.end_at,
            course_id=by_id[p.item_id].payload.get('course_id'),
            time_precision='exact', **labels[p.item_id], classification_basis='current_item'))
    progress = db.scalars(select(ProgressEntry).join(StudyItem, ProgressEntry.item_id == StudyItem.id).where(
        ProgressEntry.user_id == user.id, StudyItem.user_id == user.id, StudyItem.semester_id == semester.id))
    for p in progress:
        if p.payload.get('undone'):
            continue
        records.append(record('progress', p.id, by_id[p.item_id].payload['title'],
            resource_id=p.item_id, progress_id=p.id, recorded_at=p.created_at,
            date=instant(p.created_at).astimezone(SHANGHAI).date().isoformat(), time_precision='date',
            actual_minutes=p.payload.get('actual_minutes'), **labels[p.item_id],
            course_id=by_id[p.item_id].payload.get('course_id'),
            classification_basis='current_item'))
    for r in records:
        r['category_id'] = r['category_id'] or 'unclassified'
    return records


def date_window(entry, semester):
    """A coarse window selects context only; it never creates occupancy."""
    if entry['start_at'] or entry['due_at']:
        a = instant(entry.get('occupancy_start_at') or entry['start_at'] or entry['due_at'])
        b = instant(entry['end_at'] or entry['start_at'] or entry['due_at'])
        return a, b
    if entry['date']:
        return midnight(date.fromisoformat(entry['date'])), midnight(
            date.fromisoformat(entry['end_date'] or entry['date']) + timedelta(days=1))
    if entry['week']:
        day = date.fromisoformat(semester.first_monday) + timedelta(days=(entry['week'] - 1) * 7)
        return midnight(day), midnight(day + timedelta(days=7))
    if entry.get('time', {}).get('at'):
        t = entry['time']
        return instant(t['at']), instant(t.get('end_at') or t['at'])
    return None


@router.get('/semesters/{sid}/insights')
def insights(sid: str, from_date: date = Query(), to_date: date = Query(),
             category_id: str | None = Query(default=None, max_length=40),
             tag_ids: str | None = Query(default=None, max_length=2000),
             user: User = Depends(current_user), db: Session = Depends(get_db)):
    semester = owned_semester(db, user, sid, lock=True)
    days = (to_date - from_date).days + 1
    if days < 1 or days > 366 or to_date == date.max:
        error(422, 'INVALID_RANGE', '请核对查询日期，范围最多366天（含首尾）')
    if category_id is not None and category_id not in {c['id'] for c in BUCKETS}:
        error(422, 'INVALID_CATEGORY', '请选择已有分类')
    selected_tags = sorted({t.strip() for t in (tag_ids or '').split(',') if t.strip()})
    tags = [{'id': t.id, 'name': t.name} for t in db.scalars(select(CalendarTag).where(
        CalendarTag.user_id == user.id, CalendarTag.merged_into.is_(None)).order_by(CalendarTag.name, CalendarTag.id))]
    if any(canonical_tag(db, user.id, tid) is None for tid in selected_tags):
        error(404, 'NOT_FOUND', '找不到所选标签')
    selected_tags = sorted(canonical_tag_ids(db, user.id, selected_tags))
    begin = midnight(from_date); end = midnight(to_date + timedelta(days=1))
    daily = {str(from_date + timedelta(days=i)): {'date': str(from_date + timedelta(days=i)),
        'fixed_scheduled_minutes': 0, 'personal_planned_minutes': 0,
        'occupied_union_minutes': 0, 'actual_minutes': None} for i in range(days)}
    spans = {day: [] for day in daily}
    categories = {c['id']: {**c, 'entry_count': 0, 'scheduled_minutes': 0, 'actual_minutes': None} for c in BUCKETS}
    records = []; undated = []; unknown = 0
    for r in source_records(db, user, semester):
        if category_id is not None and r['category_id'] != category_id:
            continue
        if selected_tags and not set(selected_tags).intersection(t['id'] for t in r['tags']):
            continue
        window = date_window(r, semester)
        if window is None:
            undated.append(r); continue
        a, b = window
        if not (begin <= a < end if a == b else a < end and b > begin):
            continue
        bucket = categories[r['category_id']]; bucket['entry_count'] += 1
        if r['start_at'] and r['end_at'] and (r['fixed'] or r['resource_type'] == 'plan'):
            a, b = max(a, begin), min(b, end)
            r['scheduled_minutes'] = (b - a).total_seconds() / 60
            bucket['scheduled_minutes'] += r['scheduled_minutes']
            cursor = a.astimezone(SHANGHAI)
            while cursor < b:
                boundary = min(b, midnight(cursor.date() + timedelta(days=1)))
                day = cursor.date().isoformat()
                key = 'fixed_scheduled_minutes' if r['fixed'] else 'personal_planned_minutes'
                daily[day][key] += (boundary - cursor).total_seconds() / 60
                spans[day].append((cursor.timestamp(), boundary.timestamp()))
                cursor = boundary.astimezone(SHANGHAI)
        elif r['fixed'] and not r.get('all_day'):
            unknown += 1
        actual = r['actual_minutes']
        if actual is not None:
            daily[r['date']]['actual_minutes'] = (daily[r['date']]['actual_minutes'] or 0) + actual
            bucket['actual_minutes'] = (bucket['actual_minutes'] or 0) + actual
        records.append(r)
    for day, row in daily.items():
        row['occupied_union_minutes'] = sum(b - a for a, b in merge(spans[day])) / 60
    summary = {key: sum(row[key] for row in daily.values()) for key in (
        'fixed_scheduled_minutes', 'personal_planned_minutes', 'occupied_union_minutes')}
    actual_values = [r['actual_minutes'] for r in daily.values() if r['actual_minutes'] is not None]
    summary.update(entry_count=len(records), actual_minutes=sum(actual_values) if actual_values else None,
                   unknown_duration_count=unknown, undated_count=len(undated),
                   all_day_count=sum(bool(r.get('all_day')) and r['fixed'] for r in records))
    current=utcnow();today=current.astimezone(SHANGHAI).date()
    tasks=[r for r in records if r['resource_type']=='deadline']
    def past_deadline(r):
        if r.get('certainty')!='formal':return False
        t=r.get('time') or {}
        if t.get('meaning') not in (None,'unspecified','deadline'):return False
        if r.get('due_at'):return instant(r['due_at'])<=current
        if r.get('date'):return date.fromisoformat(r.get('end_date') or r['date'])<today
        return False
    task_summary={'active':sum(r.get('lifecycle')=='active' for r in tasks),
        'completed':sum(r.get('lifecycle')=='completed' for r in tasks),
        'overdue':sum(r.get('lifecycle')=='active' and past_deadline(r) for r in tasks),
        'scope_label':'范围内任务状态（按截止日期筛选）',
        'completed_definition':'完成数是截止落在范围内的任务当前状态，不表示在这段时间完成。'}
    summary['tasks']=task_summary
    # Current activity is independent of the due-date window. In particular,
    # completing an undated task must not manufacture a deadline to be counted.
    activity_items=[]
    for item in db.scalars(select(StudyItem).where(StudyItem.user_id==user.id,
            StudyItem.semester_id==sid)):
        if item.payload.get('kind') not in ('task','assignment'):continue
        labels=classification_value(db,item)
        if category_id is not None and (labels['category_id'] or 'unclassified')!=category_id:continue
        if selected_tags and not set(selected_tags).intersection(t['id'] for t in labels['tags']):continue
        activity_items.append(item)
    task_activity={'completed_in_range':0,'active_current':0,'overdue_current':0,'undated_active':0}
    completed_ids={item.id for item in activity_items if item.lifecycle=='completed'}
    for item in activity_items:
        if item.lifecycle!='active':continue
        task_activity['active_current']+=1
        p=item.payload;t=p.get('time') or {}
        r=record('deadline',item.id,p['title'],time=t,certainty=p.get('certainty'),
            due_at=t.get('at'),date=t.get('date'),week=t.get('week'),end_date=t.get('end_date'))
        if past_deadline(r):task_activity['overdue_current']+=1
        if date_window(r,semester) is None:task_activity['undated_active']+=1
    previous_states={};completion_times={}
    if completed_ids:
        revisions=db.scalars(select(ItemRevision).join(StudyItem,StudyItem.id==ItemRevision.item_id).where(
            ItemRevision.user_id==user.id,StudyItem.user_id==user.id,StudyItem.semester_id==sid,
            StudyItem.lifecycle=='completed').order_by(ItemRevision.item_id,ItemRevision.version,
                ItemRevision.created_at,ItemRevision.id))
        for revision in revisions:
            if revision.item_id not in completed_ids:continue
            state=revision.snapshot.get('lifecycle')
            if state not in ('active','completed','cancelled'):continue
            previous=previous_states.get(revision.item_id)
            authoritative=revision.reason in ('用户确认完成','用户确认完成并更新进度')
            if state=='completed' and previous!='completed' and (previous is not None or authoritative):
                completion_times[revision.item_id]=instant(revision.created_at)
            previous_states[revision.item_id]=state
        task_activity['completed_in_range']=sum(begin<=at<end for at in completion_times.values())
    course_titles={c.id:c.payload['title'] for c in db.scalars(select(CourseMeeting).where(
        CourseMeeting.user_id==user.id,CourseMeeting.semester_id==sid))}
    course_summary={}
    for r in records:
        course_id=r.get('resource_id') if r['resource_type']=='course' else r.get('course_id')
        if not course_id:continue
        row=course_summary.setdefault(course_id,{'course_id':course_id,'title':course_titles.get(course_id,r['title']),
            'course_scheduled_minutes':0,'personal_planned_minutes':0,'actual_minutes':None})
        if r['resource_type']=='course':row['course_scheduled_minutes']+=r.get('scheduled_minutes') or 0
        if r['resource_type']=='plan':row['personal_planned_minutes']+=r.get('scheduled_minutes') or 0
        if r['resource_type']=='progress' and r.get('actual_minutes') is not None:
            row['actual_minutes']=(row['actual_minutes'] or 0)+r['actual_minutes']
    records.sort(key=lambda r: (date_window(r, semester)[0], r['id']))
    undated.sort(key=lambda r: (r['title'], r['id']))
    return {'semester_id': sid, 'revision': semester.revision, 'from_date': str(from_date),
            'to_date': str(to_date), 'timezone': 'Asia/Shanghai', 'generated_at': utcnow().isoformat(),
            'definition_version': '1', 'filters': {'category_id': category_id, 'tag_ids': selected_tags},
            'summary': summary, 'daily': list(daily.values()), 'categories': list(categories.values()),
            'task_summary':task_summary,'task_activity':task_activity,'course_summary':list(course_summary.values()),
            'tags': tags, 'records': records, 'undated': undated, 'definitions': DEFINITIONS,
            'limitations': LIMITATIONS}
