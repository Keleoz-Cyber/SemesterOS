from collections import defaultdict, deque
from contextlib import asynccontextmanager
import time

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy import text

from . import academics, auth, items, capture, planning, schedule_api
from pathlib import Path
from dotenv import dotenv_values
from threading import Lock, BoundedSemaphore
import os
from .database import make_engine


def create_app(database_url: str | None = None, *, initialize: bool = False) -> FastAPI:
    if database_url is None:
        local = dotenv_values(Path(__file__).resolve().parents[3] / '.env')
        for key in ('DATABASE_URL', 'DEEPSEEK_API_KEY', 'DEEPSEEK_MODEL', 'DEEPSEEK_BASE_URL'):
            if local.get(key):
                os.environ.setdefault(key, local[key])
    engine = make_engine(database_url, initialize=initialize)

    @asynccontextmanager
    async def lifespan(app):
        yield
        engine.dispose()

    app = FastAPI(title="SemesterOS", version="0.1.0", lifespan=lifespan)
    app.state.engine = engine
    app.state.capture_attempts = defaultdict(deque)
    app.state.capture_lock = Lock()
    app.state.planner_lock=Lock()
    app.state.planner_users=set()
    app.state.planner_slots=BoundedSemaphore(2)
    attempts = defaultdict(deque)

    @app.middleware("http")
    async def limit_auth(request: Request, call_next):
        if request.url.path.startswith("/api/v1/auth/"):
            now = time.monotonic()
            # A bounded, single-process guard; deployments use one API worker in this batch.
            key = request.client.host if request.client else "unknown"
            if len(attempts) > 4096:
                for old in [k for k, v in attempts.items() if not v or v[-1] < now - 60]:
                    attempts.pop(old, None)
            q = attempts[key]
            while q and q[0] < now - 60:
                q.popleft()
            if len(q) >= 30:
                return JSONResponse({"code": "RATE_LIMITED", "message": "操作过于频繁，请稍后再试"}, status_code=429)
            q.append(now)
        return await call_next(request)

    @app.exception_handler(HTTPException)
    async def domain_error(_, exc):
        detail = exc.detail if isinstance(exc.detail, dict) else {"code": "ERROR", "message": str(exc.detail)}
        return JSONResponse(detail, status_code=exc.status_code)

    @app.exception_handler(RequestValidationError)
    async def validation_error(_, exc):
        # Do not echo rejected input: it may contain passwords or unapproved source fields.
        return JSONResponse({"code": "INVALID_INPUT", "message": "请核对必填项、日期、节次和输入格式",
                             "fields": [".".join(map(str, e["loc"])) for e in exc.errors()]}, status_code=422)

    @app.get("/health")
    def health():
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return {"status": "ok", "version": "0.1.0", "database": engine.dialect.name}

    app.include_router(auth.router, prefix="/api/v1")
    app.include_router(academics.router, prefix="/api/v1")
    app.include_router(items.router, prefix="/api/v1")
    app.include_router(capture.router, prefix="/api/v1")
    app.include_router(planning.router, prefix="/api/v1")
    app.include_router(schedule_api.router, prefix="/api/v1")
    return app
