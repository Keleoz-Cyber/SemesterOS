"""User-owned schedules are editable; source imports are not authorization."""
import json
from datetime import datetime

import pytest

from test_foundation import client, register, semester, imported_payload
from test_agent import call, thread, turn, run
from test_changes import setup


def decision(client, h, request):
    url = '/api/v1/agent/runs/' + request['id']
    value = client.get(url, headers=h).json()
    assert value['status'] == 'needs_confirmation', value
    saved = client.post(url + '/decision', headers=h,
        json={'decision': 'confirm', 'token': value['preview']['token']})
    assert saved.status_code == 200, saved.text
    return value, saved.json()


def test_range_suspension_uses_all_queried_occurrences_without_per_class_selection(client, monkeypatch):
    h, s, path, old = setup(client, monkeypatch)
    request = turn(client, h, thread(client, h, s['id']), '9月1日至20日全部停课，按我说的更正')
    scope = {'from_date': '2026-09-01', 'to_date': '2026-09-20'}
    def model(messages, tools):
        if messages[-1]['role'] == 'user':
            return call('query_course_occurrences', scope)
        return call('prepare_course_change', {'kind': 'suspend', 'scope': scope, 'title': '范围停课'})
    run(client, model)
    value, _ = decision(client, h, request)
    assert len(value['preview']['before']) == 2
    assert client.get(path + '/timetable?week=1', headers=h).json()['events'] == []
    assert client.get(path + '/timetable?week=3', headers=h).json()['events'] == []
    assert len(client.get(path + '/timetable?week=5', headers=h).json()['events']) == 1


def test_explicit_whole_query_group_is_not_ambiguous(client, monkeypatch):
    h, s, _, old = setup(client, monkeypatch)
    request = turn(client, h, thread(client, h, s['id']), '9月1日至20日概率论都停课')
    def model(messages, tools):
        if messages[-1]['role'] == 'user':
            return call('query_course_occurrences', {'from_date': '2026-09-01', 'to_date': '2026-09-20', 'query': old['title']})
        records = json.loads(messages[-1]['content'])['occurrences']
        return call('prepare_course_change', {'kind': 'suspend', 'targets': [r['id'] for r in records]})
    run(client, model)
    value, _ = decision(client, h, request)
    assert len(value['preview']['before']) == 2


@pytest.mark.parametrize('kind', ['cancel', 'move', 'add'])
def test_past_course_can_be_corrected_and_is_not_official_immutable_history(client, monkeypatch, kind):
    from app import changes
    h, s, path, old = setup(client, monkeypatch)
    monkeypatch.setattr(changes, 'utcnow', lambda: datetime.fromisoformat('2026-10-01T08:00:00+08:00'))
    body = {'kind': kind, 'targets': [] if kind == 'add' else [old['id']],
            'title': old['title'], 'source_text': '更正自己的课表记录'}
    if kind in ('move', 'add'):
        body.update(start_at='2026-09-03T10:00:00+08:00', end_at='2026-09-03T11:00:00+08:00')
    response = client.post(path + '/changes', headers=h, json=body)
    assert response.status_code == 201, response.text
    p = response.json()
    saved = client.post('/api/v1/changes/' + p['id'] + '/apply', headers=h, json={'expected_revision': p['base_revision']})
    assert saved.status_code == 200, saved.text
    rows = client.get(path + '/timetable?week=1', headers=h).json()['events']
    assert len(rows) == {'cancel': 0, 'move': 1, 'add': 2}[kind]


def test_formal_reference_exam_does_not_reserve_time(client):
    _, h = register(client); s = semester(client, h)
    result = client.post('/api/v1/items', headers=h, json={'semester_id': s['id'], 'kind': 'exam',
        'title': '仅供参考的考试', 'certainty': 'formal', 'reserve_time': False,
        'time': {'precision': 'exact', 'at': '2026-10-09T09:00:00+08:00', 'end_at': '2026-10-09T11:00:00+08:00'}})
    assert result.status_code == 201, result.text
    calendar = client.get('/api/v1/semesters/' + s['id'] + '/calendar', headers=h,
        params={'from_date': '2026-10-09', 'to_date': '2026-10-09'}).json()
    assert calendar['entries'][0]['fixed'] is False
    assert calendar['entries'][0]['reserve_time'] is False


