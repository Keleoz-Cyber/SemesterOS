import pytest
from test_foundation import client, register, semester
from test_agent import call, thread, turn, run
from test_calendar_events import revision


def batch(client, h, sid, groups):
    request=turn(client,h,thread(client,h,sid),'整理这些通知')
    run(client,lambda m,t:call('prepare_batch',{'groups':groups}))
    url='/api/v1/agent/runs/'+request['id']
    value=client.get(url,headers=h).json()
    assert value['status']=='needs_confirmation',str(value)
    return url,value


def group(title):
    return {'title':title,'operations':[{'tool':'prepare_item','arguments':{'fields':{'kind':'task','title':title}}}]}


def test_batch_partial_selection_and_idempotency(client):
    _,h=register(client);s=semester(client,h)
    url,value=batch(client,h,s['id'],[group('交材料'),group('组会准备')])
    assert revision(client,h,s['id'])==0
    groups=value['preview']['groups']
    data={'decision':'confirm','token':value['preview']['token'],'selected_group_ids':[groups[1]['id']]}
    result=client.post(url+'/decision',headers=h,json=data)
    assert result.status_code==200,result.text
    assert len(result.json()['receipt']['groups'])==1
    assert client.post(url+'/decision',headers=h,json=data).json()==result.json()
    data['selected_group_ids']=[groups[0]['id']]
    assert client.post(url+'/decision',headers=h,json=data).status_code==409
    items=client.get('/api/v1/semesters/'+s['id']+'/items',headers=h).json()['items']
    assert [i['title'] for i in items]==['组会准备']


def test_batch_second_failure_rolls_back_first(client,monkeypatch):
    _,h=register(client);s=semester(client,h)
    url,value=batch(client,h,s['id'],[group('A'),group('B')])
    import app.agent_tools as tools
    real=tools.create_item_command
    def broken(db,user,body):
        if body.title=='B':
            from app.auth import error
            error(422,'TEST_FAILURE','第二项失败')
        return real(db,user,body)
    monkeypatch.setattr(tools,'create_item_command',broken)
    data={'decision':'confirm','token':value['preview']['token'],
          'selected_group_ids':[g['id'] for g in value['preview']['groups']]}
    assert client.post(url+'/decision',headers=h,json=data).status_code==422
    assert revision(client,h,s['id'])==0
    assert client.get('/api/v1/semesters/'+s['id']+'/items',headers=h).json()['items']==[]
    assert client.get(url,headers=h).json()['status']=='needs_confirmation'


def test_batch_combined_conflicts_need_explicit_confirmation(client):
    _,h=register(client);s=semester(client,h)
    groups=[{'title':title,'operations':[{'tool':'prepare_event','arguments':{'action':'create','fields':{
        'title':title,'certainty':'formal','time':{'precision':'exact','at':'2026-10-01T09:00:00+08:00','end_at':'2026-10-01T10:00:00+08:00'}}}}]}
        for title in ['组会','班会']]
    url,value=batch(client,h,s['id'],groups)
    assert value['preview']['impact']['fixed_conflicts']
    assert revision(client,h,s['id'])==0
    data={'decision':'confirm','token':value['preview']['token'],'selected_group_ids':[g['id'] for g in value['preview']['groups']]}
    assert client.post(url+'/decision',headers=h,json=data).status_code==422
    data['confirm_fixed_conflicts']=True
    result=client.post(url+'/decision',headers=h,json=data)
    assert result.status_code==200,result.text
    assert revision(client,h,s['id'])==2


def test_selection_preview_detects_conflict_hidden_by_an_unselected_cancellation(client):
    _,h=register(client);s=semester(client,h)
    from test_calendar_events import create_event
    event=create_event(client,h,s['id']).json()['event']
    request=turn(client,h,thread(client,h,s['id']),'取消旧组会，新增同一时段会议')
    def model(messages,tools):
        if messages[-1]['role']=='user':return call('find_records',{'query':event['title'],'resource_type':'event'})
        return call('prepare_batch',{'groups':[
            {'title':'取消旧组会','operations':[{'tool':'prepare_event','arguments':{'action':'cancel','event_id':event['id']}}]},
            {'title':'新增班会','operations':[{'tool':'prepare_event','arguments':{'action':'create','fields':{'title':'班会','time':event['time'],'certainty':'formal'}}}]},
        ]})
    # Existing fixture event is Sept21; move the comparison clock before it.
    from unittest.mock import patch
    from datetime import datetime
    with patch('app.reminder_rules.utcnow',return_value=datetime.fromisoformat('2026-09-01T00:00:00+00:00')):
        run(client,model)
        url='/api/v1/agent/runs/'+request['id'];value=client.get(url,headers=h).json()
        assert value['status']=='needs_confirmation',str(value)
        assert not value['preview']['impact']['fixed_conflicts']
        data={'token':value['preview']['token'],'selected_group_ids':[value['preview']['groups'][1]['id']]}
        preview=client.post(url+'/selection-preview',headers=h,json=data)
        assert preview.status_code==200,preview.text
        assert preview.json()['impact']['fixed_conflicts']
        assert revision(client,h,s['id'])==1
        saved=client.post(url+'/decision',headers=h,json={**data,'decision':'confirm','confirm_fixed_conflicts':True})
        assert saved.status_code==200,saved.text
        assert saved.json()['receipt']['impact']['fixed_conflicts']
