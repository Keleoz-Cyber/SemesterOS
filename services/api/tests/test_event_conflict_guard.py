from copy import deepcopy
from datetime import datetime

import pytest

from app.capacity import calendar_context, analyze
from app.conflict_changes import introduced_conflicts
from test_foundation import client, register, semester


DAY = '2026-10-09'
CALENDAR = {'first_monday': '2026-08-31', 'total_weeks': 20, 'periods': [
    {'number': 1, 'start': '08:00', 'end': '08:50'},
    {'number': 2, 'start': '09:00', 'end': '09:50'},
    {'number': 3, 'start': '10:10', 'end': '11:00'}]}
COURSE = {'id': 'course', 'title': '软件工程', 'weekday': 5, 'weeks': [6], 'sections': [1, 2]}
PREFERENCES = {'configured': True, 'weekly': [{'weekday': 5, 'start': '08:00', 'end': '12:00'}], 'exclusions': []}
NOW = datetime.fromisoformat('2026-10-08T20:00:00+08:00')


def clock(value):
    return DAY + 'T' + value + ':00+08:00'


def event(eid='meeting', **patch):
    return {'id': eid, 'title': '班主任会议', 'certainty': 'formal', 'reserve_time': True,
            'time': {'precision': 'exact', 'at': clock('09:00')}, **patch}


def context(events, courses=(COURSE,), exams=()):
    return calendar_context({**CALENDAR, 'fixed_events': events}, PREFERENCES,
                            list(courses), list(exams), NOW)


@pytest.mark.parametrize('time', [
    {'precision': 'exact', 'at': clock('09:00')},
    {'precision': 'exact', 'at': clock('07:30')},
    {'precision': 'date', 'date': DAY},
    {'precision': 'week', 'week': 6},
    {'precision': 'range', 'date': '2026-10-08', 'end_date': DAY},
])
def test_incomplete_event_prompts_possible_course_conflict_without_inventing_end(time):
    entry = event(time=time)
    before = deepcopy(entry)
    conflicts = context([entry])['conflicts']
    assert len(conflicts) == 1
    conflict = conflicts[0]
    assert conflict['certainty'] == 'possible'
    assert conflict['time_incomplete'] is True
    assert conflict['uncertain_item_ids'] == ['event:meeting']
    assert '软件工程' in conflict['titles']
    assert entry == before and 'end_at' not in entry['time']


def test_unknown_start_after_course_and_unknown_dates_do_not_claim_course_overlap():
    assert context([event(time={'precision': 'exact', 'at': clock('09:50')})])['conflicts'] == []
    assert context([event(time={'precision': 'unknown'})])['conflicts'] == []


def test_early_arrival_is_checked_before_stated_start_even_with_unknown_end():
    conflicts = context([event(time={'precision': 'exact', 'at': clock('10:00')},
                               details={'early_arrival_minutes': 30})])['conflicts']
    assert len(conflicts) == 1 and conflicts[0]['certainty'] == 'possible'
    assert datetime.fromisoformat(conflicts[0]['start_at']) == datetime.fromisoformat(clock('09:30'))


def test_two_incomplete_events_same_known_day_require_review():
    conflicts = context([event(), event('second', title='实验室会议',
        time={'precision': 'exact', 'at': clock('11:00')})], courses=[])['conflicts']
    assert len(conflicts) == 1 and conflicts[0]['certainty'] == 'possible'
    assert set(conflicts[0]['uncertain_item_ids']) == {'event:meeting', 'event:second'}


@pytest.mark.parametrize('course_patch', [{'attendance_status': 'leave'}, {'attendance_exempt': True}])
def test_personal_leave_and_exemption_still_remove_course_occupancy(course_patch):
    assert context([event()], courses=[{**COURSE, **course_patch}])['conflicts'] == []


def test_planned_leave_still_requires_review_and_reference_event_does_not():
    assert context([event()], courses=[{**COURSE, 'attendance_status': 'plan_leave'}])['conflicts']
    assert context([event(reserve_time=False)])['conflicts'] == []


def test_incomplete_exam_uses_same_possible_conflict_path():
    exam = {**event('exam'), 'kind': 'exam', 'lifecycle': 'active', 'title': '考试'}
    conflict = context([], exams=[exam])['conflicts'][0]
    assert conflict['certainty'] == 'possible' and conflict['uncertain_item_ids'] == ['exam']


def test_possible_overlap_is_not_reported_as_proven_high_risk():
    result = analyze({**CALENDAR, 'fixed_events': [event()]}, PREFERENCES, [COURSE], [], NOW)
    assert result['summary']['level'] == 'medium'
    assert result['summary']['possible_fixed_conflict_count'] == 1
    definite = context([event(time={'precision': 'exact', 'at': clock('09:00'), 'end_at': clock('09:30')})])['conflicts']
    assert len(definite) == 1 and definite[0]['certainty'] == 'confirmed'
    possible = context([event()])['conflicts']
    assert introduced_conflicts(possible, definite) == definite
    assert introduced_conflicts(possible, deepcopy(possible)) == []


