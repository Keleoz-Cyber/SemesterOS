from datetime import datetime
from test_foundation import client, register, semester
from test_schedule_api import setup, proposal, accept


def event_body(sid, **patch):
    return {'semester_id': sid, 'title': '课题组组会', 'time': {
        'precision': 'exact', 'at': '2026-09-21T09:00:00+08:00',
        'end_at': '2026-09-21T10:00:00+08:00'}, 'certainty': 'formal',
        'category_id': 'research', 'tags': ['组会', ' 组会 ', '项目讨论'],
        'location': '6412', 'reminder_minutes': [30], **patch}


def revision(c, h, sid):
    return next(s['revision'] for s in c.get('/api/v1/semesters', headers=h).json() if s['id'] == sid)


def create_event(c, h, sid, **patch):
    return c.post('/api/v1/events', headers={**h, 'Idempotency-Key': 'event-create'},
                  json={**event_body(sid, **patch), 'expected_revision': revision(c, h, sid)})


def test_event_is_fixed_scoped_versioned_and_idempotent(client):
    _, h = register(client); _, other = register(client, 'student_b'); s = semester(client, h)
    data = {**event_body(s['id']), 'expected_revision': s['revision']}
    headers = {**h, 'Idempotency-Key': 'same-event'}
    first = client.post('/api/v1/events', headers=headers, json=data)
    assert first.status_code == 201, first.text
    saved = first.json(); event = saved['event']; url = '/api/v1/events/' + event['id']
    assert event['control'] == 'fixed'
    assert [tag['name'] for tag in event['tags']] == ['组会', '项目讨论']
    assert client.post('/api/v1/events', headers=headers, json=data).json() == saved
    assert revision(client, h, s['id']) == s['revision'] + 1
    assert client.get(url, headers=other).status_code == 404
    assert client.patch(url, headers=other, json={**data, 'expected_version': 1}).status_code == 404
    stale = client.patch(url, headers=h, json={**data, 'expected_version': 1})
    assert stale.status_code == 409
    changed = client.patch(url, headers=h, json={**data, 'expected_revision': saved['revision'],
                           'expected_version': 1, 'location': '6302'})
    assert changed.status_code == 200, changed.text
    assert changed.json()['event']['version'] == 2
    assert client.get(url + '/history', headers=h).json()['entries'][-1]['version'] == 2


def test_event_blocks_legacy_solver_and_invalidates_existing_candidate(client, monkeypatch):
    h, s, item = setup(client, monkeypatch, minutes=180)
    before = proposal(client, h, s, item)
    assert before['status'] == 'FEASIBLE_COMPLETE'
    saved = create_event(client, h, s['id'])
    assert saved.status_code == 201, saved.text
    assert accept(client, h, before).status_code == 409
    after = proposal(client, h, s, item)
    assert after['status'] == 'FEASIBLE_COMPLETE'
    assert all(datetime.fromisoformat(b['start_at']) >= datetime.fromisoformat('2026-09-21T10:00:00+08:00') for b in after['blocks'])
    assert accept(client, h, after).status_code == 200
    assert client.get('/api/v1/events/' + saved.json()['event']['id'], headers=h).json()['time']['at'].startswith('2026-09-21T01:00')


def test_event_cancel_restores_capacity_and_removes_reminders(client, monkeypatch):
    h, s, item = setup(client, monkeypatch, minutes=240)
    result = create_event(client, h, s['id']); assert result.status_code == 201, result.text
    assert proposal(client, h, s, item)['status'] == 'INFEASIBLE'
    eid = result.json()['event']['id']
    feed = client.get('/api/v1/reminders', headers=h).json()['reminders']
    assert any(r.get('resource_type') == 'event' and r['item_id'] == 'event:' + eid for r in feed)
    cancelled = client.post('/api/v1/events/' + eid + '/cancel', headers=h,
                            json={'expected_version': 1, 'expected_revision': revision(client, h, s['id'])})
    assert cancelled.status_code == 200, cancelled.text
    assert not any(r.get('item_id') == 'event:' + eid for r in client.get('/api/v1/reminders', headers=h).json()['reminders'])
    assert proposal(client, h, s, item)['status'] == 'FEASIBLE_COMPLETE'


def test_partial_time_is_preserved_and_planning_returns_candidates(client, monkeypatch):
    h, s, item = setup(client, monkeypatch)
    result = create_event(client, h, s['id'], time={'precision': 'date', 'date': '2026-09-21'}, certainty='tentative')
    assert result.status_code == 201, result.text
    event = result.json()['event']
    assert event['time']['at'] is None and event['time']['end_at'] is None
    assert event['reminders'][0]['schedule_state'] == 'pending_anchor'
    p = proposal(client, h, s, item)
    assert p['can_apply'] and p['uncertainty_warnings']
    assert all(not w['exclusion_applied'] for w in p['uncertainty_warnings'])


