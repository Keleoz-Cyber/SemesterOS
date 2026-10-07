import json
from datetime import datetime
import pytest
from test_foundation import client, register, semester
from test_agent import thread, turn, call, run


def test_model_tool_instants_are_local_without_changing_source_or_storage():
    from app.model_context import model_messages
    source='原消息写 2026-10-08T11:00:00+00:00，不改原文'
    messages=[{'role':'tool','content':json.dumps({'windows':[{'start_at':'2026-10-08T11:00:00+00:00',
        'end_at':'2026-10-08T13:00:00Z'}], 'time':{'at':'2026-10-08T16:30:00+00:00'},'source_text':source})}]
    copy=json.loads(model_messages(messages)[0]['content'])
    assert copy['windows']==[{'start_at':'2026-10-08T19:00:00+08:00','end_at':'2026-10-08T21:00:00+08:00'}]
    assert copy['time']['at']=='2026-10-09T00:30:00+08:00' and copy['source_text']==source
    assert json.loads(messages[0]['content'])['windows'][0]['start_at'].endswith('+00:00')


@pytest.mark.parametrize('args,minutes',[
    ({'from_date':'2026-10-08','to_date':'2026-10-08','duration_minutes':5},840),
    ({'from_date':'2026-10-10','to_date':'2026-10-10','duration_minutes':540},840),
    ({'from_date':'2026-10-09','to_date':'2026-10-10','duration_minutes':120,
      'window_start_at':'2026-10-09T23:00:00+08:00','window_end_at':'2026-10-10T02:00:00+08:00'},180),
    ({'from_date':'2027-02-02','to_date':'2027-02-02','duration_minutes':60},840),
    ({'from_date':'2026-10-06','to_date':'2026-10-06','duration_minutes':60,'include_past':True},840),
])
def test_free_query_respects_requested_duration_dates_and_continuity(client,monkeypatch,args,minutes):
    from app import reminder_rules
    monkeypatch.setattr(reminder_rules,'utcnow',lambda:datetime.fromisoformat('2026-10-07T14:00:00+08:00'))
    _,h=register(client);s=semester(client,h)
    req=turn(client,h,thread(client,h,s['id']),'查空闲')
    def model(m,t):
        if m[-1]['role']=='user':return call('find_free_windows',args)
        return {'content':'已按记录查询。'}
    run(client,model)
    value=client.get('/api/v1/agent/runs/'+req['id'],headers=h).json()
    assert value['status']=='completed' and value['preview'] is None
    w=value['cards'][0]['data']['windows']
    assert len(w)==1 and (datetime.fromisoformat(w[0]['end_at'])-datetime.fromisoformat(w[0]['start_at'])).total_seconds()==minutes*60
    assert client.get('/api/v1/semesters',headers=h).json()[0]['revision']==0


def test_unknown_end_is_a_checkable_candidate_not_definite_future_occupation(client,monkeypatch):
    from app import reminder_rules
    monkeypatch.setattr(reminder_rules,'utcnow',lambda:datetime.fromisoformat('2026-10-07T14:00:00+08:00'))
    _,h=register(client);s=semester(client,h)
    e=client.post('/api/v1/events',headers=h,json={'semester_id':s['id'],'expected_revision':0,'title':'彩排',
        'certainty':'formal','time':{'precision':'exact','at':'2026-10-07T19:15:00+08:00'}}).json()['event']
    for day in ['2026-10-07','2026-10-08']:
        req=turn(client,h,thread(client,h,s['id']),'晚上十分钟空闲')
        def model(m,t):
            if m[-1]['role']=='user':return call('find_free_windows',{'from_date':day,'to_date':day,
                'duration_minutes':10,'day_start_minutes':1320,'day_end_minutes':1440})
            return {'content':'按已记录安排查询。'}
        run(client,model)
        data=client.get('/api/v1/agent/runs/'+req['id'],headers=h).json()['cards'][0]['data']
        assert len(data['windows'])==1
        if day=='2026-10-07':
            assert data['windows'][0]['needs_check'] is True and '待核对' in data['overview_answer']
            assert data['confirmed_count']==0
        else:
            assert not data['windows'][0].get('needs_check') and data['uncertainty_warnings']==[]
    assert client.get('/api/v1/events/'+e['id'],headers=h).json()['time']['end_at'] is None


def test_provider_interruption_preserves_only_verified_query_reply(client,monkeypatch):
    from app import reminder_rules
    monkeypatch.setattr(reminder_rules,'utcnow',lambda:datetime.fromisoformat('2026-10-07T14:00:00+08:00'))
    _,h=register(client);s=semester(client,h)
    req=turn(client,h,thread(client,h,s['id']),'明天一小时空闲')
    def model(m,t):
        if m[-1]['role']=='user':return call('find_free_windows',{'from_date':'2026-10-08','to_date':'2026-10-08','duration_minutes':60})
        raise TimeoutError('synthetic provider failure after completed query')
    run(client,model)
    value=client.get('/api/v1/agent/runs/'+req['id'],headers=h).json()
    assert value['status']=='completed' and value['error'] is None and value['preview'] is None
    assert value['answer']==value['cards'][0]['data']['overview_answer']
    assert client.get('/api/v1/semesters',headers=h).json()[0]['revision']==0
