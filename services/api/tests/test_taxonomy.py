import os
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import pytest
from sqlalchemy.orm import Session

from app.models import StudyItem, ProgressEntry, PlanProposal, PlanBlock
from test_foundation import client, register, semester
from test_insights import item, event, insights


def preview(c, h, source, **body):
    response = c.post('/api/v1/tags/preview', headers=h, json={'source_id': source, **body})
    assert response.status_code == 200, response.text
    return response.json()


def apply(c, h, p):
    return c.post('/api/v1/tags/changes/' + p['token'] + '/apply', headers=h, json={})


def test_rename_stable_id_alias_preview_retry_and_ownership(client):
    _, h = register(client); _, other = register(client, 'other'); s = semester(client, h)
    task = item(client, h, s['id'], tags=['旧名称'])
    tid = task['tags'][0]['id']
    p = preview(client, h, tid, operation='rename', name='新名称')
    assert p['affected']['items'] == 1
    assert item(client, other, semester(client, other)['id'], tags=['旧名称'])['tags'][0]['id'] != tid
    assert apply(client, other, p).status_code == 404
    saved = apply(client, h, p)
    assert saved.status_code == 200, saved.text
    assert saved.json()['tag'] == {'id': tid, 'name': '新名称', 'version': 2}
    assert apply(client, h, p).json() == saved.json()
    assert item(client, h, s['id'], tags=['旧名称', '新名称'])['tags'] == [{'id': tid, 'name': '新名称'}]


def test_merge_preserves_history_totals_and_legacy_filter(client):
    _, h = register(client); s = semester(client, h)
    task = item(client, h, s['id'], tags=['论文', '科研'])
    old, target = [t['id'] for t in task['tags']]
    event(client, h, s['id'], tags=['论文', '科研'])
    with Session(client.app.state.engine) as db:
        row = db.get(StudyItem, task['id'])
        proposal = PlanProposal(user_id=row.user_id, semester_id=s['id'], base_revision=0,
            payload={}, created_at='2026-09-20T00:00:00Z')
        db.add(proposal); db.flush()
        db.add(PlanBlock(user_id=row.user_id, semester_id=s['id'], item_id=row.id, proposal_id=proposal.id,
            start_at='2026-09-21T01:00:00Z', end_at='2026-09-21T02:00:00Z', minutes=60,
            status='active', updated_at='2026-09-20T00:00:00Z'))
        db.add(ProgressEntry(user_id=row.user_id, item_id=row.id,
            payload={'actual_minutes': 35}, created_at='2026-09-21T00:00:00Z'))
        db.commit()
    before = insights(client, h, s['id'], tag_ids=old + ',' + target).json()
    p = preview(client, h, old, operation='merge', target_id=target)
    assert p['affected']['plans'] == 1 and p['affected']['progress'] == 1
    assert apply(client, h, p).status_code == 200
    after = insights(client, h, s['id'], tag_ids=old + ',' + target).json()
    assert after['summary'] == before['summary']
    assert after['filters']['tag_ids'] == [target]
    assert all(r['tags'] == [{'id': target, 'name': '科研'}] for r in after['records'])
    assert item(client, h, s['id'], tags=['论文'])['tags'] == [{'id': target, 'name': '科研'}]


def test_stale_preview_never_includes_unseen_changes(client):
    _, h = register(client); s = semester(client, h)
    task = item(client, h, s['id'], tags=['旧'])
    tid = task['tags'][0]['id']
    p = preview(client, h, tid, operation='rename', name='新')
    item(client, h, s['id'], tags=['旧'])
    assert apply(client, h, p).status_code == 409
    assert client.get('/api/v1/tags', headers=h).json()['tags'][0]['name'] == '旧'


