"""Live local capacity checks with one synthetic account; no model calls or real coursework."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import json
import secrets
import httpx


def main():
    now=datetime.now(timezone(timedelta(hours=8)))
    window=(now+timedelta(days=1)).replace(hour=9,minute=0,second=0,microsecond=0)
    monday=now.date()-timedelta(days=now.weekday())
    username='qa_capacity_'+secrets.token_hex(4)
    with httpx.Client(base_url='http://127.0.0.1:8871/api/v1',timeout=30) as api:
        session=api.post('/auth/register',json={'username':username,'password':secrets.token_urlsafe(24)}).json()
        api.headers['Authorization']='Bearer '+session['access_token']
        s=api.post('/semesters',json={'name':'QA容量验证（合成）','first_monday':monday.isoformat(),'total_weeks':20,
            'periods':[{'number':1,'start':'08:00','end':'08:50'}]}).json()
        path=f"/semesters/{s['id']}"
        prefs={'expected_version':0,'weekly':[{'weekday':window.isoweekday(),'start':'09:00','end':'13:00'}],'exclusions':[]}
        preview=api.post(path+'/availability/preview',json=prefs);assert preview.status_code==200
        assert not api.get(path+'/availability').json()['configured']
        saved=api.put(path+'/availability',json={**prefs,'expected_revision':preview.json()['base_revision']});assert saved.status_code==200
        tasks=[]
        for label in ('A','B'):
            r=api.post('/items',json={'semester_id':s['id'],'kind':'task','title':'QA容量任务'+label,'certainty':'formal',
                'time':{'precision':'exact','at':(window+timedelta(hours=4)).isoformat()},'remaining_minutes':150,
                'start_policy':'at','earliest_start_at':window.isoformat()})
            assert r.status_code==201;tasks.append(r.json())
        gaps=[]
        def check(expected):
            r=api.get(path+'/risk');assert r.status_code==200
            result=r.json();gap=result['summary']['window_gap_minutes'];assert gap==expected,(gap,expected)
            gaps.append(gap);return result
        initial=check(60)
        assert all(r['task_slack_minutes']==90 for r in initial['items'])
        exam=api.post('/items',json={'semester_id':s['id'],'kind':'exam','title':'QA固定考试','certainty':'formal',
            'time':{'precision':'exact','at':(window+timedelta(hours=1)).isoformat(),'end_at':(window+timedelta(hours=2)).isoformat()}})
        assert exam.status_code==201;check(120)
        progress={'expected_version':1,'remaining_minutes':60,'actual_minutes':90,'note':'合成进度验证'}
        pp=f"/items/{tasks[0]['id']}/progress"
        p=api.post(pp+'/preview',json=progress);assert p.status_code==200
        assert api.post(pp,json={**progress,'expected_revision':p.json()['base_revision']}).status_code==200
        check(30)
        prefs['expected_version']=1
        prefs['exclusions']=[{'start_at':(window+timedelta(minutes=90)).isoformat(),'end_at':(window+timedelta(minutes=150)).isoformat(),'label':'QA禁排，与考试重叠30分钟'}]
        p=api.post(path+'/availability/preview',json=prefs);assert p.status_code==200
        assert api.put(path+'/availability',json={**prefs,'expected_revision':p.json()['base_revision']}).status_code==200
        check(60)
        api.post('/auth/logout',json={'logout_token':session['logout_token']})
    report={'passed':True,'source':'synthetic','account':username,'at':now.isoformat(),
            'window_gaps_minutes':gaps,'checks':['preview_readonly','shared_capacity','exam_occupancy','explicit_progress','overlap_union']}
    out=Path(__file__).resolve().parents[1]/'output/verification/capacity-api.json'
    out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'passed':True,'window_gaps_minutes':gaps}))


if __name__=='__main__':main()
