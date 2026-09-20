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
                start=datetime.combine(day,time.fromisoformat(periods[group[0]]['start']),SHANGHAI)
                end=datetime.combine(day,time.fromisoformat(periods[group[-1]]['end']),SHANGHAI)
                events.append({**c,'course_id':c.get('id'), 'id':f"{c.get('id',c['title'])}:{day}:{group[0]}",
                    'start_at':start.isoformat(),'end_at':end.isoformat(),'sections':group,'reality_kind':'course'})
    return sorted(events,key=lambda e:(instant(e['start_at']),e['id']))


def apply_patch(events,patch):
    rows={e['id']:dict(e) for e in events}
    for e in patch['before']:rows.pop(e['id'],None)
    for e in patch['after']:rows[e['id']]=dict(e)
    return sorted(rows.values(),key=lambda e:(instant(e['start_at']),e['id']))


def effective_courses(db,user,s):
    courses=[{**r.payload,'id':r.id,'source_batch_id':r.source_batch_id} for r in db.scalars(select(CourseMeeting).where(CourseMeeting.user_id==user.id,CourseMeeting.semester_id==s.id))]
    events=expand({'first_monday':s.first_monday,'periods':s.periods},courses)
    for change in db.scalars(select(RealityChange).where(RealityChange.user_id==user.id,RealityChange.semester_id==s.id,
        RealityChange.applied_revision.is_not(None)).order_by(RealityChange.applied_revision)):
        events=apply_patch(events,change.payload['patch'])
    return [{'occurrences':events}]
