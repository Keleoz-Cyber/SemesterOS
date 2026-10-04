from datetime import datetime, timedelta

from test_foundation import client, register, semester, imported_payload


def test_explicit_start_can_anchor_a_reminder_without_becoming_a_deadline():
    from app.reminder_rules import anchor_at, reminder_anchor_at, evaluate
    payload = {'kind': 'task', 'time': {
        'precision': 'exact', 'meaning': 'start', 'at': '2026-10-09T09:00:00+08:00'}}
    assert anchor_at(payload) is None
    assert reminder_anchor_at(payload) == datetime.fromisoformat('2026-10-09T01:00:00+00:00')
    result = evaluate({'mode': 'relative', 'lead_minutes': 15, 'enabled': True},
                      payload, 'active', datetime.fromisoformat('2026-10-01T00:00:00+00:00'))
    assert result == {'trigger_at': '2026-10-09T00:45:00+00:00', 'schedule_state': 'scheduled'}


def prepare(client):
    _, headers = register(client)
    s = semester(client, headers)
    batch = client.post('/api/v1/imports', headers=headers, json=imported_payload(s['id'])).json()
    assert client.post(f"/api/v1/imports/{batch['id']}/apply", headers=headers,
                       json={'expected_revision': 0}).status_code == 200
    return headers, s


def test_course_feed_is_opt_in_owned_and_stable_until_occurrence_changes(client):
    headers, s = prepare(client)
    _, other = register(client, 'student_b')
    path = '/api/v1/reminders?course_lead_minutes=15'
    assert client.get('/api/v1/reminders', headers=headers).json()['reminders'] == []
    assert client.get(path, headers=other).json()['reminders'] == []
    rows = client.get(path, headers=headers).json()['reminders']
    assert len(rows) == 3
    first = rows[0]
    assert first['resource_type'] == 'course' and first['can_complete'] is False
    assert first['place'] == 'A305'
    assert datetime.fromisoformat(first['start_at']) - datetime.fromisoformat(first['trigger_at']) == timedelta(minutes=15)
    client.post('/api/v1/items', headers=headers,
                json={'semester_id': s['id'], 'kind': 'task', 'title': '无关待办'})
    assert client.get(path, headers=headers).json()['reminders'] == rows
    course = client.get(f"/api/v1/courses/{first['resource_id']}", headers=headers).json()
    changed = client.patch(f"/api/v1/courses/{first['resource_id']}", headers=headers,
                           json={**course['course'], 'location': 'B404', 'expected_revision': course['revision']})
    assert changed.status_code == 200, changed.text
    latest = client.get(path, headers=headers).json()['reminders'][0]
    assert latest['place'] == 'B404' and latest['version'] != first['version']
    assert client.delete(f"/api/v1/courses/{first['resource_id']}?expected_revision={changed.json()['revision']}", headers=headers).status_code == 200
    assert client.get(path, headers=headers).json()['reminders'] == []
    assert client.get('/api/v1/reminders?course_lead_minutes=121', headers=headers).status_code == 422


def test_course_feed_reconciles_moved_and_cancelled_occurrences(client, monkeypatch):
    from app import changes
    monkeypatch.setattr(changes, 'utcnow', lambda: datetime.fromisoformat('2026-09-01T08:00:00+08:00'))
    headers, s = prepare(client)
    path = '/api/v1/reminders?course_lead_minutes=15'
    initial = client.get(path, headers=headers).json()['reminders']
    first = initial[0]
    moved = client.post(f"/api/v1/semesters/{s['id']}/changes", headers=headers, json={
        'kind': 'move', 'targets': [first['occurrence_id']], 'title': first['title'],
        'source_text': '老师通知本次调课', 'start_at': '2026-09-03T10:00:00+08:00',
        'end_at': '2026-09-03T11:00:00+08:00', 'location': 'B201'}).json()
    assert client.post(f"/api/v1/changes/{moved['id']}/apply", headers=headers,
                       json={'expected_revision': moved['base_revision']}).status_code == 200
    latest = client.get(path, headers=headers).json()['reminders']
    assert latest[0]['id'] == first['id'] and latest[0]['version'] != first['version']
    assert latest[0]['place'] == 'B201' and latest[1:] == initial[1:]
    cancelled = client.post(f"/api/v1/semesters/{s['id']}/changes", headers=headers, json={
        'kind': 'cancel', 'targets': [first['occurrence_id']], 'title': first['title'], 'source_text': '老师通知本次停课'}).json()
    assert client.post(f"/api/v1/changes/{cancelled['id']}/apply", headers=headers,
                       json={'expected_revision': cancelled['base_revision']}).status_code == 200
    assert client.get(path, headers=headers).json()['reminders'] == initial[1:]
