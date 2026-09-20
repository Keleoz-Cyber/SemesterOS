from collections import defaultdict, deque
from datetime import datetime, timezone
from threading import Lock
import time
from typing import Literal

from fastapi import APIRouter, Depends, Request
from pydantic import Field, ValidationError, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from .academics import owned_semester
from .auth import current_user, error
from .database import get_db
from .item_schemas import ItemFields, ItemTime
from .models import CourseMeeting, TextCandidate, User
from .reminder_rules import utcnow
from .schemas import Input
from .text_model import deepseek_text

router = APIRouter()


class CaptureInput(Input):
    semester_id: str = Field(min_length=1, max_length=36)
    text: str = Field(min_length=1, max_length=10000)
    reference_at: datetime = Field(default_factory=utcnow)
    source_id:str|None=Field(default=None,max_length=36)
    source_version:int|None=Field(default=None,ge=1)

    @field_validator('reference_at')
    @classmethod
    def aware(cls, value):
        return ItemTime.aware(value)


class Parsed(Input):
    intent: Literal['create_item', 'update_task', 'update_reminder', 'report_change', 'request_plan', 'clarify', 'unsupported']
    item: dict | None = None
    evidence: dict[str, str] = Field(default_factory=dict, max_length=30)
    inferred_fields: list[str] = Field(default_factory=list, max_length=30)
    questions: list[str] = Field(default_factory=list, max_length=12)


@router.post('/capture/text')
def capture_text(body: CaptureInput, request: Request, user: User = Depends(current_user), db: Session = Depends(get_db)):
    s = owned_semester(db, user, body.semester_id)
    source=None
    if body.source_id:
        from .media import owned_source,version
        source=owned_source(db,user,body.source_id)
        if source.semester_id!=s.id:error(404,'NOT_FOUND','来源不属于当前学期')
        version(source,body.source_version)
        if source.status in ('queued','running') or source.text!=body.text or source.reference_at!=body.reference_at.isoformat():
            error(409,'SOURCE_STALE','请先保存并核对当前来源文稿，再解析')
    admission(request,user)
    courses = [{'id': c.id, 'title': c.payload['title'], 'teacher': c.payload['teacher']}
        for c in db.scalars(select(CourseMeeting).where(CourseMeeting.user_id == user.id,
            CourseMeeting.semester_id == s.id))]
    model = getattr(request.app.state, 'text_model', deepseek_text)
    raw, metadata = model(body.text, body.reference_at.isoformat(), courses)
    try:
        parsed = Parsed.model_validate(raw)
        if any(quote not in body.text for quote in parsed.evidence.values()):
            raise ValueError('证据未出现在原文')
        item = None
        if parsed.intent == 'create_item':
            if parsed.item is None:
                raise ValueError('新增缺少事项')
            if isinstance(parsed.item.get('time'), dict):
                parsed.item['time']['day_end_confirmed'] = False
            item = ItemFields.model_validate({**parsed.item, 'semester_id': s.id}).model_dump(mode='json')
            if item['course_id'] and item['course_id'] not in {c['id'] for c in courses}:
                raise ValueError('课程不在白名单')
            if item['time']['week'] and item['time']['week'] > s.total_weeks:
                raise ValueError('周次越界')
            item['time']['day_end_confirmed'] = False
            item['start_policy'] = 'unconfirmed'
            item['earliest_start_at'] = None
            item['source_text'] = body.text
            item['candidate_id'] = None
            item['source_id'] = None
            for key in ('title', 'time', 'remaining_minutes', 'course_id', 'certainty'):
                if key not in parsed.evidence and key not in parsed.inferred_fields and item.get(key) is not None:
                    parsed.inferred_fields.append(key)
        elif parsed.item is not None:
            raise ValueError('非新增不能附带写入事项')
    except (ValidationError, ValueError, TypeError):
        error(502, 'INVALID_MODEL_OUTPUT', 'AI整理的内容还不完整，原文已保留。请重试或手动填写')
    data = {'intent': parsed.intent, 'item': item, 'evidence': parsed.evidence,
            'inferred_fields': parsed.inferred_fields, 'questions': parsed.questions,
            'reference_at': body.reference_at.isoformat(), 'metadata': metadata, 'review_state': 'pending'}
    if source is not None:
        db.refresh(source,with_for_update=True)
        version(source,body.source_version)
        data['media_source']={'id':source.id,'version':source.version,'kind':source.kind,'original_text':source.original_text,
            'corrected_text':body.text,'recognition':source.metadata_json}
        if item is not None:item['source_id']=source.id
    candidate = TextCandidate(user_id=user.id, semester_id=s.id, source_text=body.text,
        payload=data, created_at=utcnow().isoformat())
    db.add(candidate)
    db.commit()
    return {**data, 'id': candidate.id}


def admission(request,user):
    # Per-user rate guard; no source text or secret material is logged.
    with request.app.state.capture_lock:
        attempts = request.app.state.capture_attempts
        now = time.monotonic()
        for owner in list(attempts):
            while attempts[owner] and attempts[owner][0] < now - 60:
                attempts[owner].popleft()
            if not attempts[owner]:
                del attempts[owner]
        q = attempts[user.id]
        if len(q) >= 8:
            error(429, 'RATE_LIMITED', '解析请求较多，请稍后再试')
        q.append(now)
