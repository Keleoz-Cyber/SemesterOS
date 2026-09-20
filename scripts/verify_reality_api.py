"""Synthetic real-service notice -> reality -> minimum-disruption confirmation check."""
from datetime import datetime,timedelta,timezone
from pathlib import Path
import json,secrets
import httpx


def main():
    tz=timezone(timedelta(hours=8));now=datetime.now(tz)
    day=(now+timedelta(days=1)).replace(hour=9,minute=0,second=0,microsecond=0)
    monday=now.date()-timedelta(days=now.weekday());account='qa_reality_'+secrets.token_hex(4)
    with httpx.Client(base_url='http://127.0.0.1:8871/api/v1',timeout=65) as api:
        session=api.post('/auth/register',json={'username':account,'password':secrets.token_urlsafe(24)}).json()
        api.headers['Authorization']='Bearer '+session['access_token']
        s=api.post('/semesters',json={'name':'QA现实变化（合成）','first_monday':monday.isoformat(),'total_weeks':20,
            'periods':[{'number':1,'start':'08:00','end':'09:00'}]}).json();path=f"/semesters/{s['id']}"
        pref={'expected_version':0,'weekly':[{'weekday':day.isoweekday(),'start':'09:00','end':'13:00'}],'exclusions':[]}
        preview=api.post(path+'/availability/preview',json=pref).json()
        assert api.put(path+'/availability',json={**pref,'expected_revision':preview['base_revision']}).status_code==200
        week=(day.date()-monday).days//7+1
        batch=api.post('/imports',json={'semester_id':s['id'],'source':'manual','courses':[{'title':'合成概率论','weekday':day.isoweekday(),'weeks':[week],'sections':[1]}]}).json()
        assert api.post(f"/imports/{batch['id']}/apply",json={'expected_revision':batch['base_revision']}).status_code==200
        tasks=[]
        for title in ('合成任务A','合成任务B'):
            item=api.post('/items',json={'semester_id':s['id'],'kind':'task','title':title,'certainty':'formal',
                'time':{'precision':'exact','at':day.replace(hour=13).isoformat()},'remaining_minutes':60,'splittable':False,
                'start_policy':'at','earliest_start_at':day.isoformat()});assert item.status_code==201;tasks.append(item.json())
        p=api.post(path+'/plan-proposals',json={'days':7,'lead_minutes':5,'chunk_minutes':60,'tasks':[{'item_id':t['id']} for t in tasks]}).json()
        assert p['status']=='FEASIBLE_COMPLETE'
        assert api.post(f"/plan-proposals/{p['id']}/accept",json={'expected_version':1,'expected_revision':p['base_revision']}).status_code==200
        plans=api.get(path+'/plans').json()['blocks'];plans.sort(key=lambda b:b['start_at'])
        locked=plans[-1]
        assert api.patch(f"/plan-blocks/{locked['id']}/lock",json={'expected_version':1,'locked':True}).status_code==200
        plans=api.get(path+'/plans').json()['blocks']
        original=api.get(path+f'/timetable?week={week}').json()['events'][0]
        source=f"正式调课通知：合成概率论原定{day:%Y年%m月%d日}08:00至09:00，改为同一天09:00至10:00，地点示例楼A101。"
        parsed=api.post('/changes/parse',json={'semester_id':s['id'],'text':source,'reference_at':now.isoformat()})
        assert parsed.status_code==200,parsed.status_code
        suggestion=parsed.json()['suggestion'];assert suggestion['kind']=='move'
        assert datetime.fromisoformat(suggestion['start_at'])==day and datetime.fromisoformat(suggestion['end_at'])==day.replace(hour=10)
        assert parsed.json()['target_candidates']==[original['id']]
        ch=api.post(path+'/changes',json={'kind':'move','targets':[original['id']],'title':'合成概率论','source_text':source,
            'start_at':suggestion['start_at'],'end_at':suggestion['end_at'],'location':suggestion['location']}).json()
        assert len(ch['impact']['affected_blocks'])==1
        assert api.get(path+f'/timetable?week={week}').json()['events'][0]['start_at']==original['start_at']
        assert api.get(path+'/plans').json()['blocks']==plans
        receipt=api.post(f"/changes/{ch['id']}/apply",json={'expected_revision':ch['base_revision']});assert receipt.status_code==200
        assert api.post(f"/changes/{ch['id']}/apply",json={'expected_revision':ch['base_revision']}).json()==receipt.json()
        assert api.get(path+'/plans').json()['blocks']==plans
        updated=api.get(path+f'/timetable?week={week}').json()['events'][0]
        assert updated['id']==original['id'] and datetime.fromisoformat(updated['start_at'])==day
        r=api.post(path+'/replan-proposals',json={'lead_minutes':5}).json()
        assert r['status']=='FEASIBLE_COMPLETE' and r['moved_tasks']==1 and r['shift_minutes']==120,r['status']
        assert api.get(path+'/plans').json()['blocks']==plans
        accepted=api.post(f"/plan-proposals/{r['id']}/accept",json={'expected_version':1,'expected_revision':r['base_revision']});assert accepted.status_code==200
        after=api.get(path+'/plans').json()
        assert {b['id'] for b in after['blocks']}=={b['id'] for b in plans}
        assert sum(b['minutes'] for b in after['blocks'])==120
        assert next(b for b in after['blocks'] if b['id']==locked['id'])['start_at']==locked['start_at']
        assert not after['invalid_blocks']
        assert api.post(f"/plan-proposals/{r['id']}/undo",json={'expected_version':2,'expected_revision':after['revision']}).status_code==409
        api.post('/auth/logout',json={'logout_token':session['logout_token']})
    report={'passed':True,'source':'synthetic','at':now.isoformat(),'account':account,'moved_tasks':r['moved_tasks'],
        'shift_minutes':r['shift_minutes'],'optimal':r['optimal'],'phases':r['phases'],'model':parsed.json()['metadata'].get('model'),
        'checks':['real_notice_model','preview_readonly','occurrence_identity','reality_accept_idempotent','reality_keeps_plans',
            'replan_readonly','minimum_moved_tasks','minimum_offset','locked_unchanged','block_ids_and_work_preserved','no_conflicts','unsafe_undo_rejected']}
    out=Path(__file__).resolve().parents[1]/'output/verification/reality-api.json';out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'passed':True,'moved_tasks':r['moved_tasks'],'shift_minutes':r['shift_minutes'],'checks':len(report['checks'])}))


if __name__=='__main__':main()
