"""Deterministic edits reuse preview validation and never apply the change."""
from copy import deepcopy
from fastapi import APIRouter, Depends
from pydantic import Field
from sqlalchemy.orm import Session
from .schemas import Input
from .item_schemas import ItemTime
from .auth import current_user, error
from .database import get_db
from .models import User
from .academics import owned_semester, fingerprint
from .agent_api import owned_run, owned_thread, public_run
from .agent_tools import execute_tool, EventPatch, ItemDraft, ItemPatch, preview_source_guard
from .agent_provenance import pending_draft

router = APIRouter()


class PreviewEdit(Input):
    token: str
    title: str | None = Field(default=None, min_length=1, max_length=120)
    location: str | None = Field(default=None, max_length=120)
    time: ItemTime | None = None


@router.patch('/agent/runs/{rid}/preview')
def edit_preview(rid: str, body: PreviewEdit, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = owned_run(db, user, rid, True)
    old = deepcopy(row.state.get('preview') or {})
    if row.status != 'needs_confirmation' or old.get('token') != body.token:
        error(409, 'PREVIEW_STALE', '预览已更新，请重新打开')
    if old.get('kind') not in ('event', 'item') or old.get('action') not in ('create', 'update'):
        error(422, 'EDIT_UNSUPPORTED', '请使用这类安排的专用修改入口')
    s = owned_semester(db, user, old['semester_id'], lock=True)
    if s.revision != old['expected_revision']: error(409, 'SNAPSHOT_STALE', '安排已变化，请重新整理预览')
    preview_source_guard(db, user, s.id, old)
    changes = body.model_dump(mode='json', exclude_unset=True, exclude={'token'})
    if not changes or any(v is None for v in changes.values()): error(422, 'INVALID_FIELDS', '请选择要修改的字段')
    state = deepcopy(row.state)
    state.pop('preview', None)
    state['pending_draft'] = pending_draft(row)
    state['current_user_text'] = '用户在预览中直接修改字段'
    schema = EventPatch if old['kind'] == 'event' else ItemDraft if old['action'] == 'create' else ItemPatch
    fields = {k: v for k,v in old['after'].items() if k in schema.model_fields}
    if 'tags' in fields: fields['tags'] = [t['name'] if isinstance(t, dict) else t for t in fields['tags']]
    fields.update(changes)
    if old['kind'] == 'event':
        tool, args = 'prepare_event', {'action': old['action'], 'event_id': old.get('target_id'), 'fields': fields}
    elif old['action'] == 'create': tool, args = 'prepare_item', {'fields': fields}
    else: tool, args = 'prepare_item_change', {'item_id': old['target_id'], 'fields': fields}
    if old['action'] == 'create': args['draft_run_id'] = rid
    if old.get('target_id'):
        state['known_ids'] = list(set(state.get('known_ids', []) + [old['target_id']]))
    execute_tool(tool, args, db, user, owned_thread(db, user, row.thread_id), state, '用户在预览中直接修改字段')
    preview = state['preview']
    preview['previous_draft'] = {k: old['after'].get(k) for k in changes}
    preview['edited_fields'] = list(changes)
    preview['input_sources'] = old.get('input_sources', [])
    preview['token'] = fingerprint({'run_id': rid, 'preview': {k:v for k,v in preview.items() if k != 'token'}})
    state['sequence'] = state.get('sequence', 0) + 1
    state['answer'] = '已更新预览，请核对后保存。'
    state['preview_edits'] = [*state.get('preview_edits', [])[-19:], {'fields': list(changes), 'before': preview['previous_draft'], 'after': changes}]
    row.state = state
    db.commit()
    return public_run(row)
