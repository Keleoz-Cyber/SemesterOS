"""Deterministic statistics from the user's saved semester records."""
from datetime import date, datetime, time, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from .academics import owned_semester
from .auth import current_user, error
from .capacity import merge
from .database import get_db
from .event_store import CATEGORIES, classification_value, event_rows
from .models import CalendarTag, PlanBlock, ProgressEntry, StudyItem, User
from .occurrences import effective_courses, expand
from .reminder_rules import SHANGHAI, instant, utcnow

router = APIRouter()

BUCKETS = [*CATEGORIES, {'id': 'unclassified', 'name': '未分类'}]
DEFINITIONS = {
    'scheduled': '固定安排和个人计划分别按明确起止时间计算，裁剪到所选日期；各记录的时长相加，重叠仍分别计入。包括暂定安排，不代表实际出席。',
    'occupied': '所选记录的明确时间区间取并集；重叠只计一次。筛选后按所选记录重新计算。',
    'actual': '仅累计进度记录中用户填写的实际分钟数，归入记录创建日（Asia/Shanghai），并非实际工作发生日。没有填写为未知，明确填写0保留为0；已完成任务的进度仍计入。',
    'classification': '使用当前分类与标签；计划和进度继承当前事项，课程固定为学业。作业及考试未指定分类时默认为学业，其他未指定为未分类。修改分类会重新归类历史记录。',
    'entry_count': '范围内来源记录数：每次课程、日程、事项截止、计划块、进度记录各算一条；同一记录命中多个标签只计一次。不是任务数，也不是天数。',
    'undated': '时间未知的事项和日程单列为当前学期上下文，不分配到任何日期，也不计入范围内条数和分钟数。',
    'unknown_duration': '范围内缺少明确起止区间的固定日程或考试数；截止、进度和未定日期上下文不计入此数。',
}
LIMITATIONS = [
    '计划时长不等于实际投入；剩余预计耗时不作为已完成时长。',
    '仅有日期、周次或日期范围时，不推定全天占用，也不均分时长到各天。',
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
                      category_id='study', fixed=True, classification_basis='course_default') for c in courses]
    items = list(db.scalars(select(StudyItem).where(StudyItem.user_id == user.id,
        StudyItem.semester_id == semester.id)))
    by_id = {i.id: i for i in items}
    labels = {i.id: classification_value(db, i) for i in items}
    facts = [('event', e) for e in event_rows(db, user, semester.id)]
    facts += [('exam' if i.payload['kind'] == 'exam' else 'deadline', i)
              for i in items if i.lifecycle != 'cancelled']
    for kind, row in facts:
        p = row.payload; t = p['time']; fixed = kind in ('event', 'exam')
        records.append(record(kind, row.id, p['title'], **classification_value(db, row),
            start_at=t.get('at') if fixed else None, end_at=t.get('end_at') if fixed else None,
            due_at=t.get('at') if not fixed else None, date=t.get('date'), week=t.get('week'),
            end_date=t.get('end_date'), time_precision=t['precision'], fixed=fixed,
            certainty=p.get('certainty'), lifecycle=row.lifecycle, version=row.version))
    for p in db.scalars(select(PlanBlock).where(PlanBlock.user_id == user.id,
            PlanBlock.semester_id == semester.id, PlanBlock.status == 'active')):
        if p.item_id not in by_id or by_id[p.item_id].lifecycle == 'cancelled':
            continue
        records.append(record('plan', p.id, by_id[p.item_id].payload['title'],
            resource_id=p.item_id, plan_id=p.id, start_at=p.start_at, end_at=p.end_at,
            time_precision='exact', **labels[p.item_id], classification_basis='current_item'))
    progress = db.scalars(select(ProgressEntry).join(StudyItem, ProgressEntry.item_id == StudyItem.id).where(
        ProgressEntry.user_id == user.id, StudyItem.user_id == user.id, StudyItem.semester_id == semester.id))
    for p in progress:
        records.append(record('progress', p.id, by_id[p.item_id].payload['title'],
            resource_id=p.item_id, progress_id=p.id, recorded_at=p.created_at,
            date=instant(p.created_at).astimezone(SHANGHAI).date().isoformat(), time_precision='date',
            actual_minutes=p.payload.get('actual_minutes'), **labels[p.item_id],
            classification_basis='current_item'))
    for r in records:
        r['category_id'] = r['category_id'] or 'unclassified'
    return records


def date_window(entry, semester):
    """A coarse window selects context only; it never creates occupancy."""
    if entry['start_at'] or entry['due_at']:
        a = instant(entry['start_at'] or entry['due_at'])
        b = instant(entry['end_at']) if entry['end_at'] else a
        return a, b
    if entry['date']:
        return midnight(date.fromisoformat(entry['date'])), midnight(
            date.fromisoformat(entry['end_date'] or entry['date']) + timedelta(days=1))
    if entry['week']:
        day = date.fromisoformat(semester.first_monday) + timedelta(days=(entry['week'] - 1) * 7)
        return midnight(day), midnight(day + timedelta(days=7))
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
        CalendarTag.user_id == user.id).order_by(CalendarTag.name, CalendarTag.id))]
    if not set(selected_tags).issubset({t['id'] for t in tags}):
        error(404, 'NOT_FOUND', '找不到所选标签')
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
        if r['start_at'] and r['end_at']:
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
        elif r['fixed']:
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
                   unknown_duration_count=unknown, undated_count=len(undated))
    records.sort(key=lambda r: (date_window(r, semester)[0], r['id']))
    undated.sort(key=lambda r: (r['title'], r['id']))
    return {'semester_id': sid, 'revision': semester.revision, 'from_date': str(from_date),
            'to_date': str(to_date), 'timezone': 'Asia/Shanghai', 'generated_at': utcnow().isoformat(),
            'definition_version': '1', 'filters': {'category_id': category_id, 'tag_ids': selected_tags},
            'summary': summary, 'daily': list(daily.values()), 'categories': list(categories.values()),
            'tags': tags, 'records': records, 'undated': undated, 'definitions': DEFINITIONS,
            'limitations': LIMITATIONS}
