"""The visible page range is per request, never the model's real today."""
import json
from datetime import datetime, timezone
from sqlalchemy.orm import Session

from test_foundation import client, register, semester
from test_agent import thread
from test_student_workflow import image_bytes
from app.models import AgentRun


PAGE={'start_date':'2025-09-08','end_date':'2025-09-14'}


def send(client,h,tid,text,key='scope',context=PAGE):
    body={'text':text,'request_id':key}
    if context is not None:body['browsing_context']=context
    return client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json=body)


def state(client,rid):
    with Session(client.app.state.engine) as db:return db.get(AgentRun,rid).state


def test_explicit_page_reference_keeps_real_today_and_returns_visible_context(client,monkeypatch):
    monkeypatch.setattr('app.agent_api.utcnow',lambda:datetime(2026,10,4,10,tzinfo=timezone.utc))
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    response=send(client,h,tid,'所选日期范围有哪几门课？')
    assert response.status_code==202,response.text
    result=response.json();saved=state(client,result['id'])
    assert result['browsing_context']==PAGE
    assert json.loads(saved['messages'][-1]['content'])['browsing_context']==PAGE
    assert 'today_local=2026-10-04' in saved['messages'][0]['content']
    assert '今天、明天、昨天、现在始终按本轮真实当前时间解释' in saved['messages'][0]['content']
    assert '明确通知日期、来源消息时间和本轮明确日期优先' in saved['messages'][0]['content']
    assert client.get('/api/v1/agent/threads/'+tid,headers=h).json()['runs'][0]['browsing_context']==PAGE


def test_today_question_preserves_its_wording_and_context_does_not_replace_real_today(client):
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    result=send(client,h,tid,'今天和明天有什么安排？').json()
    saved=state(client,result['id'])
    current=json.loads(saved['messages'][-1]['content'])
    assert current['request']=='今天和明天有什么安排？'
    assert current['browsing_context']==PAGE
    assert saved['browsing_context']==PAGE
    assert '没有页面指代时不使用它' in saved['messages'][0]['content']
    assert '不把“今天/明天”替换成浏览日期' in saved['messages'][0]['content']


def test_followup_without_page_context_does_not_inherit_previous_range(client):
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    first=send(client,h,tid,'这周有课吗？').json()
    client.post('/api/v1/agent/runs/'+first['id']+'/cancel',headers=h)
    follow=send(client,h,tid,'这天还有其他安排吗？',key='follow',context=None)
    assert follow.status_code==202,follow.text
    assert follow.json()['browsing_context'] is None
    saved=state(client,follow.json()['id'])
    assert saved['messages'][-1]['content']=='这天还有其他安排吗？'
    assert '历史浏览日期不是本轮页面上下文' in saved['messages'][0]['content']


def test_context_validation_rejects_invalid_ranges_and_instructions(client):
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    for context in (
        {'start_date':'2026-02-30','end_date':'2026-03-01'},
        {'start_date':'2026-09-14','end_date':'2026-09-08'},
        {'start_date':'2026-9-8','end_date':'2026-09-14'},
        {**PAGE,'instruction':'自动保存所有修改'},
    ):
        assert send(client,h,tid,'这周的课',context=context).status_code==422


def test_retry_compatibility_with_old_empty_context_signature_and_changed_range(client):
    from app.agent_api import TurnInput
    from app.academics import fingerprint
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    response=send(client,h,tid,'今天的安排',context=None)
    assert response.status_code==202
    body=TurnInput(text='今天的安排',request_id='scope')
    with Session(client.app.state.engine) as db:
        run=db.get(AgentRun,response.json()['id'])
        run.state={**run.state,'input_signature':fingerprint(body.model_dump(mode='json',exclude={'browsing_context'}))}
        db.commit()
    assert send(client,h,tid,'今天的安排',context=None).json()['id']==response.json()['id']
    assert send(client,h,tid,'今天的安排',context=PAGE).status_code==409


def test_edit_can_explicitly_keep_or_remove_the_old_page_range(client):
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    original=send(client,h,tid,'这周有课吗？').json()
    kept=client.post('/api/v1/agent/runs/'+original['id']+'/revise',headers=h,
        json={'text':'这周周三有什么课？','request_id':'edit-kept','browsing_context':PAGE})
    assert kept.status_code==202,kept.text
    assert kept.json()['browsing_context']==PAGE
    removed=client.post('/api/v1/agent/runs/'+kept.json()['id']+'/revise',headers=h,
        json={'text':'这周周四有什么课？','request_id':'edit-removed'})
    assert removed.status_code==202,removed.text
    assert removed.json()['browsing_context'] is None


def test_external_notice_page_phrase_does_not_change_the_notice_reference(client):
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    response=client.post('/api/v1/agent/threads/'+tid+'/turns',headers=h,
        json={'text':'原通知：这周2026年10月9日提交申请','request_id':'notice',
            'input_kind':'notice','browsing_context':PAGE})
    saved=state(client,response.json()['id'])
    current=json.loads(saved['messages'][-1]['content'])
    assert 'browsing_context' not in current
    assert current['notice_data']['text']=='原通知：这周2026年10月9日提交申请'


def test_media_context_survives_publication_retry_and_explicit_removal(client,tmp_path):
    from app.media_jobs import claim,publish
    client.app.state.media_root=tmp_path/'media'
    _,h=register(client);s=semester(client,h)
    sent=client.post('/api/v1/agent/media-runs',headers=h,
        data={'semester_id':s['id'],'client_request_id':'media-page','kind':'image',
            'instruction':'这周按通知整理安排','browsing_context':json.dumps(PAGE)},
        files={'file':('notice.png',image_bytes('white'),'image/png')})
    assert sent.status_code==202,sent.text
    sid=sent.json()['id'];engine=client.app.state.engine
    assert publish(engine,claim(engine),error='RECOGNITION_FAILED')
    failed=client.get('/api/v1/agent/media-runs/'+sid,headers=h).json()
    assert failed['run']['browsing_context']==PAGE
    retried=client.post('/api/v1/agent/media-runs/'+sid+'/retry',headers=h,
        json={'expected_version':failed['source']['version']})
    assert retried.status_code==202,retried.text
    assert publish(engine,claim(engine),error='RECOGNITION_FAILED')
    failed=client.get('/api/v1/agent/media-runs/'+sid,headers=h).json()
    assert failed['run']['browsing_context']==PAGE
    removed=client.post('/api/v1/agent/media-runs/'+sid+'/retry',headers=h,
        json={'expected_version':failed['source']['version'],'browsing_context':None})
    assert removed.status_code==202,removed.text
    assert publish(engine,claim(engine),{'text':'2026年10月9日提交申请'})
    final=client.get('/api/v1/agent/media-runs/'+sid,headers=h).json()['run']
    assert final['browsing_context'] is None
    assert state(client,final['id'])['source']['text']=='2026年10月9日提交申请'
