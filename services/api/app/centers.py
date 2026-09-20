"""Revision-consistent course, exam and weekly projections over the same facts."""
from datetime import timedelta
from fastapi import APIRouter,Depends
from sqlalchemy import select
from sqlalchemy.orm import Session
from .database import get_db
from .models import CourseMeeting,RealityChange,StudyItem,User
from .academics import owned_semester,serialize_semester
from .auth import current_user,error
from .items import serialize_item
from .schedule_api import snapshot
from .occurrences import expand
from .capacity import analyze,calendar_context,local_day,exam_window
from .plan_rules import classify,occupied_seconds,future_minutes
from .reminder_rules import utcnow,instant,anchor_at,SHANGHAI

router=APIRouter()


def data_snapshot(db,user,s):
    now=utcnow();source=snapshot(db,user,s)
    items=[serialize_item(db,i) for i in db.scalars(select(StudyItem).where(StudyItem.user_id==user.id,StudyItem.semester_id==s.id))]
    risk=analyze(*source[:4],now,source[4])
    events=expand(source[0],source[2])
    changes=list(db.scalars(select(RealityChange).where(RealityChange.user_id==user.id,RealityChange.semester_id==s.id,
        RealityChange.applied_revision.is_not(None)).order_by(RealityChange.applied_revision.desc())))
    return now,source,items,risk,events,changes


def family(rows,course):
    source_id=course.payload.get('source_id')
    return [r for r in rows if r.id==course.id or (source_id and r.payload.get('source_id')==source_id)]


def course_groups(db,user,s,items):
    rows=list(db.scalars(select(CourseMeeting).where(CourseMeeting.user_id==user.id,CourseMeeting.semester_id==s.id).order_by(CourseMeeting.id)))
    seen=set();result=[]
    for course in rows:
        if course.id in seen:continue
        group=family(rows,course);ids={r.id for r in group};seen.update(ids)
        related=[i for i in items if i.get('course_id') in ids and i['lifecycle']=='active']
        result.append({'id':course.id,'course_ids':sorted(ids),'title':course.payload['title'],'teacher':course.payload.get('teacher',''),
            'task_count':sum(i['kind']!='exam' for i in related),'exam_count':sum(i['kind']=='exam' for i in related)})
    return result


def change_value(row):
    return {'id':row.id,'kind':row.payload['request']['kind'],'title':row.payload['request']['title'],
        'source_text':row.payload['request']['source_text'],'before':row.payload['patch']['before'],'after':row.payload['patch']['after'],
        'created_at':row.created_at,'applied_revision':row.applied_revision}


def exam_summary(exam,items,risk):
    linked=[i for i in items if i.get('review_exam_id')==exam['id']]
    active=[i for i in linked if i['lifecycle']=='active'];known=[i for i in active if i.get('remaining_minutes') is not None]
    risks={r['item_id']:r for r in risk['items']}
    unknown=sum(i.get('remaining_minutes') is None for i in active)
    remaining=sum(i['remaining_minutes'] for i in known)
    covered=sum(risks.get(i['id'],{}).get('planned_minutes',0) for i in active)
    due=anchor_at(exam)
    issues=[]
    if exam['lifecycle']!='active' and active:issues.append('考试已取消，复习任务仍保留，请明确处理')
    for i in active:
        review_due=anchor_at(i)
        if due and exam['certainty']=='formal' and (not review_due or i['certainty']!='formal' or review_due>due):
            issues.append(i['title']+'：复习截止需与考试时间核对')
    return {'exam':exam,'reviews':linked,'review_remaining_minutes':None if unknown else remaining,
        'known_remaining_minutes':remaining,'review_planned_minutes':covered,'unknown_estimate_count':unknown,
        'review_unplanned_minutes':None if unknown else max(0,remaining-covered),
        'completed_review_count':sum(i['lifecycle']=='completed' for i in linked),'issues':issues}


def item_span(item,s):
    t=item['time'];precision=t['precision']
    if precision=='unknown':return None
    if precision=='week':
        a=local_day(s.first_monday)+timedelta(weeks=t['week']-1);return a,a+timedelta(days=7)
    if precision in ('date','range'):
        return local_day(t['date']),local_day(t.get('end_date') or t['date'])+timedelta(days=1)
    at=instant(t['at']);return at,instant(t['end_at']) if item['kind']=='exam' and t.get('end_at') else at+timedelta(microseconds=1)


