import json
import pytest
from test_foundation import client, register, semester
from test_calendar_events import create_event, revision


def call(name, arguments, id='tool-1'):
    return {'role': 'assistant', 'content': None, 'tool_calls': [
        {'id': id, 'type': 'function', 'function': {'name': name, 'arguments': json.dumps(arguments)}}]}


def thread(c, h, sid):
    r = c.post('/api/v1/agent/threads', headers=h, json={'semester_id': sid})
    assert r.status_code == 201, r.text
    return r.json()['id']


def turn(c, h, tid, text, key='turn-1'):
    r = c.post(f'/api/v1/agent/threads/{tid}/turns', headers=h,
               json={'text': text, 'request_id': key})
    assert r.status_code == 202, r.text
    return r.json()


def run(c, model):
    from app.agent_runtime import work_once
    assert work_once(c.app.state.engine, model=model)


@pytest.mark.parametrize('reply', ['下面是待确认预览：组会，周三17点。请确认是否按此保存。', '请确认：组会生成补录预览吗？'])
def test_text_only_preview_is_repaired_into_real_confirmable_preview(client, reply):
    _, h = register(client); s = semester(client, h)
    request = turn(client, h, thread(client, h, s['id']), '整理这份会议通知')
    count = 0
    def model(messages, tools):
        nonlocal count
        count += 1
        if count == 1:
            return {'content': reply}
        assert 'prepare' in messages[-1]['content']
        return call('prepare_event', {'action': 'create', 'fields': {'title': '组会'}})
    run(client, model)
    result = client.get('/api/v1/agent/runs/' + request['id'], headers=h).json()
    assert result['status'] == 'needs_confirmation' and result['preview']['token']
    assert revision(client, h, s['id']) == 0
    assert count == 2


def test_repeated_unbacked_preview_does_not_report_a_completed_action(client):
    _, h = register(client); s = semester(client, h)
    request = turn(client, h, thread(client, h, s['id']), '帮我记录组会')
    run(client, lambda m, t: {'content': '下面是待确认预览：请确认是否按此保存。'})
    result = client.get('/api/v1/agent/runs/' + request['id'], headers=h).json()
    assert result['status'] == 'failed' and result['preview'] is None
    assert not result['answer']
    assert revision(client, h, s['id']) == 0


def test_agent_queries_real_owned_data_and_remembers_followup(client):
    _, h = register(client); _, other = register(client, 'other'); s = semester(client, h)
    e = create_event(client, h, s['id']).json()['event']
    tid = thread(client, h, s['id'])
    first = turn(client, h, tid, '9月21日有什么安排')
    requests = []
    def model(messages, tools):
        requests.append(messages)
        if messages[-1]['role'] == 'user':
            return call('query_calendar', {'from_date': '2026-09-21', 'to_date': '2026-09-21'})
        data = json.loads(messages[-1]['content'])
        assert data['entries'][0]['resource_id'] == e['id']
        return {'role': 'assistant', 'content': '9点到10点有课题组组会，地点6412。'}
    run(client, model)
    value = client.get('/api/v1/agent/runs/' + first['id'], headers=h).json()
    assert value['status'] == 'completed'
    assert value['cards'][0]['kind'] == 'calendar'
    assert len(requests) == 2
    assert client.get('/api/v1/agent/threads/' + tid, headers=other).status_code == 404
    assert client.get('/api/v1/agent/runs/' + first['id'], headers=other).status_code == 404
    follow = turn(client, h, tid, '刚才那个组会在哪里', 'turn-2')
    def followup(messages, tools):
        assert any('课题组组会' in (m.get('content') or '') for m in messages)
        return {'role': 'assistant', 'content': '刚才查到的地点是6412。'}
    run(client, followup)
    assert client.get('/api/v1/agent/runs/' + follow['id'], headers=h).json()['status'] == 'completed'


