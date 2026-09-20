from datetime import datetime
from test_foundation import client,register,semester


def setup(client,monkeypatch,minutes=120):
    from app import planning,schedule_api
    now=lambda:datetime.fromisoformat('2026-09-21T08:00:00+08:00')
    monkeypatch.setattr(planning,'utcnow',now);monkeypatch.setattr(schedule_api,'utcnow',now)
    _,h=register(client);s=semester(client,h);path=f"/api/v1/semesters/{s['id']}"
    body={'expected_version':0,'weekly':[{'weekday':1,'start':'09:00','end':'13:00'}],'exclusions':[]}
    p=client.post(path+'/availability/preview',headers=h,json=body).json()
    assert client.put(path+'/availability',headers=h,json={**body,'expected_revision':p['base_revision']}).status_code==200
    item=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'合成排程任务',
        'time':{'precision':'exact','at':'2026-09-21T13:00:00+08:00'},'certainty':'formal','remaining_minutes':minutes,'start_policy':'now'}).json()
    return h,s,item


def proposal(client,h,s,item,partial=False):
    r=client.post(f"/api/v1/semesters/{s['id']}/plan-proposals",headers=h,json={'days':7,'lead_minutes':0,'chunk_minutes':45,
        'allow_partial':partial,'tasks':[{'item_id':item['id']}]})
    assert r.status_code==201,r.text
    return r.json()


def accept(client,h,p,**extra):
    return client.post(f"/api/v1/plan-proposals/{p['id']}/accept",headers=h,json={'expected_version':p['version'],'expected_revision':p['base_revision'],**extra})


def test_generation_is_readonly_accept_is_idempotent_and_undo_only_removes_its_plans(client,monkeypatch):
    h,s,item=setup(client,monkeypatch)
    p=proposal(client,h,s,item)
    assert p['status']=='FEASIBLE_COMPLETE'
    assert client.get(f"/api/v1/semesters/{s['id']}/plans",headers=h).json()['blocks']==[]
    applied=accept(client,h,p);assert applied.status_code==200,applied.text
    assert accept(client,h,p).json()==applied.json()
    data=client.get(f"/api/v1/semesters/{s['id']}/plans",headers=h).json()
    assert sum(b['minutes'] for b in data['blocks'])==120
    assert client.get(f"/api/v1/items/{item['id']}",headers=h).json()['remaining_minutes']==120
    undone=client.post(f"/api/v1/plan-proposals/{p['id']}/undo",headers=h,json={'expected_version':2,'expected_revision':data['revision']})
    assert undone.status_code==200,undone.text
    assert client.get(f"/api/v1/semesters/{s['id']}/plans",headers=h).json()['blocks']==[]


def test_owner_stale_snapshot_and_lock_changes_are_guarded(client,monkeypatch):
    h,s,item=setup(client,monkeypatch);_,other=register(client,'student_b')
    p=proposal(client,h,s,item)
    assert accept(client,other,p).status_code==404
    assert client.get(f"/api/v1/semesters/{s['id']}/plans",headers=other).status_code==404
    assert accept(client,h,p).status_code==200
    feed=client.get(f"/api/v1/semesters/{s['id']}/plans",headers=h).json();b=feed['blocks'][0]
    lock=client.patch(f"/api/v1/plan-blocks/{b['id']}/lock",headers=h,json={'expected_version':1,'locked':True})
    assert lock.status_code==200
    assert client.post(f"/api/v1/plan-blocks/{b['id']}/cancel",headers=h,json={'expected_version':2}).status_code==422
    assert client.post(f"/api/v1/plan-blocks/{b['id']}/cancel",headers=other,json={'expected_version':2,'confirm_locked':True}).status_code==404
    new=proposal(client,h,s,item)
    assert new['blocks']==[] and new['tasks'][0]['existing_minutes']==120
    assert client.post(f"/api/v1/plan-proposals/{p['id']}/undo",headers=h,json={'expected_version':2,'expected_revision':feed['revision']+1}).status_code==409


