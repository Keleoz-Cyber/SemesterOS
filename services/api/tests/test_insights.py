from sqlalchemy.orm import Session
import pytest

from app.models import StudyItem, ProgressEntry, PlanProposal, PlanBlock
from test_foundation import client, register, semester
from test_calendar_events import event_body, revision


def event(c, h, sid, **patch):
    r = c.post('/api/v1/events', headers=h, json={**event_body(sid, **patch),
        'expected_revision': revision(c, h, sid)})
    assert r.status_code == 201, r.text
    return r.json()['event']


def item(c, h, sid, **patch):
    r = c.post('/api/v1/items', headers=h, json={'semester_id': sid, 'kind': 'task',
        'title': '任务', **patch})
    assert r.status_code == 201, r.text
    return r.json()


def insights(c, h, sid, **query):
    return c.get(f'/api/v1/semesters/{sid}/insights', headers=h, params={
        'from_date': '2026-09-21', 'to_date': '2026-09-22', **query})


def test_range_and_owner_isolation(client):
    _, h = register(client); _, other = register(client, 'other'); s = semester(client, h)
    assert insights(client, h, s['id']).status_code == 200
    assert insights(client, other, s['id']).status_code == 404
    assert insights(client, h, s['id'], to_date='2026-09-20').status_code == 422
    assert insights(client, h, s['id'], from_date='2026-01-01', to_date='2027-01-01').status_code == 200
    assert insights(client, h, s['id'], from_date='2026-01-01', to_date='2027-01-02').status_code == 422
    assert insights(client, h, s['id'], from_date='bad').status_code == 422


def test_cross_day_clip_overlap_and_tag_or_dedup(client):
    _, h = register(client); s = semester(client, h)
    a = event(client, h, s['id'], time={'precision': 'exact', 'at': '2026-09-20T23:00:00+08:00',
        'end_at': '2026-09-22T01:00:00+08:00'})
    event(client, h, s['id'], title='重叠', category_id='life', tags=[], time={
        'precision': 'exact', 'at': '2026-09-21T23:30:00+08:00', 'end_at': '2026-09-22T02:00:00+08:00'})
    data = insights(client, h, s['id']).json()
    assert data['summary']['fixed_scheduled_minutes'] == 1650
    assert data['summary']['occupied_union_minutes'] == 1560
    assert [d['fixed_scheduled_minutes'] for d in data['daily']] == [1470, 180]
    assert sum(x['scheduled_minutes'] for x in data['categories']) == 1650
    filtered = insights(client, h, s['id'], tag_ids=','.join(t['id'] for t in a['tags'])).json()
    assert filtered['summary']['entry_count'] == 1
    assert filtered['summary']['fixed_scheduled_minutes'] == 1500
    assert insights(client, h, s['id'], tag_ids='foreign').status_code == 404


def test_item_metadata_reuses_event_tags_and_preserves_legacy_edit(client):
    _, h = register(client); s = semester(client, h)
    e = event(client, h, s['id'], tags=['ＡＢＣ'])
    saved = item(client, h, s['id'], category_id='research', tags=[' abc ', 'ABC'])
    assert saved['tags'] == e['tags']
    changed = client.patch('/api/v1/items/' + saved['id'], headers=h, json={
        'semester_id': s['id'], 'kind': 'task', 'title': '新标题', 'expected_version': 1,
        'change_reason': '改标题'})
    assert changed.status_code == 200, changed.text
    assert changed.json()['category_id'] == 'research'
    assert changed.json()['tags'] == saved['tags']
    assert item(client, h, s['id'], kind='assignment')['category_id'] == 'study'


