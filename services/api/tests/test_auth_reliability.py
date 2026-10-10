import threading
from concurrent.futures import ThreadPoolExecutor

from fastapi import HTTPException
from sqlalchemy import select, func
from sqlalchemy.orm import Session

from app import auth
from app.models import User, LoginSession
from app.schemas import Credentials, Recovery
from test_foundation import client, register


def test_reset_rejects_login_that_verified_the_previous_password(client, monkeypatch):
    account, _ = register(client)
    verified, resume = threading.Event(), threading.Event()
    original = auth.hasher

    class PausedHasher:
        def verify(self, *args, **kwargs):
            value = original.verify(*args, **kwargs)
            if threading.current_thread().name == 'old-password-login':
                verified.set()
                assert resume.wait(5)
            return value

        def __getattr__(self, name):
            return getattr(original, name)

    monkeypatch.setattr(auth, 'hasher', PausedHasher())
    outcome = []

    def login_old():
        with Session(client.app.state.engine) as db:
            try:
                auth.login(Credentials(username='student_a', password='test-only-password-123'), db)
            except HTTPException as exc:
                outcome.append(exc.status_code)
            else:
                outcome.append(200)

    thread = threading.Thread(target=login_old, name='old-password-login', daemon=True)
    thread.start()
    try:
        assert verified.wait(5)
        with Session(client.app.state.engine) as db:
            auth.recover(Recovery(username='student_a', recovery_code=account['recovery_code'],
                new_password='changed-password123'), db)
    finally:
        resume.set()
        thread.join(5)
    assert not thread.is_alive()
    assert outcome == [401]
    with Session(client.app.state.engine) as db:
        assert db.scalar(select(func.count()).select_from(LoginSession)) == 0
        assert original.verify(db.scalar(select(User)).password_hash, 'changed-password123')


def test_refresh_replays_only_the_same_request_without_extending_expiry(client):
    account, _ = register(client)
    body = {'refresh_token': account['refresh_token']}
    headers = {'Idempotency-Key': 'refresh-operation-one-123456789'}
    first = client.post('/api/v1/auth/refresh', json=body, headers=headers)
    assert first.status_code == 200
    with Session(client.app.state.engine) as db:
        expires = db.scalar(select(LoginSession)).access_expires
    again = client.post('/api/v1/auth/refresh', json=body, headers=headers)
    assert again.status_code == 200
    assert again.json() == first.json()
    with Session(client.app.state.engine) as db:
        row = db.scalar(select(LoginSession))
        assert row.access_expires == expires
        assert account['refresh_token'] not in repr(row.__dict__)
        assert first.json()['refresh_token'] not in repr(row.__dict__)
    assert client.post('/api/v1/auth/refresh', json=body).status_code == 401
    assert client.post('/api/v1/auth/refresh', json=body,
        headers={'Idempotency-Key': 'another-operation-1234567890'}).status_code == 401


def test_refresh_replay_has_a_short_expiration(client, monkeypatch):
    account, _ = register(client)
    body = {'refresh_token': account['refresh_token']}
    headers = {'Idempotency-Key': 'refresh-operation-one-123456789'}
    first = client.post('/api/v1/auth/refresh', json=body, headers=headers)
    assert first.status_code == 200
    now = auth.time.time()
    monkeypatch.setattr(auth.time, 'time', lambda: now + 121)
    assert client.post('/api/v1/auth/refresh', json=body, headers=headers).status_code == 401
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': first.json()['refresh_token']},
        headers={'Idempotency-Key': 'next-operation-123456789012'}).status_code == 200


def test_login_ip_limit_does_not_consume_refresh_or_logout_quota(client):
    account, _ = register(client)
    statuses = [client.post('/api/v1/auth/login', json={
        'username': f'unknown_{i}', 'password': 'incorrect-password'}).status_code for i in range(31)]
    assert statuses[:30] == [401] * 30
    assert statuses[30] == 429
    refreshed = client.post('/api/v1/auth/refresh', json={'refresh_token': account['refresh_token']})
    assert refreshed.status_code == 200
    assert client.post('/api/v1/auth/logout', json={'logout_token': account['logout_token']}).status_code == 204
    for _ in range(3000):
        client.app.state.auth_limits.allow('/api/v1/auth/refresh', 'testclient', 3000)
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': account['refresh_token']}).status_code == 429
    assert client.post('/api/v1/auth/logout', json={'logout_token': account['logout_token']}).status_code == 204


def test_concurrent_refresh_retries_share_one_result(client):
    account, _ = register(client)
    def request():
        return client.post('/api/v1/auth/refresh', json={'refresh_token': account['refresh_token']},
            headers={'Idempotency-Key': 'same-concurrent-operation-123456'})
    # SQLite does not implement row locks; the PostgreSQL run checks concurrency.
    if client.app.state.engine.dialect.name != 'postgresql':
        first, second = request(), request()
    else:
        with ThreadPoolExecutor(max_workers=2) as workers:
            first, second = list(workers.map(lambda _: request(), range(2)))
    assert first.status_code == second.status_code == 200
    assert first.json() == second.json()