def test_absolute_reminder_does_not_need_an_exam_date():
    from app.reminder_rules import evaluate
    value = evaluate({'enabled': True, 'mode': 'absolute', 'purpose': 'item',
        'trigger_at': '2026-10-09T20:00:00+08:00'}, {'kind': 'exam', 'time': {'precision': 'unknown'}},
        'active', datetime.fromisoformat('2026-10-01T08:00:00+08:00'))
    assert value['schedule_state'] == 'scheduled'


def test_explicit_end_of_day_deadline_is_allowed_in_assistant(client):
    _, h = register(client); s = semester(client, h)
    request = turn(client, h, thread(client, h, s['id']), '10月9日当天结束前交报告，当天结束就是截止')
    run(client, lambda m, t: call('prepare_item', {'fields': {'kind': 'assignment', 'title': '报告',
        'time': {'precision': 'date', 'date': '2026-10-09', 'day_end_confirmed': True}}}))
    value, _ = decision(client, h, request)
    assert value['preview']['after']['time']['day_end_confirmed'] is True


def applied_move(client, monkeypatch):
    h, s, path, old = setup(client, monkeypatch)
    p = client.post(path + '/changes', headers=h, json={'kind': 'move', 'targets': [old['id']],
        'title': old['title'], 'source_text': '课程改期', 'start_at': '2026-09-03T10:00:00+08:00',
        'end_at': '2026-09-03T11:00:00+08:00', 'location': 'B201'}).json()
    assert client.post('/api/v1/changes/' + p['id'] + '/apply', headers=h,
        json={'expected_revision': p['base_revision']}).status_code == 200
    return h, s, path, old


def test_base_course_edit_preserves_explicit_change_and_updates_other_weeks(client, monkeypatch):
    h, s, path, old = applied_move(client, monkeypatch)
    detail = client.get('/api/v1/courses/' + old['course_id'], headers=h).json()
    response = client.patch('/api/v1/courses/' + old['course_id'], headers=h,
        json={**detail['course'], 'expected_revision': detail['revision'], 'title': '概率论与数理统计', 'sections': [2, 3]})
    assert response.status_code == 200, response.text
    changed = client.get(path + '/timetable?week=1', headers=h).json()['events']
    assert len(changed) == 1
    assert changed[0]['start_at'] == '2026-09-03T10:00:00+08:00'
    assert changed[0]['title'] == '概率论与数理统计' and changed[0]['location'] == 'B201'
    third = client.get(path + '/timetable?week=3', headers=h).json()['events'][0]
    assert third['start_at'] == '2026-09-16T09:00:00+08:00'


def test_course_delete_after_change_does_not_resurrect_override(client, monkeypatch):
    h, s, path, old = applied_move(client, monkeypatch)
    p = client.get('/api/v1/courses/' + old['course_id'] + '/delete-preview', headers=h).json()
    response = client.delete('/api/v1/courses/' + old['course_id'], headers=h, params={'expected_revision': p['revision']})
    assert response.status_code == 200, response.text
    assert client.get(path + '/timetable?week=1', headers=h).json()['events'] == []
    assert client.get(path + '/timetable?week=3', headers=h).json()['events'] == []
    assert client.get(path + '/changes', headers=h).json()['changes'][0]['phase'] == 'applied'


def test_reimport_after_change_updates_base_course_and_preserves_override(client, monkeypatch):
    h, s, path, old = applied_move(client, monkeypatch)
    body = imported_payload(s['id']); body['courses'][0]['location'] = '新教室'
    p = client.post('/api/v1/imports', headers=h, json=body).json()
    result = client.post('/api/v1/imports/' + p['id'] + '/apply', headers=h,
        json={'expected_revision': p['base_revision'], 'replace_changed': True})
    assert result.status_code == 200, result.text
    first = client.get(path + '/timetable?week=1', headers=h).json()['events'][0]
    third = client.get(path + '/timetable?week=3', headers=h).json()['events'][0]
    assert first['location'] == 'B201' and third['location'] == '新教室'


def test_full_semester_course_query_is_allowed(client, monkeypatch):
    h, s, path, old = setup(client, monkeypatch)
    request = turn(client, h, thread(client, h, s['id']), '查询全学期课次')
    def model(messages, tools):
        if messages[-1]['role'] == 'user':
            return call('query_course_occurrences', {'from_date': '2026-08-31', 'to_date': '2027-01-17'})
        value = json.loads(messages[-1]['content'])
        assert len(value['occurrences']) == 3, value
        return {'content': '本学期有3次课。'}
    run(client, model)
    value = client.get('/api/v1/agent/runs/' + request['id'], headers=h).json()
    assert value['status'] == 'completed' and value['error'] is None, value


