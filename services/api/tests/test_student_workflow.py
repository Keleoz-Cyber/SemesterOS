"""Focused regressions for streaming and newly durable notice entry."""
import json
import os
import pytest
from types import SimpleNamespace
from pathlib import Path
from io import BytesIO
from PIL import Image
from test_foundation import client,register,semester
from test_agent import thread,turn,call,run


def image_bytes(color):
    out=BytesIO();Image.new('RGB',(30,20),color).save(out,format='PNG');return out.getvalue()


def test_demo_is_a_fresh_owned_account_and_samples_are_explicit(client):
    one=client.post('/api/v1/auth/demo');two=client.post('/api/v1/auth/demo')
    assert one.status_code==two.status_code==201
    one=one.json();two=two.json()
    assert one['user']['is_demo'] and one['user']['id']!=two['user']['id']
    h={'Authorization':'Bearer '+one['access_token']}
    other={'Authorization':'Bearer '+two['access_token']}
    assert client.get('/api/v1/me',headers=h).json()['is_demo']
    semesters=client.get('/api/v1/semesters',headers=h).json()
    assert len(semesters)==1 and '示例' in semesters[0]['name']
    courses=client.get(f"/api/v1/semesters/{one['semester_id']}/courses",headers=h).json()
    assert len(courses)==2 and all('示例' in c['title'] for c in courses)
    brief=client.get(f"/api/v1/semesters/{one['semester_id']}/day-brief",headers=h).json()
    assert any(r['resource_type']=='course' for r in brief['next_day']['entries'])
    assert brief['upcoming_exams'] and '示例' in brief['upcoming_exams'][0]['title']
    assert client.get(f"/api/v1/semesters/{one['semester_id']}/day-brief",headers=other).status_code==404


def test_provider_adapter_consumes_real_sse_content_and_tool_fragments(monkeypatch):
    import httpx
    from app.agent_model import model_turn
    monkeypatch.setenv('DEEPSEEK_API_KEY','test-key')
    frames=[{'choices':[{'delta':{'content':'查到'},'finish_reason':None}]},
            {'choices':[{'delta':{'content':'结果。'},'finish_reason':None}]},
            {'choices':[{'delta':{},'finish_reason':'stop'}]},
            {'choices':[],'usage':{'completion_tokens':4}}]
    original=httpx.Client
    def handle(request):
        assert json.loads(request.content)['stream'] is True
        return httpx.Response(200,text=''.join('data: '+json.dumps(frame)+'\n\n' for frame in frames)+'data: [DONE]\n\n')
    monkeypatch.setattr('app.agent_model.httpx.Client',lambda **kwargs:original(transport=httpx.MockTransport(handle),**kwargs))
    deltas=[];reply=model_turn([],[],on_delta=deltas.append)
    assert deltas==['查到','结果。'] and reply['content']=='查到结果。' and reply['_usage']['completion_tokens']==4
    frames[:]=[{'choices':[{'delta':{'tool_calls':[{'index':0,'id':'call-1','function':{'name':'find_records','arguments':'{"query":'}}]},'finish_reason':None}]},
        {'choices':[{'delta':{'tool_calls':[{'index':0,'function':{'arguments':'"报告"}'}}]},'finish_reason':'tool_calls'}]}]
    tool_reply=model_turn([],[])
    assert tool_reply['tool_calls'][0]['function']=={'name':'find_records','arguments':'{"query":"报告"}'}


def test_answer_deltas_are_pollable_before_provider_finishes_and_query_stage_precedes_tool(client,monkeypatch):
    import app.agent_runtime as runtime
    _,h=register(client);s=semester(client,h)
    request=turn(client,h,thread(client,h,s['id']),'今天有什么安排')
    original=runtime.execute_tool;observed=[]
    def tool(name,*args):
        status=client.get('/api/v1/agent/runs/'+request['id'],headers=h).json()
        observed.append(status['stage'])
        assert status['stage']=='正在查询日程'
        return original(name,*args)
    monkeypatch.setattr(runtime,'execute_tool',tool)
    def provider(messages,tools,on_delta):
        if messages[-1]['role']=='user':return call('query_calendar',{'from_date':'2026-10-01','to_date':'2026-10-01'})
        on_delta('今天')
        partial=client.get('/api/v1/agent/runs/'+request['id'],headers=h).json()
        assert partial['answer']=='今天' and partial['answer_streaming'] and partial['status']=='running'
        on_delta('没有记录的课程。')
        return {'content':'今天没有记录的课程。'}
    monkeypatch.setattr(runtime,'model_turn',provider)
    assert runtime.work_once(client.app.state.engine)
    final=client.get('/api/v1/agent/runs/'+request['id'],headers=h).json()
    assert final['status']=='completed' and not final['answer_streaming']
    assert observed and any(p['stage']=='query' for p in final['progress'])


