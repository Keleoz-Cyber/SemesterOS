"""HLJU facts stay distinct, owned, reviewable and stable on reimport."""
from copy import deepcopy
from datetime import datetime
from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import MetaData, create_engine, inspect, text

from test_foundation import client, register, semester, imported_payload


def school_payload(sid):
    return {'semester_id': sid, 'source': 'hlju_webview', 'source_term': '2026-2027-1',
        'source_first_monday': '2026-08-24',
        'courses': [
            {'title': '数学', 'source_id': 'hlju:math', 'weekday': 1, 'weeks': [1, 2],
             'sections': [11, 12], 'start_time': '19:30', 'end_time': '21:10'},
            {'title': '免听课程', 'source_id': 'hlju:exempt', 'weekday': 1, 'weeks': [1, 2],
             'sections': [11, 12], 'start_time': '19:30', 'end_time': '21:10', 'attendance_exempt': True}],
        'extras': [
            {'kind': 'exam', 'source_id': 'hlju:exam:math', 'title': '数学考试', 'location': '主楼201',
             'start_at': '2026-12-21T08:30:00+08:00', 'end_at': '2026-12-21T10:30:00+08:00',
             'raw_text': '数学考试 12月21日08:30-10:30 主楼201'},
            {'kind': 'unplaced_course', 'source_id': 'hlju:practice', 'title': '课程设计',
             'teacher': '教师甲', 'weeks': list(range(1, 17)), 'raw_text': '课程设计 第1-16周'}]}


def preview(client, h, body):
    response = client.post('/api/v1/imports', headers=h, json=body)
    assert response.status_code == 201, response.text
    return response.json()


def apply(client, h, batch, **extra):
    response = client.post('/api/v1/imports/' + batch['id'] + '/apply', headers=h,
        json={'expected_revision': batch['base_revision'], **extra})
    assert response.status_code == 200, response.text
    return response.json()


def calendar(client, h, sid):
    return client.get(f'/api/v1/semesters/{sid}/calendar?from_date=2026-08-31&to_date=2026-12-31', headers=h).json()


def test_school_times_exemption_exam_and_unplaced_course_use_one_review(client):
    _, h = register(client)
    s = semester(client, h)
    batch = preview(client, h, school_payload(s['id']))
    assert batch['new_count'] == 2 and batch['new_extra_count'] == 2
    assert batch['source_first_monday'] == '2026-08-24'
    assert client.get(f"/api/v1/semesters/{s['id']}/items", headers=h).json()['items'] == []
    receipt = apply(client, h, batch)
    assert receipt['imported_count'] == receipt['imported_extra_count'] == 2
    assert receipt['revision'] == 1
    events = client.get(f"/api/v1/semesters/{s['id']}/timetable?week=1", headers=h).json()['events']
    assert len(events) == 2 and all(not e['conflict'] for e in events)
    assert all(e['start_at'] == '2026-08-31T19:30:00+08:00' and e['end_at'] == '2026-08-31T21:10:00+08:00' for e in events)
    from app.capacity import course_intervals
    assert len(course_intervals({'periods': s['periods'], 'first_monday': s['first_monday']}, [{'occurrences': events}])) == 1
    reminders = client.get('/api/v1/reminders?course_lead_minutes=15', headers=h).json()['reminders']
    assert len(reminders) == 2 and {r['title'] for r in reminders} == {'数学'}
    facts = calendar(client, h, s['id'])
    assert len([e for e in facts['entries'] if e['resource_type'] == 'exam']) == 1
    practice = next(e for e in facts['undated'] if e['title'] == '课程设计')
    assert practice['start_at'] is None and practice['end_at'] is None and practice['reserve_time'] is False
    saved = client.get('/api/v1/events/' + practice['resource_id'], headers=h).json()
    assert saved['time']['precision'] == 'unknown' and '16' in saved['notes']
    assert {t['name'] for t in saved['tags']} == {'课程', '实践课'}
    assert client.get('/api/v1/semesters', headers=h).json()[0]['first_monday'] == s['first_monday']
    stats = client.get(f"/api/v1/semesters/{s['id']}/insights?from_date=2026-08-31&to_date=2026-08-31", headers=h).json()
    assert stats['summary']['occupied_union_minutes'] == 100


