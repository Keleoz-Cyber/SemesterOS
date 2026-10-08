"""Declared all-day occupancy is date evidence, never a fabricated start clock."""
from copy import deepcopy
from datetime import date, datetime

import pytest
from pydantic import ValidationError

from app.capacity import calendar_context
from app.item_schemas import ItemTime
from app.notice_event_time import normalize_explicit_all_day
from app.reminder_rules import anchor_at, notice_arrival_at, reminder_anchor_at, evaluate
from test_foundation import client
from test_time_evidence import CALENDAR, COURSES, DAY, NOW, PREFERENCES, api_record, event, setup_api, at


@pytest.mark.parametrize('expression,source', [
    ('明天不需要全天参加', '明天不需要全天参加'),
    ('明天不用整天参加', '明天不用整天参加'),
    ('明天全天', '明天不是全天，只有半天'),
    ('明天全天', '明天不必一整天参加'),
    ('明天全天', '明天不是全天外出，下午就回来了'),
])
@pytest.mark.parametrize('meaning', ['unspecified', 'all_day'])
def test_negated_full_day_cannot_become_whole_date_occupancy(expression, source, meaning):
    fields = {'title':'外出', 'time':{'precision':'date','date':DAY,
                                    'expression':expression,'meaning':meaning}}
    before = deepcopy(fields)
    result = normalize_explicit_all_day(fields, source)
    assert result['time']['meaning'] == 'unspecified'
    assert fields == before


@pytest.mark.parametrize('source', [
    '明天不用上课，全天外出',
    '我明天全天外出，一整天都不在学校',
    '明天不是半天，而是全天外出',
])
def test_unrelated_negation_does_not_erase_positive_full_day(source):
    fields = {'time':{'precision':'date','date':DAY,'expression':'明天全天'}}
    assert normalize_explicit_all_day(fields,source)['time']['meaning'] == 'all_day'


@pytest.mark.parametrize('time', [
    {'precision':'date','date':DAY,'meaning':'all_day','expression':'10月9日全天外出'},
    {'precision':'range','date':'2026-10-08','end_date':DAY,'meaning':'all_day','expression':'8日至9日每天全天'}])
def test_all_day_schema_preserves_date_precision_without_clock_or_anchor(time):
    result = ItemTime.model_validate(time).model_dump(mode='json')
    assert result['precision'] == time['precision'] and result['meaning'] == 'all_day'
    assert result['at'] is result['end_at'] is None and not result['day_end_confirmed']
    assert result['expression'] == time['expression']
    record = {'kind':'exam','time':result,'details':{'early_arrival_minutes':30}}
    assert anchor_at(record) is reminder_anchor_at(record) is notice_arrival_at(record) is None
    state = evaluate({'mode':'relative','lead_minutes':30,'purpose':'item','enabled':True},
                     record,'active',NOW)
    assert state['trigger_at'] is None and state['schedule_state'] == 'pending_anchor'


@pytest.mark.parametrize('time', [
    {'precision':'exact','at':at('00:00'),'end_at':'2026-10-10T00:00:00+08:00','meaning':'all_day'},
    {'precision':'week','week':6,'meaning':'all_day'},
    {'precision':'unknown','meaning':'all_day'},
    {'precision':'date','date':DAY,'meaning':'all_day','day_end_confirmed':True}])
def test_all_day_semantics_requires_date_or_date_range_without_deadline_policy(time):
    with pytest.raises(ValidationError):
        ItemTime.model_validate(time)


@pytest.mark.parametrize('kind',['event','exam'])
@pytest.mark.parametrize('time', [
    {'precision':'date','date':DAY,'meaning':'all_day'},
    {'precision':'range','date':'2026-10-08','end_date':DAY,'meaning':'all_day'}])
def test_declared_all_day_occupancy_blocks_actual_courses_without_invented_start(kind,time):
    record = event(time=time)
    before = deepcopy(record)
    exams = [{**record,'kind':'exam','lifecycle':'active'}] if kind == 'exam' else []
    cal = {**CALENDAR,'fixed_events':[record] if kind == 'event' else []}
    context = calendar_context(cal,PREFERENCES,COURSES,exams,NOW)
    assert len(context['conflicts']) == 3
    assert all(c['certainty']=='confirmed' and c['blocking'] for c in context['conflicts'])
    assert context['obligation_points'] == context['known_start_obligations'] == []
    assert context['uncertainty_warnings'] == context['time_warnings'] == []
    assert context['free'].minutes(datetime.fromisoformat(at('08:00')).timestamp(),
                                   datetime.fromisoformat(at('18:00')).timestamp()) == 0
    assert record == before and record['time'].get('at') is record['time'].get('end_at') is None


