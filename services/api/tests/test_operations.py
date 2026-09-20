from test_foundation import client,register,semester


def test_unused_model_branches_can_be_null_but_relevant_enums_remain_strict(client):
    h,s,item=setup(client)
    r=parse(client,h,s,{'intent':'update_task','target_query':'Java报告','task_patch':{'remaining_minutes':120},'reminder_action':None,'reminder_patch':None,'plan_mode':None})
    assert r.status_code==201 and r.json()['phase']=='ready'
    assert parse(client,h,s,{'intent':'update_reminder','reminder_action':None},'修改提醒').status_code==502


def setup(client):
    _,h=register(client);s=semester(client,h)
    item=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'Java报告','remaining_minutes':180,'start_policy':'now'}).json()
    return h,s,item


def parse(client,h,s,answer,text='Java报告还需要两小时'):
    client.app.state.operation_model=lambda *args:(answer,{'provider':'test'})
    return client.post('/api/v1/operations/parse',headers=h,json={'semester_id':s['id'],'text':text,'reference_at':'2026-09-20T00:00:00Z'})


def test_task_operation_preview_is_readonly_and_apply_is_idempotent(client):
    h,s,item=setup(client)
    r=parse(client,h,s,{'intent':'update_task','target_query':'Java报告','task_patch':{'remaining_minutes':120}})
    assert r.status_code==201,r.text
    p=r.json();assert p['phase']=='ready'
    assert client.get(f"/api/v1/items/{item['id']}",headers=h).json()['remaining_minutes']==180
    body={'expected_version':p['version']}
    applied=client.post(f"/api/v1/operations/{p['id']}/apply",headers=h,json=body)
    assert applied.status_code==200,applied.text
    assert client.post(f"/api/v1/operations/{p['id']}/apply",headers=h,json=body).json()==applied.json()
    after=client.get(f"/api/v1/items/{item['id']}",headers=h).json()
    assert after['remaining_minutes']==120 and after['version']==2


def test_duplicate_titles_require_selection_and_foreign_target_is_rejected(client):
    h,s,item=setup(client)
    client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'Java报告','remaining_minutes':60})
    p=parse(client,h,s,{'intent':'update_task','target_query':'Java报告','task_patch':{'remaining_minutes':120}}).json()
    assert p['phase']=='needs_clarification' and len(p['choices'])==2
    assert client.post(f"/api/v1/operations/{p['id']}/apply",headers=h,json={'expected_version':p['version']}).status_code==409
    _,other=register(client,'student_b')
    assert client.get(f"/api/v1/operations/{p['id']}",headers=other).status_code==404
    r=client.post(f"/api/v1/operations/{p['id']}/resolve",headers=h,json={'expected_version':p['version'],'target_item_id':item['id']})
    assert r.status_code==200 and r.json()['phase']=='ready'


def test_vague_evening_never_becomes_invented_twenty_oclock(client):
    h,s,item=setup(client)
    p=parse(client,h,s,{'intent':'update_reminder','target_query':'Java报告','reminder_action':'add',
        'reminder_patch':{'mode':'absolute','trigger_at':'2026-09-24T20:00:00+08:00'}},'Java报告提醒改到周四晚上').json()
    assert p['phase']=='needs_clarification'
    assert p['suggestion']['reminder_patch']['trigger_at'] is None


def test_unknown_patch_fields_cannot_modify_deadline_or_unlock(client):
    h,s,item=setup(client)
    r=parse(client,h,s,{'intent':'update_task','target_query':'Java报告','task_patch':{'time':{'at':'2026-09-25T00:00:00Z'}}})
    assert r.status_code==502


def test_multiple_reminders_require_selection_and_peer_changes_invalidate_preview(client):
    h,s,item=setup(client)
    ids=[]
    for hour in (10,12):
        r=client.post(f"/api/v1/items/{item['id']}/reminders",headers=h,json={'expected_item_version':1,'mode':'absolute','trigger_at':f'2026-12-01T{hour}:00:00+08:00'})
        assert r.status_code==201;ids.append(r.json()['id'])
    p=parse(client,h,s,{'intent':'update_reminder','target_query':'Java报告','reminder_action':'edit','reminder_patch':{'mode':'absolute','trigger_at':'2026-12-02T20:00:00+08:00'}},'Java报告提醒改成12月2日晚上八点').json()
    assert p['phase']=='needs_clarification'
    p=client.post(f"/api/v1/operations/{p['id']}/resolve",headers=h,json={'expected_version':p['version'],'target_item_id':item['id'],'reminder_id':ids[0]}).json()
    assert p['phase']=='ready'
    client.post(f"/api/v1/items/{item['id']}/reminders",headers=h,json={'expected_item_version':1,'mode':'absolute','trigger_at':'2026-12-03T10:00:00+08:00'})
    assert client.get(f"/api/v1/operations/{p['id']}",headers=h).json()['phase']=='stale'
    assert client.post(f"/api/v1/operations/{p['id']}/apply",headers=h,json={'expected_version':p['version']}).status_code==409


def test_disabling_reminder_keeps_task_time_and_revision(client):
    h,s,item=setup(client)
    rule=client.post(f"/api/v1/items/{item['id']}/reminders",headers=h,json={'expected_item_version':1,'mode':'absolute','trigger_at':'2026-12-01T10:00:00+08:00'}).json()
    revision=client.get('/api/v1/semesters',headers=h).json()[0]['revision']
    p=parse(client,h,s,{'intent':'update_reminder','target_query':'Java报告','reminder_action':'disable'},'停用Java报告提醒').json()
    assert p['phase']=='ready'
    r=client.post(f"/api/v1/operations/{p['id']}/apply",headers=h,json={'expected_version':p['version']})
    assert r.status_code==200,r.text
    after=r.json()['changed_items'][0]
    assert after['time']==item['time'] and after['version']==item['version']
    assert after['reminders'][0]['id']==rule['id'] and not after['reminders'][0]['enabled']
    assert r.json()['revision']==revision