def test_agent_preview_requires_bound_confirmation_and_replays_once(client):
    _, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    request = turn(client, h, tid, '9月30日17到18点开组会，在6412，提前30分钟提醒')
    assert turn(client, h, tid, request['text'])['id'] == request['id']
    run(client, lambda m, t: call('prepare_event', {'action': 'create', 'fields': {
        'title': '组会', 'time': {'precision': 'exact', 'at': '2026-09-30T17:00:00+08:00', 'end_at': '2026-09-30T18:00:00+08:00'},
        'location': '6412', 'reminder_minutes': [30], 'category_id': 'research', 'tags': ['组会']}}))
    url = '/api/v1/agent/runs/' + request['id']
    value = client.get(url, headers=h).json()
    assert value['status'] == 'needs_confirmation'
    assert revision(client, h, s['id']) == 0
    preview = value['preview']
    assert preview['after']['title'] == '组会'
    assert client.post(url + '/decision', headers=h, json={'decision': 'confirm', 'token': 'wrong'}).status_code == 409
    data = {'decision': 'confirm', 'token': preview['token']}
    result = client.post(url + '/decision', headers=h, json=data)
    assert result.status_code == 200, result.text
    saved = result.json()
    assert saved['receipt']['event']['title'] == '组会'
    assert saved['receipt']['event']['source_text'] == request['text']
    assert client.post(url + '/decision', headers=h, json=data).json() == saved
    assert revision(client, h, s['id']) == 1


def test_agent_cannot_write_unknown_tools_or_other_accounts(client):
    _, h = register(client); _, b = register(client, 'other'); s = semester(client,h); sb = semester(client,b)
    foreign = create_event(client,b,sb['id']).json()['event']; tid = thread(client,h,s['id'])
    request = turn(client,h,tid,'改一下组会地点')
    def model(m,t):
        if m[-1]['role']=='user':return call('prepare_event', {'action':'update','event_id':foreign['id'],'fields':{'location':'A101'}})
        assert json.loads(m[-1]['content'])['error']['code']=='NOT_FOUND'
        return {'role':'assistant','content':'没有找到这条日程，请提供名称。'}
    run(client,model)
    assert client.get('/api/v1/agent/runs/'+request['id'],headers=h).json()['preview'] is None
    assert revision(client,h,s['id'])==0


def test_agent_rejects_stale_preview_and_can_dismiss_it(client):
    _,h=register(client); s=semester(client,h); tid=thread(client,h,s['id'])
    req=turn(client,h,tid,'添加一次组会')
    run(client,lambda m,t:call('prepare_event',{'action':'create','fields':{'title':'组会'}}))
    url='/api/v1/agent/runs/'+req['id']; p=client.get(url,headers=h).json()['preview']
    create_event(client,h,s['id'])
    assert client.post(url+'/decision',headers=h,json={'decision':'confirm','token':p['token']}).status_code==409
    assert client.post(url+'/decision',headers=h,json={'decision':'reject','token':p['token']}).json()['status']=='cancelled'
    assert revision(client,h,s['id'])==1


def test_agent_modifies_task_and_reminder_via_existing_business_rules(client, monkeypatch):
    from datetime import datetime
    from app import reminder_rules
    monkeypatch.setattr(reminder_rules, 'utcnow', lambda: datetime.fromisoformat('2026-09-30T08:00:00+08:00'))
    _,h=register(client); s=semester(client,h); tid=thread(client,h,s['id'])
    item=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'Java报告'}).json()
    req=turn(client,h,tid,'Java报告重命名为Java实验报告')
    def model(m,t):
        if m[-1]['role']=='user':return call('find_records',{'query':'Java报告'})
        if len([x for x in m if x['role']=='tool'])==1:
            return call('prepare_task_change',{'item_id':item['id'],'intent':'update_task','task_patch':{'title':'Java实验报告'}})
        raise AssertionError('Preview must pause')
    run(client,model)
    url='/api/v1/agent/runs/'+req['id']; result=client.get(url,headers=h).json()
    assert result['status']=='needs_confirmation',result
    assert client.get('/api/v1/items/'+item['id'],headers=h).json()['title']=='Java报告'
    assert client.post('/api/v1/operations/'+result['preview']['operation_id']+'/apply',headers=h,
                       json={'expected_version':1}).status_code==409
    receipt=client.post(url+'/decision',headers=h,json={'decision':'confirm','token':result['preview']['token']})
    assert receipt.status_code==200,receipt.text
    assert client.get('/api/v1/items/'+item['id'],headers=h).json()['title']=='Java实验报告'
    req=turn(client,h,tid,'这个报告10月1日20点提醒我','turn-2')
    run(client,lambda m,t:call('prepare_task_change',{'item_id':item['id'],'intent':'update_reminder',
        'reminder_action':'add','reminder':{'mode':'absolute','trigger_at':'2026-10-01T20:00:00+08:00'}}))
    url='/api/v1/agent/runs/'+req['id']; result=client.get(url,headers=h).json()
    assert result['status']=='needs_confirmation',result
    assert client.post(url+'/decision',headers=h,json={'decision':'confirm','token':result['preview']['token']}).status_code==200
    reminders=client.get('/api/v1/items/'+item['id'],headers=h).json()['reminders']
    assert len(reminders)==1 and reminders[0]['trigger_at']=='2026-10-01T12:00:00+00:00'