def test_multi_image_notice_recognition_publishes_one_turn_without_client_polling(client,tmp_path,monkeypatch):
    from app.media_jobs import claim,publish,progress
    from app.media_recognition import recognize
    client.app.state.media_root=tmp_path/'media'
    _,h=register(client);s=semester(client,h)
    data={'semester_id':s['id'],'kind':'image','client_request_id':'same-notice','instruction':'保存这份组会通知'}
    files=[('files',(f'{i}.png',image_bytes(color),'image/png')) for i,color in enumerate(
        ('white','blue','red','green','yellow','black','purple'))]
    sent=client.post('/api/v1/agent/media-runs',headers=h,data=data,files=files)
    assert sent.status_code==202,sent.text
    sent=sent.json();assert sent['run'] is None
    assert sent['source']['is_image_batch'] and sent['source']['image_count']==7
    picture=f"/api/v1/sources/{sent['id']}/images/6?expected_version={sent['source']['version']}"
    assert client.get(picture,headers=h).status_code==200
    assert client.get(f"/api/v1/sources/{sent['id']}/images/0?expected_version=99",headers=h).status_code==409
    _,other=register(client,'other_reader')
    assert client.get(picture,headers=other).status_code==404
    assert client.post('/api/v1/agent/media-runs',headers=h,data=data,files=files).json()['id']==sent['id']
    job=claim(client.app.state.engine)
    assert publish(client.app.state.engine,job,error='RECOGNITION_FAILED')
    failed=client.get('/api/v1/agent/media-runs/'+sent['id'],headers=h).json()
    assert failed['run']['status']=='failed'
    retried=client.post('/api/v1/agent/media-runs/'+sent['id']+'/retry',headers=h,
        json={'expected_version':failed['source']['version']})
    assert retried.status_code==202,retried.text
    assert retried.json()['thread']['id']==sent['thread']['id'] and retried.json()['run'] is None
    assert retried.json()['source']['reference_at']==sent['source']['reference_at']
    job=claim(client.app.state.engine)
    def ocr(path):
        name=Path(path).name
        lines=['组会','10月3日14:00'] if name=='image-1.png' else ['10月3日14:00','地点A201'] if name=='image-2.png' else [name+' 补充内容']
        return SimpleNamespace(txts=lines,scores=[1]*len(lines))
    monkeypatch.setattr('app.media_recognition.ocr_engine',lambda:ocr)
    recognized=recognize(client.app.state.media_root/job['storage_key'],'image',
        on_progress=lambda message:progress(client.app.state.engine,job,message))
    assert recognized['text'].count('10月3日14:00')==1
    assert publish(client.app.state.engine,job,recognized)
    # The durable worker queued it without an API poll triggering creation.
    from sqlalchemy.orm import Session
    from sqlalchemy import select
    from app.models import AgentRun
    with Session(client.app.state.engine) as db:
        turns=list(db.scalars(select(AgentRun)))
        assert len(turns)==1 and turns[0].status=='queued'
    run(client,lambda m,t:call('prepare_event',{'action':'create','fields':{'title':'组会','location':'A201'}}))
    result=client.get('/api/v1/agent/media-runs/'+sent['id'],headers=h).json()
    assert result['run']['status']=='needs_confirmation' and result['source']['recognition']['image_count']==7
    preview=result['run']['preview']
    applied=client.post('/api/v1/agent/runs/'+result['run']['id']+'/decision',headers=h,
        json={'decision':'confirm','token':preview['token']})
    assert applied.status_code==200,applied.text
    assert len(client.get(f"/api/v1/semesters/{s['id']}/events",headers=h).json())==1


def test_exhausted_media_attempts_roll_back_interrupted_run_publication_and_recover(client,tmp_path,monkeypatch):
    import pytest
    from sqlalchemy.orm import Session
    from app.models import MediaSource, AgentRun
    from app import agent_media, media_jobs
    client.app.state.media_root=tmp_path/'media'
    _,h=register(client);s=semester(client,h)
    sent=client.post('/api/v1/agent/media-runs',headers=h,
        data={'semester_id':s['id'],'client_request_id':'interrupted-notice','kind':'image'},
        files={'file':('notice.png',image_bytes('white'),'image/png')}).json()
    sid=sent['id']
    with Session(client.app.state.engine) as db:
        source=db.get(MediaSource,sid);rid=source.metadata_json['agent_run_id']
        source.status='running';source.attempts=3;source.lease_until=0;db.commit()
    def interrupted(db,source):raise RuntimeError('synthetic interruption')
    with monkeypatch.context() as patch:
        patch.setattr(agent_media,'publish_recognized_turn',interrupted)
        with pytest.raises(RuntimeError,match='synthetic interruption'):
            media_jobs.claim(client.app.state.engine)
    with Session(client.app.state.engine) as db:
        assert db.get(MediaSource,sid).status=='running'
        assert db.get(AgentRun,rid).status=='recognizing'
    assert media_jobs.claim(client.app.state.engine) is None
    with Session(client.app.state.engine) as db:
        assert db.get(MediaSource,sid).status=='failed'
        assert db.get(AgentRun,rid).status=='failed'


