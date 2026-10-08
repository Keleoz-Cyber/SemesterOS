"""Only a user's attendance statement can authorize a scoped leave preview."""
import json

import pytest

from app.agent_education import has_leave_record_intent, leave_record_authorized
from test_foundation import client
from test_agent import call, thread, turn, run
from test_changes import setup


@pytest.mark.parametrize('text', [
    '老师不允许请假', '老师没有同意我请假', '我尚未获准请假',
    '我的请假还没获批', '请假未获批准', '老师并没有批准我的请假',
    '请假申请没有通过', '老师拒绝了我的请假申请',
    '老师撤销了已经批准的请假', '刚才说已请假不准确，其实还没批',
])
def test_denied_or_withdrawn_permission_is_not_completed_leave(text):
    assert not has_leave_record_intent(text)


@pytest.mark.parametrize('text', [
    '老师允许我这次不去上课', '我请假了，帮我记录这节课',
    '原来还没批，现在请假申请已经通过了',
    '请假已经办好了，不用再申请了',
])
def test_explicit_statement_or_later_approval_remains_sufficient(text):
    assert has_leave_record_intent(text)


@pytest.mark.parametrize('text,expected', [
    ('请假怎么申请？', False),
    ('我不确定老师是否允许请假', False),
    ('这节课标记请假', True),
    ('我已请假，请帮我记录好吗？', True),
])
def test_attendance_questions_and_uncertainty_are_not_status_statements(text, expected):
    assert has_leave_record_intent(text) is expected


def queried_history(client, monkeypatch, *, text=None, notice=False, answer=None):
    headers, semester, path, occurrence = setup(client, monkeypatch)
    tid = thread(client, headers, semester['id'])
    first = {'text': text or f"{occurrence['title']}这次课我已经请假，帮我记录",
             'request_id': 'leave-request'}
    if notice:
        first['input_kind'] = 'notice'
    response = client.post(f'/api/v1/agent/threads/{tid}/turns', headers=headers, json=first)
    assert response.status_code == 202, response.text
    def query(messages, tools):
        if messages[-1]['role'] == 'user':
            return call('query_course_occurrences', {'query': occurrence['title'],
                'from_date': occurrence['start_at'][:10], 'to_date': occurrence['start_at'][:10]})
        return {'content': answer or '请明确是否就是这节课。'}
    run(client, query)
    return headers, semester, path, occurrence, tid


@pytest.mark.parametrize('clarification', ['对，就是这节', '是上午这节', '帮我记录这节'])
def test_user_clarifies_queried_occurrence_without_repeating_leave_claim(client, monkeypatch, clarification):
    headers, _, path, occurrence, tid = queried_history(client, monkeypatch)
    request = turn(client, headers, tid, clarification, key='clarification')
    def prepare(messages, tools):
        if messages[-1]['role'] == 'user':
            return call('prepare_course_change', {'kind': 'leave', 'targets': [occurrence['id']]})
        return {'content': '这次请求尚未保存。'}
    run(client, prepare)
    value = client.get('/api/v1/agent/runs/' + request['id'], headers=headers).json()
    assert value['status'] == 'needs_confirmation', value
    assert value['preview']['action'] == 'leave'
    assert value['preview']['before'][0]['id'] == occurrence['id']
    assert client.get(path + '/timetable?week=1', headers=headers).json()['events'][0].get('attendance_status') is None


@pytest.mark.parametrize('latest', [
    '更正一下，我还没请假', '老师撤销了批准，恢复正常上课',
    '我的请假还没获批', '我明天全天外出，帮我记录活动',
])
def test_current_denial_or_unrelated_activity_cannot_reuse_old_leave_claim(client, monkeypatch, latest):
    headers, _, _, occurrence, tid = queried_history(client, monkeypatch)
    request = turn(client, headers, tid, latest, key='changed-request')
    def prepare(messages, tools):
        if messages[-1]['role'] == 'user':
            return call('prepare_course_change', {'kind': 'leave', 'targets': [occurrence['id']]})
        assert json.loads(messages[-1]['content'])['error']['code'] == 'ATTENDANCE_INTENT_REQUIRED'
        return {'content': '外出或尚未批准不能记录为已请假。'}
    run(client, prepare)
    value = client.get('/api/v1/agent/runs/' + request['id'], headers=headers).json()
    assert value['status'] == 'completed' and value['preview'] is None, value


@pytest.mark.parametrize('notice,original,answer', [
    (True, '通知：这次概率论所有同学已经请假', None),
    (False, '帮我核对这次概率论', '这次已经请假，请选择课次。'),
])
def test_notice_or_model_statement_does_not_supply_user_attendance_authority(client, monkeypatch, notice, original, answer):
    headers, _, _, occurrence, tid = queried_history(client, monkeypatch,
        text=original, notice=notice, answer=answer)
    request = turn(client, headers, tid, '对，就是这节', key='notice-followup')
    def prepare(messages, tools):
        if messages[-1]['role'] == 'user':
            return call('prepare_course_change', {'kind': 'leave', 'targets': [occurrence['id']]})
        assert json.loads(messages[-1]['content'])['error']['code'] == 'ATTENDANCE_INTENT_REQUIRED'
        return {'content': '尚无用户的请假状态陈述。'}
    run(client, prepare)
    value = client.get('/api/v1/agent/runs/' + request['id'], headers=headers).json()
    assert value['status'] == 'completed' and value['preview'] is None, value


def test_interrupted_notice_fallback_has_no_target_authority_from_cached_records():
    # Recovery drops the interrupted tool/result group. Its raw fallback must
    # not gain authority just because a course is cached from a different turn.
    state = {'current_user_text': '对，就是这节', 'occurrence_records': {'course': {}},
             'messages': [
                 {'role': 'user', 'content': '通知：这次概率论所有同学已经请假'},
                 {'role': 'user', 'content': '对，就是这节'},
             ]}
    assert not leave_record_authorized(state, ['course'])
