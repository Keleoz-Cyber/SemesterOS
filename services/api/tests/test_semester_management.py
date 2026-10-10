from test_foundation import client, imported_payload, register, semester
from pathlib import Path
from sqlalchemy import select
from sqlalchemy.orm import Session
from app.models import (
    AgentRun, AgentThread, AvailabilityRevision, CalendarEvent,
    CalendarEventRevision, ItemRevision, MediaCleanupJob, MediaSource, OperationProposal, PlanBlock,
    PlanProposal, PlanRevision, ProgressEntry, RealityChange,
    ReminderRule, StudyAvailability, StudyItem, TextCandidate,
)


def calendar_payload(s, **changes):
    return {
        'name': s['name'],
        'first_monday': s['first_monday'],
        'total_weeks': s['total_weeks'],
        'periods': s['periods'],
        'expected_revision': s['revision'],
        **changes,
    }


def test_semester_settings_can_be_corrected_before_reimport(client):
    _, headers = register(client)
    s = semester(client, headers)
    batch = client.post('/api/v1/imports', headers=headers, json=imported_payload(s['id'])).json()
    applied = client.post(f"/api/v1/imports/{batch['id']}/apply", headers=headers,
                          json={'expected_revision': s['revision']})
    assert applied.status_code == 200, applied.text
    current = client.get('/api/v1/semesters', headers=headers).json()[0]
    changed = calendar_payload(current, periods=[
        {'number': 1, 'start': '08:10', 'end': '09:00'},
        {'number': 2, 'start': '09:10', 'end': '10:00'},
        {'number': 3, 'start': '10:20', 'end': '11:10'},
        {'number': 4, 'start': '11:20', 'end': '12:10'},
    ])
    result = client.put(f"/api/v1/semesters/{s['id']}", headers=headers, json=changed)
    assert result.status_code == 200, result.text
    assert result.json()['revision'] == current['revision'] + 1
    events = client.get(f"/api/v1/semesters/{s['id']}/timetable?week=1", headers=headers).json()['events']
    assert events[0]['start_at'] == '2026-09-02T08:10:00+08:00'
    assert client.put(f"/api/v1/semesters/{s['id']}", headers=headers, json=changed).status_code == 409


def test_removing_a_section_used_by_a_course_is_rejected(client):
    _, headers = register(client)
    s = semester(client, headers)
    batch = client.post('/api/v1/imports', headers=headers,
                        json=imported_payload(s['id'])).json()
    assert client.post(f"/api/v1/imports/{batch['id']}/apply", headers=headers,
                       json={'expected_revision': 0}).status_code == 200
    current = client.get('/api/v1/semesters', headers=headers).json()[0]
    result = client.put(f"/api/v1/semesters/{s['id']}", headers=headers,
                        json=calendar_payload(current, periods=[current['periods'][0]]))
    assert result.status_code == 422
    assert result.json()['code'] == 'CALENDAR_MISMATCH'
    assert client.get('/api/v1/semesters', headers=headers).json()[0]['periods'] == current['periods']


def test_delete_semester_removes_its_data_but_keeps_other_terms_and_accounts(client):
    _, headers = register(client)
    _, foreign = register(client, 'student_b')
    doomed = semester(client, headers)
    kept = semester(client, headers)
    someone_elses = semester(client, foreign)
    batch = client.post('/api/v1/imports', headers=headers, json=imported_payload(doomed['id'])).json()
    assert client.post(f"/api/v1/imports/{batch['id']}/apply", headers=headers,
                       json={'expected_revision': doomed['revision']}).status_code == 200
    item = client.post('/api/v1/items', headers=headers,
                       json={'semester_id': doomed['id'], 'kind': 'task', 'title': '待删除任务'})
    assert item.status_code == 201, item.text
    current = next(x for x in client.get('/api/v1/semesters', headers=headers).json() if x['id'] == doomed['id'])
    preview = client.get(f"/api/v1/semesters/{doomed['id']}/delete-preview", headers=headers)
    assert preview.status_code == 200, preview.text
    assert preview.json()['courses'] == 1
    assert preview.json()['items'] == 1
    assert client.delete(f"/api/v1/semesters/{doomed['id']}?expected_revision=0", headers=headers).status_code == 409
    assert client.delete(f"/api/v1/semesters/{doomed['id']}?expected_revision={current['revision']}",
                         headers=foreign).status_code == 404
    deleted = client.delete(f"/api/v1/semesters/{doomed['id']}?expected_revision={current['revision']}",
                            headers=headers)
    assert deleted.status_code == 200, deleted.text
    assert [x['id'] for x in client.get('/api/v1/semesters', headers=headers).json()] == [kept['id']]
    assert [x['id'] for x in client.get('/api/v1/semesters', headers=foreign).json()] == [someone_elses['id']]
    assert client.get(f"/api/v1/semesters/{doomed['id']}/timetable?week=1", headers=headers).status_code == 404