@pytest.mark.skipif(not os.environ.get('POSTGRES_TEST_URL'), reason='PostgreSQL row locks required')
@pytest.mark.parametrize('winner', ['cancelled', 'lease_renewed', 'deleted'])
def test_exhausted_media_claim_rechecks_state_after_waiting_for_run_lock(client,tmp_path,winner):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Event, get_ident
    import time
    from sqlalchemy import event, select, text
    from sqlalchemy.orm import Session
    from app.models import MediaSource, AgentRun
    from app.media_jobs import claim

    client.app.state.media_root=tmp_path/'media'
    _,h=register(client);s=semester(client,h)
    sent=client.post('/api/v1/agent/media-runs',headers=h,
        data={'semester_id':s['id'],'client_request_id':'contended-notice','kind':'image'},
        files={'file':('notice.png',image_bytes('white'),'image/png')})
    assert sent.status_code==202,sent.text
    sid=sent.json()['id'];engine=client.app.state.engine
    with Session(engine) as db:
        source=db.get(MediaSource,sid);rid=source.metadata_json['agent_run_id']
        source.status='running';source.attempts=3;source.lease_until=0;db.commit()

    waiting=Event();worker={}
    def observe_run_lock(connection,cursor,statement,parameters,context,executemany):
        if (get_ident()==worker.get('thread') and 'agent_runs' in statement
                and 'FOR UPDATE' in statement and not waiting.is_set()):
            worker['pid']=connection.connection.driver_connection.info.backend_pid
            cursor.execute("SET LOCAL lock_timeout = '5s'")
            waiting.set()
    def reclaim():
        worker['thread']=get_ident()
        return claim(engine)

    event.listen(engine,'before_cursor_execute',observe_run_lock)
    try:
        with ThreadPoolExecutor(max_workers=1) as pool:
            with Session(engine) as db:
                agent_run=db.scalar(select(AgentRun).where(AgentRun.id==rid).with_for_update())
                blocker_pid=db.scalar(text('SELECT pg_backend_pid()'))
                future=pool.submit(reclaim)
                assert waiting.wait(timeout=3), 'worker did not reach the AgentRun lock'
                deadline=time.monotonic()+3
                blocked=False
                while time.monotonic()<deadline:
                    blocked=blocker_pid in db.scalar(text('SELECT pg_blocking_pids(:pid)'), {'pid':worker['pid']})
                    if blocked:break
                    Event().wait(0.01)
                assert blocked, 'PostgreSQL did not observe the worker waiting on the held run lock'
                # The worker must release its first source lock before waiting
                # for this run, so the competing transaction can use run -> source.
                source=db.scalar(select(MediaSource).where(MediaSource.id==sid).with_for_update())
                if winner=='cancelled':
                    source.status='cancelled';source.version+=1;source.lease_token=None
                    agent_run.status='cancelled'
                elif winner=='lease_renewed':
                    source.lease_until=int(time.time())+300;source.lease_token='concurrent-owner'
                else:
                    source.file_deleted=True;source.version+=1
                db.commit()
            assert future.result(timeout=8) is None
        with Session(engine) as db:
            source=db.get(MediaSource,sid);agent_run=db.get(AgentRun,rid)
            assert source.error_code is None and source.attempts==3
            assert source.status==('cancelled' if winner=='cancelled' else 'running')
            assert source.version==(1 if winner=='lease_renewed' else 2)
            assert source.file_deleted==(winner=='deleted')
            assert agent_run.status==('cancelled' if winner=='cancelled' else 'recognizing')
            if winner=='lease_renewed':
                assert source.lease_until>int(time.time()) and source.lease_token=='concurrent-owner'
    finally:
        event.remove(engine,'before_cursor_execute',observe_run_lock)