def test_unrelated_existing_conflict_does_not_block_a_course_cancellation(client, monkeypatch):
    h, s, path, old = setup(client, monkeypatch)
    for i in range(2):
        rev = client.get('/api/v1/courses/' + old['course_id'], headers=h).json()['revision']
        result = client.post('/api/v1/events', headers=h, json={'semester_id': s['id'],
            'expected_revision': rev, 'title': '已有冲突' + str(i),
            'time': {'precision': 'exact', 'at': '2026-09-05T10:00:00+08:00', 'end_at': '2026-09-05T11:00:00+08:00'}})
        assert result.status_code == 201
    p = client.post(path + '/changes', headers=h, json={'kind': 'cancel', 'targets': [old['id']],
        'title': old['title'], 'source_text': '仅取消这次课'}).json()
    assert p['impact']['new_fixed_conflicts'] == []
    saved = client.post('/api/v1/changes/' + p['id'] + '/apply', headers=h,
        json={'expected_revision': p['base_revision']})
    assert saved.status_code == 200, saved.text


def test_course_cancellation_can_be_undone_after_the_course_date(client, monkeypatch):
    from app import changes, agent_undo
    h, s, path, old = setup(client, monkeypatch)
    request = turn(client, h, thread(client, h, s['id']), '这次停课')
    def model(messages, tools):
        if messages[-1]['role'] == 'user':
            return call('query_course_occurrences', {'from_date': old['start_at'][:10], 'to_date': old['start_at'][:10]})
        return call('prepare_course_change', {'kind': 'cancel', 'targets': [old['id']]})
    run(client, model)
    decision(client, h, request)
    later = lambda: datetime.fromisoformat('2026-10-01T08:00:00+08:00')
    monkeypatch.setattr(changes, 'utcnow', later); monkeypatch.setattr(agent_undo, 'utcnow', later)
    undo = client.post('/api/v1/agent/runs/' + request['id'] + '/request-undo', headers=h,
        json={'request_id': 'undo-later'})
    assert undo.status_code == 201, undo.text
    decision(client, h, undo.json())
    assert client.get(path + '/timetable?week=1', headers=h).json()['events'][0]['id'] == old['id']


def test_natural_date_selection_resolves_a_repeated_meeting_without_a_forced_click(client):
    _, h = register(client); s = semester(client, h)
    ids = []
    for day in (8, 9):
        e = client.post('/api/v1/events', headers=h, json={'semester_id': s['id'],
            'expected_revision': len(ids), 'title': '组会',
            'time': {'precision': 'exact', 'at': f'2026-10-{day:02}T16:00:00+08:00'}}).json()['event']
        ids.append(e['id'])
    tid = thread(client, h, s['id'])
    request = turn(client, h, tid, '改一下组会地点')
    def first(messages, tools):
        if messages[-1]['role'] == 'user': return call('find_records', {'query': '组会'})
        return {'content': '修改10月8日还是9日的组会？'}
    run(client, first)
    follow = turn(client, h, tid, '9日那次，地点改为A301', 'clarified')
    def second(messages, tools):
        if messages[-1]['role'] == 'user': return call('find_records', {'query': '组会', 'on_date': '2026-10-09'})
        return call('prepare_event', {'action': 'update', 'event_id': ids[1], 'fields': {'location': 'A301'}})
    run(client, second)
    value, _ = decision(client, h, follow)
    assert value['preview']['target_id'] == ids[1]


@pytest.mark.parametrize('kind, lifecycle', [('task', 'completed'), ('exam', 'cancelled'), ('exam', 'completed')])
def test_assistant_can_apply_existing_item_state_operations(client, kind, lifecycle):
    _, h = register(client); s = semester(client, h)
    item = client.post('/api/v1/items', headers=h, json={'semester_id': s['id'], 'kind': kind,
        'title': '我的记录', 'certainty': 'formal'}).json()
    request = turn(client, h, thread(client, h, s['id']), '这条已完成' if lifecycle == 'completed' else '取消这场考试')
    def model(messages, tools):
        if messages[-1]['role'] == 'user': return call('find_records', {'query': '我的记录'})
        return call('prepare_item_state', {'item_id': item['id'], 'lifecycle': lifecycle})
    run(client, model)
    value, saved = decision(client, h, request)
    assert saved['receipt']['item']['lifecycle'] == lifecycle
    undo = client.post('/api/v1/agent/runs/' + request['id'] + '/request-undo', headers=h,
        json={'request_id': 'undo-state'})
    assert undo.status_code == 201, undo.text
    decision(client, h, undo.json())
    assert client.get('/api/v1/items/' + item['id'], headers=h).json()['lifecycle'] == 'active'


