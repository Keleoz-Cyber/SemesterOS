"""Agent planning uses the production solver and caller-owned transactions."""
import pytest
from fastapi import HTTPException
from sqlalchemy import select, func
from sqlalchemy.orm import Session
from test_foundation import client, register, semester
from test_schedule_api import setup, proposal, accept


def context(db, item, sid):
    from app.models import StudyItem, User
    from app.academics import owned_semester
    user = db.get(User, db.get(StudyItem, item['id']).user_id)
    return user, owned_semester(db, user, sid, lock=True)


def prepare(db, item, sid, **args):
    from app.agent_planning import PlanRequest, prepare_agent_plan
    user, s = context(db, item, sid)
    state = {'run_id': 'test-agent-run', 'known_ids': [item['id']]}
    return prepare_agent_plan(db, user, s, state,
        PlanRequest(mode='schedule', task_ids=[item['id']], lead_minutes=0, **args))


def test_agent_plan_preview_and_apply_stay_in_caller_transaction(client, monkeypatch):
    from app.models import PlanBlock, PlanProposal
    h, s, item = setup(client, monkeypatch)
    with Session(client.app.state.engine) as db:
        preview = prepare(db, item, s['id'])
        assert preview['kind'] == 'plan'
        assert preview['action'] == 'schedule'
        assert preview['after']['status'] == 'FEASIBLE_COMPLETE'
        assert db.scalar(select(func.count()).select_from(PlanBlock)) == 0
        p = db.get(PlanProposal, preview['target_id'])
        assert p.payload['agent_run_id'] == 'test-agent-run'
        db.commit()
    bypass = client.post(f"/api/v1/plan-proposals/{preview['target_id']}/accept", headers=h, json=preview['body'])
    assert bypass.status_code == 409
    assert bypass.json()['code'] == 'AGENT_CONFIRMATION_REQUIRED'
    from app.agent_planning import apply_agent_plan
    with Session(client.app.state.engine) as db:
        user, _ = context(db, item, s['id'])
        receipt = apply_agent_plan(db, user, preview)
        assert receipt['block_ids']
        db.rollback()
    with Session(client.app.state.engine) as db:
        assert db.scalar(select(func.count()).select_from(PlanBlock)) == 0
        assert db.get(PlanProposal, preview['target_id']).phase == 'ready'
        user, _ = context(db, item, s['id'])
        receipt = apply_agent_plan(db, user, preview)
        assert apply_agent_plan(db, user, preview) == receipt
        db.commit()
    assert sum(b['minutes'] for b in client.get(f"/api/v1/semesters/{s['id']}/plans", headers=h).json()['blocks']) == 120


@pytest.mark.parametrize('missing', ['remaining_minutes', 'start_policy', 'availability'])
def test_missing_facts_return_clarification_without_proposal(client, monkeypatch, missing):
    from app.models import StudyItem, PlanProposal
    h, s, item = setup(client, monkeypatch)
    with Session(client.app.state.engine) as db:
        row = db.get(StudyItem, item['id'])
        if missing == 'availability':
            from app.planning import availability_row
            user, _ = context(db, item, s['id'])
            db.delete(availability_row(db, user, s['id']))
        else:
            row.payload = {**row.payload, missing: None if missing == 'remaining_minutes' else 'unconfirmed'}
        db.flush()
        result = prepare(db, item, s['id'])
        assert result['status'] == 'needs_input'
        assert result['messages']
        assert result.get('kind') != 'plan'
        assert db.scalar(select(func.count()).select_from(PlanProposal)) == 0


def test_target_provenance_active_owner_and_ambiguity_are_checked(client, monkeypatch):
    from app.agent_planning import PlanRequest, prepare_agent_plan
    from app.models import StudyItem, User
    h, s, item = setup(client, monkeypatch)
    _, other_h = register(client, 'other')
    other_s = semester(client, other_h)
    foreign = client.post('/api/v1/items', headers=other_h, json={
        'semester_id': other_s['id'], 'kind': 'task', 'title': '别人的任务'}).json()
    with Session(client.app.state.engine) as db:
        user, owned = context(db, item, s['id'])
        for ids, state, code in [
            ([foreign['id']], {'known_ids': [foreign['id']]}, 'NOT_FOUND'),
            ([item['id']], {'known_ids': []}, 'READ_FIRST'),
            ([item['id']], {'known_ids': [item['id']], 'ambiguous_ids': [item['id']]}, 'AMBIGUOUS_TARGET'),
        ]:
            with pytest.raises(HTTPException) as exc:
                prepare_agent_plan(db, user, owned, {'run_id': 'r', **state}, PlanRequest(mode='schedule', task_ids=ids))
            assert exc.value.detail['code'] == code
        row = db.get(StudyItem, item['id']); row.lifecycle = 'cancelled'; db.flush()
        with pytest.raises(HTTPException) as exc:
            prepare(db, item, s['id'])
        assert exc.value.detail['code'] == 'NOT_FOUND'


