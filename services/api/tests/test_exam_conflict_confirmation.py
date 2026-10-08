"""Every personal fixed record uses the same pre-save conflict decision."""
from datetime import datetime

import pytest

from test_foundation import client, register, semester, imported_payload
from test_agent import call, thread, turn, run


@pytest.fixture
def schedule(client, monkeypatch):
    clock = lambda: datetime.fromisoformat('2026-09-01T08:00:00+08:00')
    for module in ('reminder_rules', 'items', 'agent_api', 'agent_runtime', 'agent_undo'):
        monkeypatch.setattr('app.' + module + '.utcnow', clock)
    _, headers = register(client)
    current = semester(client, headers)
    draft = client.post('/api/v1/imports', headers=headers,
        json=imported_payload(current['id'])).json()
    applied = client.post('/api/v1/imports/' + draft['id'] + '/apply', headers=headers,
        json={'expected_revision': 0})
    assert applied.status_code == 200, applied.text
    return headers, current


def exam(current, **patch):
    return {'semester_id': current['id'], 'kind': 'exam', 'title': '课堂测验',
        'certainty': 'formal', 'time': {'precision': 'exact',
            'at': '2026-09-02T09:00:00+08:00'}, **patch}


def items(client, headers, current):
    return client.get('/api/v1/semesters/' + current['id'] + '/items', headers=headers).json()


def test_unknown_end_exam_preview_and_write_require_real_decision(client, schedule):
    headers, current = schedule
    before = items(client, headers, current)
    body = exam(current, tags=['预览不能写入标签'])
    response = client.post('/api/v1/items/conflict-preview', headers=headers, json=body)
    assert response.status_code == 200, response.text
    preview = response.json()
    assert preview['impact']['new_fixed_conflicts']
    assert len(preview['impact']['course_conflicts']) == 1
    assert items(client, headers, current) == before
    assert client.get('/api/v1/taxonomy', headers=headers).json()['tags'] == []
    rejected = client.post('/api/v1/items', headers=headers, json=body)
    assert rejected.status_code == 422, rejected.text
    assert rejected.json()['code'] == 'CONFIRM_FIXED_CONFLICTS'
    assert items(client, headers, current) == before
    consent = {**body, 'expected_revision': preview['base_revision'], 'confirm_fixed_conflicts': True}
    saved = client.post('/api/v1/items', headers={**headers, 'Idempotency-Key': 'keep-overlap'}, json=consent)
    assert saved.status_code == 201, saved.text
    assert saved.json()['time']['end_at'] is None
    assert 'confirm_fixed_conflicts' not in saved.json()
    assert 'course_leave_targets' not in saved.json()
    assert client.post('/api/v1/items', headers={**headers, 'Idempotency-Key': 'keep-overlap'}, json=consent).json() == saved.json()
    course = client.get('/api/v1/semesters/' + current['id'] + '/timetable?week=1', headers=headers).json()['events'][0]
    assert course.get('attendance_status') is None


def test_exam_and_explicit_course_leave_are_atomic_and_retryable(client, schedule):
    headers, current = schedule
    body = exam(current)
    preview = client.post('/api/v1/items/conflict-preview', headers=headers, json=body).json()
    target = preview['impact']['course_conflicts'][0]['occurrence_id']
    consent = {**body, 'expected_revision': preview['base_revision'], 'course_leave_targets': [target]}
    invalid = client.post('/api/v1/items', headers=headers, json={**consent, 'course_leave_targets': ['unrelated']})
    assert invalid.status_code == 422, invalid.text
    assert items(client, headers, current)['items'] == []
    saved = client.post('/api/v1/items', headers={**headers, 'Idempotency-Key': 'leave-exam'}, json=consent)
    assert saved.status_code == 201, saved.text
    assert saved.json()['course_attendance'][0]['occurrence_id'] == target
    assert client.post('/api/v1/items', headers={**headers, 'Idempotency-Key': 'leave-exam'}, json=consent).json() == saved.json()
    course = client.get('/api/v1/semesters/' + current['id'] + '/timetable?week=1', headers=headers).json()['events'][0]
    assert course['attendance_status'] == 'leave'
    other = client.get('/api/v1/semesters/' + current['id'] + '/timetable?week=3', headers=headers).json()['events'][0]
    assert other.get('attendance_status') is None


