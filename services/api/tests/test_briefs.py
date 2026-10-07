from datetime import datetime
import pytest
from test_foundation import client,register,semester
from test_schedule_api import setup,proposal,accept
from test_calendar_events import create_event


def brief(c,h,s):
    return c.get(f"/api/v1/semesters/{s['id']}/day-brief?day=2026-09-21",headers=h)


def test_brief_is_scoped_and_does_not_assume_learning_time(client):
    _,h=register(client);_,other=register(client,'other');s=semester(client,h)
    response=brief(client,h,s);assert response.status_code==200,response.text
    data=response.json();assert data['entries']==[] and data['available_windows']==[]
    assert data['needs_availability'] is True
    assert brief(client,other,s).status_code==404
    assert data['study_opportunity'] is None


def test_gap_matches_known_work_and_uses_normal_preview_confirmation(client,monkeypatch):
    from app import briefs
    monkeypatch.setattr(briefs,'utcnow',lambda:datetime.fromisoformat('2026-09-21T08:00:00+08:00'))
    h,s,item=setup(client,monkeypatch,minutes=20)
    create_event(client,h,s['id'],time={'precision':'exact','at':'2026-09-21T09:40:00+08:00','end_at':'2026-09-21T13:00:00+08:00'})
    value=brief(client,h,s).json();match=value['study_opportunity']
    assert match['item_id']==item['id'] and match['target_minutes']==20 and match['gap_minutes']==40
    assert match['start_at']=='2026-09-21T01:00:00+00:00' and match['end_at']=='2026-09-21T01:40:00+00:00'
    path=f"/api/v1/semesters/{s['id']}"
    assert client.get(path+'/plans',headers=h).json()['blocks']==[]
    request={'days':1,'lead_minutes':0,'window_start_at':match['start_at'],'window_end_at':match['end_at'],
             'tasks':[{'item_id':match['item_id'],'target_minutes':match['target_minutes']}]}
    p=client.post(path+'/plan-proposals',headers=h,json=request).json()
    assert p['can_apply'] and sum(b['minutes'] for b in p['blocks'])==20
    assert client.get(path+'/plans',headers=h).json()['blocks']==[]
    assert accept(client,h,p).status_code==200
    assert sum(b['minutes'] for b in client.get(path+'/plans',headers=h).json()['blocks'])==20
    assert brief(client,h,s).json()['study_opportunity'] is None
    assert client.get('/api/v1/items/'+item['id'],headers=h).json()['lifecycle']=='active'


@pytest.mark.parametrize('missing',['duration','waiting','slot'])
def test_gap_does_not_invent_unknown_work_or_override_waiting(client,monkeypatch,missing):
    from app import briefs
    from app.models import StudyItem
    from sqlalchemy.orm import Session
    monkeypatch.setattr(briefs,'utcnow',lambda:datetime.fromisoformat('2026-09-21T08:00:00+08:00'))
    h,s,item=setup(client,monkeypatch,minutes=20)
    with Session(client.app.state.engine) as db:
        row=db.get(StudyItem,item['id'])
        row.payload={**row.payload,**({'remaining_minutes':None} if missing=='duration' else
            {'start_policy':'unconfirmed','details':{'conditions':['收到材料后开始']}} if missing=='waiting' else {'remaining_minutes':500})}
        db.commit()
    assert brief(client,h,s).json()['study_opportunity'] is None


def test_expired_date_window_is_not_recommended(client,monkeypatch):
    from app import briefs
    from app.models import StudyItem
    from sqlalchemy.orm import Session
    monkeypatch.setattr(briefs,'utcnow',lambda:datetime.fromisoformat('2026-09-21T08:00:00+08:00'))
    h,s,item=setup(client,monkeypatch,minutes=20)
    with Session(client.app.state.engine) as db:
        row=db.get(StudyItem,item['id']);row.payload={**row.payload,'time':{
            'precision':'date','date':'2026-09-20','meaning':'window'}};db.commit()
    assert brief(client,h,s).json()['study_opportunity'] is None


