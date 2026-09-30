"""Contextual day summaries shared by home and calendar surfaces."""
from datetime import date, timedelta
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from .academics import owned_semester
from .auth import current_user
from .database import get_db
from .models import User
from .reminder_rules import SHANGHAI, utcnow, instant
from .calendar_events import calendar
from .schedule_api import snapshot
from .capacity import calendar_context, local_day, subtract, merge, iso

router = APIRouter()


@router.get('/semesters/{sid}/day-brief')
def day_brief(sid: str, day: date | None = Query(default=None),
              user: User = Depends(current_user), db: Session = Depends(get_db)):
    semester=owned_semester(db,user,sid,lock=True)
    now=utcnow();day=day or now.astimezone(SHANGHAI).date()
    from .auth import error
    if day==date.max:error(422,'INVALID_DATE','请核对日期')
    data=calendar(sid,day,day,user,db)
    source=snapshot(db,user,semester)
    context=calendar_context(*source[:4],now)
    begin=local_day(str(day)).timestamp();end=local_day(str(day+timedelta(days=1))).timestamp()
    future=max(begin,now.timestamp())
    uncertain=[id for a,b,missing,id in context['uncertain'] if missing and a<end and b>begin]
    plans=[p for p in source[4] if p['status']=='active' and instant(p['start_at']).timestamp()<end and instant(p['end_at']).timestamp()>future]
    fixed=[r for r in data['entries'] if r.get('fixed') and r.get('start_at') and r.get('end_at')]
    overlaps=[]
    for plan in plans:
        a,b=instant(plan['start_at']).timestamp(),instant(plan['end_at']).timestamp()
        conflict=[r for r in fixed if instant(r['start_at']).timestamp()<b and instant(r['end_at']).timestamp()>max(a,future)]
        if conflict:overlaps.append({'plan_id':plan['id'],'item_id':plan['item_id'],'title':plan['title'],
            'start_at':plan['start_at'],'end_at':plan['end_at'],'with':[{'id':r['id'],'title':r['title']} for r in conflict]})
    occupied=[(instant(p['start_at']).timestamp(),instant(p['end_at']).timestamp()) for p in source[4] if p['status']=='active']
    configured=source[1].get('configured',False)
    windows=[]
    if configured and not uncertain:
        for a,b in subtract(context['free'].spans,merge(occupied)):
            a,b=max(a,future),min(b,end)
            if b-a>=30*60:windows.append({'start_at':iso(a),'end_at':iso(b),'minutes':int((b-a)//60)})
    suggestions=[]
    if overlaps:
        suggestions.append({'kind':'plan_conflict','title':f'{len(overlaps)}段个人计划与固定安排重叠',
            'detail':'、'.join(dict.fromkeys(p['title'] for p in overlaps)),
            'source_ids':[p['plan_id'] for p in overlaps], 'action_label':'查看调整建议',
            'request':f'请检查{day}与固定安排冲突的个人计划，提出调整建议，固定课程和活动保持原位。'})
    if data['fixed_conflicts']:
        suggestions.append({'kind':'fixed_conflict','title':'固定安排时间重叠','detail':'；'.join(' / '.join(c['titles']) for c in data['fixed_conflicts'][:3]),
            'source_ids':list({id for c in data['fixed_conflicts'] for id in c['item_ids']}),'action_label':'核对这一天',
            'request':f'请核对{day}的固定安排冲突，说明哪些通知需要我确认，不自动移动课程或活动。'})
    if uncertain:
        suggestions.append({'kind':'missing_time','title':'有安排的起止时间还没确定','detail':'补齐时间后才能判断可用空档',
            'source_ids':uncertain,'action_label':'核对时间','request':f'请查找可能影响{day}的时间不完整安排，列出需要我补充的信息。'})
    elif windows:
        first=windows[0]
        a=instant(first['start_at']).astimezone(SHANGHAI);b=instant(first['end_at']).astimezone(SHANGHAI)
        suggestions.append({'kind':'free_window','title':f"{a:%H:%M}—{b:%H:%M} 可安排任务",'detail':f"按你的学习时间设置，连续{first['minutes']}分钟",
            'source_ids':[], 'action_label':'安排一下','request':f'请查看我未完成的任务，建议如何利用{day} {a:%H:%M}至{b:%H:%M}这段空闲时间，先给我预览。'})
    return {**data,'date':str(day),'generated_at':now.isoformat(),'valid_until':(now+timedelta(minutes=5)).isoformat(),
            'available_windows':windows[:6],'needs_availability':not configured,'uncertain_count':len(uncertain),
            'plan_impacts':overlaps,'suggestions':suggestions}
