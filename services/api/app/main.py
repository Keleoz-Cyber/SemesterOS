from collections import defaultdict, deque
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy import text

from . import calendar_events
from . import agent_api
from . import agent_media
from . import user_profiles
from . import insights
from . import briefs
from . import taxonomy
from . import academics, auth, items, capture, planning, schedule_api, changes, change_parser, centers, exam_planning, media, operations, semester_management, course_management
from dotenv import dotenv_values
from threading import Lock, BoundedSemaphore
import os
from .database import make_engine
from .runtime_paths import PROJECT_ROOT
from .version import VERSION


def create_app(database_url: str | None = None, *, initialize: bool = False) -> FastAPI:
    if database_url is None:
        local = dotenv_values(PROJECT_ROOT / '.env')
        for key in ('DATABASE_URL', 'DEEPSEEK_API_KEY', 'DEEPSEEK_MODEL', 'DEEPSEEK_BASE_URL','MEDIA_ROOT','SENSEVOICE_MODEL_DIR','MEDIA_WORKER_MODE'):
            if local.get(key):
                os.environ.setdefault(key, local[key])
    engine = make_engine(database_url, initialize=initialize)

    @asynccontextmanager
    async def lifespan(app):
        import subprocess,sys
        worker=None
        if database_url is None or os.environ.get('MEDIA_ROOT'):
            from sqlalchemy.orm import Session
            with Session(app.state.engine) as cleanup_db:
                semester_management.drain_media_cleanup(cleanup_db, app.state.media_root)
        if database_url is None and os.environ.get('MEDIA_WORKER_MODE','managed')=='managed':
            worker=subprocess.Popen([sys.executable,'-m','app.media_worker'],env={**os.environ,'MEDIA_PARENT_PID':str(os.getpid())},
                creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        try:yield
        finally:
            if worker is not None and worker.poll() is None:
                worker.terminate()
                try:worker.wait(timeout=5)
                except subprocess.TimeoutExpired:worker.kill();worker.wait()
            engine.dispose()

    app = FastAPI(title="SemesterOS", version=VERSION, lifespan=lifespan)
    app.state.engine = engine
    from .media_files import root
    app.state.media_root=root()
    app.state.capture_attempts = defaultdict(deque)
    app.state.capture_lock = Lock()
    app.state.planner_lock=Lock()
    app.state.planner_users=set()
    app.state.planner_slots=BoundedSemaphore(2)
    from .auth_limits import AuthLimits
    app.state.auth_limits = AuthLimits()

    @app.middleware("http")
    async def limit_auth(request: Request, call_next):
        path = request.url.path
        high_risk = {'/api/v1/auth/login', '/api/v1/auth/register', '/api/v1/auth/recover', '/api/v1/auth/demo'}
        # A coarse, separate maintenance limit still bounds invalid-token abuse,
        # without making a whole campus share the login quota.
        limit = 30 if path in high_risk else 3000 if path in {
            '/api/v1/auth/refresh', '/api/v1/auth/logout'} else None
        if request.method == 'POST' and limit is not None:
            key = request.client.host if request.client else 'unknown'
            if not app.state.auth_limits.allow(path, key, limit):
                return JSONResponse({"code": "RATE_LIMITED", "message": "操作过于频繁，请稍后再试"}, status_code=429)
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
        return {"status": "ok", "version": VERSION, "database": engine.dialect.name}

    app.include_router(calendar_events.router, prefix="/api/v1")
    app.include_router(agent_api.router, prefix="/api/v1")
    app.include_router(agent_media.router, prefix="/api/v1")
    app.include_router(user_profiles.router, prefix="/api/v1")
    app.include_router(insights.router, prefix="/api/v1")
    app.include_router(briefs.router, prefix="/api/v1")
    app.include_router(taxonomy.router, prefix="/api/v1")
    app.include_router(auth.router, prefix="/api/v1")
    app.include_router(academics.router, prefix="/api/v1")
    app.include_router(semester_management.router, prefix="/api/v1")
    app.include_router(course_management.router, prefix="/api/v1")
    app.include_router(items.router, prefix="/api/v1")
    app.include_router(capture.router, prefix="/api/v1")
    app.include_router(planning.router, prefix="/api/v1")
    app.include_router(schedule_api.router, prefix="/api/v1")
    app.include_router(changes.router, prefix="/api/v1")
    app.include_router(change_parser.router, prefix="/api/v1")
    app.include_router(centers.router, prefix="/api/v1")
    app.include_router(exam_planning.router, prefix="/api/v1")
    app.include_router(media.router, prefix="/api/v1")
    app.include_router(operations.router, prefix="/api/v1")
    return app
