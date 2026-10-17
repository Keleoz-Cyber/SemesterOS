from sqlalchemy.orm import Session

from app.models import StudyItem
from test_foundation import client, register, semester
from test_insights import item, event
from test_tag_auto_organize import legacy_labels


def test_records_include_all_semesters_states_and_merged_ids_without_duplicates(client):
    account, h = register(client)
    s = semester(client, h); old = semester(client, h)
    task = item(client, h, s['id'], title='准备组会', tags=[])
    done = item(client, h, old['id'], title='整理座谈记录', tags=[])
    ids = legacy_labels(client, account['user']['id'],
        [(task, ['组会', '会议']), (done, ['座谈会'])], ['组会', '会议', '座谈会'])
    with Session(client.app.state.engine) as db:
        db.get(StudyItem, done['id']).lifecycle = 'completed'; db.commit()
    meeting = event(client, h, s['id'], title='部门例会', tags=['会议'])
    client.post('/api/v1/events/' + meeting['id'] + '/cancel', headers=h,
        json={'expected_version': meeting['version'], 'expected_revision':
            next(r['revision'] for r in client.get('/api/v1/semesters', headers=h).json() if r['id'] == s['id'])})
    item(client, h, s['id'], title='不属于这个标签', tags=['排练'])
    assert client.post('/api/v1/tags/organize', headers=h, json={}).status_code == 200
    # An old bookmark to a merged label still finds the same real records.
    result = client.get(f"/api/v1/tags/{ids['组会']}/records", headers=h).json()
    assert result['owner_id'] == account['user']['id']
    assert result['tag']['name'] == '会议' and result['tag']['id'] == ids['会议']
    assert result['total'] == 3
    assert {(r['resource_type'], r['id'], r['lifecycle']) for r in result['records']} == {
        ('item', task['id'], 'active'), ('item', done['id'], 'completed'), ('event', meeting['id'], 'cancelled')}
    assert {v['id'] for v in result['semesters']} == {s['id'], old['id']}
    assert 'source_text' not in result['records'][0]
    first = client.get(f"/api/v1/tags/{ids['会议']}/records?limit=1", headers=h).json()
    rest = client.get(f"/api/v1/tags/{ids['会议']}/records?limit=2&offset=1", headers=h).json()
    assert first['has_more'] and not rest['has_more']
    assert first['records'] + rest['records'] == result['records']


def test_tag_records_are_owner_scoped_and_missing_tag_is_not_an_empty_success(client):
    _, h = register(client); _, other = register(client, 'other')
    task = item(client, h, semester(client, h)['id'], tags=['会议'])
    tid = task['tags'][0]['id']
    assert client.get('/api/v1/tags/' + tid + '/records', headers=other).status_code == 404
    assert client.get('/api/v1/tags/' + tid + '/records').status_code == 401
    assert client.get('/api/v1/tags/missing/records', headers=h).status_code == 404
    assert client.get('/api/v1/tags/' + tid + '/records?offset=-1', headers=h).status_code == 422
    assert client.get('/api/v1/tags/' + tid + '/records?limit=101', headers=h).status_code == 422
