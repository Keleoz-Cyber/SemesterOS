from datetime import datetime, timezone

from app.capacity import analyze
from app.capacity import merge, subtract, CapacityIndex
import random


def at(value):
    return datetime.fromisoformat('2026-09-21T' + value + ':00+08:00')


SEMESTER = {'first_monday':'2026-09-21','total_weeks':20,'periods':[
    {'number':1,'start':'09:00','end':'10:00'}, {'number':2,'start':'10:00','end':'11:00'}]}
AVAILABILITY = {'configured':True,'weekly':[{'weekday':1,'start':'09:00','end':'13:00'}],'exclusions':[]}


def task(id='a', minutes=180, due='13:00', **extra):
    return {'id':id,'version':1,'kind':'task','lifecycle':'active','title':'合成任务'+id,
        'time':{'precision':'exact','at':at(due).isoformat()}, 'remaining_minutes':minutes,
        'start_policy':'now','earliest_start_at':None,'splittable':True,'certainty':'formal',**extra}


def run(items, availability=AVAILABILITY, courses=(), now=None):
    return analyze(SEMESTER, availability, list(courses), items, now or at('08:00'))


def test_two_tasks_share_one_capacity_instead_of_both_looking_safe():
    result = run([task('a',150),task('b',150)])
    assert result['summary']['window_gap_minutes'] == 60
    assert all(r['task_slack_minutes'] == 90 for r in result['items'])
    assert all(r['level'] == 'high' for r in result['items'])
    assert all(r['window_gap_minutes'] == 60 for r in result['items'])


def test_overlapping_course_exam_and_exclusion_are_counted_as_a_union():
    course = {'id':'c','title':'合成课程','weekday':1,'weeks':[1], 'sections':[1]}
    exam = {'id':'exam','version':1,'kind':'exam','title':'合成考试','lifecycle':'active','certainty':'formal',
        'reserve_time':True,'time':{'precision':'exact','at':at('09:30').isoformat(),'end_at':at('10:30').isoformat()}}
    pref = {**AVAILABILITY,'exclusions':[{'start_at':at('10:00').isoformat(),'end_at':at('11:00').isoformat(),'label':'个人禁排'}]}
    row = run([task(minutes=90),exam],pref,[course])['items'][0]
    assert row['capacity_before_fixed_minutes'] == 240
    assert row['fixed_occupied_minutes'] == 120
    assert row['capacity_after_fixed_minutes'] == 120
    assert row['task_slack_minutes'] == 30


def test_only_future_time_counts_and_elapsed_time_never_reduces_work():
    item = task(minutes=60)
    row = run([item],now=at('12:30'))['items'][0]
    assert row['capacity_after_fixed_minutes'] == 30
    assert row['remaining_minutes'] == 60
    assert row['task_slack_minutes'] == -30
    assert item['remaining_minutes'] == 60


def test_missing_preferences_estimate_or_true_waiting_dependency_do_not_get_precise_slack():
    assert run([task()],{'configured':False,'weekly':[],'exclusions':[]})['items'][0]['task_slack_minutes'] is None
    assert run([task(minutes=None)])['items'][0]['task_slack_minutes'] is None
    item=task(start_policy='unconfirmed',details={'conditions':['收到审批结果后开始']})
    row=run([item])['items'][0]
    assert row['level']=='unknown' and row['task_slack_minutes'] is None
    assert 'needs_start' in row['reason_codes']


def test_ordinary_unconfirmed_start_and_eligibility_are_available_now():
    item=task(start_policy='unconfirmed',details={'conditions':['本科生','尚未申请']})
    row=run([item])['items'][0]
    assert row['level']=='low' and row['task_slack_minutes']==60
    assert 'needs_start' not in row['reason_codes'] and row['release_at']==at('08:00').astimezone(timezone.utc).isoformat()
    assert item['start_policy']=='unconfirmed' and item['earliest_start_at'] is None


def test_release_deadline_subwindow_exposes_hidden_overload():
    # Plenty of time in the morning cannot serve tasks that only become available at noon.
    rows=[task('a',45,start_policy='at',earliest_start_at=at('12:00').isoformat()),
          task('b',45,start_policy='at',earliest_start_at=at('12:00').isoformat())]
    result=run(rows)
    assert result['summary']['window_gap_minutes']==30
    assert result['summary']['critical_window']['capacity_minutes']==60


def test_unknown_exam_end_masks_precise_capacity_and_tentative_unreserved_does_not_block():
    exam={'id':'exam','kind':'exam','lifecycle':'active','title':'待核对考试','certainty':'tentative',
          'reserve_time':True,'time':{'precision':'exact','at':at('10:00').isoformat()}}
    result=run([task(),exam]);row=result['items'][0]
    assert row['task_slack_minutes'] is None and 'uncertain_exam' in row['reason_codes']
    assert row['capacity_after_fixed_minutes']==60 and row['uncertainty_excluded_minutes']==180
    assert row['fixed_occupied_minutes']==0 and row['level']=='medium'
    assert row['window_gap_minutes']==0 and row['data_complete']
    assert result['uncertainty_warnings'][0]['exclusion_applied']
    assert exam['time'].get('end_at') is None
    row=run([task(),{**exam,'reserve_time':False}])['items'][0]
    assert row['task_slack_minutes']==60
    assert row['level']=='medium' and 'uncertain_exam' in row['reason_codes']