def test_schedule_setup_suggestions_do_not_save_preferences_or_estimates(client):
    _,h=register(client);s=semester(client,h)
    ordinary=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'实验报告'}).json()
    waiting=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'等审批后提交材料',
        'details':{'conditions':['收到审批结果后开始']}}).json()
    setup=client.get(f"/api/v1/semesters/{s['id']}/schedule/setup",headers=h).json()
    tasks={r['id']:r for r in setup['tasks']}
    assert tasks[ordinary['id']]['start_policy']=='now'
    assert tasks[waiting['id']]['start_policy']=='unconfirmed'
    assert not tasks[waiting['id']]['can_schedule'] and tasks[waiting['id']]['waiting_reason']
    assert tasks[ordinary['id']]['duration_suggestion_minutes']==120
    assert setup['availability']['needs_confirmation'] and setup['availability']['candidate']['weekly']
    assert client.get('/api/v1/items/'+ordinary['id'],headers=h).json()['remaining_minutes'] is None
    assert not client.get(f"/api/v1/semesters/{s['id']}/availability",headers=h).json()['configured']


def test_ordinary_unconfirmed_start_and_missing_deadline_do_not_block_known_effort(client,monkeypatch):
    from test_schedule_api import setup
    h,s,_=setup(client,monkeypatch)
    item=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'整理笔记',
        'certainty':'formal','remaining_minutes':45}).json()
    response=client.post(f"/api/v1/semesters/{s['id']}/plan-proposals",headers=h,
        json={'tasks':[{'item_id':item['id']}],'days':7})
    assert response.status_code==201,response.text
    assert response.json()['status']=='FEASIBLE_COMPLETE',response.text


def test_lookahead_and_task_state_statistics_use_recorded_dates_and_linked_progress(client):
    from sqlalchemy.orm import Session
    from sqlalchemy import select
    from app.models import StudyItem,ProgressEntry,CourseMeeting
    _,h=register(client);s=semester(client,h)
    batch=client.post('/api/v1/imports',headers=h,json={'semester_id':s['id'],'source':'manual',
        'courses':[{'title':'大学英语','weekday':2,'weeks':[4],'sections':[1]}]}).json()
    assert client.post('/api/v1/imports/'+batch['id']+'/apply',headers=h,json={'expected_revision':0}).status_code==200
    with Session(client.app.state.engine) as db:course=db.scalar(select(CourseMeeting));cid=course.id
    item=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'assignment','title':'英语报告',
        'course_id':cid,'certainty':'formal','time':{'precision':'date','date':'2026-09-22'}}).json()
    client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'exam','title':'英语考试',
        'course_id':cid,'certainty':'formal','time':{'precision':'week','week':5}})
    with Session(client.app.state.engine) as db:
        row=db.get(StudyItem,item['id']);row.lifecycle='completed'
        db.add(ProgressEntry(user_id=row.user_id,item_id=row.id,payload={'actual_minutes':35},created_at='2026-09-22T09:00:00+08:00'))
        db.commit()
    brief=client.get(f"/api/v1/semesters/{s['id']}/day-brief?day=2026-09-21",headers=h).json()
    assert brief['next_day']['date']=='2026-09-22'
    assert any(r['resource_type']=='course' for r in brief['next_day']['entries'])
    # Completed tasks are absent from future reminders/home deadlines, while
    # range statistics retain their current state and actual user-entered effort.
    assert brief['tomorrow_deadlines']==[]
    result=client.get(f"/api/v1/semesters/{s['id']}/insights",headers=h,
        params={'from_date':'2026-09-21','to_date':'2026-09-22'}).json()
    assert result['task_summary']['completed']==1 and result['task_summary']['active']==0
    linked=next(r for r in result['course_summary'] if r['course_id']==cid)
    assert linked['actual_minutes']==35 and linked['course_scheduled_minutes']==50
    filtered=client.get(f"/api/v1/semesters/{s['id']}/insights",headers=h,
        params={'from_date':'2026-09-21','to_date':'2026-09-22','category_id':'life'}).json()
    assert filtered['task_summary']['completed']==0 and filtered['course_summary']==[]


