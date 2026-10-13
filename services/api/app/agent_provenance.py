"""Keep a draft's original notice separate from follow-up messages and media."""
from copy import deepcopy
from sqlalchemy import select

from .auth import error
from .models import AgentRun


def pending_draft(row):
    if row is None:
        return None
    preview = row.state.get('preview') or {}
    if preview.get('action') not in ('create', 'batch'):
        return None
    return {'run_id': row.id, 'kind': preview['kind'],
            'title': (preview.get('after') or {}).get('title'),
            'source_text': preview.get('source_text') or preview.get('body', {}).get('source_text', ''),
            'source': deepcopy(preview.get('source')),
            'input_sources': deepcopy(preview.get('input_sources', []))}


def unsaved_notices(history, thread):
    result = []
    for row in history:
        if row.status == 'applied':
            break
        if row.thread_id != thread.id or row.status not in ('completed', 'needs_confirmation', 'superseded'):
            continue
        ref = row.state.get('source')
        draft = pending_draft(row)
        result.append({'run_id': row.id, 'request': row.text,
            'source_text': draft['source_text'] if draft else (ref or {}).get('text') or row.text,
            'source': draft['source'] if draft else deepcopy(ref)})
    return result


def draft_origin(db, user, thread, state, draft_run_id, kind, source):
    if not draft_run_id:
        return source, state.get('source'), []
    pending = state.get('pending_draft') or {}
    context = next((p for p in state.get('unsaved_notice_contexts', []) if p['run_id'] == draft_run_id), None)
    is_pending = pending.get('run_id') == draft_run_id
    if (not is_pending and context is None) or (is_pending and pending.get('kind') != kind):
        error(422, 'DRAFT_NOT_FOUND', '请使用当前未保存事项的来源编号；新事项不要引用旧来源。')
    row = db.scalar(select(AgentRun).where(AgentRun.id == draft_run_id,
        AgentRun.user_id == user.id, AgentRun.thread_id == thread.id))
    if row is None or row.status not in ('needs_confirmation', 'completed', 'superseded'):
        error(409, 'DRAFT_STALE', '原草稿已保存、取消或变化，请重新核对。')
    original = pending_draft(row)
    if original:
        return original['source_text'], original['source'], original['input_sources']
    ref = row.state.get('source')
    return (ref or {}).get('text') or row.text, ref, []