def test_agent_cancelled_worker_and_restart_checkpoint_do_not_duplicate(client):
    from app.agent_runtime import claim, work_once
    from app.models import AgentRun
    from sqlalchemy.orm import Session
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    req=turn(client,h,tid,'查9月21日')
    job=claim(client.app.state.engine);assert job['id']==req['id']
    # A crashed worker's lease expires; a new worker recovers the committed state.
    with Session(client.app.state.engine) as db:
        r=db.get(AgentRun,req['id']);r.lease_until=0;db.commit()
    def provider(m,t):
        client.post('/api/v1/agent/runs/'+req['id']+'/cancel',headers=h)
        return call('prepare_event',{'action':'create','fields':{'title':'不能出现'}})
    assert work_once(client.app.state.engine,model=provider)
    result=client.get('/api/v1/agent/runs/'+req['id'],headers=h).json()
    assert result['status']=='cancelled' and result['preview'] is None
    assert revision(client,h,s['id'])==0


def test_agent_analysis_counts_overlap_once_and_preserves_unknowns(client):
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    create_event(client,h,s['id'])
    client.post('/api/v1/events',headers=h,json={'semester_id':s['id'],'expected_revision':1,'title':'同时的活动',
        'time':{'precision':'exact','at':'2026-09-21T09:30:00+08:00','end_at':'2026-09-21T10:30:00+08:00'}})
    client.post('/api/v1/events',headers=h,json={'semester_id':s['id'],'expected_revision':2,'title':'时间待定的通知'})
    req=turn(client,h,tid,'分析9月21日安排')
    def model(m,t):
        if m[-1]['role']=='user':return call('analyze_schedule',{'from_date':'2026-09-21','to_date':'2026-09-21'})
        a=json.loads(m[-1]['content'])
        assert a['occupied_union_minutes']==90 and a['fixed_scheduled_minutes']==120
        assert a['actual_minutes'] is None and a['undated_count']==1
        return {'role':'assistant','content':'这天有两项固定安排，其中半小时重叠。'}
    run(client,model)
    assert client.get('/api/v1/agent/runs/'+req['id'],headers=h).json()['status']=='completed'


@pytest.mark.parametrize('start_at,expected_end', [
    ('2026-09-20T23:00:00+08:00', '2026-09-21T13:00:00+08:00'),
    ('2026-09-21T10:00:00+08:00', '2026-09-21T10:00:00+08:00'),
])
def test_free_windows_respect_known_day_and_keep_unknown_end_warning(client, monkeypatch, start_at, expected_end):
    from datetime import datetime, timezone
    from app import reminder_rules
    monkeypatch.setattr(reminder_rules,'utcnow',lambda:datetime.fromisoformat('2026-09-21T08:00:00+08:00'))
    from test_schedule_api import setup
    h,s,_=setup(client,monkeypatch)
    e=create_event(client,h,s['id'],time={'precision':'exact','at':start_at}).json()['event']
    tid=thread(client,h,s['id']);req=turn(client,h,tid,'9月21日有没有一小时空闲')
    def model(m,t):
        if m[-1]['role']=='user':return call('find_free_windows',{'from_date':'2026-09-21','to_date':'2026-09-21','duration_minutes':60,'scope':'study'})
        return {'role':'assistant','content':'这些候选时段按已知日期避让；活动结束时间仍需核对。'}
    run(client,model)
    value=client.get('/api/v1/agent/runs/'+req['id'],headers=h).json()
    result=value['cards'][0]['data']
    assert value['status']=='completed'
    expected=[{'start_at':'2026-09-21T01:00:00+00:00',
        'end_at':datetime.fromisoformat(expected_end).astimezone(timezone.utc).isoformat()}]
    if datetime.fromisoformat(start_at).date().isoformat()=='2026-09-21':
        expected.append({'start_at':'2026-09-21T02:01:00+00:00',
            'end_at':'2026-09-21T05:00:00+00:00','needs_check':True})
    assert result['windows']==expected
    if datetime.fromisoformat(start_at).date().isoformat()=='2026-09-21':
        warning=next(x for x in result['uncertainty_warnings'] if x['id']=='event:'+e['id'])
        assert not warning['exclusion_applied'] and warning['end_unknown'] and '结束时间' in warning['message']
        assert warning['end_at'] is None
    else:
        assert result['uncertainty_warnings']==[]  # The previous day is not invented as continuing occupation.
    assert result['needs_input']==[]
    assert client.get('/api/v1/events/'+e['id'],headers=h).json()['time']['end_at'] is None


