"""Regression for a spoken class-period correction replacing the notice source."""
import json

import pytest
from sqlalchemy.orm import Session

from app.class_time import resolve_period_reference, guard_event_class_time, reference_evidence
from app.models import MediaSource, AgentRun
from app.school_periods import HAUT_PERIODS
from fastapi import HTTPException
from test_foundation import client, register
from test_agent import thread, turn, run, call


ORIGINAL = '周五下午第二节课开会。其他先不确定'
CORRECTION = '下午第二节不应该是7到8节吗？'


def test_relative_second_period_never_becomes_first_afternoon_class():
    result = resolve_period_reference(HAUT_PERIODS, '下午第二节课')
    assert result['status'] == 'resolved'
    assert result['period_numbers'] == [7, 8] and result['start'] == '16:25'
    assert 'choices' not in result


@pytest.mark.parametrize('expression,numbers,clock', [
    ('第七到八节', [7, 8], '16:25'), ('第7、8节', [7, 8], '16:25'),
    ('第7节', [7], '16:25'), ('下午第二大节', [7, 8], '16:25'),
    ('下午第二节', [7, 8], '16:25'), ('第二节课', [3, 4], '10:25'),
    ('下午第一节课', [5, 6], '14:30'), ('晚上第一节课', [9, 10], '19:30'),
    ('下午第二小节', [6], '15:20'), ('晚上第一大节', [9, 10], '19:30'),
    (CORRECTION, [7, 8], '16:25')])
def test_explicit_periods_and_units_use_saved_bells(expression, numbers, clock):
    result = resolve_period_reference(HAUT_PERIODS, expression)
    assert result['status'] == 'resolved' and result['period_numbers'] == numbers
    assert result['start'] == clock


def test_period_resolution_does_not_invent_missing_or_school_specific_times():
    assert resolve_period_reference(HAUT_PERIODS, '第11节')['status'] == 'unavailable'
    assert resolve_period_reference(HAUT_PERIODS, '第1到99999999999节')['status'] == 'unavailable'
    custom = [{'number': 7, 'start': '16:00', 'end': '16:45'},
              {'number': 8, 'start': '16:50', 'end': '17:35'}]
    assert resolve_period_reference(custom, '第7到8节')['start'] == '16:00'
    assert resolve_period_reference([], '下午第二节')['status'] == 'unavailable'


def fields(at='14:30', end=None):
    return {'title': '开会', 'time': {'precision': 'exact',
        'at': f'2026-10-16T{at}:00+08:00',
        **({'end_at': f'2026-10-16T{end}:00+08:00'} if end else {})}}


def test_prepare_guard_catches_wrong_period_and_preserves_unknown_end():
    with pytest.raises(HTTPException) as raised:
        guard_event_class_time(fields(), HAUT_PERIODS, ORIGINAL)
    assert raised.value.detail['code'] == 'CLASS_TIME_MISMATCH'
    with pytest.raises(HTTPException) as raised:
        guard_event_class_time(fields(), HAUT_PERIODS, CORRECTION)
    assert raised.value.detail['code'] == 'CLASS_TIME_MISMATCH'
    value = guard_event_class_time(fields('16:25', '18:00'), HAUT_PERIODS, CORRECTION)
    assert value['time']['end_at'] is None
    assert guard_event_class_time(fields('15:30'), HAUT_PERIODS, '改成15:30开会') == fields('15:30')
    unresolved = {'title': '开会', 'time': {'precision': 'date', 'date': '2026-10-16', 'expression': '下午第二节课'}}
    assert guard_event_class_time(unresolved, HAUT_PERIODS, ORIGINAL) == unresolved


def test_short_answer_and_everyday_phrasing_need_no_unit_confirmation():
    evidence = reference_evidence('按大节算', ORIGINAL)
    assert resolve_period_reference(HAUT_PERIODS, evidence)['start'] == '16:25'
    assert resolve_period_reference(HAUT_PERIODS, '下周下午第二节课')['start'] == '16:25'
    assert guard_event_class_time(fields('16:25'), HAUT_PERIODS, ORIGINAL)


def test_explicit_unknown_end_does_not_count_as_end_evidence():
    result = guard_event_class_time(fields('16:25', '18:00'), HAUT_PERIODS, '第7节开会，结束时间不确定')
    assert result['time']['end_at'] is None


def setup(client):
    account, headers = register(client)
    response = client.post('/api/v1/semesters', headers=headers, json={
        'name': '节次核对', 'first_monday': '2026-08-31', 'total_weeks': 20, 'periods': HAUT_PERIODS})
    assert response.status_code == 201, response.text
    sid = response.json()['id']
    return account, headers, sid, thread(client, headers, sid)


def spoken(client, account, h, sid, tid, text, key):
    with Session(client.app.state.engine, expire_on_commit=False) as db:
        source = MediaSource(user_id=account['user']['id'], semester_id=sid, upload_key=key,
            input_hash='0' * 64, kind='audio', mime='audio/wav', size=1, storage_key=key+'.wav',
            status='recognized', text=text, original_text=text,
            reference_at='2026-10-13T03:00:00Z', created_at='2026-10-13T03:00:00Z')
        db.add(source); db.commit()
        source_id = source.id
    response = client.post(f'/api/v1/agent/threads/{tid}/turns', headers=h, json={
        'text': text, 'request_id': key, 'source_id': source_id, 'source_version': 1})
    assert response.status_code == 202, response.text
    return response.json(), source_id


def read(client, headers, row):
    return client.get('/api/v1/agent/runs/'+row['id'], headers=headers).json()


