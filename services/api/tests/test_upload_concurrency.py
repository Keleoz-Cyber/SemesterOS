import asyncio
import threading
import time

import httpx
import pytest
from sqlalchemy.orm import Session
from sqlalchemy import select

from app import media, agent_media
from app.models import Semester
from test_foundation import client, register, semester
from test_media import png


@pytest.mark.parametrize('assistant', [False, True])
def test_upload_obeys_semester_before_user_lock_order(client, tmp_path, monkeypatch, assistant):
    if client.app.state.engine.dialect.name != 'postgresql':
        pytest.skip('requires real PostgreSQL row locks')
    from concurrent.futures import ThreadPoolExecutor
    from sqlalchemy import text
    from app.models import User
    account, headers = register(client)
    term = semester(client, headers)
    client.app.state.media_root = tmp_path / 'media'
    reached = threading.Event()
    original = media.owned_semester
    def observe(db, user, sid, lock=False):
        if lock: reached.set()
        return original(db, user, sid, lock)
    monkeypatch.setattr(media, 'owned_semester', observe)
    monkeypatch.setattr(agent_media, 'owned_semester', observe)
    with Session(client.app.state.engine) as holding:
        holding.scalar(select(Semester).where(Semester.id == term['id']).with_for_update())
        holding.execute(text("SET LOCAL lock_timeout = '800ms'"))
        def upload():
            if assistant:
                return client.post('/api/v1/agent/media-runs', headers=headers,
                    data={'semester_id': term['id'], 'client_request_id': 'quota-order', 'kind': 'image'},
                    files={'file': ('notice.png', png(), 'image/png')})
            return client.post(f"/api/v1/semesters/{term['id']}/sources?kind=image",
                headers={**headers, 'Idempotency-Key': 'quota-order'}, content=png())
        with ThreadPoolExecutor(max_workers=1) as workers:
            uploading = workers.submit(upload)
            try:
                assert reached.wait(4)
                # Tag/item writes already own Semester and then lock User.
                # Upload must not own User while blocked on this Semester.
                holding.scalar(select(User).where(User.id == account['user']['id']).with_for_update())
                holding.commit()
            finally:
                holding.rollback()
            response = uploading.result(timeout=5)
    assert response.status_code == (202 if assistant else 201), response.text


@pytest.fixture
def anyio_backend():
    return 'asyncio'


@pytest.mark.anyio
@pytest.mark.parametrize('assistant', [False, True])
async def test_upload_database_checks_run_off_event_loop_with_own_session(client, tmp_path, monkeypatch, assistant):
    _, headers = register(client)
    term = semester(client, headers)
    client.app.state.media_root = tmp_path / 'media'
    loop_thread = threading.get_ident()
    original = media.owned_semester
    calls = []

    def checked(db, *args, **kwargs):
        assert threading.get_ident() != loop_thread, 'sync database call blocked event loop'
        calls.append((id(db), threading.get_ident()))
        return original(db, *args, **kwargs)

    monkeypatch.setattr(media, 'owned_semester', checked)
    monkeypatch.setattr(agent_media, 'owned_semester', checked)
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=client.app), base_url='http://test') as api:
        if assistant:
            result = await api.post('/api/v1/agent/media-runs', headers=headers,
                data={'semester_id': term['id'], 'client_request_id': 'isolated-media', 'kind': 'image'},
                files={'file': ('notice.png', png(), 'image/png')})
            assert result.status_code == 202, result.text
        else:
            result = await api.post(f"/api/v1/semesters/{term['id']}/sources?kind=image",
                headers={**headers, 'Idempotency-Key': 'isolated-source'}, content=png())
            assert result.status_code == 201, result.text
    assert len(calls) >= 2


@pytest.mark.anyio
@pytest.mark.parametrize('assistant', [False, True])
async def test_postgres_upload_lock_wait_does_not_block_health(client, tmp_path, assistant):
    if client.app.state.engine.dialect.name != 'postgresql':
        pytest.skip('requires real PostgreSQL row locks')
    _, headers = register(client)
    term = semester(client, headers)
    client.app.state.media_root = tmp_path / 'media'
    locked, release = threading.Event(), threading.Event()
    def hold_lock():
        with Session(client.app.state.engine) as db:
            db.scalar(select(Semester).where(Semester.id == term['id']).with_for_update())
            locked.set()
            release.wait(2)  # Bounded even if the event loop regresses.
            db.rollback()
    holder = threading.Thread(target=hold_lock, daemon=True)
    holder.start()
    assert locked.wait(3)
    try:
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=client.app), base_url='http://test') as api:
            started = time.monotonic()
            async def upload():
                if assistant:
                    return await api.post('/api/v1/agent/media-runs', headers=headers,
                        data={'semester_id': term['id'], 'client_request_id': 'lock-wait', 'kind': 'image'},
                        files={'file': ('notice.png', png(), 'image/png')})
                return await api.post(f"/api/v1/semesters/{term['id']}/sources?kind=image",
                    headers={**headers, 'Idempotency-Key': 'lock-wait'}, content=png())
            task = asyncio.create_task(upload())
            await asyncio.sleep(.1)
            health = await api.get('/health')
            assert health.status_code == 200
            assert time.monotonic() - started < 1, 'row-lock wait blocked unrelated requests'
            release.set()
            result = await asyncio.wait_for(task, 4)
            assert result.status_code == (202 if assistant else 201), result.text
    finally:
        release.set(); holder.join(3)