@pytest.mark.parametrize('configured',[False,True])
def test_general_free_time_is_not_restricted_to_study_preferences(client,monkeypatch,configured):
    from datetime import datetime
    from app import reminder_rules
    monkeypatch.setattr(reminder_rules,'utcnow',lambda:datetime.fromisoformat('2026-09-21T08:00:00+08:00'))
    if configured:
        from test_schedule_api import setup
        h,s,_=setup(client,monkeypatch)
    else:
        _,h=register(client);s=semester(client,h)
    before=client.get(f"/api/v1/semesters/{s['id']}/availability",headers=h).json()
    for scope in ['calendar','study']:
        tid=thread(client,h,s['id']);req=turn(client,h,tid,'查一小时空闲')
        def model(messages,tools):
            if messages[-1]['role']=='user':return call('find_free_windows',{
                'from_date':'2026-09-21','to_date':'2026-09-22','duration_minutes':60,'scope':scope})
            return {'role':'assistant','content':'已按查询范围列出空档。'}
        run(client,model)
        value=client.get('/api/v1/agent/runs/'+req['id'],headers=h).json()
        result=value['cards'][0]['data']
        assert value['status']=='completed' and result['scope']==scope
        if scope=='calendar':
            assert result['daily_search']=={'start':'08:00','end':'22:00'}
            assert '9月21—22日' in result['overview_answer'] and '1小时' in result['overview_answer']
            assert result['answer_style']=='summary'
            assert result['windows']==[
                {'start_at':'2026-09-21T00:00:00+00:00','end_at':'2026-09-21T14:00:00+00:00'},
                {'start_at':'2026-09-22T00:00:00+00:00','end_at':'2026-09-22T14:00:00+00:00'}]
        else:
            assert result['windows']==([{'start_at':'2026-09-21T01:00:00+00:00','end_at':'2026-09-21T05:00:00+00:00'}] if configured else [])
    assert client.get(f"/api/v1/semesters/{s['id']}/availability",headers=h).json()==before


def test_apply_failure_rolls_back_both_business_data_and_agent_receipt(client,monkeypatch):
    from app import agent_tools
    from fastapi import HTTPException
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id']);req=turn(client,h,tid,'记录一次组会')
    run(client,lambda m,t:call('prepare_event',{'action':'create','fields':{'title':'组会'}}))
    url='/api/v1/agent/runs/'+req['id'];v=client.get(url,headers=h).json()
    original=agent_tools.apply_preview
    def broken(*args,**kwargs):
        original(*args,**kwargs)
        raise HTTPException(503,detail={'code':'TEST_INTERRUPTION','message':'模拟事务中断'})
    monkeypatch.setattr(agent_tools,'apply_preview',broken)
    decision={'decision':'confirm','token':v['preview']['token']}
    assert client.post(url+'/decision',headers=h,json=decision).status_code==503
    assert revision(client,h,s['id'])==0
    assert client.get(url,headers=h).json()['receipt'] is None
    monkeypatch.setattr(agent_tools,'apply_preview',original)
    assert client.post(url+'/decision',headers=h,json=decision).status_code==200
    assert revision(client,h,s['id'])==1