def test_partial_requires_explicit_acceptance_and_changes_make_proposal_stale(client,monkeypatch):
    h,s,item=setup(client,monkeypatch,minutes=300)
    p=proposal(client,h,s,item);assert p['status']=='INFEASIBLE'
    p=proposal(client,h,s,item,partial=True);assert p['status']=='FEASIBLE_PARTIAL'
    assert accept(client,h,p).status_code==422
    assert accept(client,h,p,confirm_partial=True,unarranged_minutes=p['unarranged_minutes']).status_code==200
    other=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'额外任务','remaining_minutes':15,
        'time':{'precision':'exact','at':'2026-09-21T13:00:00+08:00'},'certainty':'formal','start_policy':'now'}).json()
    fresh=proposal(client,h,s,other,partial=True)
    client.post(f"/api/v1/items/{other['id']}/lifecycle",headers=h,json={'expected_version':1,'lifecycle':'cancelled'})
    assert accept(client,h,fresh,confirm_partial=True,unarranged_minutes=fresh['unarranged_minutes']).status_code==409


def test_elapsed_coverage_invalidates_partial_proposal_accounting(client,monkeypatch):
    from app import schedule_api
    h,s,item=setup(client,monkeypatch,minutes=60)
    first=proposal(client,h,s,item);assert accept(client,h,first).status_code==200
    edit={'semester_id':s['id'],'kind':'task','title':item['title'],'time':item['time'],'certainty':'formal',
          'remaining_minutes':300,'start_policy':'now','expected_version':1,'change_reason':'重新估计剩余工作'}
    assert client.patch(f"/api/v1/items/{item['id']}",headers=h,json=edit).status_code==200
    p=proposal(client,h,s,item,partial=True);assert p['status']=='FEASIBLE_PARTIAL'
    monkeypatch.setattr(schedule_api,'utcnow',lambda:datetime.fromisoformat('2026-09-21T10:00:00+08:00'))
    assert accept(client,h,p,confirm_partial=True,unarranged_minutes=p['unarranged_minutes']).status_code==409


def test_progress_requires_selecting_future_plans_and_explicit_locked_cancellation(client,monkeypatch):
    h,s,item=setup(client,monkeypatch)
    p=proposal(client,h,s,item);accept(client,h,p)
    feed=client.get(f"/api/v1/semesters/{s['id']}/plans",headers=h).json();b=feed['blocks'][0]
    client.patch(f"/api/v1/plan-blocks/{b['id']}/lock",headers=h,json={'expected_version':1,'locked':True})
    body={'expected_version':1,'remaining_minutes':0,'note':'确认完成'}
    path=f"/api/v1/items/{item['id']}/progress"
    preview=client.post(path+'/preview',headers=h,json=body).json()
    assert preview['affected_plan_count']>0
    data={**body,'expected_revision':preview['base_revision'],'confirm_complete':True}
    assert client.post(path,headers=h,json=data).status_code==409
    data['cancel_plan_ids']=[b['id'] for b in preview['affected_blocks']]
    assert client.post(path,headers=h,json=data).status_code==422
    data['confirm_locked_cancellation']=True
    assert client.post(path,headers=h,json=data).status_code==200
    assert client.get(f"/api/v1/semesters/{s['id']}/plans",headers=h).json()['blocks']==[]


def test_learning_time_change_reports_conflicting_plans_and_preserves_locked_positions(client,monkeypatch):
    h,s,item=setup(client,monkeypatch);p=proposal(client,h,s,item);accept(client,h,p)
    path=f"/api/v1/semesters/{s['id']}"
    original=client.get(path+'/plans',headers=h).json()['blocks']
    b=original[0];client.patch(f"/api/v1/plan-blocks/{b['id']}/lock",headers=h,json={'expected_version':1,'locked':True})
    prefs={'expected_version':1,'weekly':[],'exclusions':[]}
    preview=client.post(path+'/availability/preview',headers=h,json=prefs).json()
    assert preview['affected_plan_count']==len(original)
    data={**prefs,'expected_revision':preview['base_revision']}
    assert client.put(path+'/availability',headers=h,json=data).status_code==422
    assert client.put(path+'/availability',headers=h,json={**data,'confirm_plan_conflicts':True}).status_code==200
    feed=client.get(path+'/plans',headers=h).json()
    assert [(b['start_at'],b['end_at']) for b in feed['blocks']]==[(b['start_at'],b['end_at']) for b in original]
    assert feed['invalid_blocks']
    assert client.get(path+'/risk',headers=h).json()['summary']['plan_conflict_count']>0
