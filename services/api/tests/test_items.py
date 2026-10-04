from datetime import datetime, timedelta, timezone

from test_foundation import client, register, semester


def setup(client):
    _, h = register(client)
    s = semester(client, h)
    return h, s


def payload(s, **fields):
    return {"semester_id": s["id"], "kind": "assignment", "title": "示例实验报告",
            "time": {"precision": "date", "date": "2099-09-25"},
            "source_text": "周五交实验报告", **fields}


def create(client, h, s, **fields):
    response = client.post('/api/v1/items', headers=h, json=payload(s, **fields))
    assert response.status_code == 201, response.text
    return response.json()


def test_date_only_and_unknown_effort_stay_unknown_and_creation_is_idempotent(client):
    h, s = setup(client)
    body = payload(s)
    headers = {**h, 'Idempotency-Key': 'one-item'}
    a = client.post('/api/v1/items', headers=headers, json=body)
    assert a.status_code == 201, a.text
    b = client.post('/api/v1/items', headers=headers, json=body)
    assert a.json()['id'] == b.json()['id']
    assert a.json()['remaining_minutes'] is None
    assert a.json()['anchor_at'] is None
    assert a.json()['time']['precision'] == 'date'
    assert len(client.get(f"/api/v1/semesters/{s['id']}/items", headers=h).json()['items']) == 1


def test_items_isolation_stale_edits_and_history(client):
    h, s = setup(client)
    _, other = register(client, 'student_b')
    item = create(client, h, s)
    url = f"/api/v1/items/{item['id']}"
    assert client.get(url, headers=other).status_code == 404
    assert client.post('/api/v1/items', headers=other, json=payload(s)).status_code == 404
    edit = {**payload(s), 'title': '修正后的报告', 'expected_version': 1, 'change_reason': '本人核对'}
    assert client.patch(url, headers=other, json=edit).status_code == 404
    changed = client.patch(url, headers=h, json=edit)
    assert changed.status_code == 200, changed.text
    assert changed.json()['version'] == 2
    assert client.patch(url, headers=h, json=edit).status_code == 409
    history = client.get(url + '/history', headers=h).json()
    assert len(history) == 2
    assert history[-1]['reason'] == '本人核对'


def test_relative_reminder_needs_anchor_and_duplicates_or_expired_are_rejected(client):
    h, s = setup(client)
    rule = {'mode': 'relative', 'lead_minutes': 1440, 'purpose': 'item'}
    r = client.post('/api/v1/items', headers=h, json=payload(s, reminders=[rule]))
    assert r.status_code == 422
    assert client.get(f"/api/v1/semesters/{s['id']}/items", headers=h).json()['items'] == []
    item = create(client, h, s, time={'precision': 'exact', 'at': '2099-09-25T23:59:00+08:00'}, reminders=[rule])
    assert item['reminders'][0]['trigger_at'] == '2099-09-24T15:59:00+00:00'
    url = f"/api/v1/items/{item['id']}/reminders"
    assert client.post(url, headers=h, json={**rule, 'expected_item_version': 1}).status_code == 422
    expired = {'mode': 'absolute', 'trigger_at': '2000-01-01T00:00:00Z', 'purpose': 'item', 'expected_item_version': 1}
    assert client.post(url, headers=h, json=expired).status_code == 422


