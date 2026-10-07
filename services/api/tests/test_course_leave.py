"""Personal attendance exceptions retain the school's original occurrences."""
from datetime import date, datetime

import pytest
from sqlalchemy.orm import Session

from app.capacity import calendar_context
from app.models import Semester, User
from app.occurrences import effective_courses
from test_foundation import client, imported_payload
from test_changes import setup


NOW = datetime.fromisoformat('2026-09-01T08:00:00+08:00')


def free_minutes(client, sid):
    with Session(client.app.state.engine) as db:
        s = db.get(Semester, sid)
        courses = effective_courses(db, db.get(User, s.user_id), s)
        context = calendar_context(
            {'first_monday': s.first_monday, 'total_weeks': s.total_weeks, 'periods': s.periods},
            {'weekly': [{'weekday': 3, 'start': '08:00', 'end': '10:00'}]}, courses, [], NOW,
            query_dates=(date(2026, 9, 2), date(2026, 9, 2)))
        return context['free'].minutes(NOW.timestamp(), context['semester_end'])


def change(client, headers, path, kind, targets, **fields):
    response = client.post(path + '/changes', headers=headers, json={
        'kind': kind, 'targets': targets, 'title': '个人出席调整',
        'source_text': '  因病已请假\n本次不上课  ', **fields})
    assert response.status_code == 201, response.text
    preview = response.json()
    response = client.post('/api/v1/changes/' + preview['id'] + '/apply', headers=headers,
                           json={'expected_revision': preview['base_revision']})
    assert response.status_code == 200, response.text
    return preview


@pytest.mark.parametrize('kind,occupied,label', [('leave', False, '已请假'), ('plan_leave', True, '待请假')])
def test_personal_attendance_keeps_school_course_and_only_changes_selected_occurrence(client, monkeypatch, kind, occupied, label):
    h, s, path, old = setup(client, monkeypatch)
    school = client.get('/api/v1/courses/' + old['course_id'], headers=h).json()['course']
    reminders = client.get('/api/v1/reminders?course_lead_minutes=15', headers=h).json()['reminders']
    assert free_minutes(client, s['id']) == 10
    preview = change(client, h, path, kind, [old['id']])
    after = preview['patch']['after'][0]
    for key in ('id', 'course_id', 'title', 'start_at', 'end_at', 'location', 'sections', 'weeks'):
        assert after[key] == old[key]
    assert not after.get('changed')
    assert after['attendance_status'] == kind and after['attendance_reason'] == '因病已请假 本次不上课'
    current = client.get(path + '/timetable?week=1', headers=h).json()['events'][0]
    assert current['attendance_status'] == kind and current['attendance_label'] == label
    assert current['fixed'] is occupied
    third = client.get(path + '/timetable?week=3', headers=h).json()['events'][0]
    assert 'attendance_status' not in third
    assert client.get('/api/v1/courses/' + old['course_id'], headers=h).json()['course'] == school
    assert free_minutes(client, s['id']) == (10 if occupied else 120)
    latest = client.get('/api/v1/reminders?course_lead_minutes=15', headers=h).json()['reminders']
    assert latest == (reminders if occupied else reminders[1:])
    calendar = client.get(path + '/calendar?from_date=2026-09-02&to_date=2026-09-02', headers=h).json()
    entry = next(e for e in calendar['entries'] if e['id'] == old['id'])
    assert entry['fixed'] is occupied and entry['attendance_status'] == kind
    insight = client.get(path + '/insights?from_date=2026-09-02&to_date=2026-09-02', headers=h).json()
    assert insight['summary']['occupied_union_minutes'] == (110 if occupied else 0)
    assert insight['summary']['fixed_scheduled_minutes'] == (110 if occupied else 0)
    assert insight['records'][0]['attendance_status'] == kind


@pytest.mark.parametrize('kind', ['leave', 'plan_leave', 'attend'])
def test_attendance_group_uses_verified_occurrence_query(client, monkeypatch, kind):
    from app.agent_education import CourseChange, OccurrenceQuery, prepare_course, query_occurrences
    h, s, path, old = setup(client, monkeypatch)
    with Session(client.app.state.engine) as db:
        term = db.get(Semester, s['id']); user = db.get(User, term.user_id)
        state = {'run_id': 'attendance-query-test', 'cards': []}
        result = query_occurrences(db, user, term, state, OccurrenceQuery(
            from_date=date(2026, 9, 1), to_date=date(2026, 10, 2), query=old['title']))
        targets = [e['id'] for e in result['occurrences']]
        assert len(targets) == 3
        preview = prepare_course(db, user, term, state, CourseChange(kind=kind, targets=targets), '这些课次全部调整出席')
        assert len(preview['before']) == 3 and len(preview['after']) == 3
        assert all(e.get('attendance_status') == (None if kind == 'attend' else kind) for e in preview['after'])