def test_assistant_can_set_earliest_start_for_a_previously_unconfigured_task(client):
    _, h = register(client); s = semester(client, h)
    item = client.post('/api/v1/items', headers=h, json={'semester_id': s['id'], 'kind': 'task', 'title': '实验报告'}).json()
    request = turn(client, h, thread(client, h, s['id']), '实验报告从现在起可以安排')
    def model(messages, tools):
        if messages[-1]['role'] == 'user': return call('find_records', {'query': '实验报告'})
        return call('prepare_item_change', {'item_id': item['id'], 'fields': {'start_policy': 'now'}})
    run(client, model)
    value, saved = decision(client, h, request)
    assert saved['receipt']['item']['start_policy'] == 'now'


def test_semester_periods_can_be_corrected_without_losing_applied_changes(client, monkeypatch):
    h, s, path, old = applied_move(client, monkeypatch)
    current = client.get('/api/v1/semesters', headers=h).json()[0]
    periods = [{**p, 'start': '08:15'} if p['number'] == 1 else p for p in current['periods']]
    result = client.put(path, headers=h, json={**{k: current[k] for k in ('name', 'first_monday', 'total_weeks')},
        'periods': periods, 'expected_revision': current['revision']})
    assert result.status_code == 200, result.text
    first = client.get(path + '/timetable?week=1', headers=h).json()['events']
    assert len(first) == 1 and first[0]['start_at'] == '2026-09-03T10:00:00+08:00'
    third = client.get(path + '/timetable?week=3', headers=h).json()['events'][0]
    assert third['start_at'] == '2026-09-16T08:15:00+08:00'


def test_first_monday_correction_retains_course_change_on_its_original_week(client, monkeypatch):
    h, s, path, old = applied_move(client, monkeypatch)
    current = client.get('/api/v1/semesters', headers=h).json()[0]
    result = client.put(path, headers=h, json={**{k: current[k] for k in ('name', 'total_weeks', 'periods')},
        'first_monday': '2026-08-24', 'expected_revision': current['revision']})
    assert result.status_code == 200, result.text
    week = client.get(path + '/timetable?week=1', headers=h).json()['events']
    assert week == [], week  # Moved week-1 course remains at its explicit Sept 3 date.
    week2 = client.get(path + '/timetable?week=2', headers=h).json()['events']
    assert len(week2) == 1 and week2[0]['start_at'] == '2026-09-03T10:00:00+08:00'


def test_base_weekday_correction_retains_explicit_time_and_location(client, monkeypatch):
    h, s, path, old = applied_move(client, monkeypatch)
    detail = client.get('/api/v1/courses/' + old['course_id'], headers=h).json()
    result = client.patch('/api/v1/courses/' + old['course_id'], headers=h,
        json={**detail['course'], 'weekday': 4, 'expected_revision': detail['revision']})
    assert result.status_code == 200, result.text
    rows = client.get(path + '/timetable?week=1', headers=h).json()['events']
    assert len(rows) == 1 and rows[0]['start_at'] == '2026-09-03T10:00:00+08:00'
    assert rows[0]['location'] == 'B201'


def test_undone_cancellation_follows_corrected_base_calendar(client, monkeypatch):
    h, s, path, old = setup(client, monkeypatch)
    request = turn(client, h, thread(client, h, s['id']), '本次停课')
    def model(messages, tools):
        if messages[-1]['role'] == 'user': return call('query_course_occurrences',
            {'from_date': old['start_at'][:10], 'to_date': old['start_at'][:10]})
        return call('prepare_course_change', {'kind': 'cancel', 'targets': [old['id']]})
    run(client, model); decision(client, h, request)
    undo = client.post('/api/v1/agent/runs/' + request['id'] + '/request-undo', headers=h,
        json={'request_id': 'undo-before-calendar'})
    assert undo.status_code == 201, undo.text
    decision(client, h, undo.json())
    current = client.get('/api/v1/semesters', headers=h).json()[0]
    result = client.put(path, headers=h, json={**{k: current[k] for k in ('name', 'total_weeks', 'periods')},
        'first_monday': '2026-08-24', 'expected_revision': current['revision']})
    assert result.status_code == 200, result.text
    week = client.get(path + '/timetable?week=1', headers=h).json()['events']
    assert len(week) == 1 and week[0]['start_at'] == '2026-08-26T08:00:00+08:00'