def test_reminders_follow_relative_anchor_but_absolute_needs_review_and_completion_cancels(client):
    h, s = setup(client)
    item = create(client, h, s, time={'precision': 'exact', 'at': '2099-09-25T14:30:00+08:00'}, reminders=[
        {'mode': 'relative', 'lead_minutes': 120},
        {'mode': 'absolute', 'trigger_at': '2099-09-24T20:00:00+08:00'},
    ])
    url = f"/api/v1/items/{item['id']}"
    edit = {**payload(s), 'time': {'precision': 'exact', 'at': '2099-09-24T14:30:00+08:00'},
            'expected_version': 1, 'change_reason': '核对新的截止通知'}
    updated = client.patch(url, headers=h, json=edit)
    assert updated.status_code == 200, updated.text
    rules = updated.json()['reminders']
    assert rules[0]['trigger_at'] == '2099-09-24T04:30:00+00:00'
    assert rules[1]['trigger_at'] == '2099-09-24T12:00:00+00:00'
    assert rules[1]['schedule_state'] == 'needs_review'
    done = client.post(url + '/lifecycle', headers=h, json={'expected_version': 2, 'lifecycle': 'completed'})
    assert done.status_code == 200, done.text
    assert all(r['schedule_state'] == 'disabled' for r in done.json()['reminders'])
    assert client.get('/api/v1/reminders', headers=h).json()['reminders'] == []


def test_exam_can_be_marked_completed_without_inventing_its_date_or_effort(client):
    h, s = setup(client)
    item = create(client, h, s, kind='exam', certainty='tentative',
                  time={'precision': 'week', 'week': 14}, reminders=[
                      {'mode': 'absolute', 'trigger_at': '2099-01-01T12:00:00+08:00', 'purpose': 'check_notice'}])
    assert item['anchor_at'] is None
    assert item['certainty'] == 'tentative'
    assert item['control'] == 'authoritative'
    completed=client.post(f"/api/v1/items/{item['id']}/lifecycle", headers=h,
                       json={'expected_version': 1, 'lifecycle': 'completed'})
    assert completed.status_code == 200,completed.text
    assert completed.json()['kind']=='exam' and completed.json()['lifecycle']=='completed'
    assert completed.json()['time']['precision']=='week' and completed.json()['remaining_minutes'] is None


def test_relative_reminder_becomes_expired_after_earlier_deadline_without_catchup(client):
    h, s = setup(client)
    now = datetime.now(timezone.utc)
    item = create(client, h, s, time={'precision': 'exact', 'at': (now + timedelta(days=5)).isoformat()},
                  reminders=[{'mode': 'relative', 'lead_minutes': 1440}])
    edit = {**payload(s), 'expected_version': 1, 'change_reason': '核对通知',
            'time': {'precision': 'exact', 'at': (now + timedelta(hours=2)).isoformat()}}
    updated = client.patch(f"/api/v1/items/{item['id']}", headers=h, json=edit)
    assert updated.status_code == 200, updated.text
    assert updated.json()['reminders'][0]['schedule_state'] == 'expired'


def test_explicit_reminder_time_is_independent_of_unknown_exam_or_task_date(client):
    h, s = setup(client)
    rule = {'mode': 'absolute', 'trigger_at': '2099-01-01T12:00:00+08:00'}
    exam=client.post('/api/v1/items', headers=h, json=payload(s, kind='exam', certainty='tentative',
        time={'precision': 'week', 'week': 14}, reminders=[rule]))
    assert exam.status_code == 201,exam.text
    assert exam.json()['reminders'][0]['schedule_state']=='scheduled'
    task = create(client, h, s, time={'precision': 'unknown'}, reminders=[rule])
    assert task['reminders'][0]['schedule_state'] == 'scheduled'


def test_anchor_change_marks_duplicate_trigger_rules_for_review(client):
    h, s = setup(client)
    item = create(client, h, s, time={'precision':'exact', 'at':'2099-09-25T14:00:00+08:00'}, reminders=[
        {'mode':'relative', 'lead_minutes':1440},
        {'mode':'absolute', 'trigger_at':'2099-09-23T14:00:00+08:00'}])
    updated = client.patch(f"/api/v1/items/{item['id']}", headers=h, json={**payload(s),
        'time': {'precision':'exact', 'at':'2099-09-24T14:00:00+08:00'},
        'expected_version':1, 'change_reason':'核对老师通知'})
    assert updated.status_code == 200
    assert all(r['schedule_state'] == 'needs_review' for r in updated.json()['reminders'])