@pytest.mark.parametrize('preview_first', [False, True])
def test_spoken_correction_keeps_initial_text_and_audio_across_questions(client, preview_first):
    account, h, sid, tid = setup(client)
    first, original_source = spoken(client, account, h, sid, tid, ORIGINAL, 'original')
    if preview_first:
        run(client, lambda m, t: call('prepare_event', {'action': 'create', 'fields': {
            'title': '开会', 'time': {'precision': 'date', 'date': '2026-10-16', 'expression': '下午第二节课'}}}))
    else:
        run(client, lambda m, t: {'content': '正在核对这节课对应的开始时间。'})
    question, _ = spoken(client, account, h, sid, tid, '不是下午第二节课吗', 'question')
    run(client, lambda m, t: {'content': '下午第二节对应7、8节，从16:25开始。'})
    corrected, correction_source = spoken(client, account, h, sid, tid, CORRECTION, 'correction')
    run(client, lambda m, t: call('prepare_event', {
        'action': 'create', 'draft_run_id': first['id'], 'fields': fields('16:25', '18:00')}))
    preview = read(client, h, corrected)['preview']
    assert preview is not None, read(client, h, corrected)
    assert preview['body']['source_text'] == ORIGINAL
    assert preview['source']['id'] == original_source != correction_source
    assert preview['body']['time']['end_at'] is None
    assert read(client, h, corrected)['source']['id'] == correction_source
    result = client.post('/api/v1/agent/runs/'+corrected['id']+'/decision', headers=h,
        json={'decision': 'confirm', 'token': preview['token']})
    assert result.status_code == 200, result.text
    event = result.json()['receipt']['event']
    assert event['source_text'] == ORIGINAL and event['source_id'] == original_source
    assert event['time']['at'].startswith('2026-10-16T08:25')  # persisted UTC
    assert event['time']['end_at'] is None
    assert len(client.get('/api/v1/semesters/'+sid+'/calendar', headers=h,
        params={'from_date': '2026-10-16', 'to_date': '2026-10-16'}).json()['entries']) == 1


def test_unrelated_new_notice_does_not_inherit_pending_notice(client):
    account, h, sid, tid = setup(client)
    first, _ = spoken(client, account, h, sid, tid, ORIGINAL, 'first')
    run(client, lambda m, t: call('prepare_event', {'action': 'create', 'fields': {
        'title': '开会', 'time': {'precision': 'date', 'date': '2026-10-16'}}}))
    text = '另一个活动：周六看电影'
    other, source = spoken(client, account, h, sid, tid, text, 'other')
    run(client, lambda m, t: call('prepare_event', {'action': 'create', 'fields': {'title': '看电影'}}))
    preview = read(client, h, other)['preview']
    assert preview['body']['source_text'] == text and preview['source']['id'] == source


def test_wrong_precise_time_cannot_reach_confirmation_even_if_model_guesses(client):
    account, h, sid, tid = setup(client)
    first = turn(client, h, tid, ORIGINAL)
    def model(messages, tools):
        if messages[-1]['role'] == 'user':
            return call('prepare_event', {'action': 'create', 'fields': fields()})
        assert json.loads(messages[-1]['content'])['error']['code'] == 'CLASS_TIME_MISMATCH'
        return call('prepare_event', {'action':'create', 'fields':fields('16:25')})
    run(client, model)
    result = read(client, h, first)
    assert result['status'] == 'needs_confirmation'
    assert result['preview']['body']['time']['at'].startswith('2026-10-16T08:25')


def test_origin_reference_cannot_cross_thread_or_account(client):
    account, h, sid, tid = setup(client)
    first = turn(client, h, tid, '周五开会')
    run(client, lambda m, t: {'content': '时间还未说明。'})
    another = thread(client, h, sid)
    request = turn(client, h, another, '请记下午16:25开会')
    def model(messages, tools):
        if messages[-1]['role'] == 'user':
            return call('prepare_event', {'action': 'create', 'draft_run_id': first['id'], 'fields': fields('16:25')})
        assert json.loads(messages[-1]['content'])['error']['code'] == 'DRAFT_NOT_FOUND'
        return {'content': '没有找到本对话中的原通知。'}
    run(client, model)
    assert read(client, h, request)['preview'] is None


@pytest.mark.parametrize('kind', ['event', 'item', 'batch'])
def test_initial_source_and_new_correction_are_both_version_guarded(client, kind):
    account, h, sid, tid = setup(client)
    original = '周五安排一次班会，其他先不确定'
    first, original_source = spoken(client, account, h, sid, tid, original, 'first')
    def command(origin=None):
        args = {'draft_run_id': origin} if origin else {}
        if kind == 'event':
            return call('prepare_event', {**args, 'action':'create', 'fields':{'title':'班会'}})
        if kind == 'item':
            return call('prepare_item', {**args, 'fields':{'kind':'task', 'title':'准备班会'}})
        return call('prepare_batch', {**args, 'groups':[{'title':'班会', 'operations':[
            {'tool':'prepare_event','arguments':{'action':'create','fields':{'title':'班会'}}}]}]})
    run(client, lambda m,t: command())
    corrected, correction_source = spoken(client, account, h, sid, tid, '地点补充为A301', 'correction')
    run(client, lambda m,t: command(first['id']))
    preview = read(client,h,corrected)['preview']
    assert preview and preview['source']['id'] == original_source
    if kind == 'batch':
        assert preview['groups'][0]['operations'][0]['body']['source_text'] == original
    else:
        assert preview['body']['source_text'] == original
    with Session(client.app.state.engine) as db:
        row = db.get(MediaSource, correction_source); row.version += 1; db.commit()
    decision = {'decision':'confirm', 'token':preview['token']}
    if kind == 'batch':
        decision['selected_group_ids'] = [g['id'] for g in preview['groups']]
    result = client.post('/api/v1/agent/runs/'+corrected['id']+'/decision', headers=h, json=decision)
    assert result.status_code == 409, result.text