def test_calendar_projection_distinguishes_deadline_and_event_and_clips_cross_day(client):
    _, h = register(client); s = semester(client, h)
    result = create_event(client, h, s['id'], time={'precision': 'exact', 'at': '2026-09-21T23:00:00+08:00', 'end_at': '2026-09-22T01:00:00+08:00'})
    assert result.status_code == 201, result.text
    item = client.post('/api/v1/items', headers=h, json={'semester_id': s['id'], 'kind': 'task', 'title': '提交材料',
        'time': {'precision': 'date', 'date': '2026-09-22'}})
    assert item.status_code == 201
    feed = client.get(f"/api/v1/semesters/{s['id']}/calendar?from_date=2026-09-22&to_date=2026-09-22", headers=h)
    assert feed.status_code == 200, feed.text
    entries = feed.json()['entries']
    event = next(r for r in entries if r['resource_type'] == 'event')
    deadline = next(r for r in entries if r['resource_type'] == 'deadline')
    assert event['start_at'].startswith('2026-09-21T15:00')  # original interval, not rewritten by the view
    assert deadline['start_at'] is None and deadline['due_at'] is None
    assert deadline['date'] == '2026-09-22'
    assert client.get(f"/api/v1/semesters/{s['id']}/calendar?from_date=2026-09-23&to_date=2026-09-22", headers=h).status_code == 422


def test_event_tag_identity_is_per_owner_and_reused(client):
    _, a = register(client); _, b = register(client, 'student_b')
    sa = semester(client, a); sb = semester(client, b)
    first = create_event(client, a, sa['id']); second = create_event(client, b, sb['id'])
    assert first.status_code == second.status_code == 201
    ta = first.json()['event']['tags'][0]; tb = second.json()['event']['tags'][0]
    assert ta['id'] != tb['id']
    catalog = client.get('/api/v1/taxonomy', headers=a).json()
    assert {t['id'] for t in catalog['tags']} == {t['id'] for t in first.json()['event']['tags']}
    assert len(catalog['categories']) == 4


def test_calendar_orders_course_local_times_and_event_utc_times_chronologically(client):
    _, h = register(client); s = semester(client,h)
    batch = client.post('/api/v1/imports',headers=h,json={'semester_id':s['id'],'source':'manual','courses':[
        {'title':'早课','teacher':'示例教师','location':'A101','weekday':1,'weeks':[4],'sections':[1]}]}).json()
    assert client.post('/api/v1/imports/'+batch['id']+'/apply',headers=h,json={'expected_revision':0}).status_code==200
    assert create_event(client,h,s['id']).status_code==201
    entries=client.get(f"/api/v1/semesters/{s['id']}/calendar?from_date=2026-09-21&to_date=2026-09-21",headers=h).json()['entries']
    assert [e['title'] for e in entries]==['早课','课题组组会']


def test_invalid_interval_and_injected_owner_are_rejected(client):
    _, h = register(client); s = semester(client, h)
    body = {**event_body(s['id']), 'expected_revision': s['revision']}
    body['time']['end_at'] = body['time']['at']
    assert client.post('/api/v1/events', headers=h, json=body).status_code == 422
    body = {**event_body(s['id']), 'expected_revision': s['revision'], 'user_id': 'someone-else'}
    assert client.post('/api/v1/events', headers=h, json=body).status_code == 422


def test_manual_event_edit_preserves_original_notice_when_omitted(client):
    _, h = register(client); s = semester(client,h)
    saved = create_event(client,h,s['id'],source_text='原始会议通知').json()
    eid = saved['event']['id']
    edited = client.patch('/api/v1/events/'+eid,headers=h,json={**event_body(s['id']),
        'expected_revision':saved['revision'],'expected_version':1,'location':'新的会议室'})
    assert edited.status_code == 200, edited.text
    assert edited.json()['event']['source_text'] == '原始会议通知'


def test_ai_fixed_event_is_a_candidate_until_confirmed_and_keeps_original_source(client):
    _, h = register(client); s = semester(client, h)
    source = '周一9点到10点开组会，会议室6412'
    raw = {k: v for k, v in event_body(s['id']).items() if k != 'semester_id'}
    client.app.state.text_model = lambda *args: ({'intent': 'create_event', 'event': raw,
        'evidence': {'title': '组会'}, 'questions': []}, {'model': 'synthetic'})
    r = client.post('/api/v1/capture/text', headers=h, json={'semester_id': s['id'], 'text': source})
    assert r.status_code == 200, r.text
    candidate = r.json()
    feed = client.get(f"/api/v1/semesters/{s['id']}/calendar?from_date=2026-09-21&to_date=2026-09-27", headers=h).json()
    assert not any(e['resource_type'] == 'event' for e in feed['entries'])
    body = {**candidate['event'], 'candidate_id': candidate['id'], 'expected_revision': revision(client,h,s['id']), 'source_text': '不能覆盖原始来源'}
    saved = client.post('/api/v1/events', headers=h, json=body)
    assert saved.status_code == 201, saved.text
    assert saved.json()['event']['source_text'] == source
    assert client.post('/api/v1/events', headers=h, json={**body,'expected_revision':saved.json()['revision']}).status_code == 409