def test_worker_recovers_at_tool_boundary_without_repeating_model(client,monkeypatch):
    from app import agent_runtime
    from app.models import AgentRun
    from sqlalchemy.orm import Session
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id']);req=turn(client,h,tid,'记录组会')
    original=agent_runtime.execute_tool
    def crash(*args):raise SystemExit('synthetic worker death')
    monkeypatch.setattr(agent_runtime,'execute_tool',crash)
    with pytest.raises(SystemExit):run(client,lambda m,t:call('prepare_event',{'action':'create','fields':{'title':'组会'}}))
    with Session(client.app.state.engine) as db:
        r=db.get(AgentRun,req['id']);assert r.state['next']=='tools';r.lease_until=0;db.commit()
    monkeypatch.setattr(agent_runtime,'execute_tool',original)
    def no_model(*args):raise AssertionError('Must resume committed tool request')
    run(client,no_model)
    assert client.get('/api/v1/agent/runs/'+req['id'],headers=h).json()['status']=='needs_confirmation'


def test_unknown_tool_calls_stop_and_do_not_write(client):
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id']);req=turn(client,h,tid,'清空所有数据')
    calls=[]
    def model(*args):calls.append(1);return call('execute_sql',{'sql':'DELETE FROM calendar_events'})
    run(client,model)
    assert len(calls)==3
    assert client.get('/api/v1/agent/runs/'+req['id'],headers=h).json()['status']=='failed'
    assert revision(client,h,s['id'])==0


def test_rejecting_task_preview_also_closes_legacy_operation(client):
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    item=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'原任务'}).json()
    req=turn(client,h,tid,'原任务改名为报告')
    def model(m,t):
        if m[-1]['role']=='user':return call('find_records',{'query':'原任务'})
        return call('prepare_task_change',{'item_id':item['id'],'intent':'update_task','task_patch':{'title':'报告'}})
    run(client,model)
    url='/api/v1/agent/runs/'+req['id'];p=client.get(url,headers=h).json()['preview']
    assert client.post(url+'/decision',headers=h,json={'decision':'reject','token':p['token']}).status_code==200
    assert client.post('/api/v1/operations/'+p['operation_id']+'/apply',headers=h,json={'expected_version':1}).status_code==409
    assert client.get('/api/v1/items/'+item['id'],headers=h).json()['title']=='原任务'


def test_same_name_search_cannot_silently_pick_one_event(client):
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    first=create_event(client,h,s['id']).json()['event']
    client.post('/api/v1/events',headers=h,json={'semester_id':s['id'],'expected_revision':1,'title':first['title']})
    req=turn(client,h,tid,'把课题组组会改到6302')
    def model(m,t):
        n=sum(x['role']=='tool' for x in m)
        if n==0:return call('find_records',{'query':'课题组组会'})
        if n==1:return call('prepare_event',{'action':'update','event_id':first['id'],'fields':{'location':'6302'}})
        assert json.loads(m[-1]['content'])['error']['code']=='AMBIGUOUS_TARGET'
        return {'role':'assistant','content':'有两条同名组会，请确认是哪一条。'}
    run(client,model)
    value=client.get('/api/v1/agent/runs/'+req['id'],headers=h).json()
    assert value['status']=='completed' and value['preview'] is None
    req=turn(client,h,tid,'就改它吧','vague-followup')
    def followup(m,t):
        if m[-1]['role']=='user':return call('prepare_event',{'action':'update','event_id':first['id'],'fields':{'location':'6302'}})
        assert json.loads(m[-1]['content'])['error']['code']=='AMBIGUOUS_TARGET'
        return {'role':'assistant','content':'请先选出要修改的组会。'}
    run(client,followup)
    value=client.get('/api/v1/agent/runs/'+req['id'],headers=h).json()
    assert value['status']=='completed' and value['preview'] is None
    selected=client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json={
        'text':'选择这一条，继续修改地点','request_id':'picked','selected_record_ids':[first['id']]}).json()
    run(client,lambda m,t:call('prepare_event',{'action':'update','event_id':first['id'],'fields':{'location':'6302'}}))
    value=client.get('/api/v1/agent/runs/'+selected['id'],headers=h).json()
    assert value['status']=='needs_confirmation' and value['preview']['target_id']==first['id']


