import json
import pytest
from datetime import datetime
from test_foundation import client, register, semester
from test_agent import call, thread, turn, run
from test_changes import setup


def test_agent_course_move_queries_real_occurrence_and_commits_only_on_confirmation(client, monkeypatch):
    h,s,path,old=setup(client,monkeypatch)
    tid=thread(client,h,s['id']);request=turn(client,h,tid,'老师通知这次课程改到周四10点至11点')
    def model(messages, tools):
        if messages[-1]['role']=='user':
            return call('query_course_occurrences',{'query':old['title'],'from_date':old['start_at'][:10],'to_date':old['start_at'][:10]})
        result=json.loads(messages[-1]['content'])
        assert result['occurrences'][0]['id']==old['id']
        return call('prepare_course_change',{'kind':'move','targets':[old['id']],
            'start_at':'2026-09-03T10:00:00+08:00','end_at':'2026-09-03T11:00:00+08:00','location':'B201'})
    run(client,model)
    url='/api/v1/agent/runs/'+request['id'];value=client.get(url,headers=h).json()
    assert value['status']=='needs_confirmation',value
    assert value['preview']['kind']=='course_change'
    assert client.get(path+'/timetable?week=1',headers=h).json()['events'][0]['start_at']==old['start_at']
    change=value['preview']['change_id']
    assert client.post('/api/v1/changes/'+change+'/apply',headers=h,json={'expected_revision':1}).status_code==409
    data={'decision':'confirm','token':value['preview']['token']}
    saved=client.post(url+'/decision',headers=h,json=data)
    assert saved.status_code==200,saved.text
    assert client.post(url+'/decision',headers=h,json=data).json()==saved.json()
    changed=client.get(path+'/timetable?week=1',headers=h).json()['events'][0]
    assert changed['start_at']=='2026-09-03T10:00:00+08:00'
    assert changed['location']=='B201'


def test_agent_can_record_week_only_exam_without_inventing_date(client):
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    request=turn(client,h,tid,'暂定第14周概率论考试，具体日期等通知')
    run(client,lambda m,t:call('prepare_item',{'fields':{'kind':'exam','title':'概率论考试',
        'time':{'precision':'week','week':14},'certainty':'tentative'}}))
    url='/api/v1/agent/runs/'+request['id'];value=client.get(url,headers=h).json()
    assert value['status']=='needs_confirmation',value
    assert value['preview']['after']['time']['at'] is None
    saved=client.post(url+'/decision',headers=h,json={'decision':'confirm','token':value['preview']['token']})
    assert saved.status_code==200,saved.text
    assert saved.json()['receipt']['item']['kind']=='exam'


def test_agent_exam_reschedule_preserves_review_deadline_unless_explicitly_selected(client):
    _,h=register(client);s=semester(client,h)
    exam=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'exam','title':'期末考试',
        'certainty':'formal','time':{'precision':'exact','at':'2026-12-01T09:00:00+08:00','end_at':'2026-12-01T11:00:00+08:00'}}).json()
    review=client.post('/api/v1/exams/'+exam['id']+'/reviews',headers=h,json={
        'expected_exam_version':1,'remaining_minutes':120,'deadline_mode':'exam','start_policy':'now'}).json()
    tid=thread(client,h,s['id']);request=turn(client,h,tid,'正式通知考试改到12月2日上午9至11点')
    def model(messages,tools):
        if messages[-1]['role']=='user':return call('find_records',{'query':'期末考试','resource_type':'exam'})
        return call('prepare_exam_change',{'exam_id':exam['id'],'time':{'precision':'exact',
            'at':'2026-12-02T09:00:00+08:00','end_at':'2026-12-02T11:00:00+08:00'},'certainty':'formal'})
    run(client,model)
    url='/api/v1/agent/runs/'+request['id'];value=client.get(url,headers=h).json()
    assert value['status']=='needs_confirmation',value
    assert value['preview']['kind']=='exam_change'
    assert value['preview']['reviews'][0]['will_align'] is False
    assert client.post('/api/v1/exams/'+exam['id']+'/reschedule',headers=h,json=value['preview']['body']).status_code==409
    result=client.post(url+'/decision',headers=h,json={'decision':'confirm','token':value['preview']['token']})
    assert result.status_code==200,result.text
    assert client.get('/api/v1/items/'+review['id'],headers=h).json()['time']==review['time']