def test_partial_preview_discloses_unfinished_work_and_fixed_event_is_preserved(client, monkeypatch):
    from test_calendar_events import create_event
    from app.agent_planning import apply_agent_plan
    h, s, item = setup(client, monkeypatch, minutes=300)
    event = create_event(client, h, s['id']).json()['event']
    with Session(client.app.state.engine) as db:
        preview = prepare(db, item, s['id'], allow_partial=True)
        result = preview['after']
        assert result['status'] == 'FEASIBLE_PARTIAL'
        assert result['unarranged_minutes'] > 0
        assert sum(b['minutes'] for b in result['blocks']) + result['unarranged_minutes'] == 300
        assert preview['body']['confirm_partial'] is True
        assert preview['body']['unarranged_minutes'] == result['unarranged_minutes']
        from app.reminder_rules import instant
        assert all(instant(b['start_at']) >= instant('2026-09-21T10:00:00+08:00') for b in result['blocks'])
        user, _ = context(db, item, s['id'])
        receipt = apply_agent_plan(db, user, preview)
        assert receipt['unarranged_minutes'] == result['unarranged_minutes']
        db.commit()
    assert client.get('/api/v1/events/' + event['id'], headers=h).json() == event


def test_changed_snapshot_and_invalidation_prevent_apply(client, monkeypatch):
    from app.agent_planning import apply_agent_plan, invalidate_agent_plan
    from app.models import StudyItem, PlanProposal
    h, s, item = setup(client, monkeypatch)
    with Session(client.app.state.engine) as db:
        preview = prepare(db, item, s['id']); db.commit()
        row = db.get(StudyItem, item['id']); row.payload = {**row.payload, 'remaining_minutes': 150}; db.flush()
        user, _ = context(db, item, s['id'])
        with pytest.raises(HTTPException) as exc:
            apply_agent_plan(db, user, preview)
        assert exc.value.status_code == 409
        db.rollback()
        invalidate_agent_plan(db, user, preview)
        assert db.get(PlanProposal, preview['target_id']).phase == 'rejected'
        with pytest.raises(HTTPException):
            apply_agent_plan(db, user, preview)
        db.rollback()
        assert db.get(PlanProposal, preview['target_id']).phase == 'ready'


def test_replan_keeps_block_ids_and_does_not_commit(client, monkeypatch):
    from app.agent_planning import PlanRequest, prepare_agent_plan, apply_agent_plan
    from test_calendar_events import create_event
    from app.models import PlanBlock
    h, s, item = setup(client, monkeypatch, minutes=60)
    assert accept(client, h, proposal(client, h, s, item)).status_code == 200
    original = client.get(f"/api/v1/semesters/{s['id']}/plans", headers=h).json()['blocks']
    create_event(client, h, s['id'])
    with Session(client.app.state.engine) as db:
        user, owned = context(db, item, s['id'])
        preview = prepare_agent_plan(db, user, owned, {'run_id': 'r', 'known_ids': [item['id']]},
            PlanRequest(mode='replan', task_ids=[item['id']], lead_minutes=0))
        assert preview['after']['moved_tasks'] == 1
        assert {b['id'] for b in preview['before']['blocks']} == {b['id'] for b in original}
        apply_agent_plan(db, user, preview)
        db.rollback()
    assert client.get(f"/api/v1/semesters/{s['id']}/plans", headers=h).json()['blocks'] == original


@pytest.mark.parametrize('started', [False, True])
def test_replan_wont_move_locked_or_started_conflicting_blocks(client, monkeypatch, started):
    from app.agent_planning import PlanRequest, prepare_agent_plan
    from app import schedule_api
    from datetime import datetime
    from test_calendar_events import create_event
    h, s, item = setup(client, monkeypatch, minutes=60)
    assert accept(client, h, proposal(client, h, s, item)).status_code == 200
    blocks = client.get(f"/api/v1/semesters/{s['id']}/plans", headers=h).json()['blocks']
    if started:
        monkeypatch.setattr(schedule_api, 'utcnow', lambda: datetime.fromisoformat('2026-09-21T09:05:00+08:00'))
    else:
        assert client.patch('/api/v1/plan-blocks/' + blocks[0]['id'] + '/lock', headers=h,
            json={'expected_version': 1, 'locked': True}).status_code == 200
    create_event(client, h, s['id'])
    with Session(client.app.state.engine) as db:
        user, owned = context(db, item, s['id'])
        result = prepare_agent_plan(db, user, owned, {'run_id': 'r', 'known_ids': [item['id']]},
            PlanRequest(mode='replan', task_ids=[item['id']], lead_minutes=0))
        assert result['status'] == 'needs_input'
        assert result['result']['locked_conflicts']


