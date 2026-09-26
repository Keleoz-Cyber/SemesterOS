"""Real tool-calling verification using only synthetic data in a disposable local DB."""
import argparse
import json
import sys
import time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'services/api'))
from verify_calendar_api import client
from app.agent_runtime import work_once
from app.models import AgentRun
from sqlalchemy.orm import Session


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--repeat',type=int,default=3)
    repeat=parser.parse_args().repeat
    reports=[]
    with client(None) as c:
        def ask(tid,text,key):
            r=c.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json={'text':text,'request_id':key})
            assert r.status_code==202,r.text
            rid=r.json()['id'];begin=time.monotonic();assert work_once(c.app.state.engine)
            value=c.get('/api/v1/agent/runs/'+rid,headers=h).json()
            with Session(c.app.state.engine) as db:
                state=db.get(AgentRun,rid).state
                entry={'case':key,'status':value['status'],'seconds':round(time.monotonic()-begin,2),
                    'model_calls':state['model_calls'],'tool_calls':state['tool_calls'],'usage':state.get('usage',{}),
                    'tools':[x['function']['name'] for m in state['turn_messages'] for x in m.get('tool_calls',[])]}
            reports.append(entry)
            trace=ROOT/'output/verification/agent-model-last-turn.json';trace.parent.mkdir(parents=True,exist_ok=True)
            trace.write_text(json.dumps(state['turn_messages'],ensure_ascii=False,indent=2),encoding='utf-8')
            print(json.dumps(entry,ensure_ascii=False),flush=True)
            if value['status']=='failed':
                debug=ROOT/'output/verification/agent-model-failure.json';debug.parent.mkdir(parents=True,exist_ok=True)
                debug.write_text(json.dumps(state['turn_messages'],ensure_ascii=False,indent=2),encoding='utf-8')
                raise AssertionError(value['error'])
            return value
        def confirm(value):
            assert value['status']=='needs_confirmation',value
            data={'decision':'confirm','token':value['preview']['token']}
            url='/api/v1/agent/runs/'+value['id']+'/decision'
            first=c.post(url,headers=h,json=data)
            assert first.status_code==200,first.text
            assert c.post(url,headers=h,json=data).json()==first.json()
            return first.json()
        for n in range(repeat):
            user=c.post('/api/v1/auth/register',json={'username':f'agent_verification_{n}','password':'synthetic-test-only'}).json()
            h={'Authorization':'Bearer '+user['access_token']}
            s=c.post('/api/v1/semesters',headers=h,json={'name':'合成验证学期','first_monday':'2026-08-31','total_weeks':20,
                'periods':[{'number':1,'start':'08:00','end':'08:50'}]}).json()
            tid=c.post('/api/v1/agent/threads',headers=h,json={'semester_id':s['id']}).json()['id']
            create=ask(tid,f'帮我记一下：2026年10月{n+2}日17点到18点开项目{n+1}组会，地点6412，提前30分钟提醒。',f'create-{n}')
            assert create['preview']['kind']=='event'
            assert create['preview']['after']['reminder_minutes']==[30],create['preview']['after']
            saved=confirm(create);eid=saved['receipt']['event']['id']
            edit=ask(tid,'刚才那个组会地点改成6302，时间和提醒不变。',f'edit-{n}')
            assert edit['preview']['target_id']==eid and edit['preview']['after']['location']=='6302',edit
            confirm(edit)
            analysis=ask(tid,f'查询2026年10月{n+2}日的所有日程，再统计当天安排占用多少时间。',f'query-analysis-{n}')
            assert analysis['status']=='completed'
            cards=analysis['cards'];assert any(x['kind']=='analysis' for x in cards)
            values=next(x['data'] for x in cards if x['kind']=='analysis')
            assert values['occupied_union_minutes']==60 and values['actual_minutes'] is None
            partial=ask(tid,'另外暂定第14周举行项目总结会，具体日期和时间等通知。请记录。',f'partial-{n}')
            assert partial['preview']['after']['time']['precision']=='week'
            assert partial['preview']['after']['time']['at'] is None
            confirm(partial)
    report={'passed':True,'repetitions':repeat,'data':'synthetic, isolated local database','runs':reports}
    output=ROOT/'output/verification/agent-model.json';output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'Passed {len(reports)} real-model turns; local data only.',flush=True)


if __name__=='__main__':main()