def test_reimport_is_idempotent_and_changed_extra_requires_review(client):
    _, h = register(client)
    s = semester(client, h)
    body = school_payload(s['id'])
    first = preview(client, h, body)
    apply(client, h, first)
    original = client.get(f"/api/v1/semesters/{s['id']}/items", headers=h).json()['items'][0]
    again = preview(client, h, body)
    assert again['new_count'] == again['new_extra_count'] == again['changed_count'] == 0
    assert again['unchanged_count'] == again['unchanged_extra_count'] == 2
    assert apply(client, h, again)['revision'] == 1
    changed = deepcopy(body)
    changed['extras'][0]['start_at'] = '2026-12-22T08:30:00+08:00'
    changed['extras'][0]['end_at'] = '2026-12-22T10:30:00+08:00'
    batch = preview(client, h, changed)
    assert batch['changed_count'] == len(batch['changed_extras']) == 1
    denied = client.post('/api/v1/imports/' + batch['id'] + '/apply', headers=h, json={'expected_revision': 1})
    assert denied.status_code == 409 and denied.json()['code'] == 'CHANGE_REQUIRES_REVIEW'
    assert apply(client, h, batch, replace_changed=True)['replaced_extra_count'] == 1
    latest = client.get(f"/api/v1/semesters/{s['id']}/items", headers=h).json()['items']
    assert len(latest) == 1 and latest[0]['id'] == original['id'] and latest[0]['version'] == 2
    assert latest[0]['time']['at'] == '2026-12-22T00:30:00Z'


def test_personal_extra_edits_and_cancellations_are_retained_on_reimport(client):
    _, h = register(client)
    s = semester(client, h)
    body = school_payload(s['id'])
    apply(client, h, preview(client, h, body))
    exam = client.get(f"/api/v1/semesters/{s['id']}/items", headers=h).json()['items'][0]
    edit = client.patch('/api/v1/items/' + exam['id'], headers=h, json={
        'semester_id': s['id'], 'kind': 'exam', 'title': '本人备注过的考试', 'time': exam['time'],
        'certainty': 'formal', 'expected_version': 1, 'change_reason': '核对考试名称'})
    assert edit.status_code == 200, edit.text
    practice = next(e for e in calendar(client, h, s['id'])['undated'] if e['title'] == '课程设计')
    cancel = client.post('/api/v1/events/' + practice['resource_id'] + '/cancel', headers=h,
        json={'expected_version': 1, 'expected_revision': 2})
    assert cancel.status_code == 200, cancel.text
    body['extras'][0]['title'] = '学校更新后的考试'
    body['extras'][1]['weeks'] = [1, 2]
    batch = preview(client, h, body)
    assert batch['protected_extra_count'] == 2 and batch['new_extra_count'] == 0
    apply(client, h, batch, replace_changed=True)
    assert client.get('/api/v1/items/' + exam['id'], headers=h).json()['title'] == '本人备注过的考试'
    assert client.get('/api/v1/events/' + practice['resource_id'], headers=h).json()['lifecycle'] == 'cancelled'


def test_same_course_multi_meeting_matches_slot_and_missing_scope_is_school_and_term(client):
    _, h = register(client)
    s = semester(client, h)
    haut = imported_payload(s['id'])
    haut.update(source='haut_webview', source_term='2026-2027-1')
    apply(client, h, preview(client, h, haut))
    body = school_payload(s['id'])
    body['extras'] = []
    body['courses'] = [body['courses'][0], {**body['courses'][0], 'weekday': 3}]
    apply(client, h, preview(client, h, body))
    body['courses'][0]['weeks'] = [1, 2, 3]
    batch = preview(client, h, body)
    assert batch['changed_count'] == 1 and batch['missing_count'] == 0
    assert batch['changed_courses'][0]['before']['weekday'] == 1
    apply(client, h, batch, replace_changed=True)
    body['courses'] = [body['courses'][0]]
    batch = preview(client, h, body)
    assert batch['missing_count'] == 1 and batch['missing_courses'][0]['before']['weekday'] == 3
    apply(client, h, batch, remove_missing=True)
    courses = client.get(f"/api/v1/semesters/{s['id']}/courses", headers=h).json()
    assert len(courses) == 2 and {c['title'] for c in courses} == {'数学', '概率论'}
    other_term = deepcopy(body)
    other_term['source_term'] = '2025-2026-2'
    assert preview(client, h, other_term)['missing_count'] == 0


def test_school_clock_and_extras_validation_and_legacy_edit_preserves_source_fields(client):
    _, h = register(client)
    s = semester(client, h)
    body = school_payload(s['id'])
    apply(client, h, preview(client, h, body))
    rows = client.get(f"/api/v1/semesters/{s['id']}/courses", headers=h).json()
    course = client.get('/api/v1/courses/' + next(c['id'] for c in rows if c['title'] == '免听课程'), headers=h).json()
    edit = {k: v for k, v in course['course'].items() if k not in ('start_time', 'end_time', 'attendance_exempt')}
    edit.update(location='新教室', expected_revision=1)
    response = client.patch('/api/v1/courses/' + course['id'], headers=h, json=edit)
    assert response.status_code == 200, response.text
    assert response.json()['course']['attendance_exempt'] is True
    assert response.json()['course']['start_time'] == '19:30'
    bad = deepcopy(body); bad['courses'][0].pop('end_time')
    assert client.post('/api/v1/imports', headers=h, json=bad).status_code == 422
    bad = deepcopy(body); bad['extras'][1]['start_at'] = '2026-09-01T08:00:00+08:00'
    assert client.post('/api/v1/imports', headers=h, json=bad).status_code == 422
    bad = deepcopy(body); bad['extras'][0]['start_at'] = '2026-12-21T08:30:00'
    assert client.post('/api/v1/imports', headers=h, json=bad).status_code == 422


