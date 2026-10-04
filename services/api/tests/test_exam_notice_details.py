from test_foundation import client, register, semester
from test_agent import thread, turn, run, call


def setup_exam(c):
    _, h = register(c); s = semester(c,h)
    response = c.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'exam','title':'示例考试',
        'certainty':'formal','time':{'precision':'exact','at':'2026-12-01T10:00:00+08:00','end_at':'2026-12-01T12:00:00+08:00'},
        'details':{'materials':['校园卡'],'early_arrival_minutes':10,'conditions':['携带校园卡']}})
    assert response.status_code==201,response.text
    return h,s,response.json()


def change(e, **extra):
    return {'expected_version':e['version'],'time':e['time'],'certainty':'formal','reason':'补充考试通知',**extra}


def test_exam_detail_preview_save_arrival_and_conflict_use_new_details(client):
    h,s,e = setup_exam(client)
    other = client.post('/api/v1/events',headers=h,json={'semester_id':s['id'],'title':'另一安排','expected_revision':1,
        'time':{'precision':'exact','at':'2026-12-01T09:40:00+08:00','end_at':'2026-12-01T09:45:00+08:00'}})
    assert other.status_code==201,other.text
    path='/api/v1/exams/' + e['id'] + '/reschedule'
    body=change(e,details={'materials':['校园卡','文具'],'early_arrival_minutes':30})
    response=client.post(path+'/preview',headers=h,json=body)
    assert response.status_code==200,response.text
    preview=response.json()
    assert preview['after']['details']['materials']==['校园卡','文具']
    assert preview['after']['details']['conditions']==['携带校园卡']
    assert preview['after']['arrival_at']=='2026-12-01T01:30:00+00:00'
    assert preview['fixed_conflict_count']>0
    assert client.get('/api/v1/items/' + e['id'],headers=h).json()['details']==e['details']
    apply={**body,'preview_token':preview['preview_token'],'expected_revision':preview['base_revision']}
    assert client.post(path,headers=h,json=apply).status_code==422
    saved=client.post(path,headers=h,json={**apply,'confirm_fixed_conflicts':True})
    assert saved.status_code==200,saved.text
    assert saved.json()['item']['details']['early_arrival_minutes']==30
    assert saved.json()['item']['arrival_at']==preview['after']['arrival_at']
    entry=next(r for r in client.get('/api/v1/semesters/' + s['id'] + '/calendar',headers=h,
        params={'from_date':'2026-12-01','to_date':'2026-12-01'}).json()['entries'] if r.get('resource_id')==e['id'])
    assert entry['occupancy_start_at']==preview['after']['arrival_at']
    assert len(client.get('/api/v1/semesters/' + s['id'] + '/items',headers=h).json()['items'])==1


def test_old_exam_reschedule_preserves_details_and_recomputes_arrival_for_new_date(client):
    h,s,e=setup_exam(client)
    path='/api/v1/exams/' + e['id'] + '/reschedule'
    body=change(e,time={'precision':'exact','at':'2026-12-02T10:00:00+08:00','end_at':'2026-12-02T12:00:00+08:00'})
    preview=client.post(path+'/preview',headers=h,json=body).json()
    assert preview['after']['details']==e['details']
    assert preview['after']['arrival_at']=='2026-12-02T01:50:00+00:00'
    saved=client.post(path,headers=h,json={**body,'expected_revision':preview['base_revision'],'preview_token':preview['preview_token']})
    assert saved.status_code==200,saved.text
    assert saved.json()['item']['details']==e['details']
    assert saved.json()['item']['arrival_at']==preview['after']['arrival_at']


def test_exam_details_changed_after_preview_cannot_reuse_old_confirmation(client):
    h,s,e=setup_exam(client)
    path='/api/v1/exams/' + e['id'] + '/reschedule'
    body=change(e,details={'early_arrival_minutes':20})
    response=client.post(path+'/preview',headers=h,json=body)
    assert response.status_code==200,response.text
    preview=response.json()
    apply={**body,'details':{'early_arrival_minutes':40},'preview_token':preview['preview_token'],'expected_revision':preview['base_revision']}
    assert client.post(path,headers=h,json=apply).status_code==409
    assert client.get('/api/v1/items/' + e['id'],headers=h).json()['details']['early_arrival_minutes']==10


