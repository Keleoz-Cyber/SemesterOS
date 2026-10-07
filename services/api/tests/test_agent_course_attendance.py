from test_foundation import client, register, semester, imported_payload
from test_agent import call, thread, turn, run


def prepared_event(client, monkeypatch):
    from datetime import datetime
    from app import reminder_rules, agent_undo
    now = lambda: datetime.fromisoformat('2026-09-01T08:00:00+08:00')
    monkeypatch.setattr(reminder_rules, 'utcnow', now)
    monkeypatch.setattr(agent_undo, 'utcnow', now)
    _, h = register(client)
    s = semester(client, h)
    imported = client.post('/api/v1/imports', headers=h, json=imported_payload(s['id'])).json()
    client.post(f"/api/v1/imports/{imported['id']}/apply", headers=h, json={'expected_revision': 0})
    tid = thread(client, h, s['id'])
    request = turn(client, h, tid, '9月2日9点到10点彩排')
    run(client, lambda m, t: call('prepare_event', {'action': 'create', 'fields': {
        'title': '彩排', 'time': {'precision': 'exact', 'at': '2026-09-02T09:00:00+08:00',
                                'end_at': '2026-09-02T10:00:00+08:00'}}}))
    url = '/api/v1/agent/runs/' + request['id']
    return h, s, tid, url, client.get(url, headers=h).json()


def test_event_and_course_leave_save_and_undo_as_one_operation(client, monkeypatch):
    h, s, tid, url, pending = prepared_event(client, monkeypatch)
    p = pending['preview']
    assert pending['status'] == 'needs_confirmation', pending
    courses = p['impact']['course_conflicts']
    assert len(courses) == 1
    request = {'decision': 'confirm', 'token': p['token']}
    assert client.post(url + '/decision', headers=h, json=request).status_code == 422
    bad = client.post(url + '/decision', headers=h, json={**request, 'course_leave_targets': ['not-this-course']})
    assert bad.status_code == 422
    assert client.get(f"/api/v1/semesters/{s['id']}/timetable?week=1", headers=h).json()['events'][0].get('attendance_status') is None
    request['course_leave_targets'] = [courses[0]['occurrence_id']]
    response = client.post(url + '/decision', headers=h, json=request)
    assert response.status_code == 200, response.text
    receipt = response.json()['receipt']
    assert len(receipt['course_attendance']) == 1 and receipt['impact']['new_fixed_conflicts'] == []
    assert client.post(url + '/decision', headers=h, json=request).json() == response.json()
    after = client.get(f"/api/v1/semesters/{s['id']}/timetable?week=1", headers=h).json()['events'][0]
    assert after['attendance_status'] == 'leave' and after['id'] == courses[0]['occurrence_id']
    assert client.get(f"/api/v1/semesters/{s['id']}/timetable?week=3", headers=h).json()['events'][0].get('attendance_status') is None
    undo = client.post(url + '/request-undo', headers=h, json={'request_id': 'undo-leave-and-event'}).json()
    result = client.post('/api/v1/agent/runs/' + undo['id'] + '/decision', headers=h,
                         json={'decision': 'confirm', 'token': undo['preview']['token']})
    assert result.status_code == 200, result.text
    restored = client.get(f"/api/v1/semesters/{s['id']}/timetable?week=1", headers=h).json()['events'][0]
    assert restored.get('attendance_status') is None
    assert client.get('/api/v1/events/' + receipt['event']['id'], headers=h).json()['lifecycle'] == 'cancelled'


def test_followup_query_keeps_preview_but_new_preview_supersedes_it(client, monkeypatch):
    h, s, tid, url, original = prepared_event(client, monkeypatch)
    request = turn(client, h, tid, '那次彩排保存了吗', key='question')
    assert client.get(url, headers=h).json()['status'] == 'needs_confirmation'
    assert client.post(url + '/decision', headers=h, json={'decision': 'confirm',
                       'token': original['preview']['token'], 'confirm_fixed_conflicts': True}).status_code == 409
    run(client, lambda m, t: {'role': 'assistant', 'content': '还没有保存，现有预览待确认。'})
    assert client.get(url, headers=h).json()['status'] == 'needs_confirmation'
    turn(client, h, tid, '改成做实验的任务', key='replacement')
    run(client, lambda m, t: call('prepare_item', {'fields': {'kind': 'task', 'title': '做实验'}}))
    assert client.get(url, headers=h).json()['status'] == 'superseded'


def test_arrival_and_start_do_not_fabricate_end_or_change_separate_waiting(client):
    from app.notice_event_time import normalize_notice_event_time
    source = '14:40各节目到25-119候场，15:00正式开始彩排。'
    data = {'title': '下午联排', 'time': {'precision': 'exact', 'at': '2026-10-08T14:40:00+08:00',
                                        'end_at': '2026-10-08T15:00:00+08:00'}}
    value = normalize_notice_event_time(data, source)
    assert value['time']['at'] == data['time']['end_at'] and value['time']['end_at'] is None
    assert value['details']['early_arrival_minutes'] == 20
    waiting = {**data, 'title': '候场'}
    assert normalize_notice_event_time(waiting, source) == waiting