def test_incomplete_fixed_time_only_excludes_its_known_day_for_manual_agent_and_replan(client,monkeypatch):
    from datetime import datetime
    from app import planning,schedule_api,briefs,reminder_rules
    from test_schedule_api import accept
    now=lambda:datetime.fromisoformat('2026-10-01T10:00:00+08:00')
    for module in (planning,schedule_api,briefs,reminder_rules):monkeypatch.setattr(module,'utcnow',now)
    _,h=register(client);s=semester(client,h);sid=s['id']
    hours={'expected_version':0,'expected_revision':0,'weekly':[
        {'weekday':d,'start':'19:00','end':'21:00'} for d in range(1,8)]}
    assert client.put(f'/api/v1/semesters/{sid}/availability',headers=h,json=hours).status_code==200
    event=client.post('/api/v1/events',headers=h,json={'semester_id':sid,'expected_revision':1,
        'title':'10月3日组会','certainty':'formal','time':{'precision':'exact','at':'2026-10-03T16:00:00+08:00'}}).json()['event']
    client.post('/api/v1/events',headers=h,json={'semester_id':sid,'expected_revision':2,
        'title':'日期还没通知的活动','certainty':'formal','time':{'precision':'unknown'}})
    item=client.post('/api/v1/items',headers=h,json={'semester_id':sid,'kind':'task','title':'实验报告',
        'certainty':'formal','remaining_minutes':180,'start_policy':'at','earliest_start_at':'2026-10-03T16:00:00+08:00',
        'time':{'precision':'exact','at':'2026-10-15T20:00:00+08:00'}}).json()
    manual=client.post(f'/api/v1/semesters/{sid}/plan-proposals',headers=h,
        json={'days':14,'tasks':[{'item_id':item['id']}]}).json()
    assert manual['status']=='FEASIBLE_COMPLETE',manual
    assert manual['uncertainty_warnings'] and all('2026-10-03' not in b['start_at'] for b in manual['blocks'])
    request=turn(client,h,thread(client,h,sid),'安排实验报告')
    def provider(messages,tools):
        if messages[-1]['role']=='user':return call('find_records',{'query':'实验报告'})
        return call('prepare_plan',{'mode':'schedule','days':14,'task_ids':[item['id']]})
    run(client,provider)
    assistant=client.get('/api/v1/agent/runs/'+request['id'],headers=h).json()
    assert assistant['status']=='needs_confirmation',assistant
    assert assistant['preview']['after']['uncertainty_warnings']
    assert accept(client,h,manual).status_code==200
    replan=client.post(f'/api/v1/semesters/{sid}/replan-proposals',headers=h,json={'task_ids':[item['id']]}).json()
    assert replan['status']=='FEASIBLE_COMPLETE',replan
    risk=client.get(f'/api/v1/semesters/{sid}/risk',headers=h).json()
    row=next(r for r in risk['items'] if r['item_id']==item['id'])
    assert row['data_complete'] and row['capacity_after_fixed_minutes'] is not None
    assert row['uncertainty_excluded_minutes']>0 and row['capacity_is_upper_bound']
    brief=client.get(f'/api/v1/semesters/{sid}/day-brief?day=2026-10-06',headers=h).json()
    assert brief['available_windows'] and brief['uncertainty_warnings']
    saved=client.get('/api/v1/events/'+event['id'],headers=h).json()
    assert saved['time']['end_at'] is None and saved['time']['at']==event['time']['at']


def test_notice_frame_keeps_optional_deadline_and_external_speaker_separate(client):
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    raw='我已提交申请，没申请的同学尽快申请助学金'
    sent=client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,
        json={'text':raw,'request_id':'notice-one','input_kind':'notice'}).json()
    def provider(messages,tools):
        frame=json.loads(messages[-1]['content'])
        assert frame['notice_data']['speaker']=='external_notice' and frame['notice_data']['text']==raw
        assert '截止、地点、材料、耗时缺失都可以留空' in messages[0]['content']
        return call('prepare_item',{'fields':{'kind':'task','title':'申请助学金',
            'time':{'precision':'unknown','expression':'尽快'},'details':{'applicability':'尚未申请的学生','conditions':['尚未申请']}}})
    run(client,provider)
    result=client.get('/api/v1/agent/runs/'+sent['id'],headers=h).json()
    assert result['input_kind']=='notice' and result['status']=='needs_confirmation'
    assert result['preview']['after']['time']['at'] is None
    assert result['preview']['after']['source_text']==raw
    assert client.get(f"/api/v1/semesters/{s['id']}/items",headers=h).json()['items']==[]


def test_notice_questions_do_not_auto_record_and_kind_is_bound_to_request_id(client):
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    body={'text':'助学金通知有明确截止吗？','request_id':'query-notice','input_kind':'notice'}
    sent=client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json=body).json()
    def provider(messages,tools):
        assert '就回答查询，不生成事项' in messages[0]['content']
        return {'content':'通知没有说明具体截止。'}
    run(client,provider)
    result=client.get('/api/v1/agent/runs/'+sent['id'],headers=h).json()
    assert result['status']=='completed' and result['preview'] is None
    assert client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json={**body,'input_kind':'message'}).status_code==409


