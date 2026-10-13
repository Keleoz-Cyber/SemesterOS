import json
from sqlalchemy import select
from sqlalchemy.orm import Session
from test_foundation import client, register, semester
from test_calendar_events import create_event
from app.models import Base, User, UserFeedback


def test_search_matches_original_notice_and_is_owner_scoped(client):
    _, h = register(client)
    s = semester(client, h)
    event = create_event(client, h, s['id']).json()['event']
    from app.models import CalendarEvent
    with Session(client.app.state.engine) as db:
        row = db.get(CalendarEvent, event['id'])
        row.payload = {**row.payload, 'source_text': '请携带6108材料，完成率100%'}
        db.commit()
    for query in ['6108', '材料', '100%']:
        r = client.get(f"/api/v1/semesters/{s['id']}/search", headers=h, params={'q': query})
        assert r.status_code == 200, r.text
        assert r.json()['results'][0]['id'] == event['id']
    assert client.get(f"/api/v1/semesters/{s['id']}/search", headers=h, params={'q': '_'}).json()['results'] == []
    _, other = register(client, 'student_b')
    assert client.get(f"/api/v1/semesters/{s['id']}/search?q=6108", headers=other).status_code == 404


def test_export_omits_credentials_and_erasure_preserves_other_owner(client):
    account, h = register(client)
    s = semester(client, h)
    create_event(client, h, s['id'])
    _, other = register(client, 'student_b')
    other_s = semester(client, other)
    feedback = client.post('/api/v1/me/feedback', headers=h, json={'category': 'save', 'description': '点击后没有结果'})
    assert feedback.status_code == 201
    data = client.get('/api/v1/me/export', headers=h)
    assert data.status_code == 200, data.text
    assert data.json()['data']['semesters'][0]['id'] == s['id']
    assert all(value not in data.text for value in ['password_hash', 'recovery_hash', 'access_hash', account['access_token']])
    body = {'confirmation': '删除我的账号', 'password': 'wrong'}
    assert client.post('/api/v1/me/erase', headers=h, json=body).status_code == 403
    assert client.get('/api/v1/me', headers=h).status_code == 200
    body['password'] = 'test-only-password-123'
    r = client.post('/api/v1/me/erase', headers=h, json=body)
    assert r.status_code == 200, r.text
    assert r.json()['deleted'] is True
    assert client.get('/api/v1/me', headers=h).status_code == 401
    assert client.get('/api/v1/semesters', headers=other).json()[0]['id'] == other_s['id']
    with Session(client.app.state.engine) as db:
        assert not list(db.scalars(select(UserFeedback)))