def test_unread_course_occurrence_cannot_be_moved(client,monkeypatch):
    h,s,_,old=setup(client,monkeypatch);tid=thread(client,h,s['id']);request=turn(client,h,tid,'改课')
    def model(messages,tools):
        if messages[-1]['role']=='user':return call('prepare_course_change',{'kind':'cancel','targets':[old['id']]})
        assert json.loads(messages[-1]['content'])['error']['code']=='READ_FIRST'
        return {'content':'需要先核对原课次。'}
    run(client,model)
    value=client.get('/api/v1/agent/runs/'+request['id'],headers=h).json()
    assert value['status']=='completed' and value['preview'] is None


@pytest.mark.parametrize('in_batch',[False,True])
def test_exam_change_preserves_course_link_and_optional_field_presence(client,monkeypatch,in_batch):
    h,s,_,old=setup(client,monkeypatch)
    exam=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'exam','title':'关联考试',
        'course_id':old['course_id'],'certainty':'formal','time':{'precision':'exact','at':'2026-12-01T09:00:00+08:00','end_at':'2026-12-01T11:00:00+08:00'}}).json()
    tid=thread(client,h,s['id']);request=turn(client,h,tid,'学校通知考试改到12月2日9至11点')
    args={'exam_id':exam['id'],'certainty':'formal','time':{'precision':'exact','at':'2026-12-02T09:00:00+08:00','end_at':'2026-12-02T11:00:00+08:00'}}
    def model(messages,tools):
        if messages[-1]['role']=='user':return call('find_records',{'query':'关联考试','resource_type':'exam'})
        if in_batch:return call('prepare_batch',{'groups':[{'title':'考试改期','operations':[{'tool':'prepare_exam_change','arguments':args}]}]})
        return call('prepare_exam_change',args)
    run(client,model)
    url='/api/v1/agent/runs/'+request['id'];value=client.get(url,headers=h).json()
    assert value['status']=='needs_confirmation',str(value)
    data={'decision':'confirm','token':value['preview']['token']}
    if in_batch:data['selected_group_ids']=[value['preview']['groups'][0]['id']]
    result=client.post(url+'/decision',headers=h,json=data)
    assert result.status_code==200,result.text
    assert client.get('/api/v1/items/'+exam['id'],headers=h).json()['course_id']==old['course_id']


@pytest.mark.parametrize('kind',['cancel','suspend'])
def test_model_cannot_clear_known_course_ambiguity_by_narrowing_its_own_query(client,monkeypatch,kind):
    h,s,_,old=setup(client,monkeypatch)
    tid=thread(client,h,s['id']);request=turn(client,h,tid,'概率论停课')
    step=0
    def model(messages,tools):
        nonlocal step
        step+=1
        if step==1:return call('query_course_occurrences',{'query':old['title'],'from_date':'2026-09-01','to_date':'2026-09-20'})
        if step==2:
            assert len(json.loads(messages[-1]['content'])['occurrences'])>=2
            return call('query_course_occurrences',{'query':old['title'],'from_date':old['start_at'][:10],'to_date':old['start_at'][:10]})
        if step==3:return call('prepare_course_change',{'kind':kind,'targets':[old['id']]})
        assert json.loads(messages[-1]['content'])['error']['code']=='AMBIGUOUS_TARGET'
        return {'content':'有多次课，请选择原课次。'}
    run(client,model)
    value=client.get('/api/v1/agent/runs/'+request['id'],headers=h).json()
    assert value['status']=='completed' and old['id'] in value['ambiguous_ids']
