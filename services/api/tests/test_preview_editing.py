from test_foundation import client, register, semester
from test_agent import thread, turn, run, call


def test_direct_edit_preserves_notice_and_is_not_a_save(client):
    _, h = register(client); s = semester(client, h)
    tid = thread(client, h, s['id'])
    original = '周五开会，地点之后再说'
    r = turn(client, h, tid, original)
    run(client, lambda *_: call('prepare_event', {'action': 'create', 'fields': {
        'title': '开会', 'time': {'precision': 'date', 'date': '2026-10-16'}}}))
    p = client.get('/api/v1/agent/runs/' + r['id'], headers=h).json()['preview']
    edited = client.patch(f"/api/v1/agent/runs/{r['id']}/preview", headers=h,
        json={'token': p['token'], 'location': '6108', 'time': {'precision': 'exact', 'at': '2026-10-16T16:25:00+08:00'}})
    assert edited.status_code == 200, edited.text
    value = edited.json()
    assert value['status'] == 'needs_confirmation'
    assert value['preview']['body']['source_text'] == original
    assert value['preview']['after']['time']['end_at'] is None
    assert value['preview']['after']['location'] == '6108'
    assert value['preview']['token'] != p['token']
    assert client.patch(f"/api/v1/agent/runs/{r['id']}/preview", headers=h, json={'token': p['token'], 'title': '过期编辑'}).status_code == 409
    assert client.post(f"/api/v1/agent/runs/{r['id']}/decision", headers=h, json={'token': p['token'], 'decision': 'confirm'}).status_code == 409
    saved = client.post(f"/api/v1/agent/runs/{r['id']}/decision", headers=h,
        json={'token': value['preview']['token'], 'decision': 'confirm'})
    assert saved.status_code == 200, saved.text
    assert saved.json()['status'] == 'applied'


def test_preview_edit_owner_and_field_boundaries(client):
    _, h = register(client); s = semester(client, h)
    r = turn(client, h, thread(client, h, s['id']), '记下交报告')
    run(client, lambda *_: call('prepare_item', {'fields': {'title': '交报告', 'kind': 'task'}}))
    p = client.get('/api/v1/agent/runs/' + r['id'], headers=h).json()['preview']
    _, other = register(client, 'another')
    assert client.patch(f"/api/v1/agent/runs/{r['id']}/preview", headers=other, json={'token': p['token'], 'title': 'x'}).status_code == 404
    assert client.patch(f"/api/v1/agent/runs/{r['id']}/preview", headers=h, json={'token': p['token'], 'source_text': '篡改原文'}).status_code == 422
    value = client.patch(f"/api/v1/agent/runs/{r['id']}/preview", headers=h, json={'token': p['token'], 'title': '交实验报告'})
    assert value.status_code == 200, value.text
    assert value.json()['preview']['after']['time']['precision'] == 'unknown'
