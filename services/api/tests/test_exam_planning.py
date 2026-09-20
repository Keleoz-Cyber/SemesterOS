from test_foundation import client,register,semester


def setup(client):
    _,h=register(client);s=semester(client,h)
    exam=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'exam','title':'合成考试',
        'time':{'precision':'exact','at':'2026-12-01T10:00:00+08:00','end_at':'2026-12-01T12:00:00+08:00'},'certainty':'formal'}).json()
    return h,s,exam


def test_review_creation_is_explicit_linked_and_idempotent(client):
    h,s,e=setup(client);path=f"/api/v1/exams/{e['id']}/reviews"
    body={'expected_exam_version':1,'remaining_minutes':180,'deadline_mode':'exam'}
    r=client.post(path,headers={**h,'Idempotency-Key':'review'},json=body)
    assert r.status_code==201,r.text
    task=r.json();assert task['review_exam_id']==e['id'] and task['remaining_minutes']==180
    assert client.post(path,headers={**h,'Idempotency-Key':'review'},json=body).json()==task
    assert client.post(path,headers=h,json=body).status_code==409
    edit={k:task[k] for k in ('semester_id','kind','title','course_id','time','certainty','remaining_minutes')}
    edit.update(expected_version=1,change_reason='修订任务说明')
    updated=client.patch(f"/api/v1/items/{task['id']}",headers=h,json=edit)
    assert updated.status_code==200 and updated.json()['review_exam_id']==e['id']


def test_exam_reschedule_preview_keeps_work_and_updates_review_only_when_confirmed(client):
    h,s,e=setup(client)
    review=client.post(f"/api/v1/exams/{e['id']}/reviews",headers=h,json={'expected_exam_version':1,'remaining_minutes':120,'deadline_mode':'exam'}).json()
    body={'expected_version':1,'time':{'precision':'exact','at':'2026-12-02T10:00:00+08:00','end_at':'2026-12-02T12:00:00+08:00'},
        'certainty':'formal','location':'B101','reason':'正'*500,'align_review_deadlines':True}
    path=f"/api/v1/exams/{e['id']}/reschedule"
    p=client.post(path+'/preview',headers=h,json=body);assert p.status_code==200,p.text
    from datetime import datetime
    assert datetime.fromisoformat(p.json()['after']['anchor_at'])==datetime.fromisoformat(body['time']['at'])
    assert client.get(f"/api/v1/items/{e['id']}",headers=h).json()['time']==e['time']
    r=client.post(path,headers=h,json={**body,'preview_token':p.json()['preview_token'],'expected_revision':p.json()['base_revision'],'confirm_fixed_conflicts':False})
    assert r.status_code==200,r.text
    assert {i['id'] for i in r.json()['changed_items']}=={e['id'],review['id']}
    task=client.get(f"/api/v1/items/{review['id']}",headers=h).json()
    assert task['time']['at']=='2026-12-02T02:00:00Z' and task['remaining_minutes']==120
    assert client.post(path,headers=h,json={**body,'preview_token':p.json()['preview_token'],'expected_revision':p.json()['base_revision']}).status_code==409


def test_tentative_exam_cannot_invent_review_deadline_and_link_requires_owner(client):
    h,s,e=setup(client)
    tentative=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'exam','title':'暂定考试',
        'time':{'precision':'week','week':14},'certainty':'tentative'}).json()
    path=f"/api/v1/exams/{tentative['id']}/reviews"
    assert client.post(path,headers=h,json={'expected_exam_version':1,'remaining_minutes':120,'deadline_mode':'exam'}).status_code==422
    r=client.post(path,headers=h,json={'expected_exam_version':1,'remaining_minutes':120,'deadline_mode':'unknown'})
    assert r.status_code==201 and r.json()['time']['precision']=='unknown'
    _,other=register(client,'student_b')
    assert client.post(f"/api/v1/exams/{e['id']}/reviews",headers=other,json={'expected_exam_version':1,'remaining_minutes':120}).status_code==404


def test_reschedule_recomputes_reminder_and_keeps_review_deadline_by_default(client):
    h,s,e=setup(client)
    review=client.post(f"/api/v1/exams/{e['id']}/reviews",headers=h,json={'expected_exam_version':1,'remaining_minutes':120,'deadline_mode':'exam'}).json()
    reminder=client.post(f"/api/v1/items/{e['id']}/reminders",headers=h,json={'expected_item_version':1,'mode':'relative','lead_minutes':1440}).json()
    body={'expected_version':1,'time':{'precision':'exact','at':'2026-11-30T10:00:00+08:00','end_at':'2026-11-30T12:00:00+08:00'},'certainty':'formal','reason':'正式通知'}
    path=f"/api/v1/exams/{e['id']}/reschedule"
    p=client.post(path+'/preview',headers=h,json=body).json()
    assert p['reminders_after'][0]['trigger_at']!=reminder['trigger_at']
    r=client.post(path,headers=h,json={**body,'preview_token':p['preview_token'],'expected_revision':p['base_revision']})
    assert r.status_code==200,r.text
    assert client.get(f"/api/v1/items/{review['id']}",headers=h).json()['time']==review['time']
    hub=client.get(f"/api/v1/semesters/{s['id']}/hub",headers=h).json()
    assert hub['exams'][0]['issues']
    assert r.json()['item']['reminders'][0]['version']==reminder['version']+1
    bad={**body,'expected_version':2,'reserve_time':False}
    assert client.post(path+'/preview',headers=h,json=bad).status_code==422


def test_link_existing_task_preserves_its_effort_and_deadline(client):
    h,s,e=setup(client)
    task=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'已有复习','remaining_minutes':75}).json()
    r=client.post(f"/api/v1/exams/{e['id']}/reviews",headers=h,json={'expected_exam_version':1,'task_id':task['id'],'expected_task_version':1})
    assert r.status_code==201,r.text
    assert r.json()['remaining_minutes']==75 and r.json()['time']==task['time']
    assert r.json()['id']==task['id'] and r.json()['review_exam_id']==e['id']


def test_reminder_added_after_preview_invalidates_exam_change(client):
    h,s,e=setup(client)
    body={'expected_version':1,'time':{'precision':'exact','at':'2026-11-25T10:00:00+08:00'},'certainty':'formal','reason':'改期'}
    path=f"/api/v1/exams/{e['id']}/reschedule"
    p=client.post(path+'/preview',headers=h,json=body).json()
    client.post(f"/api/v1/items/{e['id']}/reminders",headers=h,json={'expected_item_version':1,'mode':'absolute','trigger_at':'2026-11-28T10:00:00+08:00','purpose':'start_review'})
    assert client.post(path,headers=h,json={**body,'preview_token':p['preview_token'],'expected_revision':p['base_revision'],**({'preview_token':p['preview_token']} if 'preview_token' in p else {})}).status_code==409