def test_plan_request_is_bounded_and_replan_cannot_ignore_schedule_parameters():
    from app.agent_planning import PlanRequest
    from pydantic import ValidationError
    for value in [
        {'mode': 'schedule', 'task_ids': ['x'] * 101},
        {'mode': 'schedule', 'task_ids': ['x', 'x']},
        {'mode': 'schedule', 'task_ids': ['x'], 'targets': [{'item_id': 'foreign', 'target_minutes': 20}]},
        {'mode': 'schedule', 'task_ids': ['x'], 'window_start_at': '2026-09-21T09:00:00+08:00'},
        {'mode': 'replan', 'task_ids': ['x'], 'days': 14},
    ]:
        with pytest.raises(ValidationError): PlanRequest.model_validate(value)


def agent_plan(client, h, s, item, *, partial=False, request_id='plan-turn', tid=None):
    """Exercise the real model-tool checkpoint and HTTP confirmation boundary."""
    from test_agent import call, thread, turn, run
    import json
    tid = tid or thread(client, h, s['id'])
    queued = turn(client, h, tid, '给合成排程任务安排学习时间', request_id)
    def model(messages, tools):
        if messages[-1]['role'] == 'user':
            return call('find_records', {'query': item['title']})
        result = json.loads(messages[-1]['content'])
        if 'records' in result:
            return call('prepare_plan', {'mode': 'schedule', 'task_ids': [item['id']],
                'allow_partial': partial, 'lead_minutes': 0}, 'plan-tool')
        assert result['status'] in ('needs_input', 'not_applicable'), result
        return {'role': 'assistant', 'content': '请先补充任务所需时间和最早开始时间。'}
    run(client, model)
    url = '/api/v1/agent/runs/' + queued['id']
    return tid, url, client.get(url, headers=h).json()


def test_worker_plan_confirm_is_atomic_idempotent_and_partial_is_disclosed(client, monkeypatch):
    from app.models import AgentRun, PlanProposal, PlanBlock
    h, s, item = setup(client, monkeypatch, minutes=300)
    _, url, value = agent_plan(client, h, s, item, partial=True)
    assert value['status'] == 'needs_confirmation', value
    preview = value['preview']
    assert preview['after']['unarranged_minutes'] > 0
    assert client.get(f"/api/v1/semesters/{s['id']}/plans", headers=h).json()['blocks'] == []
    data = {'decision': 'confirm', 'token': preview['token']}
    saved = client.post(url + '/decision', headers=h, json=data)
    assert saved.status_code == 200, saved.text
    assert saved.json()['receipt']['unarranged_minutes'] == preview['after']['unarranged_minutes']
    assert client.post(url + '/decision', headers=h, json=data).json() == saved.json()
    with Session(client.app.state.engine) as db:
        row = db.get(AgentRun, value['id'])
        p = db.get(PlanProposal, preview['target_id'])
        assert p.payload['agent_run_id'] == row.id
        assert p.phase == row.status == 'applied'
        assert p.receipt == row.state['receipt']
        assert db.scalar(select(func.count()).select_from(PlanBlock)) == len(p.receipt['block_ids'])


@pytest.mark.parametrize('action', ['reject', 'supersede', 'cancel'])
def test_worker_plan_invalidation_rejects_draft_without_writes(client, monkeypatch, action):
    from app.models import PlanProposal, PlanBlock
    from test_agent import turn
    h, s, item = setup(client, monkeypatch)
    tid, url, value = agent_plan(client, h, s, item)
    assert value['status'] == 'needs_confirmation', value
    preview = value['preview']
    if action == 'reject':
        result = client.post(url + '/decision', headers=h, json={'decision': 'reject', 'token': preview['token']})
        assert result.status_code == 200
    elif action == 'cancel':
        assert client.post(url + '/cancel', headers=h).status_code == 200
    else:
        turn(client, h, tid, '先不安排了', 'new-turn')
    with Session(client.app.state.engine) as db:
        assert db.get(PlanProposal, preview['target_id']).phase == 'rejected'
        assert db.scalar(select(func.count()).select_from(PlanBlock)) == 0
    assert client.post(url + '/decision', headers=h, json={'decision': 'confirm', 'token': preview['token']}).status_code == 409


