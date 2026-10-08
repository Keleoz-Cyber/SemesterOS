"""Only stated time obligations can block a fixed-fact write."""
from copy import deepcopy
from datetime import datetime

import pytest

from app.agent_attendance import conflict_courses
from app.capacity import calendar_context, uncertainty_affects_window, analyze
from app.fixed_conflict_guard import require_fixed_confirmation
from fastapi import HTTPException
from test_foundation import client, register


DAY = '2026-10-09'
CALENDAR = {'first_monday': '2026-08-31', 'total_weeks': 20, 'periods': [
    {'number': 1, 'start': '08:00', 'end': '09:50'},
    {'number': 2, 'start': '10:10', 'end': '11:00'},
    {'number': 3, 'start': '14:00', 'end': '15:00'}]}
COURSES = [{'id': f'course-{n}', 'title': f'课程{n}', 'weekday': 5,
            'weeks': [6], 'sections': [n]} for n in (1, 2, 3)]
PREFERENCES = {'configured': True, 'weekly': [
    {'weekday': 5, 'start': '08:00', 'end': '18:00'}], 'exclusions': []}
NOW = datetime.fromisoformat('2026-10-08T20:00:00+08:00')


def at(value):
    return f'{DAY}T{value}:00+08:00'


def event(eid='meeting', **patch):
    return {'id': eid, 'title': '九点会议', 'certainty': 'formal', 'reserve_time': True,
            'time': {'precision': 'exact', 'at': at('09:00')}, **patch}


def context(events, courses=COURSES):
    return calendar_context({**CALENDAR, 'fixed_events': events}, PREFERENCES, courses, [], NOW)


def test_start_only_blocks_actual_start_course_but_not_later_courses():
    value = event()
    unchanged = deepcopy(value)
    result = context([value])
    assert len(result['conflicts']) == 1
    assert result['conflicts'][0]['blocking'] is True
    assert result['conflicts'][0]['evidence_kind'] == 'start_point'
    assert result['conflicts'][0]['start_at'] == result['conflicts'][0]['end_at']
    assert [c['title'] for c in conflict_courses(CALENDAR, COURSES, result['conflicts'])] == ['课程1']
    assert result['time_warnings']
    assert all(w['blocking'] is False for w in result['time_warnings'])
    assert value == unchanged and 'end_at' not in value['time']


def test_stated_start_and_arrival_conflicts_are_confirmed_facts_for_risk_counts():
    for value in (event(), event(time={'precision':'exact','at':at('10:00')},
                                 details={'early_arrival_minutes':30})):
        result = analyze({**CALENDAR,'fixed_events':[value]},PREFERENCES,COURSES,[],NOW)
        assert result['summary']['level'] == 'high'
        assert result['summary']['fixed_conflict_count'] == 1
        assert result['summary']['possible_fixed_conflict_count'] == 0
        conflict = result['fixed_conflicts'][0]
        assert conflict['certainty'] == 'confirmed' and conflict['time_incomplete']
        assert value['time'].get('end_at') is None
        assert all(w['certainty']=='possible' and w['blocking'] is False for w in result['time_warnings'])


def test_task_risk_includes_confirmed_point_equal_to_release_boundary():
    item = {'id':'task','kind':'task','title':'课后任务','lifecycle':'active','certainty':'formal',
            'time':{'precision':'exact','at':at('18:00')},'remaining_minutes':30,
            'splittable':True,'start_policy':'at','earliest_start_at':at('09:00')}
    result = analyze({**CALENDAR,'fixed_events':[event()]},PREFERENCES,COURSES,[item],NOW)
    assert result['items'][0]['level'] == 'high'
    assert 'fixed_conflict' in result['items'][0]['reason_codes']


def test_start_only_has_no_inferred_duration_or_remainder_of_day_exclusion():
    result = context([event()], courses=[])
    assert result['conflicts'] == []
    assert result['free'].minutes(datetime.fromisoformat(at('09:00')).timestamp(),
                                  datetime.fromisoformat(at('18:00')).timestamp()) == 540
    warning = result['uncertainty_warnings'][0]
    assert warning['end_at'] is None
    assert warning['exclusion_applied'] is False
    assert warning['comparison_end_at']


@pytest.mark.parametrize('time', [
    {'precision': 'unknown'}, {'precision': 'date', 'date': DAY},
    {'precision': 'week', 'week': 6},
    {'precision': 'range', 'date': DAY, 'end_date': DAY}])
def test_incomplete_dates_are_warnings_and_can_be_saved_without_confirmation(time):
    result = context([event(time=time)])
    assert result['conflicts'] == []
    assert result['time_warnings']
    assert conflict_courses(CALENDAR, COURSES, result['time_warnings']) == []
    require_fixed_confirmation({'new_fixed_conflicts': [], 'time_warnings': result['time_warnings']}, False)
    assert result['free'].spans == result['known_free'].spans


def test_point_at_course_end_is_not_overlap_and_point_at_start_is():
    assert context([event(time={'precision': 'exact', 'at': at('09:50')})])['conflicts'] == []
    assert len(context([event(time={'precision': 'exact', 'at': at('10:10')})])['conflicts']) == 1


def test_explicit_early_arrival_remains_a_protected_interval():
    result = context([event(time={'precision': 'exact', 'at': at('10:00')},
                            details={'early_arrival_minutes': 30})])
    assert len(result['conflicts']) == 1
    conflict = result['conflicts'][0]
    assert conflict['blocking'] is True
    assert conflict['evidence_kind'] == 'arrival_interval'
    assert conflict['overlap_at_arrival'] is True and conflict['overlap_at_start'] is False
    assert result['free'].minutes(datetime.fromisoformat(at('09:50')).timestamp(),
                                  datetime.fromisoformat(at('10:10')).timestamp()) == 10
    with pytest.raises(HTTPException):
        require_fixed_confirmation({'new_fixed_conflicts': result['conflicts']}, False)