def test_notice_input_clears_inherited_source_and_legacy_message_retry_stays_compatible(client):
    from sqlalchemy.orm import Session
    from app.models import AgentRun
    from app.academics import fingerprint
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    first=turn(client,h,tid,'原消息','old-request')
    run(client,lambda m,t:{'content':'收到原消息。'})
    old_body={'text':'原消息','request_id':'old-request','source_id':None,'source_version':None,
        'selected_record_ids':[],'detach_source':False}
    with Session(client.app.state.engine) as db:
        row=db.get(AgentRun,first['id'])
        row.state={**row.state,'input_signature':fingerprint(old_body),'source':{
            'id':'stale-source','version':1,'kind':'image','text':'另一份旧通知'}}
        db.commit()
    again=client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json={'text':'原消息','request_id':'old-request'})
    assert again.status_code==202 and again.json()['id']==first['id']
    fresh=client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json={
        'text':'助学金申请已打开，没申请的尽快申请','request_id':'new-notice','input_kind':'notice'})
    assert fresh.status_code==202 and fresh.json()['source'] is None
    with Session(client.app.state.engine) as db:
        state=db.get(AgentRun,fresh.json()['id']).state
        assert json.loads(state['messages'][-1]['content'])['notice_data']['text']=='助学金申请已打开，没申请的尽快申请'


def test_task_activity_counts_real_undated_completion_but_not_metadata_edits_or_restored_work(client,monkeypatch):
    from datetime import datetime
    from app import items,insights
    clock={'at':datetime.fromisoformat('2026-09-30T10:00:00+08:00')}
    monkeypatch.setattr(items,'utcnow',lambda:clock['at'])
    monkeypatch.setattr(insights,'utcnow',lambda:datetime.fromisoformat('2026-10-02T12:00:00+08:00'))
    _,h=register(client);s=semester(client,h);sid=s['id']
    def create(title,**patch):
        result=client.post('/api/v1/items',headers=h,json={'semester_id':sid,'kind':'task','title':title,
            'certainty':'formal','category_id':'affairs','tags':['资助'],**patch})
        assert result.status_code==201,result.text
        return result.json()
    def state(item,lifecycle):
        result=client.post('/api/v1/items/'+item['id']+'/lifecycle',headers=h,
            json={'expected_version':item['version'],'lifecycle':lifecycle})
        assert result.status_code==200,result.text
        return result.json()
    old=state(create('之前已完成的无日期任务'),'completed')
    clock['at']=datetime.fromisoformat('2026-10-02T11:00:00+08:00')
    grant=state(create('申请助学金'),'completed')
    create('另一个未定日期待办',category_id='life',tags=['生活'])
    create('已有日期的逾期待办',time={'precision':'date','date':'2026-09-29'})
    assert client.patch('/api/v1/items/'+old['id'],headers=h,json={'semester_id':sid,'kind':'task',
        'title':old['title'],'expected_version':old['version'],'change_reason':'补备注','notes':'今天只补备注'}).status_code==200
    def get(**filters):
        return client.get(f'/api/v1/semesters/{sid}/insights',headers=h,
            params={'from_date':'2026-10-02','to_date':'2026-10-02',**filters}).json()
    data=get();activity=data['task_activity']
    assert activity=={'completed_in_range':1,'active_current':2,'overdue_current':1,'undated_active':1}
    assert data['task_summary']['completed']==0
    tag=grant['tags'][0]['id']
    assert get(category_id='affairs',tag_ids=tag)['task_activity']=={
        'completed_in_range':1,'active_current':1,'overdue_current':1,'undated_active':0}
    state(grant,'active')
    assert get()['task_activity']=={'completed_in_range':0,'active_current':3,'overdue_current':1,'undated_active':2}
    saved=client.get('/api/v1/items/'+grant['id'],headers=h).json()
    assert saved['time']['precision']=='unknown' and saved['anchor_at'] is None


def test_eligibility_conditions_do_not_delay_tasks_but_true_waiting_dependencies_do():
    from app.task_readiness import start_policy
    item={'kind':'task','title':'申请助学金','start_policy':'unconfirmed',
        'details':{'conditions':['尚未申请','本科生','原创作品']}}
    assert start_policy(item)=='now'
    assert item['details']['conditions']==['尚未申请','本科生','原创作品']
    for condition in ('等待资料','收到批准后','确认后才能开始'):
        assert start_policy({**item,'details':{'conditions':[condition]}})=='unconfirmed'
    assert start_policy({**item,'start_policy':'at','earliest_start_at':'2026-10-05T09:00:00+08:00'})=='at'


