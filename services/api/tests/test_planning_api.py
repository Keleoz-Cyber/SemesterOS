from datetime import datetime

from test_foundation import client, register, semester


def prepare(client):
    _, h = register(client)
    return h, semester(client,h)


def item(client,h,s,**extra):
    r=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'合成任务',
        'time':{'precision':'exact','at':'2026-09-21T13:00:00+08:00'},'remaining_minutes':150,'start_policy':'now','certainty':'formal',**extra})
    assert r.status_code==201,r.text
    return r.json()


def settings(client,h,s):
    path=f"/api/v1/semesters/{s['id']}/availability"
    old=client.get(path,headers=h)
    assert old.status_code==200,old.text
    data={'expected_version':old.json()['version'],'weekly':[{'weekday':1,'start':'09:00','end':'13:00'}],'exclusions':[]}
    preview=client.post(path+'/preview',headers=h,json=data)
    assert preview.status_code==200,preview.text
    saved=client.put(path,headers=h,json={**data,'expected_revision':preview.json()['base_revision']})
    assert saved.status_code==200,saved.text
    return saved.json()


def test_settings_preview_is_readonly_and_confirm_requires_fresh_version(client):
    h,s=prepare(client)
    path=f"/api/v1/semesters/{s['id']}/availability"
    old=client.get(path,headers=h)
    assert old.status_code==200,old.text
    assert not old.json()['configured']
    data={'expected_version':0,'weekly':[{'weekday':1,'start':'19:00','end':'21:00'}],'exclusions':[]}
    preview=client.post(path+'/preview',headers=h,json=data)
    assert preview.status_code==200
    assert not client.get(path,headers=h).json()['configured']
    body={**data,'expected_revision':preview.json()['base_revision']}
    headers={**h,'Idempotency-Key':'settings-once'}
    saved=client.put(path,headers=headers,json=body)
    assert saved.status_code==200
    assert client.put(path,headers=headers,json=body).json()==saved.json()
    assert client.put(path,headers=h,json=body).status_code==409


def test_settings_and_risk_are_owner_scoped_and_reject_invalid_spans(client):
    h,s=prepare(client)
    _,other=register(client,'student_b')
    path=f"/api/v1/semesters/{s['id']}"
    assert client.get(path+'/risk',headers=other).status_code==404
    assert client.get(path+'/availability',headers=other).status_code==404
    body={'expected_version':0,'weekly':[{'weekday':1,'start':'23:00','end':'01:00'}],'exclusions':[]}
    assert client.post(path+'/availability/preview',headers=h,json=body).status_code==422


def test_shared_window_risk_uses_real_saved_tasks_and_does_not_modify_them(client,monkeypatch):
    from app import planning
    monkeypatch.setattr(planning,'utcnow',lambda:datetime.fromisoformat('2026-09-21T08:00:00+08:00'))
    h,s=prepare(client)
    settings(client,h,s)
    a=item(client,h,s); b=item(client,h,s)
    r=client.get(f"/api/v1/semesters/{s['id']}/risk",headers=h)
    assert r.status_code==200,r.text
    assert r.json()['summary']['window_gap_minutes']==60
    assert all(row['level']=='high' for row in r.json()['items'])
    assert r.json()['revision']==3
    assert client.get(f"/api/v1/items/{a['id']}",headers=h).json()['remaining_minutes']==150
    assert client.get(f"/api/v1/items/{b['id']}",headers=h).json()['version']==1


def test_exam_end_and_start_policy_validation_and_legacy_unknown(client):
    h,s=prepare(client)
    legacy=item(client,h,s,start_policy='unconfirmed')
    assert legacy['start_policy']=='unconfirmed'
    body={'semester_id':s['id'],'kind':'exam','title':'考试','time':{'precision':'exact',
        'at':'2026-09-21T10:00:00+08:00','end_at':'2026-09-21T09:00:00+08:00'}}
    assert client.post('/api/v1/items',headers=h,json=body).status_code==422
    body['time']['end_at']='2026-09-21T11:00:00+08:00'
    assert client.post('/api/v1/items',headers=h,json=body).status_code==201