def test_partial_school_exam_times_and_useful_practice_notes_stay_partial(client):
    _, h = register(client)
    s = semester(client, h)
    body = {'semester_id': s['id'], 'source': 'hlju_webview', 'source_term': '2026-2027-1',
        'extras': [
            {'kind': 'exam', 'source_id': 'hlju:exam:date', 'title': '仅日期考试', 'date': '2026-12-21'},
            {'kind': 'exam', 'source_id': 'hlju:exam:start', 'title': '仅开始考试',
             'start_at': '2026-12-21T08:30:00+08:00'},
            {'kind': 'exam', 'source_id': 'hlju:exam:unknown', 'title': '未排考试',
             'notes': '备注:无', 'raw_text': '未排考试 备注:无'},
            {'kind': 'unplaced_course', 'source_id': 'hlju:practice', 'title': '实践课程',
             'weeks': [1, 2], 'notes': '备注：无\n完成上机实验', 'teacher': '教师乙'}]}
    apply(client, h, preview(client, h, body))
    exams = {row['title']: row for row in client.get(f"/api/v1/semesters/{s['id']}/items", headers=h).json()['items']}
    assert exams['仅日期考试']['time']['precision'] == 'date'
    assert exams['仅日期考试']['time']['date'] == '2026-12-21'
    assert exams['仅日期考试']['time']['at'] is None and exams['仅日期考试']['time']['end_at'] is None
    assert exams['仅开始考试']['time']['precision'] == 'exact'
    assert exams['仅开始考试']['time']['at'] == '2026-12-21T00:30:00Z'
    assert exams['仅开始考试']['time']['end_at'] is None
    assert exams['未排考试']['time']['precision'] == 'unknown' and exams['未排考试']['notes'] == ''
    assert exams['未排考试']['source_text'] == '未排考试 备注:无'
    practice = next(e for e in calendar(client, h, s['id'])['undated'] if e['title'] == '实践课程')
    saved = client.get('/api/v1/events/' + practice['resource_id'], headers=h).json()
    assert saved['notes'] == '第1—2周\n完成上机实验\n教师：教师乙'
    assert saved['time']['precision'] == 'unknown' and saved['reserve_time'] is False
    assert preview(client, h, body)['new_extra_count'] == 0


def test_import_extras_migration_keeps_populated_0014_batches(tmp_path, monkeypatch):
    url = 'sqlite:///' + str(tmp_path / 'import.db')
    monkeypatch.setenv('DATABASE_URL', url)
    config = Config(str(Path(__file__).resolve().parents[1] / 'alembic.ini'))
    config.set_main_option('script_location', str(Path(__file__).resolve().parents[1] / 'alembic'))
    engine = create_engine(url)
    from app.models import Base
    legacy = MetaData()
    for table in Base.metadata.sorted_tables:
        table.to_metadata(legacy)
    for name in ('extras', 'source_first_monday'):
        legacy.tables['import_batches']._columns.remove(legacy.tables['import_batches'].c[name])
    legacy.create_all(engine)
    command.stamp(config, '0014_notice_context')
    with engine.begin() as c:
        c.execute(text("INSERT INTO users (id, username, password_hash, recovery_hash) VALUES ('u','old_user','test','test')"))
        c.execute(text("INSERT INTO semesters (id,user_id,name,first_monday,total_weeks,periods,revision) VALUES ('s','u','old','2026-08-31',20,'[]',1)"))
        c.execute(text("INSERT INTO import_batches (id,user_id,semester_id,source,source_term,courses,base_revision) VALUES ('b','u','s','haut_webview','old-term','[]',0)"))
    command.upgrade(config, 'head')
    with engine.connect() as c:
        assert c.execute(text('SELECT source, source_term, extras, source_first_monday FROM import_batches')).one() == ('haut_webview', 'old-term', '[]', None)
    command.downgrade(config, '0014_notice_context')
    assert 'extras' not in {col['name'] for col in inspect(engine).get_columns('import_batches')}
    with engine.connect() as c:
        assert c.execute(text('SELECT id FROM import_batches')).scalar_one() == 'b'
    engine.dispose()