def test_unknown_end_stays_uncertain_later_but_known_shortage_and_fixed_conflict_remain_high():
    exam={'id':'exam','kind':'exam','lifecycle':'active','title':'结束待核对考试','certainty':'formal',
          'reserve_time':True,'time':{'precision':'exact','at':'2026-09-20T23:00:00+08:00'}}
    row=run([task(minutes=60),exam])['items'][0]
    assert row['task_slack_minutes'] is None and row['level']=='medium'
    assert row['capacity_after_fixed_minutes']==240 and row['uncertainty_excluded_minutes']==0
    assert row['capacity_is_upper_bound'] and 'uncertain_exam' in row['reason_codes']
    shortage=run([task(minutes=300),exam])['items'][0]
    assert shortage['level']=='high' and shortage['window_gap_minutes']==60
    assert shortage['critical_window']['capacity_is_upper_bound']
    course={'id':'course','title':'已知课程','weekday':1,'weeks':[1], 'sections':[1]}
    exact={**exam,'id':'exact-exam','time':{'precision':'exact','at':at('09:00').isoformat(),'end_at':at('10:00').isoformat()}}
    conflict=run([task(minutes=30),exam,exact],courses=[course])['items'][0]
    assert conflict['level']=='high' and 'fixed_conflict' in conflict['reason_codes']


def test_capacity_without_a_contiguous_slot_is_not_reported_as_safe():
    pref={**AVAILABILITY,'weekly':[{'weekday':1,'start':'09:00','end':'10:00'},{'weekday':1,'start':'12:00','end':'13:00'}]}
    row=run([task(minutes=90,splittable=False)],pref)['items'][0]
    assert row['capacity_after_fixed_minutes']==120
    assert row['max_contiguous_minutes']==60
    assert row['level'] != 'low'


def test_completed_tasks_are_excluded_and_unknown_tasks_are_not_zero_work():
    result=run([task('done',1000,lifecycle='completed'),task('known',60),task('unknown',None)])
    assert [r['item_id'] for r in result['items']]==['known','unknown']
    assert result['summary']['incomplete_count']==1
    assert result['summary']['level']=='unknown'
    assert result['items'][0]['level']=='unknown'
    assert 'other_tasks_incomplete' in result['items'][0]['reason_codes']


def test_overdue_and_beyond_semester_have_explicit_different_reasons():
    overdue=run([task(due='09:00')],now=at('10:00'))['items'][0]
    assert overdue['level']=='high' and 'overdue' in overdue['reason_codes']
    future=task(time={'precision':'exact','at':'2099-01-01T00:00:00+08:00'})
    row=run([future])['items'][0]
    assert row['task_slack_minutes'] is None and 'outside_semester' in row['reason_codes']


def test_start_after_deadline_is_a_hard_conflict_and_input_is_not_silently_repaired():
    row=run([task(due='11:00',start_policy='at',earliest_start_at=at('12:00').isoformat())])['items'][0]
    assert row['level']=='high' and 'start_after_deadline' in row['reason_codes']
    assert row['task_slack_minutes']==-180


def test_discontinuous_sections_do_not_consume_the_gap_and_touching_windows_merge():
    semester={**SEMESTER,'periods':[*SEMESTER['periods'],{'number':3,'start':'12:00','end':'13:00'}]}
    c={'id':'course','title':'间隔课程','weekday':1,'weeks':[1],'sections':[1,3]}
    prefs={**AVAILABILITY,'weekly':[{'weekday':1,'start':'09:00','end':'11:00'},{'weekday':1,'start':'11:00','end':'13:00'}]}
    row=analyze(semester,prefs,[c],[task(minutes=60)],at('08:00'))['items'][0]
    assert row['capacity_before_fixed_minutes']==240
    assert row['capacity_after_fixed_minutes']==120


def test_tentative_task_deadline_is_not_promoted_to_a_confirmed_low_risk_fact():
    row=run([task(certainty='tentative')])['items'][0]
    assert row['level']=='unknown' and row['task_slack_minutes'] is None
    assert 'needs_deadline_confirmation' in row['reason_codes']


def test_interval_capacity_matches_an_independent_minute_bitmap():
    randomizer=random.Random(20260920)
    for _ in range(100):
        allowed=[sorted(randomizer.sample(range(241),2)) for _ in range(8)]
        blocked=[sorted(randomizer.sample(range(241),2)) for _ in range(8)]
        available_set={m for a,b in allowed for m in range(a,b)}
        blocked_set={m for a,b in blocked for m in range(a,b)}
        expected=available_set-blocked_set
        index=CapacityIndex(subtract([(a*60,b*60) for a,b in allowed],merge([(a*60,b*60) for a,b in blocked])))
        a,b=sorted(randomizer.sample(range(241),2))
        assert index.minutes(a*60,b*60)==len(expected & set(range(a,b)))


def test_real_plans_deduct_only_other_tasks_and_never_duplicate_window_demand():
    items=[task('a',180),task('b',60)]
    plans=[{'id':'pa','item_id':'a','start_at':at('09:00').isoformat(),'end_at':at('11:00').isoformat(),'minutes':120,'status':'active','locked':False},
           {'id':'pb','item_id':'b','start_at':at('11:00').isoformat(),'end_at':at('12:00').isoformat(),'minutes':60,'status':'active','locked':False}]
    result=analyze(SEMESTER,AVAILABILITY,[],items,at('08:00'),plans)
    a=result['items'][0]
    assert a['other_plan_minutes']==60 and a['task_slack_minutes']==0
    assert a['planned_minutes']==120 and a['unplanned_minutes']==60
    assert result['summary']['window_gap_minutes']==0
    later=analyze(SEMESTER,AVAILABILITY,[],items,at('12:01'),plans)
    assert later['items'][0]['planned_minutes']==0
    assert later['items'][0]['remaining_minutes']==180