def test_two_start_only_records_at_different_times_do_not_require_resolution():
    result = context([event(), event('second', time={'precision': 'exact', 'at': at('11:00')})], [])
    assert result['conflicts'] == [] and result['time_warnings']
    same_point = context([event(), event('second')], [])
    assert len(same_point['conflicts']) == 1
    assert same_point['conflicts'][0]['evidence_kind'] == 'start_point'


def test_complete_all_day_interval_is_blocking_but_date_or_window_is_not():
    result = context([event(time={'precision': 'exact', 'at': at('00:00'),
                                  'end_at': '2026-10-10T00:00:00+08:00'})])
    assert len(result['conflicts']) == 3
    assert all(c['certainty'] == 'confirmed' for c in result['conflicts'])
    assert context([event(time={'precision': 'date', 'date': DAY})])['conflicts'] == []
    assert context([event(time={'precision': 'exact', 'at': at('08:00'),
                               'end_at': at('18:00'), 'meaning': 'window'})])['conflicts'] == []


def test_unknown_end_warning_uses_finite_comparison_window_without_claiming_record_end():
    warning = context([event()], [])['uncertainty_warnings'][0]
    assert uncertainty_affects_window(warning, datetime.fromisoformat(at('14:00')).timestamp(),
                                     datetime.fromisoformat(at('15:00')).timestamp())
    assert not uncertainty_affects_window(warning,
        datetime.fromisoformat('2026-10-10T14:00:00+08:00').timestamp(),
        datetime.fromisoformat('2026-10-10T15:00:00+08:00').timestamp())


def test_warning_rows_cannot_be_reused_as_leave_targets_or_blocking_guards():
    result = context([event(time={'precision': 'exact', 'at': at('07:30')})])
    assert result['conflicts'] == []
    assert conflict_courses(CALENDAR, COURSES, result['time_warnings']) == []
    require_fixed_confirmation({'new_fixed_conflicts': result['time_warnings']}, False)


def setup_api(client,monkeypatch):
    from app import calendar_events, reminder_rules
    monkeypatch.setattr(calendar_events,'utcnow',lambda:NOW)
    monkeypatch.setattr(reminder_rules,'utcnow',lambda:NOW)
    _,headers = register(client)
    response = client.post('/api/v1/semesters',headers=headers,json={
        'name':'时间事实边界测试',**CALENDAR})
    assert response.status_code == 201,response.text
    term = response.json()
    imported = client.post('/api/v1/imports',headers=headers,json={
        'semester_id':term['id'],'source':'manual',
        'courses':[{k:v for k,v in c.items() if k!='id'} for c in COURSES]}).json()
    applied = client.post(f'/api/v1/imports/{imported["id"]}/apply',headers=headers,
                          json={'expected_revision':0})
    assert applied.status_code == 200,applied.text
    return headers,term['id']


def api_record(sid,time):
    return {'semester_id':sid,'expected_revision':1,'title':'九点会议',
            'certainty':'formal','reserve_time':True,'time':time}


@pytest.mark.parametrize('time', [
    {'precision':'exact','at':at('07:30')}, {'precision':'unknown'},
    {'precision':'date','date':DAY}, {'precision':'week','week':6},
    {'precision':'range','date':DAY,'end_date':DAY}])
def test_manual_api_can_preview_and_save_warning_only_without_a_conflict_choice(client,monkeypatch,time):
    headers,sid = setup_api(client,monkeypatch)
    body = api_record(sid,time)
    preview = client.post('/api/v1/events/conflict-preview',headers=headers,json=body)
    assert preview.status_code == 200,preview.text
    impact = preview.json()['impact']
    assert impact['new_fixed_conflicts'] == impact['new_blocking_fixed_conflicts'] == []
    assert impact['course_conflicts'] == [] and impact['new_time_warnings']
    saved = client.post('/api/v1/events',headers=headers,json=body)
    assert saved.status_code == 201,saved.text
    assert saved.json()['event']['time']['end_at'] is None


def test_manual_api_start_only_leave_targets_exclude_ten_ten_and_fourteen_courses(client,monkeypatch):
    headers,sid = setup_api(client,monkeypatch)
    body = api_record(sid,{'precision':'exact','at':at('09:00')})
    preview = client.post('/api/v1/events/conflict-preview',headers=headers,json=body)
    assert preview.status_code == 200,preview.text
    impact = preview.json()['impact']
    assert [c['title'] for c in impact['course_conflicts']] == ['课程1']
    assert len(impact['new_blocking_fixed_conflicts']) == 1 and impact['new_time_warnings']
    entries = client.get(f'/api/v1/semesters/{sid}/timetable?week=6',headers=headers).json()['events']
    later = next(c['id'] for c in entries if c['title']=='课程2')
    rejected = client.post('/api/v1/events',headers=headers,json={**body,'course_leave_targets':[later]})
    assert rejected.status_code == 422
    assert client.post('/api/v1/events',headers=headers,json=body).status_code == 422
    target = impact['course_conflicts'][0]['occurrence_id']
    saved = client.post('/api/v1/events',headers=headers,json={**body,'course_leave_targets':[target]})
    assert saved.status_code == 201,saved.text
    assert saved.json()['event']['time']['end_at'] is None
    entries = client.get(f'/api/v1/semesters/{sid}/timetable?week=6',headers=headers).json()['events']
    assert next(c for c in entries if c['id']==target)['attendance_status'] == 'leave'
    assert all(c.get('attendance_status')!='leave' for c in entries if c['title'] in ('课程2','课程3'))
