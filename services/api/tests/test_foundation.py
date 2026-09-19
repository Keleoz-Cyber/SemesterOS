from fastapi.testclient import TestClient
import pytest
import os
import uuid
from concurrent.futures import ThreadPoolExecutor
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

from app.main import create_app


@pytest.fixture
def client(tmp_path):
    pg = os.environ.get('POSTGRES_TEST_URL')
    if not pg:
        with TestClient(create_app(f"sqlite:///{tmp_path / 'test.db'}", initialize=True)) as c:
            yield c
        return
    # Each test gets its own new schema. Never delete application tables.
    schema = 'test_' + uuid.uuid4().hex
    admin = create_engine(pg)
    with admin.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA {schema}'))
    url = make_url(pg).update_query_dict({'options': f'-csearch_path={schema}'})
    try:
        with TestClient(create_app(url.render_as_string(hide_password=False), initialize=True)) as c:
            yield c
    finally:
        with admin.begin() as connection:
            connection.execute(text(f'DROP SCHEMA {schema} CASCADE'))
        admin.dispose()


def register(client, username="student_a"):
    response = client.post("/api/v1/auth/register", json={
        "username": username, "password": "test-only-password-123",
    })
    assert response.status_code == 201, response.text
    data = response.json()
    return data, {"Authorization": f"Bearer {data['access_token']}"}


def semester(client, headers):
    response = client.post("/api/v1/semesters", headers=headers, json={
        "name": "测试学期", "first_monday": "2026-08-31", "total_weeks": 20,
        "periods": [
            {"number": 1, "start": "08:00", "end": "08:50"},
            {"number": 2, "start": "09:00", "end": "09:50"},
            {"number": 3, "start": "10:10", "end": "11:00"},
        ],
    })
    assert response.status_code == 201, response.text
    return response.json()


def imported_payload(sid):
    return {"semester_id": sid, "source": "manual", "courses": [{
        "title": "概率论", "teacher": "示例教师", "location": "A305",
        "weekday": 3, "weeks": [1, 3, 5], "sections": [1, 2],
    }]}


def test_auth_is_required_and_accounts_are_isolated(client):
    assert client.get("/api/v1/semesters").status_code == 401
    _, a = register(client)
    _, b = register(client, "student_b")
    s = semester(client, a)
    assert len(client.get("/api/v1/semesters", headers=a).json()) == 1
    assert client.get("/api/v1/semesters", headers=b).json() == []
    assert client.get(f"/api/v1/semesters/{s['id']}/timetable?week=1", headers=b).status_code == 404


def test_import_requires_confirmation_and_retries_do_not_duplicate(client):
    _, h = register(client)
    s = semester(client, h)
    batch = client.post("/api/v1/imports", headers=h, json=imported_payload(s["id"]))
    assert batch.status_code == 201, batch.text
    assert client.get(f"/api/v1/semesters/{s['id']}/timetable?week=1", headers=h).json()["events"] == []
    apply = f"/api/v1/imports/{batch.json()['id']}/apply"
    request = {"expected_revision": 0}
    first = client.post(apply, headers={**h, "Idempotency-Key": "apply-one"}, json=request)
    assert first.status_code == 200, first.text
    second = client.post(apply, headers={**h, "Idempotency-Key": "apply-one"}, json=request)
    assert second.json() == first.json()
    again = client.post("/api/v1/imports", headers=h, json=imported_payload(s["id"])).json()
    assert again["new_count"] == 0
    events = client.get(f"/api/v1/semesters/{s['id']}/timetable?week=1", headers=h).json()["events"]
    assert len(events) == 1
    assert events[0]["start_at"] == "2026-09-02T08:00:00+08:00"
    assert events[0]["end_at"] == "2026-09-02T09:50:00+08:00"
    assert client.get(f"/api/v1/semesters/{s['id']}/timetable?week=2", headers=h).json()["events"] == []


def test_stale_import_and_cross_user_apply_are_rejected(client):
    _, h = register(client)
    _, other = register(client, "student_b")
    s = semester(client, h)
    a = client.post("/api/v1/imports", headers=h, json=imported_payload(s["id"])).json()
    b = client.post("/api/v1/imports", headers=h, json=imported_payload(s["id"])).json()
    url = f"/api/v1/imports/{a['id']}/apply"
    assert client.post(url, headers=other, json={"expected_revision": 0}).status_code == 404
    assert client.post(url, headers=h, json={"expected_revision": 0}).status_code == 200
    assert client.post(f"/api/v1/imports/{b['id']}/apply", headers=h, json={"expected_revision": 0}).status_code == 409