def test_name_collision_requires_explicit_merge_and_foreign_target_blocked(client):
    _, h = register(client); _, other = register(client, 'other'); s = semester(client, h)
    task = item(client, h, s['id'], tags=['A', 'B'])
    a, b = [t['id'] for t in task['tags']]
    foreign = item(client, other, semester(client, other)['id'], tags=['C'])['tags'][0]['id']
    assert client.post('/api/v1/tags/preview', headers=h, json={'operation':'rename', 'source_id':a, 'name':'Ｂ'}).status_code == 409
    assert client.post('/api/v1/tags/preview', headers=h, json={'operation':'merge', 'source_id':a, 'target_id':foreign}).status_code == 404
    p = preview(client, h, a, operation='rename', name='C')
    assert apply(client, h, p).status_code == 200
    assert client.post('/api/v1/tags/preview', headers=h, json={'operation':'rename', 'source_id':b, 'name':'A'}).status_code == 409


def test_merge_chain_keeps_all_old_names_and_ids_and_nonclassification_fields(client):
    _, h = register(client); s = semester(client, h)
    task = item(client, h, s['id'], tags=['A', 'B', 'C'], remaining_minutes=75, priority='high')
    a, b, c = [t['id'] for t in task['tags']]
    with Session(client.app.state.engine) as db:
        before = dict(db.get(StudyItem, task['id']).payload)
    assert apply(client, h, preview(client, h, a, operation='merge', target_id=b)).status_code == 200
    assert apply(client, h, preview(client, h, b, operation='merge', target_id=c)).status_code == 200
    saved = item(client, h, s['id'], tags=['A', 'B', 'C'])
    assert saved['tags'] == [{'id': c, 'name': 'C'}]
    assert insights(client, h, s['id'], tag_ids=a + ',' + b).json()['filters']['tag_ids'] == [c]
    with Session(client.app.state.engine) as db:
        row = db.get(StudyItem, task['id'])
        assert row.version == 3
        assert row.payload == {**before, 'tag_ids': [c]}
    assert [t['id'] for t in client.get('/api/v1/taxonomy', headers=h).json()['tags']] == [c]


@pytest.mark.skipif(not os.environ.get('POSTGRES_TEST_URL'), reason='PostgreSQL row locks required')
def test_concurrent_repeat_confirmation_is_atomic(client):
    _, h = register(client); s = semester(client, h)
    task = item(client, h, s['id'], tags=['A', 'B'])
    a, b = [t['id'] for t in task['tags']]
    p = preview(client, h, a, operation='merge', target_id=b)
    barrier = Barrier(2)
    def save():
        barrier.wait(timeout=10)
        return apply(client, h, p)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: save(), range(2)))
    assert [r.status_code for r in results] == [200, 200]
    assert results[0].json() == results[1].json()
    with Session(client.app.state.engine) as db:
        assert db.get(StudyItem, task['id']).version == 2


@pytest.mark.skipif(not os.environ.get('POSTGRES_TEST_URL'), reason='PostgreSQL row locks required')
def test_concurrent_cross_semester_new_old_name_cannot_escape_merge(client):
    _, h = register(client); s1 = semester(client, h); s2 = semester(client, h)
    task = item(client, h, s1['id'], tags=['A', 'B'])
    a, b = [t['id'] for t in task['tags']]
    p = preview(client, h, a, operation='merge', target_id=b)
    barrier = Barrier(2)
    def merge():
        barrier.wait(timeout=10)
        return apply(client, h, p)
    def create():
        barrier.wait(timeout=10)
        return item(client, h, s2['id'], tags=['A'])
    with ThreadPoolExecutor(max_workers=2) as pool:
        merge_future = pool.submit(merge); create_future = pool.submit(create)
        merged, added = merge_future.result(timeout=20), create_future.result(timeout=20)
    assert merged.status_code in (200, 409), merged.text
    if merged.status_code == 409:
        # The newly affected second semester must be presented before confirmation.
        fresh = preview(client, h, a, operation='merge', target_id=b)
        assert {s['id'] for s in fresh['semesters']} == {s1['id'], s2['id']}
        assert apply(client, h, fresh).status_code == 200
    result = client.get('/api/v1/items/' + added['id'], headers=h)
    assert result.status_code == 200, result.text
    assert result.json()['tags'] == [{'id': b, 'name': 'B'}]
