from sqlalchemy import select
from sqlalchemy.orm import Session
from app.models import AgentRun
from test_foundation import client, register, semester
from test_agent import thread, turn, run, call


def test_revise_forks_context_keeps_original_applied_receipt_and_replays(client):
    _, h = register(client); _, other = register(client, 'student_b')
    s = semester(client, h); tid = thread(client, h, s['id'])
    first = turn(client, h, tid, '上文资料：会议由班长组织')
    run(client, lambda m, t: {'content': '已了解组织背景。'})
    second = turn(client, h, tid, '记录班会', 'second')
    run(client, lambda m, t: call('prepare_event', {'action': 'create', 'fields': {'title': '班会'}}))
    url = '/api/v1/agent/runs/' + second['id']
    p = client.get(url, headers=h).json()['preview']
    applied = client.post(url + '/decision', headers=h, json={'decision': 'confirm', 'token': p['token']}).json()
    body = {'text': '查找班会地点', 'request_id': 'revise-1'}
    assert client.post(url + '/revise', headers=other, json=body).status_code == 404
    response = client.post(url + '/revise', headers=h, json=body)
    assert response.status_code == 202, response.text
    revised = response.json()
    assert revised['thread_id'] != tid
    assert client.post(url + '/revise', headers=h, json=body).json()['id'] == revised['id']
    assert client.post(url + '/revise', headers=h, json={**body, 'text': '改为取消'}).status_code == 409
    def model(messages, tools):
        assert any('上文资料：会议由班长组织' in (m.get('content') or '') for m in messages)
        assert not any(m.get('content') == '记录班会' for m in messages)
        return {'content': '请查询已记录的班会。'}
    run(client, model)
    original = client.get(url, headers=h).json()
    assert original['status'] == 'applied' and original['receipt'] == applied['receipt']
    assert client.get('/api/v1/events/' + applied['receipt']['event']['id'], headers=h).status_code == 200
    assert len(client.get('/api/v1/agent/threads/' + tid, headers=h).json()['runs']) == 2
    branch = client.get('/api/v1/agent/threads/' + revised['thread_id'], headers=h).json()
    assert [r['text'] for r in branch['runs']] == [first['text'], body['text']]
    assert branch['runs'][0]['context_only'] is True
    assert branch['runs'][0]['undo_available'] is False and branch['runs'][0]['preview'] is None


def test_revise_running_request_invalidates_lease_and_old_preview(client):
    _, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    req = turn(client, h, tid, '记录旧地点')
    def model(messages, tools):
        response = client.post('/api/v1/agent/runs/' + req['id'] + '/revise', headers=h,
            json={'text': '记录新地点', 'request_id': 'revise'})
        assert response.status_code == 202, response.text
        return call('prepare_event', {'action': 'create', 'fields': {'title': '旧地点会议'}})
    run(client, model)
    old = client.get('/api/v1/agent/runs/' + req['id'], headers=h).json()
    assert old['status'] == 'superseded' and old['preview'] is None
    assert client.get('/api/v1/semesters/' + s['id'] + '/calendar', headers=h,
        params={'from_date': '2026-10-01', 'to_date': '2026-10-01'}).json()['undated'] == []


def test_lazy_history_and_thread_cursor_are_owned_stable_pages(client):
    _, h = register(client); _, other = register(client, 'student_b')
    s = semester(client, h)
    tids = [thread(client, h, s['id']) for _ in range(3)]
    for i in range(3):
        req = turn(client, h, tids[0], '问题' + str(i), str(i))
        run(client, lambda m, t: {'content': '回答。'})
    response = client.get('/api/v1/agent/history', headers=h, params={'semester_id': s['id'], 'limit': 2})
    assert response.status_code == 200, response.text
    page = response.json(); assert len(page['threads']) == 2 and page['has_more']
    older = client.get('/api/v1/agent/history', headers=h,
        params={'semester_id': s['id'], 'limit': 2, 'before_thread_id': page['next_cursor']}).json()
    assert len(older['threads']) == 1 and not older['has_more']
    assert {t['id'] for t in page['threads'] + older['threads']} == set(tids)
    assert client.get('/api/v1/agent/history', headers=other,
        params={'semester_id': s['id']}).status_code == 404
    first = client.get('/api/v1/agent/threads/' + tids[0], headers=h, params={'limit': 2}).json()
    assert [r['text'] for r in first['runs']] == ['问题1', '问题2']
    assert first['has_more'] and first['next_cursor'] == first['runs'][0]['id']
    older = client.get('/api/v1/agent/threads/' + tids[0], headers=h,
        params={'limit': 2, 'before_run_id': first['next_cursor']}).json()
    assert [r['text'] for r in older['runs']] == ['问题0'] and not older['has_more']
    assert client.get('/api/v1/agent/threads/' + tids[1], headers=h,
        params={'before_run_id': req['id']}).status_code == 404


def test_failed_revision_does_not_cancel_original_or_publish_half_a_branch(client):
    _, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    req = turn(client, h, tid, '原问题')
    before = client.get('/api/v1/agent/history', headers=h, params={'semester_id':s['id']}).json()
    response = client.post('/api/v1/agent/runs/' + req['id'] + '/revise', headers=h,
        json={'text':'新问题', 'request_id':'bad-source', 'source_id':'missing', 'source_version':1})
    assert response.status_code == 404
    assert client.get('/api/v1/agent/runs/' + req['id'], headers=h).json()['status'] == 'queued'
    assert client.get('/api/v1/agent/history', headers=h, params={'semester_id':s['id']}).json() == before


def test_revise_retains_source_as_quoted_notice_data_without_resending_fields(client):
    from app.models import MediaSource
    account, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    with Session(client.app.state.engine, expire_on_commit=False) as db:
        source = MediaSource(user_id=account['user']['id'], semester_id=s['id'], upload_key='revision-source',
            input_hash='0'*64, kind='image', mime='image/png', size=1, storage_key='synthetic.png',
            status='recognized', text='原发布9月29日，本周二09:00说明会', original_text='示例原文',
            reference_at='2026-09-29T04:17:00Z', created_at='2026-09-30T00:00:00Z')
        db.add(source); db.commit(); source_id = source.id
    req = client.post('/api/v1/agent/threads/' + tid + '/turns', headers=h,
        json={'text':'整理通知', 'request_id':'source', 'source_id':source_id,'source_version':1}).json()
    revised = client.post('/api/v1/agent/runs/' + req['id'] + '/revise', headers=h,
        json={'text':'记录原消息中的时间', 'request_id':'edited'}).json()
    def model(messages, tools):
        import json
        notice = json.loads(messages[-1]['content'])['notice_data']
        assert notice['reference_at'] == '2026-09-29T12:17:00+08:00'
        assert notice['today_local']=='2026-09-29' and notice['timezone']=='Asia/Shanghai'
        assert notice['text']=='原发布9月29日，本周二09:00说明会'
        return {'content':'原消息时间是**9月29日09:00**，早于发布时刻。'}
    run(client, model)
    assert client.get('/api/v1/agent/runs/' + revised['id'], headers=h).json()['status'] == 'completed'
    with Session(client.app.state.engine) as db:
        saved=db.get(MediaSource,source_id)
        assert saved.reference_at=='2026-09-29T04:17:00Z'
        assert saved.text=='原发布9月29日，本周二09:00说明会' and saved.original_text=='示例原文'
