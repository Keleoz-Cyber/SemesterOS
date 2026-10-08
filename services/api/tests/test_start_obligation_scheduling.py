from copy import deepcopy
from datetime import datetime

import pytest

from app.capacity import calendar_context
from app.plan_rules import classify
from app.scheduler import generate, prepare, validate_result
from app.replanner import generate as replan
from app.study_opportunity import study_opportunity
from test_capacity import SEMESTER, AVAILABILITY, at, task
from test_scheduler import request


PREFERENCES = {**AVAILABILITY, 'weekly':[{'weekday':1,'start':'08:30','end':'12:00'}]}


def calendar(point='09:00', lead=None, **time_patch):
    value = {'id':'meeting','title':'开始时间已知的会议','certainty':'formal','reserve_time':True,
             'time':{'precision':'exact','at':at(point).isoformat(),**time_patch}}
    if lead is not None:
        value['details'] = {'early_arrival_minutes':lead}
    return {**SEMESTER,'fixed_events':[value]}


def block(start,end):
    return {'id':'plan','item_id':'a','start_at':start,'end_at':end,
            'minutes':int((datetime.fromisoformat(end)-datetime.fromisoformat(start)).total_seconds()/60),
            'status':'active','version':1,'locked':False}


@pytest.mark.parametrize('point', ['2026-09-21T09:00:00+08:00','2026-09-21T09:00:30+08:00'])
def test_solver_splits_at_start_and_can_schedule_later_with_warning(point):
    c = calendar(at=point)
    result = generate(c,PREFERENCES,[],[task(minutes=60,splittable=False)],[],request('a'),at('08:00'))
    assert result['status'] == 'FEASIBLE_COMPLETE', result
    assert result['can_apply'] and result['uncertainty_warnings']
    assert result['uncertainty_warnings'][0]['end_at'] is None
    p = datetime.fromisoformat(point)
    assert all(not (datetime.fromisoformat(b['start_at']) <= p < datetime.fromisoformat(b['end_at']))
               for b in result['blocks'])
    assert datetime.fromisoformat(result['blocks'][0]['start_at']) == at('09:01')


@pytest.mark.parametrize('start,end,valid', [('08:30','09:30',False),('09:00','10:00',False),
                                           ('08:30','09:00',True),('09:01','10:01',True)])
def test_existing_plan_contains_start_point_only_with_half_open_boundaries(start,end,valid):
    c = calendar()
    context = calendar_context(c,PREFERENCES,[],[task(minutes=120)],at('08:00'))
    accepted,issues = classify([block(at(start).isoformat(),at(end).isoformat())],
        [task(minutes=120)], context['free'].spans,context['begin'],
        obligation_points=context['obligation_points'])
    assert bool(accepted) is valid and bool(issues) is not valid


def test_scheduler_validator_checks_point_even_if_candidate_spans_were_merged():
    items = [task(minutes=60)]
    _,context = prepare(calendar(),PREFERENCES,[],items,[],request('a',size=60),at('08:00'))
    result = generate(calendar(),PREFERENCES,[],items,[],request('a',size=60),at('08:00'))
    tampered = deepcopy(result)
    tampered['blocks'][0].update(start_at=at('09:00').isoformat(),end_at=at('10:00').isoformat())
    context['free'] = [(int(at('08:30').timestamp()/60),int(at('12:00').timestamp()/60))]
    assert not validate_result(context,tampered,False)


def test_explicit_arrival_is_respected_and_later_same_day_capacity_is_usable():
    c = calendar(lead=30)
    result = generate(c,PREFERENCES,[],[task(minutes=60)],[],request('a',size=60),at('08:00'))
    assert result['status'] == 'FEASIBLE_COMPLETE'
    assert datetime.fromisoformat(result['blocks'][0]['start_at']) == at('09:01')
    context = calendar_context(c,PREFERENCES,[],[],at('08:00'))
    assert context['free'].minutes(at('08:30').timestamp(),at('12:00').timestamp()) == 180


@pytest.mark.parametrize('time', [{'precision':'date','date':'2026-09-21'},
                                {'precision':'week','week':1},{'precision':'unknown'}])
def test_incomplete_date_does_not_remove_learning_candidates(time):
    c = {**SEMESTER,'fixed_events':[{**calendar()['fixed_events'][0],'time':time}]}
    result = generate(c,PREFERENCES,[],[task(minutes=180,splittable=False)],[],request('a'),at('08:00'))
    assert result['status'] == 'FEASIBLE_COMPLETE' and result['uncertainty_warnings']
    assert datetime.fromisoformat(result['blocks'][0]['start_at']) == at('08:30')


def test_replan_moves_across_point_but_keeps_end_equal_point_valid():
    c = calendar()
    pref = {**PREFERENCES,'weekly':[{'weekday':1,'start':'08:00','end':'12:00'}]}
    plan = block(at('08:30').isoformat(),at('09:30').isoformat())
    result = replan(c,pref,[],[task(minutes=60)],[plan],{'lead_minutes':0},at('07:00'))
    assert result['status'] == 'FEASIBLE_COMPLETE' and result['moved_blocks'] == 1
    assert datetime.fromisoformat(result['blocks'][0]['end_at']) == at('09:00')
    locked = replan(c,pref,[],[task(minutes=60)],[{**plan,'locked':True}],{'lead_minutes':0},at('07:00'))
    assert locked['status'] == 'INPUT_INVALID' and locked['locked_conflicts']


def test_study_opportunity_uses_later_gap_without_spanning_obligation_point():
    c = calendar()
    items = [task(minutes=60)]
    context = calendar_context(c,PREFERENCES,[],items,at('08:00'))
    suggestion = study_opportunity((c,PREFERENCES,[],items,[]),context,at('08:00'),
                                  at('00:00').timestamp(),at('23:59').timestamp(),[])
    assert suggestion is not None and suggestion['needs_check']
    assert datetime.fromisoformat(suggestion['start_at']) == at('09:01')