def test_correcting_periods_does_not_require_cancelling_existing_personal_plans(client, monkeypatch):
    from test_schedule_api import setup as scheduled, proposal, accept
    h, s, item = scheduled(client, monkeypatch)
    accept(client, h, proposal(client, h, s, item))
    path = '/api/v1/semesters/' + s['id']
    original = client.get(path + '/plans', headers=h).json()['blocks']
    current = client.get('/api/v1/semesters', headers=h).json()[0]
    periods = [{**p, 'start': '08:15'} if p['number'] == 1 else p for p in current['periods']]
    result = client.put(path, headers=h, json={**{k: current[k] for k in ('name', 'first_monday', 'total_weeks')},
        'periods': periods, 'expected_revision': current['revision']})
    assert result.status_code == 200, result.text
    assert client.get(path + '/plans', headers=h).json()['blocks'] == original


def test_calendar_shift_cannot_swap_two_moved_occurrences_with_same_actual_time(client, monkeypatch):
    h, s, path, old = setup(client, monkeypatch)
    detail = client.get('/api/v1/courses/' + old['course_id'], headers=h).json()
    changed = client.patch('/api/v1/courses/' + old['course_id'], headers=h,
        json={**detail['course'], 'weeks': [1, 2, 3], 'expected_revision': detail['revision']})
    assert changed.status_code == 200
    originals = [client.get(path + f'/timetable?week={week}', headers=h).json()['events'][0] for week in (1, 2)]
    for original, location in zip(originals, ('B', 'C')):
        p = client.post(path + '/changes', headers=h, json={'kind': 'move', 'targets': [original['id']],
            'title': original['title'], 'source_text': '更正课程', 'location': location,
            'start_at': '2026-09-10T10:00:00+08:00', 'end_at': '2026-09-10T11:00:00+08:00'}).json()
        assert client.post('/api/v1/changes/' + p['id'] + '/apply', headers=h,
            json={'expected_revision': p['base_revision'], 'confirm_fixed_conflicts': True}).status_code == 200
    p = client.post(path + '/changes', headers=h, json={'kind': 'cancel', 'targets': [originals[0]['id']],
        'title': old['title'], 'source_text': '取消第一周那次'}).json()
    assert client.post('/api/v1/changes/' + p['id'] + '/apply', headers=h,
        json={'expected_revision': p['base_revision']}).status_code == 200
    current = client.get('/api/v1/semesters', headers=h).json()[0]
    result = client.put(path, headers=h, json={**{k: current[k] for k in ('name', 'total_weeks', 'periods')},
        'first_monday': '2026-08-24', 'expected_revision': current['revision']})
    assert result.status_code == 200, result.text
    rows = client.get(path + '/timetable?week=3', headers=h).json()['events']
    moved = [r for r in rows if r['start_at'] == '2026-09-10T10:00:00+08:00']
    assert len(moved) == 1 and moved[0]['location'] == 'C', rows
    assert any(r['start_at'] == '2026-09-09T08:00:00+08:00' for r in rows)


def test_unchanged_record_preview_is_not_expired_by_an_arbitrary_age(client):
    from app.models import AgentRun
    from app.reminder_rules import utcnow
    from sqlalchemy.orm import Session
    from datetime import timedelta
    _, h = register(client); s = semester(client, h)
    request = turn(client, h, thread(client, h, s['id']), '记一下修改群昵称，无截止时间')
    run(client, lambda m,t: call('prepare_item', {'fields': {'kind': 'task', 'title': '修改群昵称'}}))
    with Session(client.app.state.engine) as db:
        db.get(AgentRun, request['id']).created_at = (utcnow() - timedelta(days=3)).isoformat()
        db.commit()
    value, saved = decision(client, h, request)
    assert saved['receipt']['item']['time']['precision'] == 'unknown'
