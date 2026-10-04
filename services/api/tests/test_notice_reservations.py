import pytest
from test_foundation import client, register, semester
from test_agent import thread, turn, run, call


def event_body(sid, **extra):
    return {'semester_id':sid, 'title':'讲座通知', 'expected_revision':0,
        'time':{'precision':'exact','at':'2026-10-09T15:00:00+08:00','end_at':'2026-10-09T16:00:00+08:00'}, **extra}


@pytest.mark.parametrize('status', ['optional','conditional','other'])
def test_reference_activity_stays_visible_without_occupancy_conflicts_or_statistics(client, status):
    _, h = register(client); s = semester(client,h)
    response = client.post('/api/v1/events', headers=h, json=event_body(s['id'],
        details={'participation_status':status,'participation':'班长选择两名同学参会，自己尚未报名'}))
    assert response.status_code == 201, response.text
    saved = response.json()['event']
    assert saved['reserve_time'] is False
    value = client.get('/api/v1/semesters/' + s['id'] + '/calendar', headers=h,
        params={'from_date':'2026-10-09','to_date':'2026-10-09'}).json()['entries'][0]
    assert value['resource_id'] == saved['id'] and value['start_at'] is not None
    assert value['reserve_time'] is False and value['fixed'] is False
    assert value['occupancy_start_at'] is None
    stats = client.get('/api/v1/semesters/' + s['id'] + '/insights', headers=h,
        params={'from_date':'2026-10-09','to_date':'2026-10-09'}).json()['summary']
    assert stats['occupied_union_minutes'] == 0 and stats['fixed_scheduled_minutes'] == 0
    other = client.post('/api/v1/events', headers=h, json=event_body(s['id'],
        title='本人确定参会', expected_revision=1, details={'participation_status':'confirmed'}))
    assert other.status_code == 201, other.text
    assert other.json()['event']['reserve_time'] is True
    assert other.json()['fixed_conflicts'] == []


@pytest.mark.parametrize('include_details', [False, True])
def test_old_client_title_edit_preserves_explicit_nonreservation(client, include_details):
    _, h = register(client); s = semester(client,h)
    body = event_body(s['id'], reserve_time=False, details={'participation_status':'confirmed'})
    saved = client.post('/api/v1/events', headers=h, json=body).json()['event']
    old = event_body(s['id'], title='重命名参考安排', expected_revision=1,
        expected_version=1, change_reason='只改标题')
    if include_details: old['details'] = saved['details']
    changed = client.patch('/api/v1/events/' + saved['id'], headers=h, json=old)
    assert changed.status_code == 200, changed.text
    assert changed.json()['event']['reserve_time'] is False


def test_formal_exam_edit_preserves_omitted_reservation_and_allows_explicit_changes(client):
    _, h = register(client); s = semester(client, h)
    fields = {'semester_id':s['id'], 'kind':'exam', 'title':'参考考试', 'certainty':'formal',
        'reserve_time':False, 'time':{'precision':'exact', 'at':'2026-10-09T09:00:00+08:00',
                                    'end_at':'2026-10-09T11:00:00+08:00'}}
    saved = client.post('/api/v1/items', headers=h, json=fields).json()
    edit = {key:value for key,value in fields.items() if key != 'reserve_time'}
    edit.update(title='参考考试改名', expected_version=saved['version'], change_reason='只改标题')
    url = '/api/v1/items/' + saved['id']
    changed = client.patch(url, headers=h, json=edit)
    assert changed.status_code == 200, changed.text
    assert changed.json()['reserve_time'] is False
    for reserve in (True, False):
        edit.update(expected_version=changed.json()['version'], reserve_time=reserve)
        changed = client.patch(url, headers=h, json=edit)
        assert changed.status_code == 200, changed.text
        assert changed.json()['reserve_time'] is reserve


def test_confirmation_update_reserves_and_legacy_create_still_defaults_true(client):
    _, h = register(client); s = semester(client,h)
    body = event_body(s['id'], details={'participation_status':'optional'})
    event = client.post('/api/v1/events', headers=h, json=body).json()['event']
    changed = client.patch('/api/v1/events/' + event['id'], headers=h,
        json={**body, 'expected_revision':1,'expected_version':1,'change_reason':'本人已报名',
              'details':{'participation_status':'confirmed'}})
    assert changed.status_code == 200, changed.text
    assert changed.json()['event']['reserve_time'] is True
    legacy = client.post('/api/v1/events', headers=h, json=event_body(s['id'], title='旧客户端会议',expected_revision=2))
    assert legacy.status_code == 201, legacy.text
    assert legacy.json()['event']['reserve_time'] is True


def test_agent_class_leader_can_save_reference_notice_without_confirming_own_attendance(client):
    _, h = register(client); s = semester(client,h); tid = thread(client,h,s['id'])
    client.put('/api/v1/me/profile', headers=h, json={'expected_version':0,'class_role':'班长'})
    req = turn(client,h,tid,'通知要班长选两人参加讲座，我保存讲座信息，还未确定本人参加。')
    def model(messages, tools):
        assert '时间精度' in messages[0]['content'] and '参考安排' in messages[0]['content']
        return call('prepare_event',{'action':'create','fields':{'title':'讲座参考信息',
            'time':{'precision':'exact','at':'2026-10-09T15:00:00+08:00','end_at':'2026-10-09T16:00:00+08:00'},
            'details':{'participation_status':'other','participation':'另选两人参加'}}})
    run(client,model)
    url = '/api/v1/agent/runs/' + req['id']; p = client.get(url,headers=h).json()['preview']
    assert p is not None and p['after']['reserve_time'] is False
    saved = client.post(url + '/decision',headers=h,json={'decision':'confirm','token':p['token']})
    assert saved.status_code == 200, saved.text
    assert saved.json()['receipt']['event']['reserve_time'] is False


def test_omitted_reservation_and_explicit_reservation_are_distinct_idempotent_edits(client):
    _, h = register(client); s = semester(client,h)
    saved = client.post('/api/v1/events',headers=h,json=event_body(s['id'],reserve_time=False)).json()['event']
    edit = event_body(s['id'],title='改名',expected_revision=1,expected_version=1,change_reason='改名')
    headers = {**h,'Idempotency-Key':'reservation-edit'}
    first = client.patch('/api/v1/events/' + saved['id'],headers=headers,json=edit)
    assert first.status_code == 200, first.text
    assert first.json()['event']['reserve_time'] is False
    changed = client.patch('/api/v1/events/' + saved['id'],headers=headers,json={**edit,'reserve_time':True})
    assert changed.status_code == 409, changed.text


def test_preserved_notice_details_and_explicit_clear_are_distinct_idempotent_edits(client):
    _, h = register(client); s = semester(client,h)
    saved = client.post('/api/v1/events',headers=h,
        json=event_body(s['id'],details={'materials':['申请表']})).json()['event']
    edit = event_body(s['id'],title='改名',expected_revision=1,expected_version=1,change_reason='改名')
    headers = {**h,'Idempotency-Key':'details-edit'}
    assert client.patch('/api/v1/events/' + saved['id'],headers=headers,json=edit).status_code == 200
    changed = client.patch('/api/v1/events/' + saved['id'],headers=headers,json={**edit,'details':{'materials':[]}})
    assert changed.status_code == 409, changed.text