def test_agent_media_keeps_source_and_rejects_changed_source_before_apply(client):
    from app.models import MediaSource
    from sqlalchemy.orm import Session
    account,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    with Session(client.app.state.engine,expire_on_commit=False) as db:
        source=MediaSource(user_id=account['user']['id'],semester_id=s['id'],upload_key='synthetic',input_hash='0'*64,
            kind='image',mime='image/png',size=1,storage_key='synthetic.png',status='recognized',text='10月2日17点到18点组会',
            original_text='10月2日17点到18点组会',reference_at='2026-09-27T00:00:00+00:00',created_at='2026-09-27T00:00:00+00:00')
        db.add(source);db.commit();source_id=source.id
    body={'text':'请根据这份通知记录日程，先给我预览','request_id':'media-turn','source_id':source_id,'source_version':1}
    response=client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json=body)
    assert response.status_code==202,response.text
    req=response.json()
    def model(m,t):
        assert source.text in json.dumps(m,ensure_ascii=False)
        return call('prepare_event',{'action':'create','fields':{'title':'组会','time':{'precision':'exact','at':'2026-10-02T17:00:00+08:00','end_at':'2026-10-02T18:00:00+08:00'}}})
    run(client,model)
    url='/api/v1/agent/runs/'+req['id'];p=client.get(url,headers=h).json()['preview']
    assert p['source']['id']==source_id
    with Session(client.app.state.engine) as db:
        r=db.get(MediaSource,source_id);r.version=2;db.commit()
    assert client.post(url+'/decision',headers=h,json={'decision':'confirm','token':p['token']}).status_code==409
    assert revision(client,h,s['id'])==0
    assert client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json={**body,'source_version':2}).status_code==409


def test_media_source_survives_clarification_and_stops_after_application(client):
    from app.models import MediaSource
    from sqlalchemy.orm import Session
    account,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    with Session(client.app.state.engine,expire_on_commit=False) as db:
        source=MediaSource(user_id=account['user']['id'],semester_id=s['id'],upload_key='clarify',input_hash='0'*64,
            kind='audio',mime='audio/wav',size=1,storage_key='synthetic.wav',status='recognized',text='明天下午组会',
            original_text='明天下午组会',reference_at='2026-09-27T00:00:00Z',created_at='2026-09-27T00:00:00Z')
        db.add(source);db.commit();source_id=source.id
    response=client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json={
        'text':'整理这份通知','request_id':'media','source_id':source_id,'source_version':1})
    assert response.status_code==202
    run(client,lambda m,t:{'role':'assistant','content':'组会几点开始、几点结束？'})
    req=turn(client,h,tid,'下午4点到5点','clarify')
    run(client,lambda m,t:call('prepare_event',{'action':'create','fields':{'title':'组会','time':{
        'precision':'exact','at':'2026-09-28T16:00:00+08:00','end_at':'2026-09-28T17:00:00+08:00'}}}))
    url='/api/v1/agent/runs/'+req['id'];p=client.get(url,headers=h).json()['preview']
    assert p['source']['id']==source_id
    result=client.post(url+'/decision',headers=h,json={'decision':'confirm','token':p['token']})
    assert result.status_code==200,result.text
    assert result.json()['receipt']['event']['source_id']==source_id
    assert result.json()['receipt']['event']['source_text']=='明天下午组会'
    next_run=turn(client,h,tid,'另记一件事','next')
    assert next_run['source'] is None


def test_agent_assignment_omitted_category_keeps_study_default(client):
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id']);req=turn(client,h,tid,'记录数学作业')
    run(client,lambda m,t:call('prepare_item',{'fields':{'kind':'assignment','title':'数学作业'}}))
    url='/api/v1/agent/runs/'+req['id'];p=client.get(url,headers=h).json()['preview']
    result=client.post(url+'/decision',headers=h,json={'decision':'confirm','token':p['token']})
    assert result.status_code==200,result.text
    assert result.json()['receipt']['item']['category_id']=='study'


def test_agent_semester_analysis_reuses_canonical_statistics(client):
    _,h=register(client);s=semester(client,h);create_event(client,h,s['id']);tid=thread(client,h,s['id'])
    req=turn(client,h,tid,'本学期科研安排和实际记录各有多少时间？')
    def model(m,t):
        if m[-1]['role']=='user':return call('query_insights',{'scope':'semester','category_id':'research'})
        value=json.loads(m[-1]['content'])
        assert value['from_date']=='2026-08-31' and value['to_date']=='2027-01-17'
        assert value['summary']['fixed_scheduled_minutes']==60 and value['summary']['actual_minutes'] is None
        return {'role':'assistant','content':'科研固定安排有1小时；还没有实际投入记录。'}
    run(client,model)
    result=client.get('/api/v1/agent/runs/'+req['id'],headers=h).json()
    assert result['status']=='completed' and result['cards'][0]['kind']=='insights'
