import json
from sqlalchemy.orm import Session
from test_foundation import client, register, semester
from test_agent import thread, turn, run


def test_profile_defaults_account_isolation_and_optimistic_version(client):
    _, h = register(client); _, other = register(client, 'student_b')
    url = '/api/v1/me/profile'
    assert client.get(url).status_code == 401
    initial = client.get(url, headers=h)
    assert initial.status_code == 200
    assert initial.json() == {'version': 0, 'school': '', 'college': '', 'major': '',
        'class_name': '', 'education_level': None, 'entry_year': None,
        'class_role': '', 'onboarding_completed': False}
    body = {**initial.json(), 'expected_version': 0, 'college': '示例学院',
            'class_role': '学委', 'onboarding_completed': True}
    body.pop('version')
    saved = client.put(url, headers=h, json=body)
    assert saved.status_code == 200, saved.text
    assert saved.json()['version'] == 1
    assert client.put(url, headers=h, json=body).status_code == 409
    assert client.get(url, headers=other).json()['version'] == 0
    assert client.get(url, headers=other).json()['class_role'] == ''
    assert client.put(url, headers=h, json={**body, 'expected_version': 1,
        'education_level': 'staff'}).status_code == 422


def test_empty_profile_can_finish_onboarding_and_is_not_authorization(client):
    _, h = register(client)
    saved = client.put('/api/v1/me/profile', headers=h,
        json={'expected_version': 0, 'onboarding_completed': True})
    assert saved.status_code == 200, saved.text
    assert saved.json()['class_role'] == ''
    assert saved.json()['onboarding_completed'] is True
    assert client.put('/api/v1/me/profile', headers=h,
        json={'expected_version': 1, 'class_role': '管理员', 'user_id': 'other'}).status_code == 422


def test_latest_self_reported_profile_is_quoted_data_in_next_agent_request(client):
    _, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    for version, role in enumerate(['学委', '普通学生']):
        assert client.put('/api/v1/me/profile', headers=h,
            json={'expected_version': version, 'class_role': role}).status_code == 200
        req = turn(client, h, tid, '帮我整理补办学生证通知', str(version))
        def model(messages, tools):
            context = [m for m in messages if m['role'] == 'user' and 'self_reported_profile' in (m.get('content') or '')]
            assert len(context) == 1
            assert context[0]['role'] == 'user'
            assert json.loads(context[0]['content'])['self_reported_profile']['class_role'] == role
            assert '本人自述' in messages[0]['content'] and '权限' in messages[0]['content']
            return {'content': '请按通知中的**适用对象**核对。'}
        run(client, model)
        assert client.get('/api/v1/agent/runs/' + req['id'], headers=h).json()['status'] == 'completed'