def test_work_reduction_requires_explicit_future_block_and_locked_cancellation(client,monkeypatch):
    from test_schedule_api import setup as planning_setup,proposal,accept
    h,s,item=planning_setup(client,monkeypatch,minutes=120)
    original=proposal(client,h,s,item);assert accept(client,h,original).status_code==200
    plans=client.get(f"/api/v1/semesters/{s['id']}/plans",headers=h).json()['blocks']
    client.patch(f"/api/v1/plan-blocks/{plans[0]['id']}/lock",headers=h,json={'expected_version':1,'locked':True})
    p=parse(client,h,s,{'intent':'update_task','target_query':item['title'],'task_patch':{'remaining_minutes':30}},f"{item['title']}还需30分钟").json()
    endpoint=f"/api/v1/operations/{p['id']}/apply";body={'expected_version':p['version']}
    assert client.post(endpoint,headers=h,json=body).status_code==422
    body['cancel_plan_ids']=[b['id'] for b in plans]
    assert client.post(endpoint,headers=h,json=body).status_code==422
    body['confirm_locked_cancellation']=True
    assert client.post(endpoint,headers=h,json=body).status_code==200
    assert client.get(f"/api/v1/semesters/{s['id']}/plans",headers=h).json()['blocks']==[]


def test_planning_handoff_does_not_generate_or_apply_any_blocks(client):
    h,s,item=setup(client)
    p=parse(client,h,s,{'intent':'request_plan','target_query':'Java报告','plan_mode':'replan'},'把Java报告重新安排一下').json()
    assert p['phase']=='needs_clarification'
    p=client.post(f"/api/v1/operations/{p['id']}/resolve",headers=h,json={'expected_version':p['version'],'plan_mode':'replan','tasks':[{'item_id':item['id']}]}).json()
    assert p['phase']=='ready'
    receipt=client.post(f"/api/v1/operations/{p['id']}/apply",headers=h,json={'expected_version':p['version']}).json()
    assert receipt['planning_request']['task_ids']==[item['id']]
    assert client.get(f"/api/v1/semesters/{s['id']}/plans",headers=h).json()['blocks']==[]


def test_image_instruction_requires_explicit_user_intent_confirmation(client,tmp_path):
    from test_media import png
    client.app.state.media_root=tmp_path/'media'
    h,s,item=setup(client)
    source=client.post(f"/api/v1/semesters/{s['id']}/sources?kind=image",headers={**h,'Idempotency-Key':'image'},content=png()).json()
    source=client.patch(f"/api/v1/sources/{source['id']}",headers=h,json={'expected_version':source['version'],'text':'Java报告还需要两小时','reference_at':source['reference_at']}).json()
    client.app.state.operation_model=lambda *args:({'intent':'update_task','target_query':'Java报告','task_patch':{'remaining_minutes':120}},{'provider':'test'})
    payload={'semester_id':s['id'],'text':'Java报告还需要两小时','reference_at':source['reference_at'],'source_id':source['id'],'source_version':source['version']}
    assert client.post('/api/v1/operations/parse',headers=h,json={**payload,'text':'旧文稿'}).status_code==409
    p=client.post('/api/v1/operations/parse',headers=h,json=payload).json()
    assert p['phase']=='needs_clarification'
    body={'expected_version':p['version'],'target_item_id':item['id']}
    assert client.post(f"/api/v1/operations/{p['id']}/resolve",headers=h,json=body).status_code==422
    assert client.post(f"/api/v1/operations/{p['id']}/resolve",headers=h,json={**body,'confirm_direct_request':True}).status_code==200


def test_duplicate_replan_task_ids_are_a_validation_error(client):
    h,s,item=setup(client)
    p=parse(client,h,s,{'intent':'request_plan','plan_mode':'replan'},'重新安排任务').json()
    response=client.post(f"/api/v1/operations/{p['id']}/resolve",headers=h,json={'expected_version':p['version'],'tasks':[{'item_id':item['id']},{'item_id':item['id']}],'plan_mode':'replan'})
    assert response.status_code==422


def test_manual_reminder_edit_versions_are_separate_and_enforced(client):
    h,s,item=setup(client)
    rule=client.post(f"/api/v1/items/{item['id']}/reminders",headers=h,json={'expected_item_version':1,'mode':'absolute','trigger_at':'2026-12-01T10:00:00+08:00'}).json()
    p=parse(client,h,s,{'intent':'update_reminder','target_query':'Java报告','reminder_patch':{'mode':'absolute'}},'Java报告提醒改到周四晚上').json()
    payload={'expected_version':p['version'],'target_item_id':item['id'],'reminder_id':rule['id'],'expected_item_version':1,'expected_reminder_version':2,'reminder':{'mode':'absolute','trigger_at':'2026-12-01T20:00:00+08:00'}}
    assert client.post(f"/api/v1/operations/{p['id']}/resolve",headers=h,json=payload).status_code==409
    response=client.post(f"/api/v1/operations/{p['id']}/resolve",headers=h,json={**payload,'expected_reminder_version':1})
    assert response.status_code==200,response.text
