"""Synthetic live OR-Tools/API check. Does not use model credentials or real user sessions."""
from datetime import datetime,timedelta,timezone
from pathlib import Path
import json,secrets
import httpx


def main():
    now=datetime.now(timezone(timedelta(hours=8)))
    day=(now+timedelta(days=1)).replace(hour=9,minute=0,second=0,microsecond=0)
    monday=now.date()-timedelta(days=now.weekday())
    username='qa_schedule_'+secrets.token_hex(4)
    with httpx.Client(base_url='http://127.0.0.1:8871/api/v1',timeout=30) as api:
        session=api.post('/auth/register',json={'username':username,'password':secrets.token_urlsafe(24)}).json()
        api.headers['Authorization']='Bearer '+session['access_token']
        s=api.post('/semesters',json={'name':'QA自动排程（合成）','first_monday':monday.isoformat(),'total_weeks':20,
            'periods':[{'number':1,'start':'10:00','end':'11:00'}]}).json();path=f"/semesters/{s['id']}"
        settings={'expected_version':0,'weekly':[{'weekday':day.isoweekday(),'start':'09:00','end':'13:00'}],'exclusions':[]}
        p=api.post(path+'/availability/preview',json=settings).json()
        assert api.put(path+'/availability',json={**settings,'expected_revision':p['base_revision']}).status_code==200
        batch=api.post('/imports',json={'semester_id':s['id'],'source':'manual','courses':[{'title':'QA固定课程','weekday':day.isoweekday(),
            'weeks':[(day.date()-monday).days//7+1],'sections':[1]}]}).json()
        assert api.post(f"/imports/{batch['id']}/apply",json={'expected_revision':batch['base_revision']}).status_code==200
        tasks=[]
        for title,minutes in [('A',90),('B',60)]:
            r=api.post('/items',json={'semester_id':s['id'],'kind':'task','title':'QA任务'+title,'certainty':'formal',
                'time':{'precision':'exact','at':day.replace(hour=13).isoformat()},'remaining_minutes':minutes,
                'start_policy':'at','earliest_start_at':day.isoformat()});assert r.status_code==201;tasks.append(r.json())
        request={'days':7,'lead_minutes':5,'chunk_minutes':45,'allow_partial':False,'tasks':[{'item_id':t['id']} for t in tasks]}
        p=api.post(path+'/plan-proposals',json=request);assert p.status_code==201
        p=p.json();assert p['status']=='FEASIBLE_COMPLETE',p['status']
        assert api.get(path+'/plans').json()['blocks']==[]
        spans=sorted((datetime.fromisoformat(b['start_at']),datetime.fromisoformat(b['end_at'])) for b in p['blocks'])
        assert all(a>=day and b<=day.replace(hour=13) and (b<=day.replace(hour=10) or a>=day.replace(hour=11)) for a,b in spans)
        assert all(b<=c for (_,b),(c,_) in zip(spans,spans[1:]))
        accept={'expected_version':p['version'],'expected_revision':p['base_revision']}
        receipt=api.post(f"/plan-proposals/{p['id']}/accept",json=accept);assert receipt.status_code==200
        assert api.post(f"/plan-proposals/{p['id']}/accept",json=accept).json()==receipt.json()
        feed=api.get(path+'/plans').json();assert sum(b['minutes'] for b in feed['blocks'])==150
        risk=api.get(path+'/risk').json();assert sum(r['planned_minutes'] for r in risk['items'])==150
        assert sum(r['remaining_minutes'] for r in risk['items'])==150
        first=feed['blocks'][0]
        locked=api.patch(f"/plan-blocks/{first['id']}/lock",json={'expected_version':1,'locked':True});assert locked.status_code==200
        assert locked.json()['block']['start_at']==first['start_at']
        assert api.post(f"/plan-blocks/{first['id']}/cancel",json={'expected_version':2}).status_code==422
        assert api.post(f"/plan-blocks/{first['id']}/cancel",json={'expected_version':2,'confirm_locked':True}).status_code==200
        second=api.post(path+'/plan-proposals',json=request).json()
        assert sum(b['minutes'] for b in second['blocks'])==first['minutes']
        assert api.post(f"/plan-proposals/{second['id']}/accept",json={'expected_version':1,'expected_revision':second['base_revision']}).status_code==200
        feed=api.get(path+'/plans').json()
        assert api.post(f"/plan-proposals/{second['id']}/undo",json={'expected_version':2,'expected_revision':feed['revision']}).status_code==200
        for item in tasks:
            pp=f"/items/{item['id']}/progress";update={'expected_version':1,'remaining_minutes':0,'note':'合成验证完成'}
            preview=api.post(pp+'/preview',json=update).json()
            assert api.post(pp,json={**update,'expected_revision':preview['base_revision'],'confirm_complete':True,
                'cancel_plan_ids':[b['id'] for b in preview['affected_blocks']],'confirm_locked_cancellation':True}).status_code==200
        assert api.get(path+'/plans').json()['blocks']==[]
        api.post('/auth/logout',json={'logout_token':session['logout_token']})
    result={'passed':True,'source':'synthetic','account':username,'at':now.isoformat(),'scheduled_minutes':150,
        'new_blocks':len(p['blocks']),'solver_status':p['solver_status'],'solver_version':p['solver_version'],
        'checks':['preview_readonly','real_solver','no_overlap','fixed_course_preserved','accept_idempotent','work_not_completed',
                  'lock_preserves_time','locked_cancel_consent','no_duplicate_coverage','undo_latest','completion_cancels_plans']}
    out=Path(__file__).resolve().parents[1]/'output/verification/schedule-api.json'
    out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'passed':True,'scheduled_minutes':150,'checks':len(result['checks'])}))


if __name__=='__main__':main()
