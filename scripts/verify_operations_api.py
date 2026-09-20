"""Real DeepSeek + PostgreSQL smoke, isolated synthetic account, no credentials logged."""
from datetime import datetime,timedelta,timezone
from pathlib import Path
import json,secrets
import httpx


def main():
    now=datetime.now(timezone(timedelta(hours=8)));checks=[]
    def check(condition,label):
        assert condition,label
        checks.append(label)
    with httpx.Client(base_url='http://127.0.0.1:8871/api/v1',timeout=90) as api:
        def request(method,path,**kw):
            r=api.request(method,path,**kw)
            assert r.is_success,{'path':path,'status':r.status_code,'code':r.json().get('code')}
            return r.json() if r.content else None
        session=request('POST','/auth/register',json={'username':'qa_operation_'+secrets.token_hex(4),'password':secrets.token_urlsafe(24)})
        api.headers['Authorization']='Bearer '+session['access_token']
        s=request('POST','/semesters',json={'name':'QA自然语言修改（合成）','first_monday':(now.date()-timedelta(days=now.weekday())).isoformat(),'total_weeks':20,'periods':[{'number':1,'start':'08:00','end':'08:50'}]})
        sp='/semesters/'+s['id']
        av={'expected_version':0,'weekly':[{'weekday':d,'start':'08:00','end':'22:00'} for d in range(1,8)],'exclusions':[]}
        preview=request('POST',sp+'/availability/preview',json=av)
        request('PUT',sp+'/availability',json={**av,'expected_revision':preview['base_revision']})
        item=request('POST','/items',json={'semester_id':s['id'],'kind':'task','title':'Java实验报告','remaining_minutes':180,'start_policy':'now','certainty':'formal','time':{'precision':'exact','at':(now+timedelta(days=4)).isoformat()}})
        def parse(text):return request('POST','/operations/parse',json={'semester_id':s['id'],'text':text,'reference_at':now.isoformat()})
        def apply(p):return request('POST','/operations/'+p['id']+'/apply',json={'expected_version':p['version']})
        p=parse('Java实验报告还需要两小时')
        check(p['phase']=='ready' and p['preview']['task_patch']['remaining_minutes']==120,'real_model_extracts_effort')
        check(request('GET','/items/'+item['id'])['remaining_minutes']==180,'parse_does_not_mutate')
        receipt=apply(p);check(apply(p)==receipt,'apply_is_idempotent')
        item=request('GET','/items/'+item['id']);check(item['remaining_minutes']==120,'confirmed_task_patch')
        p=parse('Java实验报告提醒改到周四晚上')
        check(p['phase']=='needs_clarification' and p['suggestion']['reminder_patch']['trigger_at'] is None,'vague_evening_has_no_invented_clock')
        remind=(now+timedelta(days=2)).replace(hour=20,minute=0,second=0,microsecond=0)
        p=parse(f'给Java实验报告新增一条提醒，{remind:%Y年%m月%d日}晚上八点提醒我')
        check(p['phase']=='ready' and p['preview']['reminder_action']=='add','real_model_extracts_reminder')
        r=apply(p);check(len(r['changed_items'][0]['reminders'])==1,'confirmed_reminder_saved')
        p=parse('给Java实验报告安排一个学习计划')
        check(p['suggestion']['intent']=='request_plan','real_model_routes_planning')
        p=request('POST','/operations/'+p['id']+'/resolve',json={'expected_version':p['version'],'tasks':[{'item_id':item['id']}],'plan_mode':'schedule','days':7,'use_default_window':True})
        receipt=apply(p)
        check(request('GET',sp+'/plans')['blocks']==[],'operation_handoff_writes_no_blocks')
        key='operation-plan-'+p['id']+'-'+str(receipt['operation_version'])
        proposal=request('POST',sp+'/plan-proposals',headers={'Idempotency-Key':key},json=receipt['planning_request'])
        check(proposal['status']=='FEASIBLE_COMPLETE','solver_generates_candidate')
        check(request('GET',sp+'/plans')['blocks']==[],'candidate_is_readonly')
        request('POST','/plan-proposals/'+proposal['id']+'/accept',json={'expected_version':proposal['version'],'expected_revision':proposal['base_revision']})
        check(sum(b['minutes'] for b in request('GET',sp+'/plans')['blocks'])==120,'separate_confirmation_writes_plan')
        request('POST','/auth/logout',json={'logout_token':session['logout_token']})
    report={'passed':True,'at':now.isoformat(),'model':'deepseek-flash','data':'isolated synthetic account','checks':checks}
    path=Path(__file__).resolve().parents[1]/'output/verification/operations-api.json';path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'passed':True,'checks':len(checks)}))


if __name__=='__main__':main()