def test_agent_exam_notice_details_are_carried_through_preview_and_save(client):
    h,s,e=setup_exam(client); tid=thread(client,h,s['id'])
    req=turn(client,h,tid,'考试补通知：提前30分钟到场，另带文具。更新原考试。')
    def model(messages,tools):
        if messages[-1]['role']=='user':return call('find_records',{'query':'示例考试'})
        return call('prepare_exam_change',{'exam_id':e['id'],'time':e['time'],'certainty':'formal',
            'details':{'materials':['校园卡','文具'],'early_arrival_minutes':30}})
    run(client,model)
    url='/api/v1/agent/runs/' + req['id']; value=client.get(url,headers=h).json()
    assert value['status']=='needs_confirmation',value
    assert value['preview']['after']['details']['early_arrival_minutes']==30
    saved=client.post(url+'/decision',headers=h,json={'decision':'confirm','token':value['preview']['token']})
    assert saved.status_code==200,saved.text
    assert saved.json()['receipt']['item']['details']['materials']==['校园卡','文具']


def test_unreserved_tentative_exam_is_reference_in_calendar_brief_and_statistics(client,monkeypatch):
    from datetime import datetime
    from app import briefs
    from test_schedule_api import setup,proposal,accept
    monkeypatch.setattr(briefs,'utcnow',lambda:datetime.fromisoformat('2026-09-21T08:00:00+08:00'))
    h,s,item=setup(client,monkeypatch,minutes=60)
    plan=proposal(client,h,s,item); assert accept(client,h,plan).status_code==200
    response=client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'exam','title':'参考考试',
        'certainty':'tentative','reserve_time':False,
        'time':{'precision':'exact','at':'2026-09-21T09:00:00+08:00','end_at':'2026-09-21T10:00:00+08:00'}})
    assert response.status_code==201,response.text
    value=client.get('/api/v1/semesters/' + s['id'] + '/day-brief',headers=h,params={'day':'2026-09-21'}).json()
    entry=next(r for r in value['entries'] if r.get('resource_id')==response.json()['id'])
    assert entry['reserve_time'] is False and entry['fixed'] is False and entry['occupancy_start_at'] is None
    assert entry['start_at'] is not None
    assert value['plan_impacts']==[] and not any(r['kind']=='plan_conflict' for r in value['suggestions'])
    stats=client.get('/api/v1/semesters/' + s['id'] + '/insights',headers=h,
        params={'from_date':'2026-09-21','to_date':'2026-09-21'}).json()['summary']
    assert stats['fixed_scheduled_minutes']==0 and stats['personal_planned_minutes']==60
    assert stats['occupied_union_minutes']==60


def test_day_brief_plan_conflict_includes_explicit_required_arrival(client,monkeypatch):
    from datetime import datetime
    from app import briefs
    from test_schedule_api import setup,proposal,accept
    monkeypatch.setattr(briefs,'utcnow',lambda:datetime.fromisoformat('2026-09-21T08:00:00+08:00'))
    h,s,item=setup(client,monkeypatch,minutes=60)
    plan=proposal(client,h,s,item); assert accept(client,h,plan).status_code==200
    rev=next(r['revision'] for r in client.get('/api/v1/semesters',headers=h).json() if r['id']==s['id'])
    event=client.post('/api/v1/events',headers=h,json={'semester_id':s['id'],'title':'需提前到场的会议',
        'expected_revision':rev,'time':{'precision':'exact','at':'2026-09-21T10:00:00+08:00','end_at':'2026-09-21T11:00:00+08:00'},
        'details':{'early_arrival_minutes':30,'participation_status':'confirmed'}})
    assert event.status_code==201,event.text
    brief=client.get('/api/v1/semesters/' + s['id'] + '/day-brief',headers=h,params={'day':'2026-09-21'}).json()
    assert brief['plan_impacts'] and any(r['kind']=='plan_conflict' for r in brief['suggestions'])
