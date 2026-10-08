import time
from sqlalchemy.orm import Session

from app.models import AgentRun, AgentThread, MediaSource
from test_foundation import client, register, semester
from test_agent import call, run, thread, turn


def test_history_delete_is_not_restorable_and_cursor_survives_deleted_row(client):
    _, h = register(client); _, other = register(client, 'other')
    s = semester(client, h)
    tids = [thread(client, h, s['id']) for _ in range(4)]
    query = {'semester_id': s['id'], 'limit': 2}
    first = client.get('/api/v1/agent/history', headers=h, params=query).json()
    tid = first['next_cursor']; url = '/api/v1/agent/threads/' + tid
    assert client.delete(url, headers=other).status_code == 404
    response = client.delete(url, headers=h)
    assert response.status_code == 200, response.text
    deleted = response.json()
    assert deleted['deleted_at']
    assert client.delete(url, headers=h).json() == deleted
    assert client.get(url, headers=h).status_code == 404
    assert client.post(url + '/turns', headers=h,
        json={'text': '旧对话继续', 'request_id': 'deleted'}).status_code == 404
    assert tid not in {r['id'] for r in client.get('/api/v1/agent/threads', headers=h,
        params={'semester_id': s['id']}).json()}
    older = client.get('/api/v1/agent/history', headers=h,
        params={**query, 'before_thread_id': tid}).json()
    assert {r['id'] for r in first['threads'] + older['threads']} == set(tids)
    legacy_query = client.get('/api/v1/agent/history', headers=h,
        params={'semester_id': s['id'], 'deleted': True}).json()
    assert {r['id'] for r in legacy_query['threads']} == set(tids) - {tid}
    assert all(r['deleted_at'] is None for r in legacy_query['threads'])
    assert client.post(url + '/restore', headers=other).status_code == 404
    assert client.post(url + '/restore', headers=h).status_code == 404
    assert client.get(url, headers=h).status_code == 404
    visible = client.get('/api/v1/agent/history', headers=h,
        params={'semester_id': s['id']}).json()
    assert {r['id'] for r in visible['threads']} == set(tids) - {tid}


def test_delete_revokes_running_worker_and_recognition_leases_without_purging_media(client, tmp_path):
    account, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    req = turn(client, h, tid, '记录会议')
    client.app.state.media_root = tmp_path / 'media'
    source_path = client.app.state.media_root / 'history-source.png'
    source_path.parent.mkdir(parents=True, exist_ok=True)
    source_path.write_bytes(b'preserved original')
    with Session(client.app.state.engine) as db:
        source = MediaSource(user_id=account['user']['id'], semester_id=s['id'],
            upload_key='history-media', input_hash='0' * 64, kind='image', mime='image/png',
            size=18, storage_key=source_path.name, status='running', lease_token='recognition-lease',
            lease_until=int(time.time()) + 600, reference_at='2026-10-01T00:00:00Z',
            created_at='2026-10-01T00:00:00Z',
            metadata_json={'agent_run_id': req['id'], 'thread_id': tid})
        db.add(source); db.flush(); source_id = source.id
        row = db.get(AgentRun, req['id'])
        row.state = {**row.state, 'media_source_id': source_id}
        db.commit()
    def model(messages, tools):
        response = client.delete('/api/v1/agent/threads/' + tid, headers=h)
        assert response.status_code == 200, response.text
        return call('prepare_event', {'action': 'create', 'fields': {'title': '不应保存'}})
    run(client, model)
    with Session(client.app.state.engine) as db:
        row = db.get(AgentRun, req['id']); source = db.get(MediaSource, source_id)
        assert row.status == 'cancelled' and row.lease_token is None and row.lease_until == 0
        assert row.state.get('preview') is None and not row.state.get('answer_streaming')
        assert source.status == 'cancelled' and source.lease_token is None and source.lease_until == 0
        assert source.file_deleted is False
    assert source_path.read_bytes() == b'preserved original'
    assert client.get('/api/v1/agent/media-runs/' + source_id, headers=h).status_code == 404
    assert client.post('/api/v1/agent/media-runs/' + source_id + '/retry', headers=h,
        json={'expected_version': 2}).status_code == 404
    assert client.post('/api/v1/agent/threads/' + tid + '/restore', headers=h).status_code == 404
    assert client.get('/api/v1/agent/runs/' + req['id'], headers=h).status_code == 404
    with Session(client.app.state.engine) as db:
        row = db.get(AgentRun, req['id'])
        assert row.status == 'cancelled' and row.state.get('preview') is None


