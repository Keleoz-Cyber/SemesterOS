"""One projection shared by timetable, capacity and the solver."""
from datetime import date,datetime,time,timedelta
from sqlalchemy import select
from .models import CourseMeeting,RealityChange
from .reminder_rules import SHANGHAI,instant


def expand(calendar,courses):
    periods={p['number']:p for p in calendar['periods']};events=[]
    for c in courses:
        if 'occurrences' in c:
            events.extend(c['occurrences']);continue
        groups=[]
        for section in sorted(c['sections']):
            if not groups or groups[-1][-1]+1!=section:groups.append([])
            groups[-1].append(section)
        for week in c['weeks']:
            day=date.fromisoformat(calendar['first_monday'])+timedelta(days=(week-1)*7+c['weekday']-1)
            for group in groups:
                start=datetime.combine(day,time.fromisoformat(c.get('start_time') or periods[group[0]]['start']),SHANGHAI)
                end=datetime.combine(day,time.fromisoformat(c.get('end_time') or periods[group[-1]]['end']),SHANGHAI)
                events.append({**c,'course_id':c.get('id'), 'id':f"{c.get('id',c['title'])}:{day}:{group[0]}",
                    'start_at':start.isoformat(),'end_at':end.isoformat(),'sections':group,'reality_kind':'course'})
    return sorted(events,key=lambda e:(instant(e['start_at']),e['id']))


def apply_patch(events,patch):
    rows={e['id']:dict(e) for e in events}
    for e in patch['before']:rows.pop(e['id'],None)
    for e in patch['after']:rows[e['id']]=dict(e)
    return sorted(rows.values(),key=lambda e:(instant(e['start_at']),e['id']))


def replay_course_patch(events, patch, courses, *, original_monday=None, current_monday=None, base_events=()):
    """Replay exceptions against corrected base rows without editing history.

    Section changes can alter occurrence IDs. A same-course/day replacement
    remains the exception's target when there is one unambiguous matching row.
    Deleted base courses cannot be resurrected by an earlier move exception.
    """
    rows = {e['id']: dict(e) for e in events}
    old_rows = {e['id']: e for e in patch['before']}
    def base_day(e):
        day = instant(e['start_at']).astimezone(SHANGHAI).date()
        if current_monday and e.get('course_id') in courses and not e.get('changed'):
            first = date.fromisoformat(original_monday or current_monday)
            week = (day - first).days // 7
            return date.fromisoformat(current_monday) + timedelta(days=week * 7 + courses[e['course_id']]['weekday'] - 1)
        return day

    def matching(rows, old):
        if old.get('changed'):
            origin = old.get('origin_occurrence_id', old['id'])
            choices = [e for e in rows if e.get('course_id') == old.get('course_id')
                and e.get('origin_occurrence_id', e['id']) == origin and e.get('changed')]
            return choices[0] if len(choices) == 1 else None
        candidates = [e for e in rows if e.get('course_id') == old.get('course_id')
            and instant(e['start_at']).astimezone(SHANGHAI).date() == base_day(old)]
        overlap = [e for e in candidates if set(e.get('sections', [])) & set(old.get('sections', []))]
        choices = overlap or candidates
        return choices[0] if len(choices) == 1 else None
    mapped = {}
    for old in patch['before']:
        shifted = base_day(old) != instant(old['start_at']).astimezone(SHANGHAI).date()
        current = rows.get(old['id']) if not shifted else None
        if current is not None and old.get('changed') and (
                not current.get('changed') or current.get('origin_occurrence_id', current['id']) != old.get('origin_occurrence_id', old['id'])):
            current = None
        if current is None and old.get('course_id'):
            current = matching(rows.values(), old)
        if current is not None:
            mapped[old['id']] = current
            rows.pop(current['id'], None)
    for saved in patch['after']:
        course_id = saved.get('course_id')
        if course_id and course_id not in courses: continue
        # If the source recurrence was removed, its moved exception is removed
        # as well. Independent additions (course_id=None) remain independent.
        if course_id and saved['id'] in old_rows and saved['id'] not in mapped: continue
        previous = old_rows.get(saved['id'])
        attendance_fields = ('attendance_status', 'attendance_reason')
        # Attendance is an overlay on the current occurrence. Reuse corrected
        # school times or an earlier move instead of replaying its old snapshot.
        attendance_only = previous is not None and (
            {k: v for k, v in saved.items() if k not in attendance_fields} ==
            {k: v for k, v in previous.items() if k not in attendance_fields})
        if attendance_only and saved['id'] in mapped:
            after = dict(mapped[saved['id']])
            for field in attendance_fields:
                after.pop(field, None)
                if field in saved: after[field] = saved[field]
            rows[after['id']] = after
            continue
        # An undo can restore an ordinary base occurrence. Keep its relationship
        # to the base timetable rather than freezing an old date/time snapshot.
        restored = matching(base_events, saved) if course_id and not saved.get('changed') else None
        if course_id and not saved.get('changed') and restored is None: continue
        after = dict(restored or saved)
        if restored is not None:
            for field in attendance_fields:
                if field in saved: after[field] = saved[field]
        if restored is None and saved['id'] in mapped: after['id'] = mapped[saved['id']]['id']
        base = courses.get(course_id)
        if saved.get('changed') and course_id:
            after['origin_occurrence_id'] = saved.get('origin_occurrence_id') or (previous or {}).get('origin_occurrence_id') or saved['id']
        if base and previous:
            for field in ('title', 'location', 'teacher'):
                if after.get(field) == previous.get(field):
                    after[field] = base.get(field, after.get(field))
            if base.get('attendance_exempt'):
                after['attendance_exempt'] = True
            else:
                after.pop('attendance_exempt', None)
            after['source_batch_id'] = base.get('source_batch_id')
        rows[after['id']] = after
    return sorted(rows.values(), key=lambda e: (instant(e['start_at']), e['id']))


def effective_courses(db,user,s):
    courses=[{**r.payload,'id':r.id,'source_batch_id':r.source_batch_id} for r in db.scalars(select(CourseMeeting).where(CourseMeeting.user_id==user.id,CourseMeeting.semester_id==s.id))]
    events=expand({'first_monday':s.first_monday,'periods':s.periods},courses)
    base_events=list(events)
    by_id = {c['id']: c for c in courses}
    for change in db.scalars(select(RealityChange).where(RealityChange.user_id==user.id,RealityChange.semester_id==s.id,
        RealityChange.applied_revision.is_not(None)).order_by(RealityChange.applied_revision)):
        events=replay_course_patch(events,change.payload['patch'],by_id,
            original_monday=change.payload.get('base_calendar',{}).get('first_monday'),current_monday=s.first_monday,base_events=base_events)
    return [{'occurrences':events}]