def test_detail_context_is_owned_target_survives_followup_revision_and_does_not_relax_selection(client):
    _,h=register(client);_,other=register(client,'context_other');s=semester(client,h);foreign=semester(client,other)
    own=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'申请材料'}).json()
    denied=client.post('/api/v1/items',headers=other,json={'semester_id':foreign['id'],'kind':'task','title':'私有材料'}).json()
    sibling=semester(client,h)
    wrong_sem=client.post('/api/v1/items',headers=h,json={'semester_id':sibling['id'],'kind':'task','title':'另一学期'}).json()
    tid=thread(client,h,s['id'])
    previous=turn(client,h,tid,'你好','prefix')
    run(client,lambda m,t:{'content':'请说明要修改的内容。'})
    body={'text':'补充地点A201','request_id':'detail-context','context_record_ids':[own['id']]}
    sent=client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json=body)
    assert sent.status_code==202,sent.text
    request=sent.json();assert request['context_record_ids']==[own['id']]
    def provider(messages,tools):
        context=json.loads(messages[-1]['content'])['context_records']
        assert context[0]['id']==own['id'] and context[0]['title']=='申请材料'
        return call('prepare_item_change',{'item_id':own['id'],'fields':{'location':'A201'}})
    run(client,provider)
    assert client.get('/api/v1/agent/runs/'+request['id'],headers=h).json()['status']=='needs_confirmation'
    follow=client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json={'text':'这件事叫什么','request_id':'follow-context'})
    assert follow.status_code==202 and follow.json()['context_record_ids']==[own['id']]
    run(client,lambda m,t:{'content':'申请材料。'})
    revised=client.post('/api/v1/agent/runs/'+request['id']+'/revise',headers=h,
        json={'text':'地点应为A202','request_id':'revise-context'})
    assert revised.status_code==202 and revised.json()['context_record_ids']==[own['id']]
    run(client,lambda m,t:call('prepare_item_change',{'item_id':own['id'],'fields':{'location':'A202'}}))
    for target in (denied['id'],wrong_sem['id']):
        fresh=thread(client,h,s['id'])
        response=client.post(f'/api/v1/agent/threads/{fresh}/turns',headers=h,json={
            'text':'修改这条','request_id':'denied-context','context_record_ids':[target]})
        assert response.status_code==404,response.text
    fresh=thread(client,h,s['id'])
    response=client.post(f'/api/v1/agent/threads/{fresh}/turns',headers=h,json={
        'text':'选择这条','request_id':'no-ambiguity','selected_record_ids':[own['id']]})
    assert response.status_code==409 and response.json()['code']=='SELECTION_STALE'


def test_cancelled_event_restores_with_one_conflict_confirmation_then_undo_returns_cancelled(client,monkeypatch):
    from datetime import datetime
    from app import calendar_events,reminder_rules,agent_undo
    from test_calendar_events import create_event,revision,event_body
    now=lambda:datetime.fromisoformat('2026-10-02T10:00:00+08:00')
    for module in (calendar_events,reminder_rules,agent_undo):monkeypatch.setattr(module,'utcnow',now)
    _,h=register(client);s=semester(client,h);sid=s['id']
    event=create_event(client,h,sid,title='待恢复组会',reminder_minutes=[30],time={
        'precision':'exact','at':'2026-10-03T14:00:00+08:00','end_at':'2026-10-03T15:00:00+08:00'}).json()['event']
    cancelled=client.post('/api/v1/events/'+event['id']+'/cancel',headers=h,json={
        'expected_version':event['version'],'expected_revision':revision(client,h,sid)})
    assert cancelled.status_code==200 and not cancelled.json()['event']['reminders'][0]['enabled']
    overlap=client.post('/api/v1/events',headers=h,json={**event_body(sid,title='另一场会议',time={
        'precision':'exact','at':'2026-10-03T14:30:00+08:00','end_at':'2026-10-03T15:30:00+08:00'}),
        'expected_revision':revision(client,h,sid)})
    assert overlap.status_code==201,overlap.text
    tid=thread(client,h,sid)
    sent=client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json={
        'text':'恢复这条日程','request_id':'restore-event','context_record_ids':[event['id']]}).json()
    run(client,lambda m,t:call('prepare_event',{'action':'restore','event_id':event['id']}))
    value=client.get('/api/v1/agent/runs/'+sent['id'],headers=h).json();preview=value['preview']
    assert value['status']=='needs_confirmation' and preview['after']['lifecycle']=='active'
    assert preview['impact']['new_fixed_conflicts'] and preview['after']['reminders'][0]['enabled']
    decision={'decision':'confirm','token':preview['token']}
    assert client.post('/api/v1/agent/runs/'+sent['id']+'/decision',headers=h,json=decision).status_code==422
    saved=client.post('/api/v1/agent/runs/'+sent['id']+'/decision',headers=h,
        json={**decision,'confirm_fixed_conflicts':True})
    assert saved.status_code==200,saved.text
    assert saved.json()['receipt']['event']['id']==event['id'] and saved.json()['undo_available']
    undo=client.post('/api/v1/agent/runs/'+sent['id']+'/request-undo',headers=h,
        json={'request_id':'undo-restore'}).json()
    done=client.post('/api/v1/agent/runs/'+undo['id']+'/decision',headers=h,
        json={'decision':'confirm','token':undo['preview']['token']})
    assert done.status_code==200,done.text
    restored=client.get('/api/v1/events/'+event['id'],headers=h).json()
    assert restored['lifecycle']=='cancelled' and restored['time']==event['time']
    assert restored['source_text']==event['source_text'] and not restored['reminders'][0]['enabled']
    past=client.post('/api/v1/events',headers=h,json={**event_body(sid,title='补录的过去日程'),
        'expected_revision':revision(client,h,sid)}).json()['event']
    assert client.post('/api/v1/events/'+past['id']+'/cancel',headers=h,json={
        'expected_version':past['version'],'expected_revision':revision(client,h,sid)}).status_code==200
    sent=client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json={
        'text':'恢复过去这条日程','request_id':'restore-past','context_record_ids':[past['id']]}).json()
    run(client,lambda m,t:call('prepare_event',{'action':'restore','event_id':past['id']}))
    value=client.get('/api/v1/agent/runs/'+sent['id'],headers=h).json()
    assert value['status']=='needs_confirmation'
    assert client.post('/api/v1/agent/runs/'+sent['id']+'/decision',headers=h,json={
        'decision':'confirm','token':value['preview']['token']}).status_code==200