def test_unknown_zero_completed_progress_and_plan_classification(client):
    _, h = register(client); s = semester(client, h)
    task = item(client, h, s['id'], category_id='research', tags=['论文'])
    event(client, h, s['id'], time={'precision': 'date', 'date': '2026-09-21'}, tags=[])
    event(client, h, s['id'], title='待定', time={'precision': 'unknown'}, tags=[])
    data = insights(client, h, s['id']).json()
    assert data['summary']['actual_minutes'] is None
    assert data['summary']['unknown_duration_count'] == 1

    assert data['summary']['undated_count'] == 2
    with Session(client.app.state.engine) as db:
        row = db.get(StudyItem, task['id']); row.lifecycle = 'completed'
        p = PlanProposal(user_id=row.user_id, semester_id=s['id'], base_revision=0,
            payload={}, created_at='2026-09-20T00:00:00Z')
        db.add(p); db.flush()
        for status in ['active', 'cancelled']:
            db.add(PlanBlock(user_id=row.user_id, semester_id=s['id'], item_id=row.id, proposal_id=p.id,
                start_at='2026-09-21T15:00:00Z', end_at='2026-09-21T17:00:00Z', minutes=120,
                status=status, updated_at='2026-09-20T00:00:00Z'))
        for actual, at in [(None, '2026-09-21T00:00:00Z'), (0, '2026-09-21T16:01:00Z')]:
            db.add(ProgressEntry(user_id=row.user_id, item_id=row.id,
                payload={'actual_minutes': actual}, created_at=at))
        db.commit()
    data = insights(client, h, s['id']).json()
    assert data['summary']['actual_minutes'] == 0
    assert [d['actual_minutes'] for d in data['daily']] == [None, 0]
    assert data['summary']['personal_planned_minutes'] == 120
    assert all(r['category_id'] == 'research' and r['tags'] == task['tags']
        for r in data['records'] if r['resource_type'] in ('plan', 'progress'))
    assert data['summary']['unknown_duration_count'] == 1
    # A fixed interval can overlap a personal plan without multiplying union occupancy.
    event(client, h, s['id'], tags=[], time={'precision': 'exact',
        'at': '2026-09-22T00:00:00+08:00', 'end_at': '2026-09-22T02:00:00+08:00'})
    with Session(client.app.state.engine) as db:
        row = db.get(StudyItem, task['id'])
        db.add(ProgressEntry(user_id=row.user_id, item_id=row.id,
            payload={'actual_minutes': 35}, created_at='2026-09-21T00:00:00Z'))
        db.commit()
    data = insights(client, h, s['id']).json()
    assert data['summary']['fixed_scheduled_minutes'] == 120
    assert data['summary']['personal_planned_minutes'] == 120
    assert data['summary']['occupied_union_minutes'] == 180
    assert data['summary']['actual_minutes'] == 35
    assert [d['actual_minutes'] for d in data['daily']] == [35, 0]
    assert sum(c['scheduled_minutes'] for c in data['categories']) == 240
    assert sum(c['actual_minutes'] or 0 for c in data['categories']) == 35


def test_cancelled_and_other_semester_sources_do_not_enter_range(client):
    _, h = register(client); _, other = register(client, 'other')
    s = semester(client, h); sibling = semester(client, h); foreign = semester(client, other)
    cancelled = event(client, h, s['id'])
    response = client.post('/api/v1/events/' + cancelled['id'] + '/cancel', headers=h, json={
        'expected_version': 1, 'expected_revision': revision(client, h, s['id'])})
    assert response.status_code == 200, response.text
    event(client, h, sibling['id'])
    private = event(client, other, foreign['id'], tags=['私有'])
    foreign_id = private['tags'][0]['id']
    assert insights(client, h, s['id'], tag_ids=foreign_id).status_code == 404
    own = item(client, h, sibling['id'], title='其他学期')
    with Session(client.app.state.engine) as db:
        row = db.get(StudyItem, own['id'])
        db.add(ProgressEntry(user_id=row.user_id, item_id=row.id, payload={'actual_minutes': 77},
            created_at='2026-09-21T00:00:00Z'))
        db.commit()
    result = insights(client, h, s['id']).json()
    assert {k:v for k,v in result['summary'].items() if k!='tasks'} == {'entry_count': 0, 'fixed_scheduled_minutes': 0,
        'personal_planned_minutes': 0, 'occupied_union_minutes': 0, 'actual_minutes': None,
        'unknown_duration_count': 0, 'undated_count': 0}
    assert all(result['summary']['tasks'][k]==0 for k in ('active','completed','overdue'))
    assert foreign_id not in {t['id'] for t in result['tags']}


def test_course_exam_and_coarse_dates_are_not_invented_durations(client):
    _, h = register(client); s = semester(client, h)
    batch = client.post('/api/v1/imports', headers=h, json={'semester_id': s['id'], 'source': 'manual',
        'courses': [{'title': '课程', 'teacher': '', 'location': '', 'weekday': 1, 'weeks': [4], 'sections': [1]}]}).json()
    assert client.post('/api/v1/imports/' + batch['id'] + '/apply', headers=h,
        json={'expected_revision': 0}).status_code == 200
    item(client, h, s['id'], kind='exam', title='考试', time={'precision': 'exact',
        'at': '2026-09-21T09:00:00+08:00', 'end_at': '2026-09-21T10:00:00+08:00'})
    event(client, h, s['id'], title='某周通知', time={'precision': 'week', 'week': 4})
    event(client, h, s['id'], title='范围通知', time={'precision': 'range', 'date': '2026-09-20', 'end_date': '2026-09-23'})
    event(client, h, s['id'], title='边界之后', time={'precision': 'exact', 'at': '2026-09-23T00:00:00+08:00'})
    result = insights(client, h, s['id']).json()
    assert result['summary']['fixed_scheduled_minutes'] == 110
    assert result['summary']['unknown_duration_count'] == 2
    assert result['summary']['entry_count'] == 4
    assert result['daily'][1]['fixed_scheduled_minutes'] == 0
    study = insights(client, h, s['id'], category_id='study').json()
    assert study['summary']['fixed_scheduled_minutes'] == 110
    assert study['summary']['entry_count'] == 2
    assert insights(client, h, s['id'], category_id='fake').status_code == 422