@router.get('/courses/{id}/hub')
def course_hub(id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    course=db.scalar(select(CourseMeeting).where(CourseMeeting.id==id,CourseMeeting.user_id==user.id))
    if course is None:error(404,'NOT_FOUND','找不到课程')
    s=owned_semester(db,user,course.semester_id,lock=True);now,source,items,risk,events,changes=data_snapshot(db,user,s)
    group=next(g for g in course_groups(db,user,s,items) if id in g['course_ids']);ids=set(group['course_ids'])
    related=[i for i in items if i.get('course_id') in ids]
    return {'semester':serialize_semester(s),'revision':s.revision,'course':group,
        'items':related,'occurrences':[e for e in events if e.get('course_id') in ids],
        'changes':[change_value(c) for c in changes if any(e.get('course_id') in ids for e in c.payload['patch']['before']+c.payload['patch']['after'])],
        'risk':{**risk,'revision':s.revision,'semester_id':s.id}}


@router.get('/semesters/{sid}/hub')
def semester_hub(sid:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    s=owned_semester(db,user,sid,lock=True);now,source,items,risk,events,changes=data_snapshot(db,user,s)
    active=[i for i in items if i['lifecycle']=='active'];c=calendar_context(*source[:4],now)
    valid,_=classify(source[4],source[3],c['free'].spans,c['begin'])
    first=local_day(s.first_monday);finish=first+timedelta(weeks=s.total_weeks)
    risks={r['item_id']:r for r in risk['items']};weeks=[];undated=[];outside=[]
    spans={i['id']:item_span(i,s) for i in active}
    for i in active:
        span=spans[i['id']]
        if span is None:undated.append(i)
        elif span[1]<=first or span[0]>=finish:outside.append(i)
    for n in range(s.total_weeks):
        a=first+timedelta(weeks=n);b=a+timedelta(days=7)
        entries=[i for i in active if spans[i['id']] and spans[i['id']][0]<b and spans[i['id']][1]>a]
        capacity=c['free'].minutes(max(a.timestamp(),now.timestamp()),b.timestamp()) if source[1].get('configured') else None
        unknown_exam=any(x<b.timestamp() and z>max(a.timestamp(),now.timestamp()) and missing for x,z,missing,_ in c['uncertain'])
        if unknown_exam:capacity=None
        planned=int(occupied_seconds(valid,max(a.timestamp(),now.timestamp()),b.timestamp())//60) if b>now else 0
        high=sum(risks.get(i['id'],{}).get('level')=='high' for i in entries)
        known_due=sum(i['remaining_minutes'] for i in entries if i['kind']!='exam' and i.get('remaining_minutes') is not None
            and i.get('certainty')=='formal' and anchor_at(i) and
            ((a<anchor_at(i)<=b) if i['time']['precision']=='date' and i['time'].get('day_end_confirmed') else (a<=anchor_at(i)<b)))
        changes_here=[]
        for change in changes:
            value=change_value(change)
            if any(instant(e['start_at'])<b and instant(e['end_at'])>a for e in value['before']+value['after']):changes_here.append(value)
        weeks.append({'week':n+1,'start_date':a.date().isoformat(),'end_date':(b-timedelta(days=1)).date().isoformat(),
            'items':entries,'changes':changes_here,'available_minutes':capacity,'planned_minutes':planned,
            'known_due_remaining_minutes':known_due,'high_risk_count':high,
            'load_level':'past' if b<=now else 'high' if high or (capacity and planned/capacity>=.8) else 'unknown' if capacity is None else 'normal'})
    return {'semester':serialize_semester(s),'revision':s.revision,'computed_at':now.isoformat(),'valid_until':risk['valid_until'],
        'courses':course_groups(db,user,s,items),'exams':[exam_summary(i,items,risk) for i in items if i['kind']=='exam'],
        'weeks':weeks,'undated':undated,'outside':outside,'risk':{**risk,'revision':s.revision,'semester_id':s.id}}
