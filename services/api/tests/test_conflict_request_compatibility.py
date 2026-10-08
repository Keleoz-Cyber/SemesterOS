"""Conflict controls preserve old replay hashes and never become user facts."""
import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.academics import fingerprint
from app.event_schemas import EventFields, EventEdit
from app.item_schemas import ItemCreate, ItemEdit, LifecycleInput
from app.models import CalendarEvent, IdempotencyRecord, StudyItem
from test_foundation import client, register, semester


def legacy_request(body, *, classified=False, item=False):
    # Reproduce the old signature contract independently of the new helper.
    sensitive = set()
    editing = 'expected_version' in type(body).model_fields
    if classified:
        sensitive = {'category_id', 'tags'} | ({'reserve_time', 'details'} if editing else set())
    value = body.model_dump(mode='json', exclude=sensitive - body.model_fields_set)
    value.pop('confirm_fixed_conflicts', None)
    value.pop('course_leave_targets', None)
    if item:
        value.pop('expected_revision', None)
    if classified and editing:
        if 'details' in value:
            value['details'] = body.details.model_dump(mode='json', exclude_unset=True)
        for field in ('expression', 'meaning', 'candidate_dates', 'course_anchor', 'end_at'):
            if field not in body.time.model_fields_set:
                value['time'].pop(field, None)
    return value


@pytest.mark.parametrize('action', ['event_create', 'event_edit', 'item_create', 'item_edit', 'lifecycle'])
def test_saved_legacy_request_replays_after_conflict_controls_are_added(client, action):
    _, headers = register(client)
    term = semester(client, headers)
    event = {'semester_id': term['id'], 'title': '旧客户端会议', 'time': {'precision': 'unknown'},
             'expected_revision': 0}
    item = {'semester_id': term['id'], 'kind': 'task', 'title': '旧客户端任务', 'time': {'precision': 'unknown'}}
    method, path = 'POST', '/api/v1/events' if action.startswith('event') else '/api/v1/items'
    if action.endswith('_edit') or action == 'lifecycle':
        initial = client.post(path, headers=headers, json=event if action.startswith('event') else item)
        assert initial.status_code == 201, initial.text
        record = initial.json()['event'] if action.startswith('event') else initial.json()
        path += '/' + record['id']
    if action == 'event_create':
        raw, schema, operation = event, EventFields, 'event-create'
    elif action == 'event_edit':
        raw = {**event, 'expected_revision': 1, 'expected_version': 1, 'title': '修正会议'}
        schema, operation, method = EventEdit, 'event-edit/' + record['id'], 'PATCH'
    elif action == 'item_create':
        raw, schema, operation = item, ItemCreate, 'create-item'
    elif action == 'item_edit':
        raw = {**item, 'title': '修正任务', 'expected_version': 1, 'change_reason': '本人核对'}
        schema, operation, method = ItemEdit, 'edit-item/' + record['id'], 'PATCH'
    else:
        path += '/lifecycle'
        raw, schema, operation = {'expected_version': 1, 'lifecycle': 'completed'}, LifecycleInput, 'item-state/' + record['id']
    request_headers = {**headers, 'Idempotency-Key': 'legacy-retry'}
    first = client.request(method, path, headers=request_headers, json=raw)
    assert first.status_code in (200, 201), first.text
    old = legacy_request(schema.model_validate(raw), classified=action != 'event_create' and action != 'lifecycle',
                         item=action.startswith('item'))
    with Session(client.app.state.engine) as db:
        saved = db.scalar(select(IdempotencyRecord).where(IdempotencyRecord.operation == operation,
                                                        IdempotencyRecord.key == 'legacy-retry'))
        assert saved.request_hash == fingerprint(old)
        saved.request_hash = fingerprint(old)
        db.commit()
    before = client.get('/api/v1/semesters', headers=headers).json()
    for retry in (raw, {**raw, 'confirm_fixed_conflicts': False, 'course_leave_targets': []}):
        response = client.request(method, path, headers=request_headers, json=retry)
        assert response.status_code == first.status_code, response.text
        assert response.json() == first.json()
    assert client.get('/api/v1/semesters', headers=headers).json() == before
    for patch in ({'confirm_fixed_conflicts': True}, {'course_leave_targets': ['different-course']},
                  {'expected_revision': 2}):
        changed = client.request(method, path, headers=request_headers, json={**raw, **patch})
        assert changed.status_code == 409, changed.text
        assert changed.json()['code'] == 'IDEMPOTENCY_CONFLICT'


def test_review_and_school_import_payloads_exclude_confirmation_controls(client):
    _, headers = register(client)
    term = semester(client, headers)
    exam = client.post('/api/v1/items', headers=headers,
        json={'semester_id': term['id'], 'kind': 'exam', 'title': '考试', 'time': {'precision': 'unknown'}})
    assert exam.status_code == 201, exam.text
    review = client.post('/api/v1/exams/' + exam.json()['id'] + '/reviews', headers=headers,
        json={'expected_exam_version': 1, 'remaining_minutes': 60})
    assert review.status_code == 201, review.text
    imported = client.post('/api/v1/imports', headers=headers, json={'semester_id': term['id'],
        'source': 'hlju_webview', 'source_term': '2026-2027-1', 'extras': [{
            'kind': 'unplaced_course', 'source_id': 'hlju:practice:sample', 'title': '实践课程', 'weeks': [1, 2]}]})
    assert imported.status_code == 201, imported.text
    applied = client.post('/api/v1/imports/' + imported.json()['id'] + '/apply', headers=headers,
        json={'expected_revision': imported.json()['base_revision']})
    assert applied.status_code == 200, applied.text
    controls = {'expected_revision', 'confirm_fixed_conflicts', 'course_leave_targets'}
    with Session(client.app.state.engine) as db:
        stored_review = db.get(StudyItem, review.json()['id'])
        stored_event = db.scalar(select(CalendarEvent).where(CalendarEvent.semester_id == term['id']))
        assert controls.isdisjoint(stored_review.payload)
        assert controls.isdisjoint(stored_event.payload)
        assert stored_review.payload['review_exam_id'] == exam.json()['id']
        assert stored_event.payload['title'] == '实践课程'
        assert stored_event.payload['reserve_time'] is False