def test_delete_with_linked_plans_events_media_and_agent_history(client, tmp_path):
    account, headers = register(client)
    s = semester(client, headers)
    uid, sid = account['user']['id'], s['id']
    now = '2026-09-21T08:00:00Z'
    client.app.state.media_root = tmp_path
    (tmp_path / 'qa-media').write_bytes(b'qa')
    with Session(client.app.state.engine) as db:
        item = StudyItem(user_id=uid, semester_id=sid, payload={'title': '任务'},
                         created_at=now, updated_at=now)
        event = CalendarEvent(user_id=uid, semester_id=sid, payload={'title': '活动'},
                              created_at=now, updated_at=now)
        proposal = PlanProposal(user_id=uid, semester_id=sid, base_revision=0,
                                payload={}, created_at=now)
        thread = AgentThread(user_id=uid, semester_id=sid, created_at=now, updated_at=now)
        db.add_all([item, event, proposal, thread])
        db.flush()
        db.add_all([
            ReminderRule(user_id=uid, item_id=item.id, payload={}, created_at=now, updated_at=now),
            ItemRevision(user_id=uid, item_id=item.id, version=1, snapshot={},
                         reason='测试', created_at=now),
            ProgressEntry(user_id=uid, item_id=item.id, payload={}, created_at=now),
            TextCandidate(user_id=uid, semester_id=sid, source_text='测试', payload={},
                          item_id=item.id, created_at=now),
            CalendarEventRevision(user_id=uid, event_id=event.id, version=1,
                                  snapshot={}, reason='测试', created_at=now),
            PlanBlock(user_id=uid, semester_id=sid, item_id=item.id,
                      proposal_id=proposal.id, start_at=now, end_at=now,
                      minutes=30, updated_at=now),
            PlanRevision(user_id=uid, semester_id=sid, kind='test', payload={}, created_at=now),
            RealityChange(user_id=uid, semester_id=sid, base_revision=0,
                          payload={}, created_at=now),
            StudyAvailability(user_id=uid, semester_id=sid, payload={}, updated_at=now),
            AvailabilityRevision(user_id=uid, semester_id=sid, payload={}, created_at=now),
            OperationProposal(user_id=uid, semester_id=sid, base_revision=0,
                              source_text='测试', reference_at=now, payload={}, created_at=now),
            AgentRun(user_id=uid, thread_id=thread.id, request_id='one',
                     text='测试', created_at=now),
            MediaSource(user_id=uid, semester_id=sid, upload_key='qa', input_hash='0' * 64,
                        kind='image', mime='image/png', size=2, storage_key='qa-media',
                        reference_at=now, created_at=now),
        ])
        db.commit()
    result = client.delete(f"/api/v1/semesters/{sid}?expected_revision=0", headers=headers)
    assert result.status_code == 200, result.text
    assert not (tmp_path / 'qa-media').exists()
    with Session(client.app.state.engine) as db:
        assert db.scalars(select(StudyItem).where(StudyItem.semester_id == sid)).all() == []
        assert db.scalars(select(AgentRun).where(AgentRun.user_id == uid)).all() == []