def test_worker_missing_estimate_has_no_confirmation_or_mutation(client, monkeypatch):
    from app.models import StudyItem, PlanProposal, PlanBlock
    h, s, item = setup(client, monkeypatch)
    with Session(client.app.state.engine) as db:
        row = db.get(StudyItem, item['id']); row.payload = {**row.payload, 'remaining_minutes': None}; db.commit()
    _, _, value = agent_plan(client, h, s, item)
    assert value['status'] == 'completed', value
    assert value['preview'] is None
    assert any(card['kind'] == 'planning_result' for card in value['cards'])
    with Session(client.app.state.engine) as db:
        assert db.scalar(select(func.count()).select_from(PlanProposal)) == 0
        assert db.scalar(select(func.count()).select_from(PlanBlock)) == 0


def test_worker_revision_change_rejects_confirmation(client, monkeypatch):
    from test_calendar_events import create_event
    h, s, item = setup(client, monkeypatch)
    _, url, value = agent_plan(client, h, s, item)
    assert value['status'] == 'needs_confirmation', value
    create_event(client, h, s['id'])
    response = client.post(url + '/decision', headers=h,
        json={'decision': 'confirm', 'token': value['preview']['token']})
    assert response.status_code == 409
    assert client.get(f"/api/v1/semesters/{s['id']}/plans", headers=h).json()['blocks'] == []


def test_confirmation_failure_before_agent_receipt_rolls_back_plan_apply(client, monkeypatch):
    from app import agent_tools
    from app.models import PlanProposal, AgentRun, PlanBlock
    h, s, item = setup(client, monkeypatch)
    _, url, value = agent_plan(client, h, s, item)
    preview = value['preview']; original = agent_tools.apply_preview
    def fail_after_business_write(db, user, p, **kwargs):
        original(db, user, p, **kwargs)
        raise RuntimeError('simulate interrupted AgentRun receipt')
    monkeypatch.setattr(agent_tools, 'apply_preview', fail_after_business_write)
    with pytest.raises(RuntimeError, match='simulate interrupted'):
        client.post(url + '/decision', headers=h, json={'decision': 'confirm', 'token': preview['token']})
    with Session(client.app.state.engine) as db:
        assert db.get(PlanProposal, preview['target_id']).phase == 'ready'
        assert db.get(AgentRun, value['id']).status == 'needs_confirmation'
        assert db.scalar(select(func.count()).select_from(PlanBlock)) == 0


def test_worker_replan_moves_only_personal_blocks_and_confirms_once(client, monkeypatch):
    from test_agent import call, thread, turn, run
    from test_calendar_events import create_event
    import json
    h, s, item = setup(client, monkeypatch, minutes=60)
    assert accept(client, h, proposal(client, h, s, item)).status_code == 200
    path = f"/api/v1/semesters/{s['id']}/plans"
    original = client.get(path, headers=h).json()['blocks']
    event = create_event(client, h, s['id']).json()['event']
    tid = thread(client, h, s['id'])
    queued = turn(client, h, tid, '组会冲突，重新安排这个任务的个人计划')
    def model(messages, tools):
        if messages[-1]['role'] == 'user': return call('find_records', {'query': item['title']})
        assert json.loads(messages[-1]['content'])['records']
        return call('prepare_plan', {'mode': 'replan', 'task_ids': [item['id']], 'lead_minutes': 0}, 'replan')
    run(client, model)
    url = '/api/v1/agent/runs/' + queued['id']; value = client.get(url, headers=h).json()
    assert value['status'] == 'needs_confirmation', value
    preview = value['preview']; assert preview['after']['moved_tasks'] == 1
    assert client.get(path, headers=h).json()['blocks'] == original
    data = {'decision': 'confirm', 'token': preview['token']}
    saved = client.post(url + '/decision', headers=h, json=data)
    assert saved.status_code == 200, saved.text
    assert client.post(url + '/decision', headers=h, json=data).json() == saved.json()
    after = client.get(path, headers=h).json()['blocks']
    assert {b['id'] for b in after} == {b['id'] for b in original}
    assert sum(b['minutes'] for b in after) == 60
    assert client.get('/api/v1/events/' + event['id'], headers=h).json() == event
