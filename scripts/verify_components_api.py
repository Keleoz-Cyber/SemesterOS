"""Real model/solver/media-source integration using disposable synthetic accounts."""
import json
import sys
import time
from datetime import datetime,timedelta
from pathlib import Path
from sqlalchemy.orm import Session

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'services/api'))
from verify_calendar_api import client
from app.agent_runtime import work_once
from app.models import AgentRun,MediaSource
from app.reminder_rules import SHANGHAI,utcnow,instant


def main():
    cases=[]
    with client(None) as c:
        for n in range(3):
            account=c.post('/api/v1/auth/register',json={'username':f'components_{n}','password':'synthetic-only-password'}).json()
            h={'Authorization':'Bearer '+account['access_token']}
            today=utcnow().astimezone(SHANGHAI).date();monday=today-timedelta(days=today.weekday())
            s=c.post('/api/v1/semesters',headers=h,json={'name':'组件集成合成学期','first_monday':str(monday),'total_weeks':20,
                'periods':[{'number':1,'start':'08:00','end':'08:50'}]}).json()
            tid=c.post('/api/v1/agent/threads',headers=h,json={'semester_id':s['id']}).json()['id']
            def ask(text,key,expected='needs_confirmation',**extra):
                response=c.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json={'text':text,'request_id':key,**extra})
                assert response.status_code==202,response.text
                rid=response.json()['id'];start=time.monotonic();work_once(c.app.state.engine)
                result=c.get('/api/v1/agent/runs/'+rid,headers=h).json()
                with Session(c.app.state.engine) as db:
                    state=db.get(AgentRun,rid).state
                    tools=[x['function']['name'] for m in state['turn_messages'] for x in m.get('tool_calls',[])]
                item={'case':key,'seconds':round(time.monotonic()-start,2),'status':result['status'],'tools':tools,'model_calls':state['model_calls']}
                cases.append(item);print(json.dumps(item,ensure_ascii=False),flush=True)
                if result['status']!=expected:
                    p=ROOT/'output/verification/components-model-failure.json';p.parent.mkdir(parents=True,exist_ok=True)
                    p.write_text(json.dumps(state['turn_messages'],ensure_ascii=False,indent=2),encoding='utf-8')
                assert result['status']==expected,result
                return result
            def confirm(result):
                data={'decision':'confirm','token':result['preview']['token']}
                r=c.post('/api/v1/agent/runs/'+result['id']+'/decision',headers=h,json=data)
                assert r.status_code==200,r.text
                assert c.post('/api/v1/agent/runs/'+result['id']+'/decision',headers=h,json=data).json()==r.json()
                return r.json()
            def revision():return c.get('/api/v1/semesters',headers=h).json()[0]['revision']
            availability={'expected_version':0,'weekly':[{'weekday':d,'start':'09:00','end':'18:00'} for d in range(1,8)],'exclusions':[]}
            preview=c.post(f"/api/v1/semesters/{s['id']}/availability/preview",headers=h,json=availability).json()
            assert c.put(f"/api/v1/semesters/{s['id']}/availability",headers=h,json={**availability,'expected_revision':preview['base_revision']}).status_code==200
            tomorrow=today+timedelta(days=1);due=today+timedelta(days=3)
            item=c.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'Java报告','remaining_minutes':120,
                'start_policy':'now','certainty':'formal','category_id':'study','tags':['实验报告'],
                'time':{'precision':'exact','at':f'{due}T18:00:00+08:00'}}).json()
            r=ask(f'请先查询Java报告，按已经填写的剩余耗时，在{tomorrow}的9点到14点内安排个人计划，先给我预览。',f'plan-{n}')
            assert r['preview']['kind']=='plan'
            assert sum(b['minutes'] for b in r['preview']['after']['blocks'])==120
            confirm(r)
            blocks=c.get(f"/api/v1/semesters/{s['id']}/plans",headers=h).json()['blocks'];block=blocks[0]
            e=c.post('/api/v1/events',headers=h,json={'semester_id':s['id'],'expected_revision':revision(),'title':'新通知中的会议',
                'time':{'precision':'exact','at':block['start_at'],'end_at':block['end_at']}})
            assert e.status_code==201,e.text
            r=ask('刚才的Java报告个人计划与新增会议冲突，请重新安排这个任务已有的个人计划。不要改会议或增加任务量。',f'replan-{n}')
            assert r['preview']['action']=='replan'
            confirm(r)
            revised=c.get(f"/api/v1/semesters/{s['id']}/plans",headers=h).json()['blocks']
            assert not any(instant(b['start_at'])<instant(block['end_at']) and instant(b['end_at'])>instant(block['start_at']) for b in revised if b['status']=='active')
            text='明天下午四点到五点举办项目组会，地点A301。'
            reference=datetime.combine(today,datetime.min.time(),SHANGHAI)
            with Session(c.app.state.engine,expire_on_commit=False) as db:
                source=MediaSource(user_id=account['user']['id'],semester_id=s['id'],upload_key='verified-transcript',input_hash='0'*64,
                    kind='image',mime='image/png',size=1,storage_key='synthetic.png',status='recognized',text=text,original_text=text,
                    reference_at=reference.isoformat(),created_at=utcnow().isoformat())
                db.add(source);db.commit();sid=source.id;version=source.version
            r=ask('请整理这份已核对的图片通知，先给我日程预览。',f'media-{n}',source_id=sid,source_version=version)
            assert r['preview']['kind']=='event'
            event=confirm(r)['receipt']['event']
            assert event['source_id']==sid and event['source_text']==text
            assert instant(event['time']['at']).astimezone(SHANGHAI).date()==tomorrow
            stats=c.get(f"/api/v1/semesters/{s['id']}/insights",headers=h,params={'from_date':str(today),'to_date':str(due)}).json()
            assert stats['summary']['personal_planned_minutes']==120
            assert stats['summary']['actual_minutes'] is None
            assert sum(x['scheduled_minutes'] for x in stats['categories'])==stats['summary']['fixed_scheduled_minutes']+120
            answer=ask('请统计整个学期学业分类的个人计划时长和实际投入记录，说明两者区别。',f'insights-{n}',expected='completed')
            facts=next(card['data'] for card in answer['cards'] if card['kind']=='insights')
            assert facts['summary']['personal_planned_minutes']==120 and facts['summary']['actual_minutes'] is None
    report={'passed':True,'data':'synthetic, disposable local DB; seeded reviewed media text, not OCR verification','runs':cases}
    path=ROOT/'output/verification/components-model.json';path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('PASS: real model planning, replan, reviewed media handoff, and statistics integration.',flush=True)


if __name__=='__main__':main()