def test_attend_and_existing_undo_restore_original_occupancy(client, monkeypatch):
    from test_agent_undo import capture, record, prepare, apply, undo_api
    h, s, path, old = setup(client, monkeypatch)
    monkeypatch.setattr(undo_api(), 'utcnow', lambda: NOW)
    initial = client.get('/api/v1/reminders?course_lead_minutes=15', headers=h).json()['reminders']
    before = capture(client, s['id'])
    change(client, h, path, 'leave', [old['id']])
    rid = record(client, s['id'], before, 'course_change')
    receipt = apply(client, s['id'], prepare(client, s['id'], rid))
    assert receipt['undone'] is True and free_minutes(client, s['id']) == 10
    assert client.get('/api/v1/reminders?course_lead_minutes=15', headers=h).json()['reminders'] == initial
    change(client, h, path, 'plan_leave', [old['id']])
    change(client, h, path, 'leave', [old['id']])
    assert free_minutes(client, s['id']) == 120
    change(client, h, path, 'attend', [old['id']])
    current = client.get(path + '/timetable?week=1', headers=h).json()['events'][0]
    assert 'attendance_status' not in current and 'attendance_reason' not in current
    assert current['fixed'] is True and free_minutes(client, s['id']) == 10
    assert client.get('/api/v1/reminders?course_lead_minutes=15', headers=h).json()['reminders'] == initial


def test_leave_follows_corrected_school_clock_and_survives_reimport(client, monkeypatch):
    h, s, path, old = setup(client, monkeypatch)
    change(client, h, path, 'leave', [old['id']])
    detail = client.get('/api/v1/courses/' + old['course_id'], headers=h).json()
    corrected = {**detail['course'], 'weekday': 4, 'sections': [3], 'location': 'A401',
                 'expected_revision': detail['revision']}
    response = client.patch('/api/v1/courses/' + old['course_id'], headers=h, json=corrected)
    assert response.status_code == 200, response.text
    current = client.get(path + '/timetable?week=1', headers=h).json()['events'][0]
    assert current['attendance_status'] == 'leave' and current['start_at'] == '2026-09-03T10:10:00+08:00'
    assert current['location'] == 'A401' and not current.get('changed')
    payload = imported_payload(s['id'])
    payload['courses'][0] = {**response.json()['course'], 'location': 'C505', 'start_time': '10:20', 'end_time': '11:10'}
    batch = client.post('/api/v1/imports', headers=h, json=payload).json()
    applied = client.post('/api/v1/imports/' + batch['id'] + '/apply', headers=h,
                          json={'expected_revision': batch['base_revision'], 'replace_changed': True})
    assert applied.status_code == 200, applied.text
    current = client.get(path + '/timetable?week=1', headers=h).json()['events'][0]
    assert current['attendance_status'] == 'leave' and current['location'] == 'C505'
    assert current['start_at'] == '2026-09-03T10:20:00+08:00' and not current.get('changed')


def test_leave_on_moved_occurrence_preserves_move_time_place_and_undo(client, monkeypatch):
    from test_agent_undo import capture, record, prepare, apply, undo_api
    h, s, path, old = setup(client, monkeypatch)
    monkeypatch.setattr(undo_api(), 'utcnow', lambda: NOW)
    change(client, h, path, 'move', [old['id']], title=old['title'],
           start_at='2026-09-03T12:00:00+08:00', end_at='2026-09-03T13:00:00+08:00', location='B201')
    before = capture(client, s['id'])
    change(client, h, path, 'leave', [old['id']])
    current = client.get(path + '/timetable?week=1', headers=h).json()['events'][0]
    assert current['start_at'] == '2026-09-03T12:00:00+08:00' and current['location'] == 'B201'
    assert current['attendance_status'] == 'leave' and current['changed'] is True
    rid = record(client, s['id'], before, 'course_change')
    apply(client, s['id'], prepare(client, s['id'], rid))
    restored = client.get(path + '/timetable?week=1', headers=h).json()['events'][0]
    assert restored['start_at'] == current['start_at'] and restored['location'] == 'B201'
    assert 'attendance_status' not in restored and restored['fixed'] is True