def test_all_day_occupancy_ends_after_declared_dates_without_excluding_next_day():
    pref = {**PREFERENCES,'weekly':[*PREFERENCES['weekly'],{'weekday':6,'start':'08:00','end':'18:00'}]}
    c = calendar_context({**CALENDAR,'fixed_events':[event(time={
        'precision':'range','date':'2026-10-08','end_date':DAY,'meaning':'all_day'})]},
        pref,[],[],NOW,query_dates=(date(2026,10,9),date(2026,10,10)))
    assert c['free'].minutes(datetime.fromisoformat('2026-10-10T08:00:00+08:00').timestamp(),
                              datetime.fromisoformat('2026-10-10T18:00:00+08:00').timestamp()) == 600


def test_ordinary_date_with_all_day_in_raw_expression_stays_information_until_meaning_is_declared():
    time = {'precision':'date','date':DAY,'expression':'全天外出原文，尚未分类'}
    assert ItemTime.model_validate(time).meaning == 'unspecified'
    c = calendar_context({**CALENDAR,'fixed_events':[event(time=time)]},PREFERENCES,COURSES,[],NOW)
    assert c['conflicts'] == [] and len(c['time_warnings']) == 1
    assert c['free'].minutes(datetime.fromisoformat(at('08:00')).timestamp(),
                              datetime.fromisoformat(at('18:00')).timestamp()) == 380


def test_start_only_warnings_do_not_name_later_courses_or_other_start_only_records():
    first = event()
    second = event('second',title='另一会议',time={'precision':'exact','at':at('11:00')})
    c = calendar_context({**CALENDAR,'fixed_events':[first,second]},PREFERENCES,COURSES,[],NOW)
    assert len(c['conflicts']) == 1
    assert len(c['time_warnings']) == 2
    assert [w['item_ids'] for w in c['time_warnings']] == [['event:meeting'],['event:second']]
    assert [w['titles'] for w in c['time_warnings']] == [['九点会议'],['另一会议']]
    assert all('课程2' not in w['message'] and '课程3' not in w['message'] for w in c['time_warnings'])


def test_manual_all_day_preview_and_save_preserve_dates_and_confirm_real_three_course_occupancy(client,monkeypatch):
    headers,sid = setup_api(client,monkeypatch)
    body = {**api_record(sid,{'precision':'date','date':DAY,'meaning':'all_day','expression':'10月9日全天外出'}),
            'title':'全天外出'}
    preview = client.post('/api/v1/events/conflict-preview',headers=headers,json=body)
    assert preview.status_code == 200,preview.text
    impact = preview.json()['impact']
    assert len(impact['course_conflicts']) == len(impact['new_fixed_conflicts']) == 3
    assert impact['new_time_warnings'] == []
    saved = client.post('/api/v1/events',headers=headers,json={**body,'confirm_fixed_conflicts':True})
    assert saved.status_code == 201,saved.text
    record = saved.json()['event']
    assert record['time']['precision']=='date' and record['time']['meaning']=='all_day'
    assert record['time']['at'] is record['time']['end_at'] is record['arrival_at'] is None


def test_old_exam_reschedule_metadata_edit_preserves_declared_all_day_and_expression(client,monkeypatch):
    from app import exam_planning
    monkeypatch.setattr(exam_planning,'utcnow',lambda:NOW)
    headers,sid = setup_api(client,monkeypatch)
    time = {'precision':'date','date':DAY,'meaning':'all_day','expression':'10月9日全天考试'}
    made = client.post('/api/v1/items',headers=headers,json={
        'semester_id':sid,'expected_revision':1,'kind':'exam','title':'全天考试','certainty':'formal',
        'time':time,'confirm_fixed_conflicts':True})
    assert made.status_code == 201,made.text
    exam = made.json()
    # Old clients repeat the same date when editing location and cannot send meaning.
    body = {'expected_version':1,'time':{'precision':'date','date':DAY},
            'certainty':'formal','location':'A101','reserve_time':True,'reason':'只补充地点'}
    url = '/api/v1/exams/'+exam['id']+'/reschedule'
    preview = client.post(url+'/preview',headers=headers,json=body)
    assert preview.status_code == 200,preview.text
    detail = preview.json()
    assert detail['after']['time'] == exam['time']
    assert detail['after']['location'] == 'A101'
    assert detail['new_fixed_conflicts'] == detail['new_time_warnings'] == []
    assert len(detail['fixed_conflicts']) == 3
    assert detail['after']['anchor_at'] is detail['after']['arrival_at'] is None
    saved = client.post(url,headers=headers,json={**body,'expected_revision':detail['base_revision'],
                                                 'preview_token':detail['preview_token']})
    assert saved.status_code == 200,saved.text
    value = client.get('/api/v1/items/'+exam['id'],headers=headers).json()
    assert value['time'] == exam['time'] and value['location'] == 'A101'
