import os

from fastapi import Request
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session

from .models import Base


def make_engine(url=None, initialize=False):
    url = url or os.environ.get("DATABASE_URL")
    if not url:
        raise RuntimeError("DATABASE_URL is required; use scripts/dev.ps1 or the documented Compose setup")
    kwargs = {"connect_args": {"check_same_thread": False}} if url.startswith("sqlite") else {}
    engine = create_engine(url, pool_pre_ping=True, **kwargs)
    if url.startswith("sqlite"):
        @event.listens_for(engine, "connect")
        def enforce_foreign_keys(connection, _):
            connection.execute("PRAGMA foreign_keys=ON")
    if initialize:
        Base.metadata.create_all(engine)
    return engine


def get_db(request: Request):
    with Session(request.app.state.engine, expire_on_commit=False) as session:
        yield session