def test_reimport_shows_exact_course_change_and_requires_explicit_replacement(client):
    _, headers = register(client)
    s = semester(client, headers)
    original = client.post('/api/v1/imports', headers=headers,
                           json=imported_payload(s['id'])).json()
    assert client.post(f"/api/v1/imports/{original['id']}/apply", headers=headers,
                       json={'expected_revision': 0}).status_code == 200
    before = client.get(f"/api/v1/semesters/{s['id']}/timetable?week=1", headers=headers).json()['events'][0]
    changed = imported_payload(s['id'])
    changed['source'] = 'haut_webview'
    changed['courses'][0]['sections'] = [2, 3]
    changed['courses'][0]['location'] = 'B404'
    preview = client.post('/api/v1/imports', headers=headers, json=changed)
    assert preview.status_code == 201, preview.text
    batch = preview.json()
    assert batch['changed_count'] == 1
    assert batch['changed_courses'][0]['before']['sections'] == [1, 2]
    assert batch['changed_courses'][0]['after']['sections'] == [2, 3]
    endpoint = f"/api/v1/imports/{batch['id']}/apply"
    assert client.post(endpoint, headers=headers,
                       json={'expected_revision': 1}).status_code == 409
    applied = client.post(endpoint, headers=headers,
                          json={'expected_revision': 1, 'replace_changed': True})
    assert applied.status_code == 200, applied.text
    assert applied.json()['replaced_count'] == 1
    after = client.get(f"/api/v1/semesters/{s['id']}/timetable?week=1", headers=headers).json()['events'][0]
    assert after['course_id'] == before['course_id']
    assert after['start_at'] == '2026-09-02T09:20:00+08:00'
    assert after['location'] == 'B404'


def test_reimport_does_not_guess_between_same_named_courses(client):
    _, headers = register(client)
    s = semester(client, headers)
    original = imported_payload(s['id'])
    original['courses'].append({**original['courses'][0], 'weekday': 4})
    batch = client.post('/api/v1/imports', headers=headers, json=original).json()
    assert client.post(f"/api/v1/imports/{batch['id']}/apply", headers=headers,
                       json={'expected_revision': 0}).status_code == 200
    updated = imported_payload(s['id'])
    updated['source'] = 'haut_webview'
    updated['courses'][0]['sections'] = [2, 3]
    preview = client.post('/api/v1/imports', headers=headers, json=updated)
    assert preview.status_code == 422
    assert preview.json()['code'] == 'AMBIGUOUS_COURSE'


def test_reimport_reserves_exact_meeting_before_matching_new_rows(client):
    _, headers = register(client)
    s = semester(client, headers)
    original = imported_payload(s['id'])
    original['courses'][0]['source_id'] = 'class-a'
    batch = client.post('/api/v1/imports', headers=headers, json=original).json()
    assert client.post(f"/api/v1/imports/{batch['id']}/apply", headers=headers,
                       json={'expected_revision': 0}).status_code == 200
    incoming = imported_payload(s['id'])
    incoming['source'] = 'haut_webview'
    incoming['courses'] = [
        {**original['courses'][0], 'sections': [2, 3]},
        original['courses'][0],
    ]
    preview = client.post('/api/v1/imports', headers=headers, json=incoming)
    assert preview.status_code == 201, preview.text
    assert preview.json()['new_count'] == 1
    assert preview.json()['unchanged_count'] == 1
    assert preview.json()['changed_count'] == 0
    applied = client.post(f"/api/v1/imports/{preview.json()['id']}/apply",
                          headers=headers, json={'expected_revision': 1})
    assert applied.status_code == 200, applied.text
    courses = client.get(f"/api/v1/semesters/{s['id']}/courses", headers=headers).json()
    assert len(courses) == 2


def test_failed_media_unlink_has_durable_retry_job(client, tmp_path, monkeypatch):
    account, headers = register(client)
    s = semester(client, headers)
    client.app.state.media_root = tmp_path
    (tmp_path / 'source-file').write_bytes(b'private test media')
    with Session(client.app.state.engine) as db:
        db.add(MediaSource(user_id=account['user']['id'], semester_id=s['id'],
                           upload_key='media', input_hash='0' * 64, kind='image',
                           mime='image/png', size=18, storage_key='source-file',
                           reference_at='2026-09-21T08:00:00Z',
                           created_at='2026-09-21T08:00:00Z'))
        db.commit()
    original_unlink = Path.unlink
    def refuse_unlink(path, *args, **kwargs):
        if path.name == 'source-file':
            raise OSError('busy')
        return original_unlink(path, *args, **kwargs)
    with monkeypatch.context() as patch:
        patch.setattr(Path, 'unlink', refuse_unlink)
        first = client.delete(f"/api/v1/semesters/{s['id']}?expected_revision=0",
                              headers={**headers, 'Idempotency-Key': 'same-delete'})
    assert first.status_code == 200, first.text
    assert first.json()['media_files_pending_cleanup'] == 1
    assert (tmp_path / 'source-file').exists()
    with Session(client.app.state.engine) as db:
        assert len(db.scalars(select(MediaCleanupJob)).all()) == 1
    retry = client.delete(f"/api/v1/semesters/{s['id']}?expected_revision=0",
                          headers={**headers, 'Idempotency-Key': 'same-delete'})
    assert retry.status_code == 200, retry.text
    assert retry.json()['media_files_pending_cleanup'] == 0
    assert not (tmp_path / 'source-file').exists()
    with Session(client.app.state.engine) as db:
        assert db.scalars(select(MediaCleanupJob)).all() == []