def test_refresh_rotation_logout_and_recovery(client):
    session, h = register(client)
    rotated = client.post("/api/v1/auth/refresh", json={"refresh_token": session["refresh_token"]})
    assert rotated.status_code == 200
    assert client.post("/api/v1/auth/refresh", json={"refresh_token": session["refresh_token"]}).status_code == 401
    current = rotated.json()
    assert client.post("/api/v1/auth/logout", headers={"Authorization": f"Bearer {current['access_token']}"}).status_code == 204
    assert client.get("/api/v1/me", headers={"Authorization": f"Bearer {current['access_token']}"}).status_code == 401
    recovery = {"username": "student_a", "recovery_code": session["recovery_code"], "new_password": "replacement-test-password"}
    assert client.post("/api/v1/auth/recover", json=recovery).status_code == 200
    assert client.post("/api/v1/auth/recover", json=recovery).status_code == 401
    assert client.post("/api/v1/auth/login", json={"username": "student_a", "password": "replacement-test-password"}).status_code == 200


def test_reject_bad_calendar_unknown_periods_and_secret_fields(client):
    _, h = register(client)
    s = semester(client, h)
    payload = imported_payload(s["id"])
    payload["courses"][0]["sections"] = [99]
    assert client.post("/api/v1/imports", headers=h, json=payload).status_code == 422
    payload = imported_payload(s["id"])
    payload["password"] = "must-not-be-accepted"
    response = client.post("/api/v1/imports", headers=h, json=payload)
    assert response.status_code == 422
    assert 'must-not-be-accepted' not in response.text
    payload = imported_payload(s["id"])
    payload["courses"] = []
    assert client.post("/api/v1/imports", headers=h, json=payload).status_code == 422


def test_changed_week_pattern_is_not_imported_as_a_duplicate_course(client):
    _, h = register(client)
    s = semester(client, h)
    payload = imported_payload(s['id'])
    payload['courses'][0]['source_id'] = 'same-teaching-class'
    payload['source'] = 'haut_webview'
    first = client.post('/api/v1/imports', headers=h, json=payload).json()
    assert client.post(f"/api/v1/imports/{first['id']}/apply", headers=h, json={'expected_revision': 0}).status_code == 200
    payload['courses'][0]['weeks'] = [1, 3, 5, 7]
    second = client.post('/api/v1/imports', headers=h, json=payload).json()
    assert second['changed_count'] == 1
    assert second['new_count'] == 0
    assert client.post(f"/api/v1/imports/{second['id']}/apply", headers=h, json={'expected_revision': 1}).status_code == 409
    assert len(client.get(f"/api/v1/semesters/{s['id']}/timetable?week=1", headers=h).json()['events']) == 1


def test_manual_second_weekday_is_a_new_meeting(client):
    _, h = register(client)
    s = semester(client, h)
    payload = imported_payload(s['id'])
    a = client.post('/api/v1/imports', headers=h, json=payload).json()
    client.post(f"/api/v1/imports/{a['id']}/apply", headers=h, json={'expected_revision': 0})
    payload['courses'][0]['weekday'] = 5
    b = client.post('/api/v1/imports', headers=h, json=payload).json()
    assert b['new_count'] == 1 and b['changed_count'] == 0


def test_logout_proof_survives_token_rotation(client):
    initial, _ = register(client)
    # A session-scoped revocation proof is independent of access/refresh rotation.
    assert 'logout_token' in initial
    rotated = client.post('/api/v1/auth/refresh', json={'refresh_token': initial['refresh_token']}).json()
    assert client.post('/api/v1/auth/logout', json={'logout_token': initial['logout_token']}).status_code == 204
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': rotated['refresh_token']}).status_code == 401


@pytest.mark.skipif(not os.environ.get('POSTGRES_TEST_URL'), reason='PostgreSQL concurrency test')
def test_concurrent_confirmations_only_apply_one_snapshot(client):
    _, h = register(client)
    s = semester(client, h)
    batches = [client.post('/api/v1/imports', headers=h, json=imported_payload(s['id'])).json() for _ in range(2)]
    def apply(b):
        return client.post(f"/api/v1/imports/{b['id']}/apply", headers=h, json={'expected_revision': 0}).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(apply, batches))
    assert sorted(results) == [200, 409]
    assert len(client.get(f"/api/v1/semesters/{s['id']}/timetable?week=1", headers=h).json()['events']) == 1
