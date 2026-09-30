"""Synthetic real-model end-to-end checks; isolated DB, no production writes."""
import json
import sys
import time
from pathlib import Path
from sqlalchemy.orm import Session

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'services/api'))
from verify_calendar_api import client
from app.agent_runtime import work_once
from app.models import AgentRun
from app.reminder_rules import instant


def main():
    evidence=[]
    with client(None) as c:
        account=c.post('/api/v1/auth/register',json={'username':'operations_check','password':'synthetic-only-password'}).json()
        h={'Authorization':'Bearer '+account['access_token']}
        s=c.post('/api/v1/semesters',headers=h,json={'name':'合成验证学期','first_monday':'2026-08-31','total_weeks':20,
            'periods':[{'number':1,'start':'08:00','end':'08:50'},{'number':2,'start':'09:00','end':'09:50'}]}).json()
        sid=s['id'];path='/api/v1/semesters/'+sid
        imported=c.post('/api/v1/imports',headers=h,json={'semester_id':sid,'source':'manual','courses':[{
            'title':'概率论','teacher':'示例教师','location':'A305','weekday':3,'weeks':[5,6,7],'sections':[1,2]}]}).json()
        assert c.post('/api/v1/imports/'+imported['id']+'/apply',headers=h,json={'expected_revision':0}).status_code==200
        def new_thread():return c.post('/api/v1/agent/threads',headers=h,json={'semester_id':sid}).json()['id']
        def ask(tid,text,label):
            request=c.post('/api/v1/agent/threads/'+tid+'/turns',headers=h,json={'text':text,'request_id':label})
            assert request.status_code==202,request.text
            rid=request.json()['id'];start=time.monotonic();work_once(c.app.state.engine)
            result=c.get('/api/v1/agent/runs/'+rid,headers=h).json()
            with Session(c.app.state.engine) as db:
                state=db.get(AgentRun,rid).state
                tools=[t['function']['name'] for m in state.get('turn_messages',[]) for t in m.get('tool_calls',[])]
                errors=[json.loads(m['content']) for m in state.get('turn_messages',[]) if m.get('role')=='tool' and 'error' in json.loads(m['content'])]
            row={'case':label,'status':result['status'],'tools':tools,'errors':errors,'seconds':round(time.monotonic()-start,2)}
            evidence.append(row);print(json.dumps(row,ensure_ascii=False),flush=True)
            return result
        def confirm(result,group_ids=None):
            data={'decision':'confirm','token':result['preview']['token']}
            if group_ids is not None:data['selected_group_ids']=group_ids
            response=c.post('/api/v1/agent/runs/'+result['id']+'/decision',headers=h,json=data)
            assert response.status_code==200,response.text
            return response.json()
        tid=new_thread()
        result=ask(tid,'帮我整理三条通知：2026年10月1日17点到18点项目组会，地点6412，提前30分钟提醒；我10月2日要交项目材料，提前1天提醒，标签“项目材料”；概率论考试暂定第14周，具体日期等通知。请分组预览。','mixed-notice')
        if result['status']=='completed' and result['preview'] is None:
            assert '时刻' in result['answer'] or '时间' in result['answer'],result
            result=ask(tid,'交材料的截止时刻是2026年10月2日17:00，提前1天提醒。其他两条不变，一起分组预览。','clarify-deadline')
        assert result['status']=='needs_confirmation' and result['preview']['kind']=='batch',result
        assert sum(len(g['operations']) for g in result['preview']['groups'])==3
        result=ask(tid,'组会改为10月2日17点到18点，其余两条不变，继续保留三个分组。','follow-up')
        assert result['status']=='needs_confirmation' and result['preview']['kind']=='batch',result
        groups=result['preview']['groups'];ops=[p for g in groups for p in g['operations']]
        event=next(p for p in ops if p['kind']=='event')
        assert instant(event['after']['time']['at']).isoformat().startswith('2026-10-02T09:00')
        exam=next(p for p in ops if p['kind']=='item' and p['after']['kind']=='exam')
        assert exam['after']['time']['precision']=='week' and exam['after']['time']['week']==14
        selected=[g['id'] for g in groups if not any(p['kind']=='item' and p['after']['kind']=='exam' for p in g['operations'])]
        saved=confirm(result,selected)
        assert len(saved['receipt']['groups'])==2
        assert len(c.get(path+'/items',headers=h).json()['items'])==1
        undo=ask(tid,'撤销刚才一次保存的组会和交材料，不要动课表。','model-undo')
        assert undo['status']=='needs_confirmation' and undo['preview']['kind']=='undo',undo
        confirm(undo)
        assert all(i['lifecycle']=='cancelled' for i in c.get(path+'/items',headers=h).json()['items'])
        # Exact original occurrence date avoids model-selected course ambiguity.
        course=ask(new_thread(),'老师正式通知：2026年9月30日周三上午第1、2节概率论改到2026年10月1日10:00至11:00，地点B201。请记录调课通知。','course-move')
        assert course['status']=='needs_confirmation' and course['preview']['kind']=='course_change',course
        confirm(course)
        week=c.get(path+'/timetable?week=5',headers=h).json()['events']
        assert any(e['location']=='B201' for e in week)
        exam=c.post('/api/v1/items',headers=h,json={'semester_id':sid,'kind':'exam','title':'期末概率论考试',
            'certainty':'formal','time':{'precision':'exact','at':'2026-12-01T09:00:00+08:00','end_at':'2026-12-01T11:00:00+08:00'}}).json()
        change=ask(new_thread(),'教务通知期末概率论考试改为2026年12月2日9:00至11:00，其他不变，请修改。','exam-move')
        assert change['status']=='needs_confirmation' and change['preview']['kind']=='exam_change',change
        confirm(change)
        assert instant(c.get('/api/v1/items/'+exam['id'],headers=h).json()['time']['at']).day==2
        tags=c.get('/api/v1/tags',headers=h).json()['tags']
        old=next(t for t in tags if t['name']=='项目材料')
        rename=c.post('/api/v1/tags/preview',headers=h,json={'operation':'rename','source_id':old['id'],'name':'材料提交'}).json()
        assert c.post('/api/v1/tags/changes/'+rename['token']+'/apply',headers=h,json={}).status_code==200
        alias=ask(new_thread(),'帮我新增任务“交第二份材料”，2026年10月8日17点截止，标签使用“项目材料”。','tag-alias')
        assert alias['status']=='needs_confirmation' and alias['preview']['kind']=='item',alias
        alias_saved=confirm(alias)['receipt']['item']
        assert alias_saved['tags']==[{'id':old['id'],'name':'材料提交'}],alias_saved['tags']
        analysis=ask(new_thread(),'查询本学期的统计，告诉我固定安排和个人计划的时长，不要猜实际投入。','statistics')
        assert analysis['status']=='completed' and 'query_insights' in evidence[-1]['tools'],analysis
    report={'passed':True,'scope':'isolated database, synthetic notices, real model; not device/voice/production','checks':evidence}
    out=ROOT/'output/verification/schedule-operations-model.json';out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')


if __name__=='__main__':main()