def test_progress_preview_preserves_work_then_confirmation_completes_and_cancels(client):
    h,s=prepare(client)
    a=item(client,h,s,time={'precision':'exact','at':'2099-09-21T13:00:00+08:00'},reminders=[{'mode':'relative','lead_minutes':120}])
    path=f"/api/v1/items/{a['id']}/progress"
    body={'expected_version':1,'remaining_minutes':0,'actual_minutes':60,'note':'本人确认做完'}
    p=client.post(path+'/preview',headers=h,json=body)
    assert p.status_code==200,p.text
    assert client.get(f"/api/v1/items/{a['id']}",headers=h).json()['remaining_minutes']==150
    data={**body,'expected_revision':p.json()['base_revision']}
    assert client.post(path,headers=h,json=data).status_code==422
    data['confirm_complete']=True
    headers={**h,'Idempotency-Key':'progress-once'}
    done=client.post(path,headers=headers,json=data)
    assert done.status_code==200,done.text
    assert done.json()['lifecycle']=='completed' and done.json()['remaining_minutes']==0
    assert client.post(path,headers=headers,json=data).json()==done.json()
    assert client.get('/api/v1/reminders',headers=h).json()['reminders']==[]
    history=client.get(path,headers=h).json()
    assert len(history)==1 and history[0]['before_remaining_minutes']==150 and history[0]['actual_minutes']==60
    restored=client.post(f"/api/v1/items/{a['id']}/lifecycle",headers=h,json={'expected_version':2,'lifecycle':'active'})
    assert restored.json()['remaining_minutes'] is None


def test_actual_time_is_not_automatically_subtracted_and_stale_progress_is_rejected(client):
    h,s=prepare(client)
    a=item(client,h,s)
    path=f"/api/v1/items/{a['id']}/progress"
    body={'expected_version':1,'remaining_minutes':120,'actual_minutes':60,'note':'剩余部分比预期多'}
    p=client.post(path+'/preview',headers=h,json=body)
    assert p.status_code==200,p.text
    settings(client,h,s)
    assert client.post(path,headers=h,json={**body,'expected_revision':p.json()['base_revision']}).status_code==409
    p=client.post(path+'/preview',headers=h,json=body).json()
    done=client.post(path,headers=h,json={**body,'expected_revision':p['base_revision']})
    assert done.status_code==200,done.text
    assert done.json()['remaining_minutes']==120


def test_legacy_edit_preserves_planning_fields_but_explicit_clear_is_respected(client):
    h,s=prepare(client)
    a=item(client,h,s)
    data={'semester_id':s['id'],'kind':'task','title':'标题修正','time':a['time'],
          'certainty':'formal','remaining_minutes':150,'expected_version':1,'change_reason':'核对标题'}
    changed=client.patch(f"/api/v1/items/{a['id']}",headers=h,json=data)
    assert changed.status_code==200
    assert changed.json()['start_policy']=='now'
    data.update(expected_version=2,start_policy='unconfirmed',earliest_start_at=None)
    assert client.patch(f"/api/v1/items/{a['id']}",headers=h,json=data).json()['start_policy']=='unconfirmed'
    exam=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'exam','title':'考试',
        'time':{'precision':'exact','at':'2026-09-21T09:00:00+08:00','end_at':'2026-09-21T11:00:00+08:00'}}).json()
    edit={'semester_id':s['id'],'kind':'exam','title':'考试地点核对','time':{'precision':'exact','at':exam['time']['at']},
          'expected_version':1,'change_reason':'补充地点','location':'A305'}
    response=client.patch(f"/api/v1/items/{exam['id']}",headers=h,json=edit)
    assert response.status_code==200
    assert response.json()['time']['end_at']==exam['time']['end_at']
    edit['expected_version']=2;edit['time']['end_at']=None
    assert client.patch(f"/api/v1/items/{exam['id']}",headers=h,json=edit).json()['time']['end_at'] is None
