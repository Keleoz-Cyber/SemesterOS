from datetime import datetime
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


def test_unknown_fixed_end_blocks_optimistic_gap_suggestion(client,monkeypatch):
    from app import briefs
    monkeypatch.setattr(briefs,'utcnow',lambda:datetime.fromisoformat('2026-09-21T08:00:00+08:00'),raising=False)
    h,s,_=setup(client,monkeypatch)
    assert create_event(client,h,s['id'],time={'precision':'exact','at':'2026-09-20T23:00:00+08:00'}).status_code==201
    response=brief(client,h,s);assert response.status_code==200,response.text
    data=response.json();assert data['available_windows']==[] and data['uncertain_count']==1
    assert not any(x['kind']=='free_window' for x in data['suggestions'])