def api_setup(c, monkeypatch):
    from app import calendar_events, reminder_rules
    monkeypatch.setattr(calendar_events, 'utcnow', lambda: NOW)
    monkeypatch.setattr(reminder_rules, 'utcnow', lambda: NOW)
    _, headers = register(c)
    term = semester(c, headers)
    imported = c.post('/api/v1/imports', headers=headers, json={
        'semester_id': term['id'], 'source': 'manual', 'courses': [
            {key: value for key, value in COURSE.items() if key != 'id'}]}).json()
    applied = c.post('/api/v1/imports/' + imported['id'] + '/apply', headers=headers,
                     json={'expected_revision': 0})
    assert applied.status_code == 200, applied.text
    return headers, term['id']


def api_body(sid, rev, **patch):
    entry = event(**patch)
    return {key: value for key, value in {**entry, 'semester_id': sid,
        'expected_revision': rev, 'tags': ['冲突测试']}.items() if key != 'id'}


def test_raw_create_conflict_is_blocked_before_save_and_explicit_choice_is_idempotent(client, monkeypatch):
    headers, sid = api_setup(client, monkeypatch)
    body = api_body(sid, 1)
    blocked = client.post('/api/v1/events', headers=headers, json=body)
    assert blocked.status_code == 422 and blocked.json()['code'] == 'CONFIRM_FIXED_CONFLICTS'
    assert blocked.json()['new_fixed_conflicts'][0]['certainty'] == 'possible'
    assert not client.get('/api/v1/taxonomy', headers=headers).json()['tags']
    url = f'/api/v1/semesters/{sid}/calendar?from_date={DAY}&to_date={DAY}'
    assert not any(e['resource_type'] == 'event' for e in client.get(url, headers=headers).json()['entries'])
    term = next(s for s in client.get('/api/v1/semesters', headers=headers).json() if s['id'] == sid)
    assert term['revision'] == 1
    confirmed = {**body, 'confirm_fixed_conflicts': True}
    request_headers = {**headers, 'Idempotency-Key': 'chosen-overlap'}
    saved = client.post('/api/v1/events', headers=request_headers, json=confirmed)
    assert saved.status_code == 201, saved.text
    assert saved.json()['event']['time']['end_at'] is None
    assert 'confirm_fixed_conflicts' not in saved.json()['event']
    assert client.post('/api/v1/events', headers=request_headers, json=confirmed).json() == saved.json()


def test_raw_edit_to_conflict_requires_choice_but_metadata_edit_does_not(client, monkeypatch):
    headers, sid = api_setup(client, monkeypatch)
    first = client.post('/api/v1/events', headers=headers,
        json=api_body(sid, 1, time={'precision': 'exact', 'at': clock('12:00'), 'end_at': clock('13:00')}))
    assert first.status_code == 201, first.text
    saved = first.json()
    path = '/api/v1/events/' + saved['event']['id']
    body = {**api_body(sid, saved['revision']), 'expected_version': 1}
    blocked = client.patch(path, headers=headers, json=body)
    assert blocked.status_code == 422 and blocked.json()['code'] == 'CONFIRM_FIXED_CONFLICTS'
    assert client.get(path, headers=headers).json()['time']['at'] == saved['event']['time']['at']
    chosen = client.patch(path, headers=headers, json={**body, 'confirm_fixed_conflicts': True})
    assert chosen.status_code == 200, chosen.text
    edited = client.patch(path, headers=headers, json={**body, 'expected_version': 2,
        'expected_revision': chosen.json()['revision'], 'title': '会议改名'})
    assert edited.status_code == 200, edited.text


def test_conflict_preview_is_read_only_and_identifies_real_course_targets(client, monkeypatch):
    headers, sid = api_setup(client, monkeypatch)
    body = api_body(sid, 1)
    response = client.post('/api/v1/events/conflict-preview', headers=headers, json=body)
    assert response.status_code == 200, response.text
    impact = response.json()['impact']
    assert len(impact['new_fixed_conflicts']) == len(impact['course_conflicts']) == 1
    conflict = impact['new_fixed_conflicts'][0]
    assert conflict['certainty'] == 'possible' and conflict['overlap_at_start'] is True
    assert datetime.fromisoformat(conflict['event_start_at']) == datetime.fromisoformat(clock('09:00'))
    target = impact['course_conflicts'][0]['occurrence_id']
    assert conflict['item_ids'] == [target]
    assert conflict['pending_record'] is True
    assert not client.get('/api/v1/taxonomy', headers=headers).json()['tags']
    assert next(s for s in client.get('/api/v1/semesters', headers=headers).json() if s['id'] == sid)['revision'] == 1


