from test_capacity import SEMESTER,AVAILABILITY,task,at


def block(id,item,start,end,locked=False):
    return {'id':id,'item_id':item,'start_at':at(start).isoformat(),'end_at':at(end).isoformat(),
        'minutes':int((at(end)-at(start)).total_seconds()/60),'locked':locked,'version':1,'status':'active'}


def solve(plans,courses=(),items=None):
    from app.replanner import generate
    return generate(SEMESTER,AVAILABILITY,list(courses),items or [task('a',60),task('b',60)],plans,{'lead_minutes':0},at('08:00'))


def test_replan_moves_only_necessary_task_and_preserves_ids_lengths():
    plans=[block('p1','a','09:00','10:00'),block('p2','b','10:00','11:00')]
    course={'id':'c','title':'课','weekday':1,'weeks':[1],'sections':[1]}
    r=solve(plans,[course]);assert r['status']=='FEASIBLE_COMPLETE',r
    assert r['moved_tasks']==1 and r['shift_minutes']==120
    rows={b['id']:b for b in r['blocks']}
    assert rows['p1']['start_at']==at('11:00').astimezone(__import__('datetime').timezone.utc).isoformat()
    assert rows['p2']['start_at']==at('10:00').astimezone(__import__('datetime').timezone.utc).isoformat()
    assert all(b['minutes']==60 for b in rows.values())
    assert plans[0]['start_at']==at('09:00').isoformat()


def test_conflicting_locked_plan_is_not_moved_or_dropped():
    course={'id':'c','title':'课','weekday':1,'weeks':[1],'sections':[1]}
    r=solve([block('p1','a','09:00','10:00',True)],[course])
    assert r['status']=='INPUT_INVALID' and not r['can_apply']
    assert r['locked_conflicts'][0]['id']=='p1'


def test_infeasible_replan_keeps_old_blocks_and_reports_failure():
    r=solve([block('p1','a','09:00','10:00'),block('p2','b','10:00','11:00')],
        [{'occurrences':[{'id':'all','title':'活动','start_at':at('09:00').isoformat(),'end_at':at('13:00').isoformat()}]}])
    assert r['status']=='INFEASIBLE' and not r['can_apply']


def test_no_change_is_a_zero_movement_solution():
    r=solve([block('p1','a','09:00','10:00')])
    assert r['status']=='FEASIBLE_COMPLETE' and r['moved_tasks']==0 and not r['can_apply']


def test_overlap_with_movable_block_does_not_falsely_block_locked_plan():
    r=solve([block('p1','a','09:00','10:00',True),block('p2','b','09:30','10:30')])
    assert r['status']=='FEASIBLE_COMPLETE',r
    assert r['moved_tasks']==1 and r['shift_minutes']==30
    assert next(b for b in r['blocks'] if b['id']=='p1')['locked']
