from test_foundation import client,register,semester,imported_payload
from datetime import datetime


def setup(client,monkeypatch):
    from app import changes
    monkeypatch.setattr(changes,'utcnow',lambda:datetime.fromisoformat('2026-09-01T08:00:00+08:00'))
    _,h=register(client);s=semester(client,h)
    b=client.post('/api/v1/imports',headers=h,json=imported_payload(s['id'])).json()
    client.post(f"/api/v1/imports/{b['id']}/apply",headers=h,json={'expected_revision':0})
    path=f"/api/v1/semesters/{s['id']}"
    old=client.get(path+'/timetable?week=1',headers=h).json()['events'][0]
    return h,s,path,old


def test_occurrence_move_is_previewed_and_only_changes_one_week(client,monkeypatch):
    h,s,path,old=setup(client,monkeypatch)
    data={'kind':'move','targets':[old['id']],'source_text':'老师通知：本周课程改到周四10点至11点。',
          'title':old['title'],'start_at':'2026-09-03T10:00:00+08:00','end_at':'2026-09-03T11:00:00+08:00','location':'B201'}
    r=client.post(path+'/changes',headers=h,json=data);assert r.status_code==201,r.text
    p=r.json()
    assert client.get(path+'/timetable?week=1',headers=h).json()['events'][0]['start_at']==old['start_at']
    body={'expected_revision':p['base_revision']}
    applied=client.post(f"/api/v1/changes/{p['id']}/apply",headers=h,json=body)
    assert applied.status_code==200,applied.text
    assert client.post(f"/api/v1/changes/{p['id']}/apply",headers=h,json=body).json()==applied.json()
    updated=client.get(path+'/timetable?week=1',headers=h).json()['events'][0]
    assert updated['id']==old['id'] and updated['start_at']=='2026-09-03T10:00:00+08:00'
    assert updated['location']=='B201'
    assert client.get(path+'/timetable?week=3',headers=h).json()['events'][0]['start_at']=='2026-09-16T08:00:00+08:00'


def test_cross_user_and_stale_changes_are_rejected(client,monkeypatch):
    h,s,path,old=setup(client,monkeypatch);_,other=register(client,'student_b')
    body={'kind':'cancel','targets':[old['id']],'source_text':'本次停课','title':old['title']}
    p=client.post(path+'/changes',headers=h,json=body).json()
    q=client.post(path+'/changes',headers=h,json=body).json()
    assert client.post(f"/api/v1/changes/{p['id']}/apply",headers=other,json={'expected_revision':1}).status_code==404
    assert client.post(f"/api/v1/changes/{p['id']}/apply",headers=h,json={'expected_revision':1}).status_code==200
    assert client.post(f"/api/v1/changes/{q['id']}/apply",headers=h,json={'expected_revision':1}).status_code==409
    assert client.get(path+'/timetable?week=1',headers=h).json()['events']==[]


def test_holiday_cancels_only_selected_occurrences_and_addition_reaches_capacity(client,monkeypatch):
    h,s,path,old=setup(client,monkeypatch)
    third=client.get(path+'/timetable?week=3',headers=h).json()['events'][0]
    p=client.post(path+'/changes',headers=h,json={'kind':'suspend','targets':[old['id'],third['id']],
        'title':'放假停课','source_text':'已核对这两次课程停课'}).json()
    assert len(p['patch']['before'])==2 and p['patch']['after']==[]
    assert client.post(f"/api/v1/changes/{p['id']}/apply",headers=h,json={'expected_revision':p['base_revision']}).status_code==200
    assert len(client.get(path+'/timetable?week=5',headers=h).json()['events'])==1
    prefs={'expected_version':0,'weekly':[{'weekday':4,'start':'09:00','end':'12:00'}],'exclusions':[]}
    preview=client.post(path+'/availability/preview',headers=h,json=prefs).json()
    client.put(path+'/availability',headers=h,json={**prefs,'expected_revision':preview['base_revision']})
    client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'待办','certainty':'formal',
        'time':{'precision':'exact','at':'2026-09-03T12:00:00+08:00'},'remaining_minutes':60,'start_policy':'now'})
    from app import planning
    monkeypatch.setattr(planning,'utcnow',lambda:datetime.fromisoformat('2026-09-01T08:00:00+08:00'))
    before=client.get(path+'/risk',headers=h).json()['items'][0]['task_slack_minutes']
    p=client.post(path+'/changes',headers=h,json={'kind':'add','title':'补课','source_text':'周四补课通知',
        'start_at':'2026-09-03T10:00:00+08:00','end_at':'2026-09-03T11:00:00+08:00'}).json()
    assert p['impact']['risk_changes'][0]['after_slack']==before-60
    assert client.post(f"/api/v1/changes/{p['id']}/apply",headers=h,json={'expected_revision':p['base_revision']}).status_code==200
    assert client.get(path+'/risk',headers=h).json()['items'][0]['task_slack_minutes']==before-60
    assert client.get(path+'/timetable?week=1',headers=h).json()['events'][0]['title']=='补课'


def test_course_correction_is_not_invalidated_only_because_its_date_passed(client,monkeypatch):
    from app import changes
    h,s,path,old=setup(client,monkeypatch)
    p=client.post(path+'/changes',headers=h,json={'kind':'cancel','targets':[old['id']],'title':'停课','source_text':'停课通知'}).json()
    monkeypatch.setattr(changes,'utcnow',lambda:datetime.fromisoformat('2026-09-02T09:00:00+08:00'))
    assert client.post(f"/api/v1/changes/{p['id']}/apply",headers=h,json={'expected_revision':p['base_revision']}).status_code==200
    assert client.get(path+'/timetable?week=1',headers=h).json()['events']==[]


def test_parser_suggestions_never_write_reality_and_reject_fabricated_evidence(client,monkeypatch):
    h,s,path,old=setup(client,monkeypatch)
    answer={'kind':'move','title':'概率论','original_date':'2026-09-02','start_at':None,'end_at':None,
        'location':'','evidence':{'kind':'改到周四晚上'},'questions':['晚上具体时刻待确认']}
    client.app.state.change_model=lambda *args:(answer,{'provider':'test'})
    r=client.post('/api/v1/changes/parse',headers=h,json={'semester_id':s['id'],'text':'概率论改到周四晚上'})
    assert r.status_code==200 and r.json()['suggestion']['start_at'] is None
    assert r.json()['target_candidates']==[old['id']]
    assert client.get(path+'/timetable?week=1',headers=h).json()['events'][0]['start_at']==old['start_at']
    answer['evidence']={'kind':'并不存在的原文'}
    assert client.post('/api/v1/changes/parse',headers=h,json={'semester_id':s['id'],'text':'概率论改到周四晚上'}).status_code==502
