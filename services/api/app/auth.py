from hashlib import sha256
import base64
import hmac
import json
import secrets
import time
from typing import Annotated

from argon2 import PasswordHasher
from argon2.exceptions import VerificationError
from fastapi import APIRouter, Depends, HTTPException, Request, Header
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import delete, select, or_
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
    return {"id": user.id, "username": user.username, "is_demo":user.username.startswith('demo_')}


def limit_account(request, operation, principal, count=10):
    if request is not None and not request.app.state.auth_limits.allow(operation, principal, count):
        error(429, 'RATE_LIMITED', '操作过于频繁，请稍后再试')


def clear_refresh_replay(row):
    row.refresh_replay_hash = row.refresh_request_hash = row.refresh_replay_nonce = None
    row.refresh_replay_until = 0


def replay_tokens(old_token, row, request_id):
    # HMAC is a PRF keyed by the client's high-entropy random refresh secret.
    # The server nonce makes outputs unpredictable without the stored receipt.
    # Only hashes and nonce persist: no plaintext/encrypted bearer tokens or new server key.
    context = json.dumps([row.id, row.refresh_replay_nonce, request_id], separators=(',', ':')).encode()
    def derive(purpose):
        raw = hmac.new(old_token.encode(), purpose + b'\0' + context, sha256).digest()
        return base64.urlsafe_b64encode(raw).decode().rstrip('=')
    return derive(b'shiri-access-v1'), derive(b'shiri-refresh-v1')


def session_result(user, access, refresh):
    return {'user': public_user(user), 'access_token': access, 'refresh_token': refresh, 'expires_in': 900}


def mint(db, user, existing=None):
    access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(40)
    row = existing or LoginSession(user_id=user.id)
    logout = secrets.token_urlsafe(32) if existing is None else None
    if logout:
        row.logout_hash = digest(logout)
    row.access_hash, row.refresh_hash = digest(access), digest(refresh)
    row.access_expires = int(time.time()) + 900
    row.refresh_expires = int(time.time()) + 7 * 86400
    clear_refresh_replay(row)
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
def register(body: Credentials, db: Session = Depends(get_db), request: Request = None):
    limit_account(request, 'register-account', body.username)
    if body.username.startswith('demo_'):error(422,'RESERVED_USERNAME','此用户名用于体验账号，请换一个用户名')
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


@router.post('/auth/demo',status_code=201)
def demo(db:Session=Depends(get_db)):
    """Create a fresh, normally authenticated owner with clearly labelled samples."""
    from datetime import timedelta
    from .reminder_rules import utcnow,SHANGHAI
    from .models import Semester,ImportBatch,CourseMeeting,UserProfile
    from .academics import identity
    from .schemas import CourseInput
    from .item_schemas import ItemCreate
    from .items import create_item_command
    now=utcnow();today=now.astimezone(SHANGHAI).date();monday=today-timedelta(days=today.weekday())
    user=User(username='demo_'+secrets.token_hex(10),password_hash=hasher.hash(secrets.token_urlsafe(32)),
        recovery_hash=digest(secrets.token_urlsafe(32)))
    db.add(user);db.flush()
    s=Semester(user_id=user.id,name='体验学期 · 示例数据',first_monday=str(monday),total_weeks=16,
        periods=[{'number':1,'start':'08:00','end':'08:50'},{'number':2,'start':'09:00','end':'09:50'},
                 {'number':3,'start':'14:00','end':'14:50'},{'number':4,'start':'15:00','end':'15:50'}])
    db.add(s);db.flush()
    tomorrow=today+timedelta(days=1)
    demo_courses=[CourseInput(title='示例 · 大学英语',teacher='示例教师',location='教学楼 A201',
        weekday=today.isoweekday(),weeks=list(range(1,17)),sections=[3,4]).model_dump(mode='json'),
        CourseInput(title='示例 · 高等数学',teacher='示例教师',location='教学楼 B302',
        weekday=tomorrow.isoweekday(),weeks=list(range(1,17)),sections=[1,2]).model_dump(mode='json')]
    batch=ImportBatch(user_id=user.id,semester_id=s.id,source='manual',source_term='体验示例',
        courses=demo_courses,base_revision=0,receipt={'sample':True})
    db.add(batch);db.flush()
    for course in demo_courses:
        db.add(CourseMeeting(user_id=user.id,semester_id=s.id,identity_key=identity(course),payload=course,source_batch_id=batch.id))
    db.add(UserProfile(user_id=user.id,payload={'onboarding_completed':True}))
    create_item_command(db,user,ItemCreate(semester_id=s.id,kind='assignment',title='示例 · 整理实验报告',
        certainty='formal',remaining_minutes=90,start_policy='now',
        time={'precision':'date','date':str(today+timedelta(days=1))},
        notes='这是体验数据，可自由修改；退出体验后可登录自己的账号。',category_id='study'))
    create_item_command(db,user,ItemCreate(semester_id=s.id,kind='task',title='示例 · 汇总班级材料',
        certainty='formal',details={'responsibility':'班委收集并汇总材料','materials':['申请表'],
        'submission_channel':'示例班级群'},category_id='affairs'))
    exam_day=monday+timedelta(days=9)
    create_item_command(db,user,ItemCreate(semester_id=s.id,kind='exam',title='示例 · 大学英语测验',
        certainty='formal',location='教学楼 A201',category_id='study',
        time={'precision':'exact','at':f'{exam_day}T10:00:00+08:00','end_at':f'{exam_day}T11:00:00+08:00'},
        notes='这是演示考试，可用于体验考试日程和提醒；不是真实学校通知。',
        reminders=[{'mode':'relative','lead_minutes':1440}]))
    response=mint(db,user);db.commit()
    return {**response,'is_demo':True,'semester_id':s.id}


