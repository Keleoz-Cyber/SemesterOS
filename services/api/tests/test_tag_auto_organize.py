from sqlalchemy.orm import Session

from app.models import CalendarTag, StudyItem
from app.event_store import canonical_tag_ids
from test_foundation import client, register, semester
from test_insights import item


def legacy_labels(client, user_id, resources, labels):
    """Build an old database fixture; current writes already normalize names."""
    with Session(client.app.state.engine) as db:
        tags = {name: CalendarTag(user_id=user_id, name=name, normalized=name.casefold()) for name in labels}
        db.add_all(tags.values()); db.flush()
        for resource, names in resources:
            row = db.get(StudyItem, resource['id'])
            row.payload = {**row.payload, 'tag_ids': [tags[n].id for n in names]}
        db.commit()
        return {name: t.id for name, t in tags.items()}


def test_system_merges_old_labels_without_confirmation_and_preserves_source(client):
    account, h = register(client); _, other = register(client, 'unrelated')
    s = semester(client, h); s2 = semester(client, h)
    a = item(client, h, s['id'], title='周五合唱彩排', source_text='请大家周五到礼堂彩排', tags=[])
    b = item(client, h, s2['id'], title='合唱联排', tags=[])
    ids = legacy_labels(client, account['user']['id'], [(a, ['彩排', '排练']), (b, ['联排'])], ['彩排', '联排', '排练'])
    untouched = item(client, other, semester(client, other)['id'], title='其他人', tags=['自定义标签'])
    response = client.post('/api/v1/tags/organize', headers=h, json={})
    assert response.status_code == 200, response.text
    assert response.json()['merged'] == 2
    assert len(response.json()['semesters']) == 2
    tags = client.get('/api/v1/tags', headers=h).json()['tags']
    assert [(t['name'], t['usage_count']) for t in tags] == [('排练', 2)]
    assert tags[0]['id'] == ids['排练']
    saved = client.get('/api/v1/items/' + a['id'], headers=h).json()
    assert saved['tags'] == [{'id': ids['排练'], 'name': '排练'}]
    assert saved['title'] == '周五合唱彩排'
    assert saved['source_text'] == '请大家周五到礼堂彩排'
    assert client.get('/api/v1/items/' + untouched['id'], headers=other).json()['version'] == 1
    retry = client.post('/api/v1/tags/organize', headers=h, json={}).json()
    assert retry['merged'] == retry['renamed'] == 0
    assert client.get('/api/v1/items/' + a['id'], headers=h).json()['version'] == saved['version']
    added = item(client, h, s['id'], tags=['彩排', '联排', '排练'])
    assert added['tags'] == [{'id': ids['排练'], 'name': '排练'}]
    with Session(client.app.state.engine) as db:
        assert canonical_tag_ids(db, account['user']['id'], list(ids.values())) == [ids['排练']]


def test_only_old_variant_is_renamed_in_place_and_custom_rename_is_respected(client):
    account, h = register(client); s = semester(client, h)
    task = item(client, h, s['id'], tags=[])
    ids = legacy_labels(client, account['user']['id'], [(task, ['彩排'])], ['彩排'])
    result = client.post('/api/v1/tags/organize', headers=h, json={}).json()
    assert result['renamed'] == 1 and result['merged'] == 0
    tags = client.get('/api/v1/tags', headers=h).json()['tags']
    assert tags[0]['id'] == ids['彩排'] and tags[0]['name'] == '排练'
    p = client.post('/api/v1/tags/preview', headers=h, json={
        'operation': 'rename', 'source_id': tags[0]['id'], 'name': '周五训练'}).json()
    assert client.post('/api/v1/tags/changes/' + p['token'] + '/apply', headers=h, json={}).status_code == 200
    second = item(client, h, s['id'], tags=[])
    legacy_labels(client, account['user']['id'], [(second, ['联排'])], ['联排'])
    assert client.post('/api/v1/tags/organize', headers=h, json={}).json()['merged'] == 1
    assert [t['name'] for t in client.get('/api/v1/tags', headers=h).json()['tags']] == ['周五训练']
    assert item(client, h, s['id'], tags=['彩排'])['tags'][0]['name'] == '周五训练'


def test_new_variant_labels_never_create_duplicates(client):
    _, h = register(client); s = semester(client, h)
    a = item(client, h, s['id'], title='周五联排', tags=['联排', '彩排', '排练'])
    b = item(client, h, s['id'], title='带妆排练', tags=['带妆排练'])
    assert len(a['tags']) == 1 and a['tags'][0]['name'] == '排练'
    assert a['tags'] == b['tags']
    assert a['title'] == '周五联排' and b['title'] == '带妆排练'
    assert client.get('/api/v1/tags').status_code == 401