def test_midnight_model_references_use_shanghai_local_date_without_changing_stored_instants(client,tmp_path,monkeypatch):
    from datetime import datetime,timedelta
    from sqlalchemy.orm import Session
    from app import agent_api,media
    from app.models import MediaSource
    from app.model_context import model_reference,model_messages
    from test_media import upload
    clock=datetime.fromisoformat('2026-10-01T16:30:00+00:00')
    monkeypatch.setattr(agent_api,'utcnow',lambda:clock);monkeypatch.setattr(media,'utcnow',lambda:clock)
    client.app.state.media_root=tmp_path/'midnight-media'
    _,h=register(client);s=semester(client,h)
    original='明天下午15:00在A201举行宣讲会。'
    source=upload(client,h,s).json()
    with Session(client.app.state.engine) as db:
        row=db.get(MediaSource,source['id']);row.status='recognized';row.text=original;row.original_text=original;db.commit()
    tid=thread(client,h,s['id'])
    sent=client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json={'text':'整理这份通知',
        'request_id':'midnight-ref','input_kind':'notice','source_id':source['id'],'source_version':source['version']}).json()
    def provider(messages,tools):
        notice=json.loads(messages[-1]['content'])['notice_data']
        assert notice['reference_at']=='2026-10-02T00:30:00+08:00' and notice['today_local']=='2026-10-02'
        assert notice['text']==original and 'today_local=2026-10-02' in messages[0]['content']
        tomorrow=(datetime.fromisoformat(notice['today_local'])+timedelta(days=1)).date()
        return call('prepare_event',{'action':'create','fields':{'title':'宣讲会','time':{
            'precision':'exact','at':f'{tomorrow}T15:00:00+08:00'}}})
    run(client,provider)
    result=client.get('/api/v1/agent/runs/'+sent['id'],headers=h).json()
    assert result['status']=='needs_confirmation' and result['preview']['after']['time']['at']=='2026-10-03T07:00:00Z'
    assert client.get('/api/v1/sources/'+source['id'],headers=h).json()['reference_at']=='2026-10-01T16:30:00+00:00'
    assert model_reference(clock)['today_local']=='2026-10-02'
    wrapped=[{'role':'user','content':json.dumps({'request':json.dumps({'notice_data':{
        'reference_at':'2026-10-01T16:30:00Z','text':original}})})}]
    nested=json.loads(json.loads(model_messages(wrapped)[0]['content'])['request'])
    assert nested['notice_data']['today_local']=='2026-10-02' and wrapped[0]['content'].find('today_local')<0
    def parser(text,reference,courses):
        assert reference=='2026-10-02T00:30:00+08:00'
        return {'intent':'clarify','questions':['核对通知']},{}
    client.app.state.text_model=parser
    parsed=client.post('/api/v1/capture/text',headers=h,json={'semester_id':s['id'],'text':original,
        'reference_at':'2026-10-01T16:30:00Z'})
    assert parsed.status_code==200 and parsed.json()['reference_at']=='2026-10-01T16:30:00+00:00'