def test_in_progress_coverage_is_recomputed_when_opening_preview(client,monkeypatch):
    from app import briefs,schedule_api
    h,s,item=setup(client,monkeypatch,minutes=60)
    assert accept(client,h,proposal(client,h,s,item)).status_code==200
    clock=datetime.fromisoformat('2026-09-21T09:30:00+08:00')
    monkeypatch.setattr(briefs,'utcnow',lambda:clock)
    match=brief(client,h,s).json()['study_opportunity'];assert match['target_minutes']==30
    monkeypatch.setattr(schedule_api,'utcnow',lambda:datetime.fromisoformat('2026-09-21T09:30:01+08:00'))
    p=client.post(f"/api/v1/semesters/{s['id']}/plan-proposals",headers=h,json={
        'days':1,'lead_minutes':0,'window_start_at':match['start_at'],'window_end_at':match['end_at'],
        'tasks':[{'item_id':item['id']}]}).json()
    assert p['can_apply'] and sum(b['minutes'] for b in p['blocks'])==31


def test_preview_cannot_spill_beyond_an_explicit_handling_window(client,monkeypatch):
    from app import briefs,schedule_api
    from app.models import StudyItem
    from sqlalchemy.orm import Session
    h,s,item=setup(client,monkeypatch,minutes=30)
    assert accept(client,h,proposal(client,h,s,item)).status_code==200
    with Session(client.app.state.engine) as db:
        row=db.get(StudyItem,item['id']);row.payload={**row.payload,'remaining_minutes':45,
            'time':{'precision':'exact','meaning':'window','at':'2026-09-21T01:00:00+00:00','end_at':'2026-09-21T02:00:00+00:00'}};db.commit()
    monkeypatch.setattr(briefs,'utcnow',lambda:datetime.fromisoformat('2026-09-21T09:15:00+08:00'))
    match=brief(client,h,s).json()['study_opportunity'];assert match['end_at']=='2026-09-21T02:00:00+00:00'
    monkeypatch.setattr(schedule_api,'utcnow',lambda:datetime.fromisoformat('2026-09-21T09:15:01+08:00'))
    p=client.post(f"/api/v1/semesters/{s['id']}/plan-proposals",headers=h,json={
        'days':1,'lead_minutes':0,'window_start_at':match['start_at'],'window_end_at':match['end_at'],
        'tasks':[{'item_id':item['id']}]}).json()
    assert not p['can_apply']


def test_new_notice_conflict_has_contextual_action_not_only_a_count(client,monkeypatch):
    from app import briefs
    monkeypatch.setattr(briefs,'utcnow',lambda:datetime.fromisoformat('2026-09-21T08:00:00+08:00'),raising=False)
    h,s,item=setup(client,monkeypatch);p=proposal(client,h,s,item);assert accept(client,h,p).status_code==200
    assert create_event(client,h,s['id'],time={'precision':'exact','at':'2026-09-21T09:00:00+08:00','end_at':'2026-09-21T10:00:00+08:00'}).status_code==201
    response=brief(client,h,s);assert response.status_code==200,response.text
    data=response.json();suggestion=next(x for x in data['suggestions'] if x['kind']=='plan_conflict')
    assert suggestion['source_ids'] and '2026-09-21' in suggestion['request']
    assert suggestion['action_label']=='查看调整建议'
    assert data['revision']>s['revision']
    assert all(x['resource_type'] in ('event','plan','deadline','course','exam') for x in data['entries'])


@pytest.mark.parametrize('start_at,expected_minutes', [
    ('2026-09-20T23:00:00+08:00',240), ('2026-09-21T10:00:00+08:00',60),
])
def test_unknown_fixed_end_keeps_candidate_windows_qualified(client,monkeypatch,start_at,expected_minutes):
    from app import briefs
    monkeypatch.setattr(briefs,'utcnow',lambda:datetime.fromisoformat('2026-09-21T08:00:00+08:00'),raising=False)
    h,s,_=setup(client,monkeypatch)
    response=create_event(client,h,s['id'],time={'precision':'exact','at':start_at})
    assert response.status_code==201
    event=response.json()['event']
    response=brief(client,h,s);assert response.status_code==200,response.text
    data=response.json();assert data['uncertain_count']==1
    assert len(data['available_windows'])==1 and data['available_windows'][0]['minutes']==expected_minutes
    warning=next(w for w in data['uncertainty_warnings'] if w['id']=='event:'+event['id'])
    assert warning['end_unknown'] and warning['exclusion_applied'] and '结束时间' in warning['message']
    assert any(x['kind']=='missing_time' for x in data['suggestions'])
    suggestion=next(x for x in data['suggestions'] if x['kind']=='free_window')
    assert '待核对' in suggestion['detail']
    if data['study_opportunity']:assert data['study_opportunity']['needs_check'] is True
    assert client.get('/api/v1/events/'+event['id'],headers=h).json()['time']['end_at'] is None