def test_deleted_confirmation_cannot_be_restored_or_applied(client):
    _, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    req = turn(client, h, tid, '添加组会')
    run(client, lambda m, t: call('prepare_event', {'action': 'create', 'fields': {'title': '组会'}}))
    url = '/api/v1/agent/runs/' + req['id']
    decision = {'decision': 'confirm', 'token': client.get(url, headers=h).json()['preview']['token']}
    assert client.delete('/api/v1/agent/threads/' + tid, headers=h).status_code == 200
    assert client.post(url + '/decision', headers=h, json=decision).status_code == 404
    assert client.post('/api/v1/agent/threads/' + tid + '/restore', headers=h).status_code == 404
    assert client.get(url, headers=h).status_code == 404
    assert client.post(url + '/decision', headers=h, json=decision).status_code == 404
    with Session(client.app.state.engine) as db:
        assert db.get(AgentRun, req['id']).status == 'cancelled'
    assert client.get('/api/v1/semesters/' + s['id'] + '/calendar', headers=h,
        params={'from_date': '2026-10-01', 'to_date': '2026-10-01'}).json()['undated'] == []


def test_delete_keeps_saved_business_records_receipts_and_independent_branch(client):
    _, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    saved = []
    for key, tool, fields in [('event', 'prepare_event', {'title': '组会'}),
                              ('item', 'prepare_item', {'kind': 'task', 'title': '材料任务'})]:
        req = turn(client, h, tid, '保存' + key, key)
        run(client, lambda m, t, tool=tool, fields=fields: call(tool, {'fields': fields, **({'action': 'create'} if tool == 'prepare_event' else {})}))
        value = client.get('/api/v1/agent/runs/' + req['id'], headers=h).json()
        response = client.post('/api/v1/agent/runs/' + req['id'] + '/decision', headers=h,
            json={'decision': 'confirm', 'token': value['preview']['token']})
        assert response.status_code == 200, response.text
        saved.append(response.json())
    branch = client.post('/api/v1/agent/runs/' + saved[-1]['id'] + '/revise', headers=h,
        json={'text': '之后独立的问题', 'request_id': 'branch'}).json()
    assert client.delete('/api/v1/agent/threads/' + tid, headers=h).status_code == 200
    visible = client.get('/api/v1/agent/threads/' + branch['thread_id'], headers=h)
    assert visible.status_code == 200, visible.text
    assert visible.json()['runs'][-1]['id'] == branch['id']
    assert visible.json()['runs'][0]['context_only'] is True
    assert client.get('/api/v1/agent/threads/' + branch['thread_id'], headers=h,
        params={'before_run_id': saved[0]['id']}).status_code == 200
    run(client, lambda m, t: {'content': '后续回答。'})
    assert client.get('/api/v1/agent/runs/' + branch['id'], headers=h).json()['status'] == 'completed'
    for value, kind in zip(saved, ('event', 'item')):
        assert client.get('/api/v1/' + ('events/' if kind == 'event' else 'items/') +
            value['receipt'][kind]['id'], headers=h).status_code == 200
        with Session(client.app.state.engine) as db:
            assert db.get(AgentRun, value['id']).state['receipt'] == value['receipt']
            assert db.get(AgentThread, tid).deleted_at is not None