def test_school_reimport_can_explicitly_remove_absent_old_school_courses(client):
    _, headers = register(client)
    s = semester(client, headers)
    first = imported_payload(s['id'])
    first['source'] = 'haut_webview'
    first['source_term'] = '2026-2027 第一学期'
    first['courses'][0]['source_id'] = 'class-a'
    first['courses'].append({
        **first['courses'][0], 'title': '软件工程', 'source_id': 'class-b',
        'weekday': 4,
    })
    initial = client.post('/api/v1/imports', headers=headers, json=first).json()
    assert client.post(f"/api/v1/imports/{initial['id']}/apply", headers=headers,
                       json={'expected_revision': 0}).status_code == 200
    manual = imported_payload(s['id'])
    manual['courses'][0].update({'title': '手工补充课', 'weekday': 5})
    manual_batch = client.post('/api/v1/imports', headers=headers, json=manual).json()
    assert client.post(f"/api/v1/imports/{manual_batch['id']}/apply", headers=headers,
                       json={'expected_revision': 1}).status_code == 200
    ids = {row['title']: row['id'] for row in client.get(
        f"/api/v1/semesters/{s['id']}/courses", headers=headers).json()}
    item = client.post('/api/v1/items', headers=headers, json={
        'semester_id': s['id'], 'kind': 'assignment', 'title': '软件作业',
        'course_id': ids['软件工程'],
    }).json()
    latest = next(row for row in client.get('/api/v1/semesters', headers=headers).json()
                  if row['id'] == s['id'])
    second = {**first, 'courses': [first['courses'][0]]}
    preview = client.post('/api/v1/imports', headers=headers, json=second)
    assert preview.status_code == 201, preview.text
    batch = preview.json()
    assert batch['missing_count'] == 1
    assert batch['missing_courses'][0]['before']['title'] == '软件工程'
    endpoint = f"/api/v1/imports/{batch['id']}/apply"
    applied = client.post(endpoint, headers=headers, json={
        'expected_revision': latest['revision'], 'remove_missing': True,
    })
    assert applied.status_code == 200, applied.text
    assert applied.json()['removed_count'] == 1
    remaining = client.get(f"/api/v1/semesters/{s['id']}/courses", headers=headers).json()
    assert sorted(row['title'] for row in remaining) == ['手工补充课', '概率论']
    task = client.get(f"/api/v1/items/{item['id']}", headers=headers).json()
    assert task['course_id'] is None
    assert task['course_title'] == ''


def test_manual_course_correction_is_not_silently_classed_as_missing_school_row(client):
    _, headers = register(client)
    s = semester(client, headers)
    first = imported_payload(s['id'])
    first['source'] = 'haut_webview'
    first['source_term'] = '2026-2027 第一学期'
    first['courses'][0]['source_id'] = 'class-a'
    first['courses'].append({**first['courses'][0], 'title': '软件工程',
                             'source_id': 'class-b', 'weekday': 4})
    batch = client.post('/api/v1/imports', headers=headers, json=first).json()
    assert client.post(f"/api/v1/imports/{batch['id']}/apply", headers=headers,
                       json={'expected_revision': 0}).status_code == 200
    rows = client.get(f"/api/v1/semesters/{s['id']}/courses", headers=headers).json()
    course_id = next(row['id'] for row in rows if row['title'] == '软件工程')
    detail = client.get(f'/api/v1/courses/{course_id}', headers=headers).json()
    saved = client.patch(f'/api/v1/courses/{course_id}', headers=headers,
                         json={**detail['course'], 'location': '手工修正地点',
                               'expected_revision': detail['revision']})
    assert saved.status_code == 200, saved.text
    second = {**first, 'courses': [first['courses'][0]]}
    preview = client.post('/api/v1/imports', headers=headers, json=second)
    assert preview.status_code == 201, preview.text
    assert preview.json()['missing_count'] == 0