def test_explicit_metadata_clear_and_event_legacy_edit(client):
    _, h = register(client); s = semester(client, h)
    e = event(client, h, s['id'])
    payload = event_body(s['id'])
    payload.pop('category_id'); payload.pop('tags')
    response = client.patch('/api/v1/events/' + e['id'], headers=h, json={**payload,
        'expected_version': 1, 'expected_revision': revision(client, h, s['id'])})
    assert response.status_code == 200, response.text
    assert response.json()['event']['category_id'] == e['category_id']
    assert response.json()['event']['tags'] == e['tags']
    saved = item(client, h, s['id'], kind='assignment', category_id='research', tags=['研究'])
    edited = client.patch('/api/v1/items/' + saved['id'], headers=h, json={
        'semester_id': s['id'], 'kind': 'assignment', 'title': saved['title'],
        'category_id': None, 'tags': [], 'expected_version': 1, 'change_reason': '清空分类'})
    assert edited.status_code == 200, edited.text
    assert edited.json()['category_id'] is None and edited.json()['tags'] == []
    result = insights(client, h, s['id'], category_id='unclassified').json()
    assert result['summary']['undated_count'] == 1


def test_item_create_idempotency_distinguishes_default_from_explicit_unclassified(client):
    _, h = register(client); s = semester(client, h)
    headers = {**h, 'Idempotency-Key': 'classification-create'}
    body = {'semester_id': s['id'], 'kind': 'assignment', 'title': '默认学业'}
    first = client.post('/api/v1/items', headers=headers, json=body)
    assert first.status_code == 201, first.text
    assert first.json()['category_id'] == 'study'
    assert client.post('/api/v1/items', headers=headers, json=body).json() == first.json()
    assert client.post('/api/v1/items', headers=headers, json={**body, 'notes': ''}).json() == first.json()
    conflict = client.post('/api/v1/items', headers=headers, json={**body, 'category_id': None})
    assert conflict.status_code == 409, conflict.text
    assert conflict.json()['code'] == 'IDEMPOTENCY_CONFLICT'


@pytest.mark.parametrize('clear', [{'category_id': None}, {'tags': []}])
def test_item_edit_idempotency_distinguishes_preservation_from_clear(client, clear):
    _, h = register(client); s = semester(client, h)
    saved = item(client, h, s['id'], category_id='research', tags=['研究'])
    headers = {**h, 'Idempotency-Key': 'classification-edit'}
    body = {'semester_id': s['id'], 'kind': 'task', 'title': '修改标题',
        'expected_version': saved['version'], 'change_reason': '改标题'}
    url = '/api/v1/items/' + saved['id']
    first = client.patch(url, headers=headers, json=body)
    assert first.status_code == 200, first.text
    assert first.json()['category_id'] == saved['category_id'] and first.json()['tags'] == saved['tags']
    assert client.patch(url, headers=headers, json=body).json() == first.json()
    assert client.patch(url, headers=headers, json={**body, 'notes': ''}).json() == first.json()
    conflict = client.patch(url, headers=headers, json={**body, **clear})
    assert conflict.status_code == 409, conflict.text
    assert conflict.json()['code'] == 'IDEMPOTENCY_CONFLICT'
    assert client.get(url, headers=h).json() == first.json()


@pytest.mark.parametrize('clear', [{'category_id': None}, {'tags': []}])
def test_event_edit_idempotency_distinguishes_preservation_from_clear(client, clear):
    _, h = register(client); s = semester(client, h)
    saved = event(client, h, s['id'])
    headers = {**h, 'Idempotency-Key': 'event-classification-edit'}
    body = {**event_body(s['id']), 'expected_version': saved['version'],
        'expected_revision': revision(client, h, s['id'])}
    body.pop('category_id'); body.pop('tags')
    url = '/api/v1/events/' + saved['id']
    first = client.patch(url, headers=headers, json=body)
    assert first.status_code == 200, first.text
    assert first.json()['event']['category_id'] == saved['category_id']
    assert first.json()['event']['tags'] == saved['tags']
    assert client.patch(url, headers=headers, json=body).json() == first.json()
    assert client.patch(url, headers=headers, json={**body, 'notes': ''}).json() == first.json()
    conflict = client.patch(url, headers=headers, json={**body, **clear})
    assert conflict.status_code == 409, conflict.text
    assert conflict.json()['code'] == 'IDEMPOTENCY_CONFLICT'
    assert client.get(url, headers=h).json() == first.json()['event']
