from datetime import datetime
from app.scheduler import chunks, generate
from test_capacity import SEMESTER, AVAILABILITY, task, at


def request(*ids,partial=False,size=45,targets=None):
    return {'days':7,'lead_minutes':0,'chunk_minutes':size,'allow_partial':partial,
            'tasks':[{'item_id':id,'target_minutes':None if targets is None else targets[id]} for id in ids]}


def run(items,req=None,prefs=AVAILABILITY,plans=(),courses=()):
    return generate(SEMESTER,prefs,list(courses),items,list(plans),req or request(*(i['id'] for i in items)),at('08:00'))


def test_chunking_preserves_work_and_merges_short_tail():
    assert chunks(100)==[45,55]
    assert chunks(10)==[10]
    assert chunks(180,45,False)==[180]


def test_explicit_requested_window_constrains_every_new_block():
    req={**request('a',targets={'a':60}),'window_start_at':at('11:00').isoformat(),'window_end_at':at('12:00').isoformat()}
    result=run([task(minutes=180)],req)
    assert result['status']=='FEASIBLE_COMPLETE',result
    assert sum(b['minutes'] for b in result['blocks'])==60
    assert all(at('11:00')<=datetime.fromisoformat(b['start_at'])<datetime.fromisoformat(b['end_at'])<=at('12:00') for b in result['blocks'])


def test_complete_plan_has_no_overlap_and_respects_course_release_and_deadline():
    items=[task('a',60,start_policy='at',earliest_start_at=at('10:00').isoformat()),task('b',60)]
    course={'id':'c','title':'课程','weekday':1,'weeks':[1],'sections':[1]}
    result=run(items,courses=[course])
    assert result['status']=='FEASIBLE_COMPLETE',result
    assert sum(b['minutes'] for b in result['blocks'])==120
    spans=sorted((datetime.fromisoformat(b['start_at']),datetime.fromisoformat(b['end_at'])) for b in result['blocks'])
    assert all(a>=at('10:00') and b<=at('13:00') for a,b in spans)
    assert all(b<=c for (_,b),(c,_) in zip(spans,spans[1:]))
    assert all(i['remaining_minutes']==60 for i in items)


def test_partial_requires_explicit_request_and_reports_unarranged_work():
    items=[task('a',150),task('b',150)]
    full=run(items)
    assert full['status']=='INFEASIBLE' and full['blocks']==[]
    partial=run(items,request('a','b',partial=True))
    assert partial['status']=='FEASIBLE_PARTIAL'
    assert 0<sum(b['minutes'] for b in partial['blocks'])<=240
    assert partial['unarranged_minutes']==300-sum(b['minutes'] for b in partial['blocks'])


def test_split_failure_is_not_claimed_as_universal_infeasibility():
    prefs={**AVAILABILITY,'weekly':[{'weekday':1,'start':'09:00','end':'09:30'},{'weekday':1,'start':'12:00','end':'12:30'}]}
    assert run([task(minutes=60)],prefs=prefs)['status']=='CHUNKING_LIMITED'
    assert run([task(minutes=60)],request('a',size=30),prefs=prefs)['status']=='FEASIBLE_COMPLETE'
    assert run([task(minutes=60,splittable=False)],prefs=prefs)['status']=='INFEASIBLE'


def test_existing_coverage_is_preserved_not_added_to_remaining_work():
    plan={'id':'existing','item_id':'a','start_at':at('09:00').isoformat(),'end_at':at('10:00').isoformat(),
          'minutes':60,'status':'active','locked':True,'version':1}
    result=run([task(minutes=120)],plans=[plan])
    assert result['status']=='FEASIBLE_COMPLETE'
    assert sum(b['minutes'] for b in result['blocks'])==60
    assert result['tasks'][0]['existing_minutes']==60
    assert plan['start_at']==at('09:00').isoformat() and plan['locked']


def test_unknown_deadline_uses_known_remaining_effort_and_accepts_explicit_round_target():
    item=task(time={'precision':'unknown'},certainty='unknown')
    result=run([item])
    assert result['status']=='FEASIBLE_COMPLETE'
    assert sum(b['minutes'] for b in result['blocks'])==180
    assert result['tasks'][0]['later_minutes']==0
    assert item['time']=={'precision':'unknown'} and item['earliest_start_at'] is None
    result=run([item],request('a',targets={'a':60}))
    assert result['status']=='FEASIBLE_COMPLETE'
    assert result['tasks'][0]['later_minutes']==120


def test_reserved_unknown_exam_excludes_known_day_and_overallocated_plans_remain_invalid():
    exam={'id':'exam','kind':'exam','lifecycle':'active','title':'待核对考试','certainty':'tentative',
          'reserve_time':True,'time':{'precision':'exact','at':at('10:00').isoformat()}}
    result=run([task(),exam],request('a'))
    assert result['status']=='INFEASIBLE' and result['blocks']==[]
    assert result['uncertainty_warnings'][0]['exclusion_applied']
    later=task(time={'precision':'exact','at':'2026-09-28T13:00:00+08:00'},
        start_policy='at',earliest_start_at=at('10:00').isoformat())
    result=run([later,exam],{**request('a'),'days':14})
    assert result['status']=='FEASIBLE_COMPLETE'
    assert all(datetime.fromisoformat(b['start_at']).astimezone(at('08:00').tzinfo).date().isoformat()=='2026-09-28' for b in result['blocks'])
    assert result['uncertainty_warnings'] and exam['time'].get('end_at') is None
    plan={'id':'p','item_id':'a','start_at':at('09:00').isoformat(),'end_at':at('11:00').isoformat(),
          'minutes':120,'status':'active','locked':False,'version':1}
    assert run([task(minutes=60)],plans=[plan])['status']=='INPUT_INVALID'


def test_unsplittable_partial_existing_coverage_cannot_be_supplemented_discontinuously():
    plan={'id':'p','item_id':'a','start_at':at('09:00').isoformat(),'end_at':at('10:00').isoformat(),
          'minutes':60,'status':'active','locked':True,'version':1}
    assert run([task(minutes=120,splittable=False)],plans=[plan])['status']=='INPUT_INVALID'


def test_oversized_chunk_request_is_rejected_before_materializing_chunks(monkeypatch):
    import app.scheduler as scheduler
    monkeypatch.setattr(scheduler,'chunks',lambda *args: (_ for _ in ()).throw(AssertionError('must check count first')))
    result=run([task(minutes=525600)],request('a',size=15))
    assert result['status']=='INPUT_LIMIT'