def test_restore_exam_has_new_impact_and_cannot_silently_reoccupy_course(client, schedule):
    headers, current = schedule
    saved = client.post('/api/v1/items', headers=headers,
        json=exam(current, expected_revision=1, confirm_fixed_conflicts=True)).json()
    cancelled = client.post('/api/v1/items/' + saved['id'] + '/lifecycle', headers=headers,
        json={'expected_version': saved['version'], 'lifecycle': 'cancelled'}).json()
    request = {'expected_version': cancelled['version'], 'lifecycle': 'active'}
    preview = client.post('/api/v1/items/' + saved['id'] + '/lifecycle/preview', headers=headers, json=request).json()
    assert len(preview['impact']['course_conflicts']) == 1
    rejected = client.post('/api/v1/items/' + saved['id'] + '/lifecycle', headers=headers, json=request)
    assert rejected.status_code == 422, rejected.text
    assert client.get('/api/v1/items/' + saved['id'], headers=headers).json()['lifecycle'] == 'cancelled'
    consent = {**request, 'expected_revision': preview['base_revision'],
        'course_leave_targets': [preview['impact']['course_conflicts'][0]['occurrence_id']]}
    restored = client.post('/api/v1/items/' + saved['id'] + '/lifecycle', headers=headers, json=consent)
    assert restored.status_code == 200, restored.text
    assert restored.json()['lifecycle'] == 'active'
    assert restored.json()['course_attendance']


def test_exam_confirm_cannot_reuse_stale_preview_revision(client, schedule):
    headers, current = schedule
    preview = client.post('/api/v1/items/conflict-preview', headers=headers, json=exam(current)).json()
    client.post('/api/v1/items', headers=headers,
        json={'semester_id': current['id'], 'kind': 'task', 'title': '临时待办'})
    stale = client.post('/api/v1/items', headers=headers,
        json=exam(current, expected_revision=preview['base_revision'], confirm_fixed_conflicts=True))
    assert stale.status_code == 409, stale.text
    assert all(value['kind'] != 'exam' for value in items(client, headers, current)['items'])


def test_exam_edit_with_leave_preserves_omitted_details_tags_and_category(client, schedule):
    headers, current = schedule
    created = client.post('/api/v1/items', headers=headers, json=exam(current,
        time={'precision': 'exact', 'at': '2026-09-02T16:00:00+08:00'},
        details={'materials': ['原有材料要求']}, category_id='life', tags=['原有标签']))
    assert created.status_code == 201, created.text
    saved = created.json()
    request = {'semester_id': current['id'], 'kind': 'exam', 'title': saved['title'],
        'time': exam(current)['time'], 'expected_version': saved['version'],
        'expected_revision': items(client, headers, current)['revision'], 'change_reason': '改到上午'}
    preview = client.post('/api/v1/items/conflict-preview', headers=headers,
        json={**request, 'item_id': saved['id']}).json()
    response = client.patch('/api/v1/items/' + saved['id'], headers=headers,
        json={**request, 'course_leave_targets': [preview['impact']['course_conflicts'][0]['occurrence_id']]})
    assert response.status_code == 200, response.text
    result = response.json()
    assert result['details']['materials'] == ['原有材料要求']
    assert result['tags'] == saved['tags']
    assert result['category_id'] == 'life'
    assert result['course_attendance']


def test_reference_exam_and_ordinary_todo_do_not_require_conflict_consent(client, schedule):
    headers, current = schedule
    saved = client.post('/api/v1/items', headers=headers, json=exam(current, reserve_time=False))
    assert saved.status_code == 201, saved.text
    task = client.post('/api/v1/items', headers=headers,
        json={'semester_id': current['id'], 'kind': 'task', 'title': '上课时截止的待办',
            'time': exam(current)['time']})
    assert task.status_code == 201, task.text


def test_assistant_exam_creation_shows_conflict_before_any_write(client, schedule):
    headers, current = schedule
    tid = thread(client, headers, current['id'])
    request = turn(client, headers, tid, '明天9点有个课堂测验')
    fields = {key: value for key, value in exam(current).items() if key != 'semester_id'}
    run(client, lambda m, t: call('prepare_item', {'fields': fields}))
    url = '/api/v1/agent/runs/' + request['id']
    result = client.get(url, headers=headers).json()
    assert result['status'] == 'needs_confirmation', result
    assert result['preview']['impact']['course_conflicts']
    assert '请假' in result['answer']
    assert items(client, headers, current)['items'] == []
    rejected = client.post(url + '/decision', headers=headers,
        json={'decision': 'confirm', 'token': result['preview']['token']})
    assert rejected.status_code == 422, rejected.text
    consent = {'decision': 'confirm', 'token': result['preview']['token'],
        'course_leave_targets': [result['preview']['impact']['course_conflicts'][0]['occurrence_id']]}
    saved = client.post(url + '/decision', headers=headers, json=consent)
    assert saved.status_code == 200, saved.text
    assert saved.json()['receipt']['item']['kind'] == 'exam'


def test_confirmation_answer_distinguishes_unknown_and_reference_records():
    from app.agent_runtime import preview_confirmation_answer
    assert preview_confirmation_answer({'impact': {'new_fixed_conflicts': []}}) == '请核对这次修改，确认后保存。'
    answer = preview_confirmation_answer({'impact': {'new_fixed_conflicts': [{'certainty': 'possible'}]}})
    assert '可能' in answer and '请假' not in answer
    answer = preview_confirmation_answer({'impact': {'new_fixed_conflicts': [{'overlap_at_start': True}],
        'course_conflicts': [{'title': '已有课程'}]}})
    assert '开始时刻' in answer and '准备请假仍' in answer
