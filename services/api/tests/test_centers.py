from test_foundation import client,register,semester,imported_payload


def setup(client):
    _,h=register(client);s=semester(client,h);path=f"/api/v1/semesters/{s['id']}"
    batch=client.post('/api/v1/imports',headers=h,json=imported_payload(s['id'])).json()
    client.post(f"/api/v1/imports/{batch['id']}/apply",headers=h,json={'expected_revision':0})
    course=client.get(path+'/courses',headers=h).json()[0]
    return h,s,path,course


def test_course_hub_only_includes_explicitly_related_items(client):
    h,s,path,c=setup(client)
    for title,course in [('相关报告',c['id']),('同名但未关联',None)]:
        client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'assignment','title':title,'course_id':course})
    r=client.get(f"/api/v1/courses/{c['id']}/hub",headers=h)
    assert r.status_code==200,r.text
    assert [i['title'] for i in r.json()['items']]==['相关报告']
    assert len(r.json()['occurrences'])==3
    _,other=register(client,'student_b')
    assert client.get(f"/api/v1/courses/{c['id']}/hub",headers=other).status_code==404


def test_timeline_retains_week_and_unknown_precision(client):
    h,s,path,c=setup(client)
    for title,time in [('暂定考试',{'precision':'week','week':14}),('待通知',{'precision':'unknown'}),
                       ('跨周范围',{'precision':'range','date':'2026-09-06','end_date':'2026-09-08'})]:
        client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'exam','title':title,'time':time,'certainty':'tentative'})
    r=client.get(path+'/hub',headers=h);assert r.status_code==200,r.text
    data=r.json()
    assert any(i['title']=='暂定考试' and i['time']['at'] is None for i in data['weeks'][13]['items'])
    assert [i['title'] for i in data['undated']]==['待通知']
    assert all(any(i['title']=='跨周范围' for i in data['weeks'][n]['items']) for n in (0,1))
    assert data['weeks'][0]['available_minutes'] is None
    assert len(data['exams'])==3


def test_same_title_without_school_identity_is_not_automatically_merged(client):
    h,s,path,c=setup(client)
    payload=imported_payload(s['id']);payload['courses'][0]['weekday']=4
    b=client.post('/api/v1/imports',headers=h,json=payload).json()
    rev=client.get('/api/v1/semesters',headers=h).json()[0]['revision']
    assert client.post(f"/api/v1/imports/{b['id']}/apply",headers=h,json={'expected_revision':rev}).status_code==200
    data=client.get(path+'/hub',headers=h).json()
    assert len(data['courses'])==2


def test_weekly_load_does_not_treat_later_deadlines_as_same_week_demand(client,monkeypatch):
    from app import centers
    from datetime import datetime
    monkeypatch.setattr(centers,'utcnow',lambda:datetime.fromisoformat('2026-08-31T08:00:00+08:00'))
    h,s,path,c=setup(client)
    preferences={'expected_version':0,'weekly':[{'weekday':1,'start':'09:00','end':'10:00'}],'exclusions':[]}
    preview=client.post(path+'/availability/preview',headers=h,json=preferences).json()
    client.put(path+'/availability',headers=h,json={**preferences,'expected_revision':preview['base_revision']})
    client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'可提前完成','remaining_minutes':100,'start_policy':'now','certainty':'formal',
        'time':{'precision':'exact','at':'2026-09-07T11:00:00+08:00'}})
    data=client.get(path+'/hub',headers=h).json()
    assert data['weeks'][1]['known_due_remaining_minutes']==100
    assert data['weeks'][1]['available_minutes']==60
    assert data['weeks'][1]['load_level']=='normal' # Both weeks together provide 120 minutes.


def test_sunday_day_end_task_stays_in_sunday_week_totals(client):
    h,s,path,c=setup(client)
    client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'周日日末截止',
        'time':{'precision':'date','date':'2026-09-06','day_end_confirmed':True},'certainty':'formal','remaining_minutes':120})
    data=client.get(path+'/hub',headers=h).json()
    assert data['weeks'][0]['known_due_remaining_minutes']==120
    assert data['weeks'][1]['known_due_remaining_minutes']==0