def test_manual_event_with_explicit_course_leave_is_atomic_and_replayable(client, monkeypatch):
    headers, sid = api_setup(client, monkeypatch)
    body = api_body(sid, 1)
    preview = client.post('/api/v1/events/conflict-preview', headers=headers, json=body)
    assert preview.status_code == 200, preview.text
    target = preview.json()['impact']['course_conflicts'][0]['occurrence_id']
    invalid = client.post('/api/v1/events', headers=headers, json={**body, 'course_leave_targets': ['another-user-course']})
    assert invalid.status_code == 422
    chosen = {**body, 'course_leave_targets': [target]}
    h = {**headers, 'Idempotency-Key': 'leave-and-event'}
    saved = client.post('/api/v1/events', headers=h, json=chosen)
    assert saved.status_code == 201, saved.text
    assert saved.json()['event']['time']['end_at'] is None
    assert saved.json()['course_attendance'][0]['attendance_status'] == 'leave'
    assert client.post('/api/v1/events', headers=h, json=chosen).json() == saved.json()
    table = client.get(f'/api/v1/semesters/{sid}/timetable?week=6', headers=headers).json()['events']
    assert next(c for c in table if c['id'] == target)['attendance_status'] == 'leave'
    other = client.get(f'/api/v1/semesters/{sid}/timetable?week=5', headers=headers).json()['events']
    assert not any(c.get('attendance_status') == 'leave' for c in other)


def test_preview_guards_owner_semester_and_revision_before_returning_targets(client, monkeypatch):
    headers, sid = api_setup(client, monkeypatch)
    response = client.post('/api/v1/events/conflict-preview', headers=headers,
                           json=api_body(sid, 0))
    assert response.status_code == 409
    saved = client.post('/api/v1/events', headers=headers,
        json=api_body(sid, 1, time={'precision': 'exact', 'at': clock('12:00'), 'end_at': clock('13:00')})).json()
    _, other = register(client, 'other_student')
    other_term = semester(client, other)
    foreign = {**api_body(other_term['id'], 0), 'event_id': saved['event']['id'], 'expected_version': 1}
    assert client.post('/api/v1/events/conflict-preview', headers=other, json=foreign).status_code == 404
    own_other_term = semester(client, headers)
    misplaced = {**api_body(own_other_term['id'], 0), 'event_id': saved['event']['id'], 'expected_version': 1}
    assert client.post('/api/v1/events/conflict-preview', headers=headers, json=misplaced).status_code == 404
    stale = {**api_body(sid, saved['revision']), 'event_id': saved['event']['id'], 'expected_version': 2}
    assert client.post('/api/v1/events/conflict-preview', headers=headers, json=stale).status_code == 409


def test_atomic_manual_edit_preserves_omitted_metadata_and_failed_choice_rolls_back(client, monkeypatch):
    headers, sid = api_setup(client, monkeypatch)
    first_body = api_body(sid, 1, time={'precision': 'exact', 'at': clock('12:00'), 'end_at': clock('13:00')},
                          category_id='research', details={'materials': ['原始资料']}, reserve_time=True,
                          source_text='原始会议通知')
    first = client.post('/api/v1/events', headers=headers, json=first_body).json()
    eid = first['event']['id']
    body = {key: value for key, value in api_body(sid, first['revision']).items()
            if key not in ('tags', 'reserve_time')}
    body.update(expected_version=1, time={'precision': 'exact', 'at': clock('09:00')})
    preview = client.post('/api/v1/events/conflict-preview', headers=headers,
                          json={**body, 'event_id': eid}).json()['impact']
    target = preview['course_conflicts'][0]['occurrence_id']
    path = '/api/v1/events/' + eid
    failed = client.patch(path, headers=headers,
                          json={**body, 'course_leave_targets': [target, 'not-an-owned-occurrence']})
    assert failed.status_code == 422
    untouched = client.get(path, headers=headers).json()
    assert untouched['version'] == 1 and untouched['time'] == first['event']['time']
    timetable = client.get(f'/api/v1/semesters/{sid}/timetable?week=6', headers=headers).json()['events']
    assert next(c for c in timetable if c['id'] == target).get('attendance_status') != 'leave'
    saved = client.patch(path, headers=headers, json={**body, 'course_leave_targets': [target]})
    assert saved.status_code == 200, saved.text
    after = saved.json()['event']
    for field in ('category_id', 'details', 'reserve_time', 'tags', 'source_text'):
        assert after[field] == first['event'][field], field


def test_day_brief_does_not_describe_possible_conflict_as_proven_overlap(client, monkeypatch):
    from app import briefs
    headers, sid = api_setup(client, monkeypatch)
    monkeypatch.setattr(briefs, 'utcnow', lambda: NOW)
    saved = client.post('/api/v1/events', headers=headers,
        json={**api_body(sid, 1), 'confirm_fixed_conflicts': True})
    assert saved.status_code == 201, saved.text
    response = client.get(f'/api/v1/semesters/{sid}/day-brief?day={DAY}', headers=headers)
    assert response.status_code == 200, response.text
    suggestion = next(s for s in response.json()['suggestions'] if s['kind'] == 'fixed_conflict')
    assert suggestion['title'] == '有安排时间待核对'
    assert '可能重叠' in suggestion['detail'] and '班主任会议' in suggestion['detail']
