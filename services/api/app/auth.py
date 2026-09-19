from hashlib import sha256
import secrets
import time

from argon2 import PasswordHasher
from argon2.exceptions import VerificationError
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .database import get_db
from .models import LoginSession, User
from .schemas import Credentials, Logout, Recovery, Refresh

router = APIRouter()
bearer = HTTPBearer(auto_error=False)
hasher = PasswordHasher()
dummy_hash = hasher.hash("invalid-account-constant-password")


def digest(value: str):
    return sha256(value.encode()).hexdigest()


def error(status, code, message):
    raise HTTPException(status, detail={"code": code, "message": message})


def public_user(user):
    return {"id": user.id, "username": user.username}


def mint(db, user, existing=None):
    access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(40)
    row = existing or LoginSession(user_id=user.id)
    logout = secrets.token_urlsafe(32) if existing is None else None
    if logout:
        row.logout_hash = digest(logout)
    row.access_hash, row.refresh_hash = digest(access), digest(refresh)
    row.access_expires = int(time.time()) + 900
    row.refresh_expires = int(time.time()) + 7 * 86400
    db.add(row)
    return {"user": public_user(user), "access_token": access, "refresh_token": refresh, "expires_in": 900,
            **({"logout_token": logout} if logout else {})}


def current_session(credentials: HTTPAuthorizationCredentials | None = Depends(bearer), db: Session = Depends(get_db)):
    row = None if credentials is None else db.scalar(select(LoginSession).where(LoginSession.access_hash == digest(credentials.credentials)))
    if row is None or row.access_expires <= time.time():
        error(401, "SESSION_EXPIRED", "请重新登录学期OS")
    return row


def current_user(login: LoginSession = Depends(current_session), db: Session = Depends(get_db)):
    return db.get(User, login.user_id)


@router.post("/auth/register", status_code=201)
def register(body: Credentials, db: Session = Depends(get_db)):
    code = secrets.token_urlsafe(24)
    user = User(username=body.username, password_hash=hasher.hash(body.password), recovery_hash=digest(code))
    db.add(user)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        error(409, "USERNAME_EXISTS", "此用户名不可用，请换一个")
    response = mint(db, user)
    db.commit()
    return {**response, "recovery_code": code}


@router.post("/auth/login")
def login(body: Credentials, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.username == body.username))
    try:
        hasher.verify(user.password_hash if user else dummy_hash, body.password)
    except VerificationError:
        error(401, "INVALID_CREDENTIALS", "用户名或密码不正确")
    if user is None:
        error(401, "INVALID_CREDENTIALS", "用户名或密码不正确")
    response = mint(db, user)
    db.commit()
    return response


@router.post("/auth/refresh")
def refresh(body: Refresh, db: Session = Depends(get_db)):
    row = db.scalar(select(LoginSession).where(LoginSession.refresh_hash == digest(body.refresh_token)).with_for_update())
    if row is None or row.refresh_expires <= time.time():
        error(401, "SESSION_EXPIRED", "请重新登录学期OS")
    response = mint(db, db.get(User, row.user_id), row)
    db.commit()
    return response


@router.post("/auth/logout", status_code=204)
def logout(body: Logout | None = None, credentials: HTTPAuthorizationCredentials | None = Depends(bearer), db: Session = Depends(get_db)):
    if body:
        row = db.scalar(select(LoginSession).where(LoginSession.logout_hash == digest(body.logout_token)).with_for_update())
    elif credentials:
        row = db.scalar(select(LoginSession).where(LoginSession.access_hash == digest(credentials.credentials)).with_for_update())
    else:
        error(401, "SESSION_REQUIRED", "需要退出凭证")
    if row is not None:
        db.delete(row)
    db.commit()


@router.post("/auth/recover")
def recover(body: Recovery, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.username == body.username.lower()).with_for_update())
    if user is None or not secrets.compare_digest(user.recovery_hash, digest(body.recovery_code)):
        error(401, "INVALID_RECOVERY", "用户名或恢复码不正确")
    code = secrets.token_urlsafe(24)
    user.password_hash, user.recovery_hash = hasher.hash(body.new_password), digest(code)
    db.execute(delete(LoginSession).where(LoginSession.user_id == user.id))
    db.commit()
    return {"recovery_code": code}


@router.get("/me")
def me(user: User = Depends(current_user)):
    return public_user(user)