@pytest.mark.parametrize('kind', ['leave', 'plan_leave', 'attend'])
def test_attendance_adjustment_requires_actual_targets_and_cannot_change_time(client, monkeypatch, kind):
    h, s, path, old = setup(client, monkeypatch)
    data = {'kind': kind, 'targets': [], 'title': old['title'], 'source_text': '个人出席调整'}
    assert client.post(path + '/changes', headers=h, json=data).status_code == 422
    data.update(targets=[old['id']], start_at='2026-09-03T10:00:00+08:00', end_at='2026-09-03T11:00:00+08:00')
    assert client.post(path + '/changes', headers=h, json=data).status_code == 422
    block = change(client, h, path, 'block', [], title='个人活动',
                   start_at='2026-09-03T10:00:00+08:00', end_at='2026-09-03T11:00:00+08:00')
    data = {'kind': kind, 'targets': [block['patch']['after'][0]['id']], 'title': '个人活动', 'source_text': '个人出席调整'}
    response = client.post(path + '/changes', headers=h, json=data)
    assert response.status_code == 422 and response.json()['code'] == 'COURSE_OCCURRENCE_REQUIRED'


def test_planned_leave_keeps_overlap_and_confirmed_leave_releases_it(client, monkeypatch):
    from app import calendar_events
    h, s, path, old = setup(client, monkeypatch)
    monkeypatch.setattr(calendar_events, 'utcnow', lambda: NOW)
    payload = imported_payload(s['id']); payload['courses'][0]['title'] = '重叠课程'
    payload['courses'][0]['weeks'] = [1]
    batch = client.post('/api/v1/imports', headers=h, json=payload).json()
    response = client.post('/api/v1/imports/' + batch['id'] + '/apply', headers=h,
                           json={'expected_revision': batch['base_revision']})
    assert response.status_code == 200, response.text
    change(client, h, path, 'plan_leave', [old['id']])
    assert all(e['conflict'] for e in client.get(path + '/timetable?week=1', headers=h).json()['events'])
    calendar_url = path + '/calendar?from_date=2026-09-02&to_date=2026-09-02'
    assert len(client.get(calendar_url, headers=h).json()['fixed_conflicts']) == 1
    preview = change(client, h, path, 'leave', [old['id']])
    assert preview['impact']['fixed_conflicts'] == []
    assert all(not e['conflict'] for e in client.get(path + '/timetable?week=1', headers=h).json()['events'])
    assert client.get(calendar_url, headers=h).json()['fixed_conflicts'] == []
    preview = client.post(path + '/changes', headers=h, json={'kind': 'attend', 'targets': [old['id']],
        'title': old['title'], 'source_text': '恢复出席'}).json()
    url = '/api/v1/changes/' + preview['id'] + '/apply'
    body = {'expected_revision': preview['base_revision']}
    blocked = client.post(url, headers=h, json=body)
    assert blocked.status_code == 422 and blocked.json()['code'] == 'CONFIRM_FIXED_CONFLICTS'
    assert client.post(url, headers=h, json={**body, 'confirm_fixed_conflicts': True}).status_code == 200
    assert len(client.get(calendar_url, headers=h).json()['fixed_conflicts']) == 1


def test_restoring_attendance_respects_independent_school_exemption(client, monkeypatch):
    h, s, path, old = setup(client, monkeypatch)
    detail = client.get('/api/v1/courses/' + old['course_id'], headers=h).json()
    response = client.patch('/api/v1/courses/' + old['course_id'], headers=h, json={
        **detail['course'], 'attendance_exempt': True, 'expected_revision': detail['revision']})
    assert response.status_code == 200, response.text
    change(client, h, path, 'leave', [old['id']])
    change(client, h, path, 'attend', [old['id']])
    current = client.get(path + '/timetable?week=1', headers=h).json()['events'][0]
    assert current['attendance_exempt'] is True and current['fixed'] is False
    assert current['attendance_label'] == '免听' and 'attendance_status' not in current
    assert free_minutes(client, s['id']) == 120
    assert client.get('/api/v1/reminders?course_lead_minutes=15', headers=h).json()['reminders'] == []
