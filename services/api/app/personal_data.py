"""Owner-scoped search, portable records, feedback and explicit account erasure."""
from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import select, delete, or_, update
from sqlalchemy.orm import Session
from argon2.exceptions import VerificationError
from .auth import current_user, error, hasher
from .database import get_db
from .academics import owned_semester
from .models import (Base, User, Semester, CourseMeeting, StudyItem, CalendarEvent,
    MediaSource, AgentThread, AgentRun, CalendarTag, AccountErasure, UserFeedback)
from .reminder_rules import utcnow

router = APIRouter()


def excerpt(text, needle):
    text = str(text or '')
    position = text.casefold().find(needle.casefold())
    start = max(0, position - 25)
    return ('…' if start else '') + text[start:start + 150] + ('…' if len(text) > start + 150 else '')


@router.get('/semesters/{sid}/search')
def search(sid: str, q: str = Query(min_length=1, max_length=100),
           kind: str = Query('all', pattern='^(all|course|item|event|source)$'),
           offset: int = Query(0, ge=0, le=10000), limit: int = Query(30, ge=1, le=50),
           user: User = Depends(current_user), db: Session = Depends(get_db)):
    owned_semester(db, user, sid)
    q = q.strip()
    if not q: return {'results': [], 'has_more': False}
    pattern = '%' + q.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%'
    result = []
    # Fixed kind/id ordering makes pagination stable without storing private search history.
    for name, model in [('course', CourseMeeting), ('event', CalendarEvent), ('item', StudyItem), ('source', MediaSource)]:
        if kind not in ('all', name): continue
        fields = [model.text, model.original_text] if name == 'source' else [
            model.payload[k].as_string() for k in ('title', 'location', 'source_text', 'notes')]
        query = select(model).where(model.user_id == user.id, model.semester_id == sid,
            or_(*(field.ilike(pattern, escape='\\') for field in fields))).order_by(model.id).limit(offset + limit + 1)
        for row in db.scalars(query):
            payload = {'title': '图片通知' if row.kind == 'image' else '语音通知',
                       'source_text': row.text or row.original_text} if name == 'source' else row.payload
            match = next((str(payload.get(k) or '') for k in ('title', 'location', 'source_text', 'notes')
                          if q.casefold() in str(payload.get(k) or '').casefold()), '')
            result.append({'id': row.id, 'kind': name, 'title': payload.get('title', ''),
                'location': payload.get('location', ''), 'time': payload.get('time', {}),
                'lifecycle': getattr(row, 'lifecycle', 'active'), 'excerpt': excerpt(match, q)})
    return {'results': result[offset:offset + limit], 'has_more': len(result) > offset + limit}


@router.get('/me/export')
def export_data(user: User = Depends(current_user), db: Session = Depends(get_db)):
    # Explicit allowlist: never export credential hashes, leases, model traces or idempotency secrets.
    fields = {
        'semesters': ['id', 'name', 'first_monday', 'total_weeks', 'periods', 'revision'],
        'course_meetings': ['id', 'semester_id', 'payload'],
        'calendar_events': ['id', 'semester_id', 'payload', 'lifecycle', 'version'],
        'study_items': ['id', 'semester_id', 'payload', 'lifecycle', 'version'],
        'plan_blocks': ['id', 'semester_id', 'item_id', 'start_at', 'end_at', 'status'],
        'study_availability': ['semester_id', 'payload'],
        'user_profiles': ['payload'],
        'calendar_tags': ['id', 'name'],
        'media_sources': ['id', 'semester_id', 'kind', 'text', 'original_text', 'reference_at', 'file_deleted'],
        'reminder_rules': ['id', 'item_id', 'payload', 'enabled'],
        'reality_changes': ['id', 'semester_id', 'payload', 'applied_revision', 'created_at'],
        'calendar_event_revisions': ['event_id', 'version', 'snapshot', 'reason', 'created_at'],
        'item_revisions': ['item_id', 'version', 'snapshot', 'reason', 'created_at'],
        'progress_entries': ['item_id', 'payload', 'created_at'],
        'user_feedback': ['id', 'payload', 'created_at'],
    }
    data = {}
    for name, names in fields.items():
        table = Base.metadata.tables[name]
        columns = [table.c[n] for n in names if n in table.c]
        data[name] = [dict(r) for r in db.execute(select(*columns).where(table.c.user_id == user.id)).mappings()]
    threads = list(db.scalars(select(AgentThread).where(AgentThread.user_id == user.id, AgentThread.deleted_at.is_(None))))
    data['conversations'] = [{'title': t.title, 'semester_id': t.semester_id,
        'messages': [{'text': r.text, 'answer': r.state.get('answer', ''), 'status': r.status, 'created_at': r.created_at}
            for r in db.scalars(select(AgentRun).where(AgentRun.user_id == user.id, AgentRun.thread_id == t.id).order_by(AgentRun.created_at))]}
        for t in threads]
    return {'format': 'shiri-personal-data', 'version': 1, 'exported_at': utcnow().isoformat(),
            'username': user.username, 'data': data,
            'note': '附件识别文字已导出；图片和录音文件请在来源详情中查看。此文件可能包含个人信息，请妥善保存。'}


class EraseAccount(BaseModel):
    password: str = Field(min_length=1, max_length=200)
    confirmation: str


@router.post('/me/erase')
def erase_account(body: EraseAccount, request: Request,
                  user: User = Depends(current_user), db: Session = Depends(get_db)):
    locked = db.scalar(select(User).where(User.id == user.id).with_for_update().execution_options(populate_existing=True))
    if locked is None: error(401, 'SESSION_EXPIRED', '账号已退出')
    if body.confirmation != '删除我的账号': error(422, 'CONFIRM_REQUIRED', '请输入“删除我的账号”确认')
    try: hasher.verify(locked.password_hash, body.password)
    except VerificationError: error(403, 'PASSWORD_INCORRECT', '密码不正确，账号未删除')
    # Lock semester rows before removing descendants; workers use these same locks.
    list(db.scalars(select(Semester).where(Semester.user_id == user.id).order_by(Semester.id).with_for_update()))
    keys = list(db.scalars(select(MediaSource.storage_key).where(MediaSource.user_id == user.id)))
    cleanup = Base.metadata.tables['media_cleanup_jobs']
    keys += list(db.scalars(select(cleanup.c.storage_key).where(cleanup.c.user_id == user.id)))
    if keys: db.add(AccountErasure(storage_keys=list(set(keys)), created_at=utcnow().isoformat()))
    db.flush()
    db.execute(update(CalendarTag).where(CalendarTag.user_id == user.id).values(merged_into=None))
    for table in reversed(Base.metadata.sorted_tables):
        if 'user_id' in table.c:
            db.execute(delete(table).where(table.c.user_id == user.id))
    db.execute(delete(User).where(User.id == user.id))
    db.commit()
    from .semester_management import drain_media_cleanup
    pending = drain_media_cleanup(db, request.app.state.media_root)
    return {'deleted': True, 'media_files_pending_cleanup': pending}


class FeedbackInput(BaseModel):
    category: str = Field(pattern='^(wrong_answer|save|reminder|interface|other)$')
    description: str = Field(min_length=3, max_length=2000)
    expected: str = Field(default='', max_length=1000)
    app_version: str = Field(default='', max_length=40)


@router.post('/me/feedback', status_code=201)
def feedback(body: FeedbackInput, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = UserFeedback(user_id=user.id, payload=body.model_dump(), created_at=utcnow().isoformat())
    db.add(row); db.commit()
    return {'id': row.id, 'message': '反馈已保存，谢谢你提供具体情况'}
