import json
from sqlalchemy.orm import Session
from app.models import AgentRun
from test_foundation import client, register, semester
from test_agent import thread, turn, run, call


def test_unverified_defensive_answer_is_not_published(client):
    _, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    first = turn(client, h, tid, '周五开会')
    run(client, lambda *_: call('prepare_event', {'action': 'create', 'fields': {'title': '开会', 'time': {'precision': 'date', 'date': '2026-10-16'}}}))
    correction = turn(client, h, tid, '不是周五吗，你确定吗', 'followup')
    count = 0
    def model(messages, tools):
        nonlocal count
        count += 1
        if count == 1: return {'content': '没有记错，肯定就是周五。'}
        if count == 2: return call('query_calendar', {'from_date': '2026-10-16', 'to_date': '2026-10-16'})
        return {'content': '预览是10月16日周五，仍待你确认保存。'}
    run(client, model)
    value = client.get('/api/v1/agent/runs/' + correction['id'], headers=h).json()
    assert value['status'] == 'completed', value
    assert value['answer'] == '预览是10月16日周五，仍待你确认保存。'
    assert count == 3
    assert client.get('/api/v1/agent/runs/' + first['id'], headers=h).json()['status'] == 'needs_confirmation'
    with Session(client.app.state.engine) as db:
        state = db.get(AgentRun, correction['id']).state
        assert state['facts_verified'] is True
        assert state['metrics']['worker_ms'] >= 0


def test_no_context_question_does_not_force_a_calendar_query():
    from app.assistant_policy import needs_fact_check
    assert not needs_fact_check('为什么下雨', False, 'message')
    assert not needs_fact_check('通知写错了', True, 'notice')
    assert needs_fact_check('我已经保存了吗', True, 'message')