@router.post("/auth/login")
def login(body: Credentials, db: Session = Depends(get_db), request: Request = None):
    limit_account(request, 'login-account', body.username)
    user = db.scalar(select(User).where(User.username == body.username))
    observed = user.password_hash if user else dummy_hash
    try:
        hasher.verify(observed, body.password)
    except VerificationError:
        error(401, "INVALID_CREDENTIALS", "用户名或密码不正确")
    if user is None:
        error(401, "INVALID_CREDENTIALS", "用户名或密码不正确")
    user = db.scalar(select(User).where(User.id == user.id).with_for_update()
        .execution_options(populate_existing=True))
    if user is None or not secrets.compare_digest(user.password_hash, observed):
        error(401, 'INVALID_CREDENTIALS', '密码已更新，请使用新密码重新登录')
    response = mint(db, user)
    db.commit()
    return response


@router.post("/auth/refresh")
def refresh(body: Refresh, db: Session = Depends(get_db), request: Request = None,
            idempotency_key: Annotated[str | None, Header(min_length=20, max_length=120)] = None):
    token_hash = digest(body.refresh_token)
    row = db.scalar(select(LoginSession).where(or_(LoginSession.refresh_hash == token_hash,
        LoginSession.refresh_replay_hash == token_hash)).with_for_update().execution_options(populate_existing=True))
    if row is None or row.refresh_expires <= time.time():
        error(401, "SESSION_EXPIRED", "请重新登录学期OS")
    limit_account(request, 'refresh-session', row.id, 30)
    user = db.get(User, row.user_id)
    if user is None:
        error(401, 'SESSION_EXPIRED', '请重新登录学期OS')
    if row.refresh_hash != token_hash:
        if not idempotency_key or row.refresh_replay_until <= time.time() or not secrets.compare_digest(
                row.refresh_request_hash or '', digest(idempotency_key)):
            error(401, 'SESSION_EXPIRED', '请重新登录学期OS')
        access, new_refresh = replay_tokens(body.refresh_token, row, idempotency_key)
        if digest(access) != row.access_hash or digest(new_refresh) != row.refresh_hash:
            error(401, 'SESSION_EXPIRED', '请重新登录学期OS')
        return session_result(user, access, new_refresh)
    if idempotency_key:
        row.refresh_replay_hash = token_hash
        row.refresh_request_hash = digest(idempotency_key)
        row.refresh_replay_nonce = secrets.token_hex(32)
        row.refresh_replay_until = int(time.time()) + 120
        access, new_refresh = replay_tokens(body.refresh_token, row, idempotency_key)
        row.access_hash, row.refresh_hash = digest(access), digest(new_refresh)
        row.access_expires = int(time.time()) + 900
        row.refresh_expires = int(time.time()) + 7 * 86400
        response = session_result(user, access, new_refresh)
    else:
        response = mint(db, user, row)
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
def recover(body: Recovery, db: Session = Depends(get_db), request: Request = None):
    limit_account(request, 'recover-account', body.username.lower())
    user = db.scalar(select(User).where(User.username == body.username.lower()).with_for_update()
        .execution_options(populate_existing=True))
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
