"""Business undo contract, independently of the agent HTTP orchestration."""
import importlib
import os
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from datetime import datetime
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import (AgentRun, AgentThread, CalendarEvent, ItemRevision, PlanBlock,
    PlanProposal, ProgressEntry, RealityChange, ReminderRule, Semester, StudyItem, User)
from test_foundation import client, register, semester
from test_insights import item, event, insights


def undo_api():
    assert importlib.util.find_spec('app.agent_undo') is not None, 'Unified undo is not implemented'
    return importlib.import_module('app.agent_undo')


def capture(client, sid):
    with Session(client.app.state.engine) as db:
        s = db.get(Semester, sid)
        return undo_api().capture(db, db.get(User, s.user_id), sid)


def record(client, sid, before, kind='item'):
    module = undo_api()
    with Session(client.app.state.engine) as db:
        s = db.get(Semester, sid); user = db.get(User, s.user_id)
        now = datetime.now().isoformat()
        thread = AgentThread(user_id=user.id, semester_id=sid, created_at=now, updated_at=now)
        db.add(thread); db.flush()
        run = AgentRun(user_id=user.id, thread_id=thread.id, request_id=str(uuid4()), text='已确认操作',
            status='applied', created_at=now, state={'preview': {'kind': kind},
                'undo_data': module.changes(before, module.capture(db, user, sid))})
        db.add(run); db.commit()
        return run.id


def prepare(client, sid, rid):
    with Session(client.app.state.engine) as db:
        s = db.get(Semester, sid)
        preview = undo_api().prepare_undo(db, db.get(User, s.user_id), s, rid)
        return {**preview, 'undo_run_id': str(uuid4())}


def apply(client, sid, preview):
    with Session(client.app.state.engine) as db:
        s = db.get(Semester, sid)
        result = undo_api().apply_undo(db, db.get(User, s.user_id), preview)
        db.commit()
        return result


def test_created_item_undo_cancels_preserves_history_and_retries_once(client):
    _, h = register(client); s = semester(client, h)
    before = capture(client, s['id'])
    saved = item(client, h, s['id'], tags=['材料'], reminders=[{
        'mode': 'absolute', 'trigger_at': '2099-09-01T10:00:00+08:00', 'purpose': 'check_notice'}])
    rid = record(client, s['id'], before)
    preview = prepare(client, s['id'], rid)
    assert preview['kind'] == 'undo' and preview['source_run_id'] == rid
    assert preview['summary'] and 'undo_data' not in preview
    assert client.get('/api/v1/items/' + saved['id'], headers=h).json()['lifecycle'] == 'active'
    receipt = apply(client, s['id'], preview)
    assert apply(client, s['id'], preview) == receipt
    result = client.get('/api/v1/items/' + saved['id'], headers=h).json()
    assert result['lifecycle'] == 'cancelled' and result['version'] == 2
    assert result['reminders'][0]['enabled'] is False
    with Session(client.app.state.engine) as db:
        assert len(list(db.scalars(select(ItemRevision).where(ItemRevision.item_id == saved['id'])))) == 2
        assert db.get(AgentRun, rid).state['undone_by'] == preview['undo_run_id']
    with pytest.raises(HTTPException): prepare(client, s['id'], rid)


def test_event_edit_undo_restores_saved_payload_and_advances_version(client):
    _, h = register(client); s = semester(client, h)
    saved = event(client, h, s['id'], tags=['会议'])
    before = capture(client, s['id'])
    payload = {k: v for k, v in saved.items() if k in ('title','time','certainty','location','notes','category_id','reminder_minutes')}
    response = client.patch('/api/v1/events/' + saved['id'], headers=h, json={**payload,
        'semester_id':s['id'], 'title':'新标题', 'expected_version':1, 'expected_revision':before['revision']})
    assert response.status_code == 200, response.text
    rid = record(client, s['id'], before, 'event')
    apply(client, s['id'], prepare(client, s['id'], rid))
    restored = client.get('/api/v1/events/' + saved['id'], headers=h).json()
    assert restored['title'] == saved['title'] and restored['time'] == saved['time']
    assert restored['tags'] == saved['tags'] and restored['version'] == 3


@pytest.mark.parametrize('dependency', ['reminder', 'progress', 'review', 'edit'])
def test_later_dependencies_block_undo_even_without_semester_revision(client, dependency):
    _, h = register(client); s = semester(client, h)
    before = capture(client, s['id']); saved = item(client, h, s['id'], kind='exam')
    rid = record(client, s['id'], before); preview = prepare(client, s['id'], rid)
    with Session(client.app.state.engine) as db:
        row = db.get(StudyItem, saved['id']); now = row.updated_at
        if dependency == 'reminder':
            db.add(ReminderRule(user_id=row.user_id,item_id=row.id,payload={'enabled':True,
                'mode':'absolute','trigger_at':'2099-01-01T00:00:00Z','purpose':'check_notice'},created_at=now,updated_at=now))
        elif dependency == 'progress':
            db.add(ProgressEntry(user_id=row.user_id,item_id=row.id,payload={'actual_minutes':25},created_at=now))
        elif dependency == 'review':
            db.add(StudyItem(user_id=row.user_id,semester_id=s['id'],payload={**row.payload,'kind':'task','review_exam_id':row.id},created_at=now,updated_at=now))
        else:
            row.payload={**row.payload,'title':'后续修改'}; row.version+=1
        db.commit()
    with pytest.raises(HTTPException) as failure: apply(client, s['id'], preview)
    assert failure.value.status_code == 409
    assert client.get('/api/v1/items/' + saved['id'], headers=h).json()['lifecycle'] == 'active'


def test_progress_undo_preserves_entry_but_excludes_actual_statistics(client):
    _, h = register(client); s = semester(client, h)
    saved = item(client, h, s['id'], remaining_minutes=60)
    before = capture(client, s['id'])
    with Session(client.app.state.engine) as db:
        row=db.get(StudyItem,saved['id']); row.payload={**row.payload,'remaining_minutes':30}; row.version+=1
        db.add(ProgressEntry(user_id=row.user_id,item_id=row.id,payload={'actual_minutes':35,'remaining_minutes':30},created_at='2026-09-21T00:00:00Z'))
        db.get(Semester,s['id']).revision+=1; db.commit()
    rid=record(client,s['id'],before,'operation')
    assert insights(client,h,s['id']).json()['summary']['actual_minutes']==35
    apply(client,s['id'],prepare(client,s['id'],rid))
    assert insights(client,h,s['id']).json()['summary']['actual_minutes'] is None
    assert client.get('/api/v1/items/'+saved['id'],headers=h).json()['remaining_minutes']==60
    with Session(client.app.state.engine) as db:
        rows=list(db.scalars(select(ProgressEntry)))
        assert len(rows)==1 and rows[0].payload['undone'] is True


def test_other_owner_old_receipt_and_undo_of_undo_rejected(client):
    _,h=register(client); _,other=register(client,'other'); s=semester(client,h); foreign=semester(client,other)
    before=capture(client,s['id']); item(client,h,s['id']); rid=record(client,s['id'],before)
    with pytest.raises(HTTPException) as failure: prepare(client,foreign['id'],rid)
    assert failure.value.status_code==404
    with Session(client.app.state.engine) as db:
        row=db.get(AgentRun,rid); old=deepcopy(row.state); row.state={'preview':{'kind':'undo'},'undo_data':old['undo_data']}; db.commit()
    with pytest.raises(HTTPException): prepare(client,s['id'],rid)
    with Session(client.app.state.engine) as db:
        row=db.get(AgentRun,rid); row.state={}; db.commit()
    with pytest.raises(HTTPException) as failure: prepare(client,s['id'],rid)
    assert failure.value.detail['code']=='UNDO_UNAVAILABLE'


def test_batch_undo_rolls_back_all_members_when_audit_fails(client, monkeypatch):
    _,h=register(client); s=semester(client,h)
    before=capture(client,s['id']); saved=item(client,h,s['id']); fixed=event(client,h,s['id'])
    rid=record(client,s['id'],before,'batch'); p=prepare(client,s['id'],rid)
    from app import calendar_events
    def fail(*args): raise RuntimeError('injected audit failure')
    with monkeypatch.context() as context:
        context.setattr(calendar_events,'record',fail)
        with pytest.raises(RuntimeError): apply(client,s['id'],p)
    assert client.get('/api/v1/items/'+saved['id'],headers=h).json()['lifecycle']=='active'
    assert client.get('/api/v1/events/'+fixed['id'],headers=h).json()['lifecycle']=='active'
    result=apply(client,s['id'],p)
    assert result['undone'] is True
    assert client.get('/api/v1/items/'+saved['id'],headers=h).json()['lifecycle']=='cancelled'
    assert client.get('/api/v1/events/'+fixed['id'],headers=h).json()['lifecycle']=='cancelled'


def test_reminder_undo_restores_rule_and_keeps_unrelated_items(client):
    _,h=register(client); s=semester(client,h)
    saved=item(client,h,s['id'],reminders=[{'mode':'absolute','trigger_at':'2099-01-01T00:00:00Z','purpose':'check_notice'}])
    before=capture(client,s['id']); reminder=saved['reminders'][0]
    with Session(client.app.state.engine) as db:
        rule=db.get(ReminderRule,reminder['id']); rule.payload={**rule.payload,'enabled':False}; rule.version+=1
        db.commit()
    rid=record(client,s['id'],before,'operation')
    unrelated=item(client,h,s['id'],title='后续无关任务')
    apply(client,s['id'],prepare(client,s['id'],rid))
    value=client.get('/api/v1/items/'+saved['id'],headers=h).json()
    assert value['reminders'][0]['enabled'] is True and value['reminders'][0]['version']==3
    assert client.get('/api/v1/items/'+unrelated['id'],headers=h).json()['lifecycle']=='active'


def test_course_undo_preserves_notification_history_and_blocks_later_same_occurrence(client, monkeypatch):
    from test_changes import setup
    h,s,path,old=setup(client,monkeypatch)
    monkeypatch.setattr(undo_api(),'utcnow',lambda:datetime.fromisoformat('2026-09-01T08:00:00+08:00'))
    before=capture(client,s['id'])
    change=client.post(path+'/changes',headers=h,json={'kind':'move','targets':[old['id']],
        'title':old['title'],'source_text':'正式调课通知','start_at':'2026-09-03T10:00:00+08:00',
        'end_at':'2026-09-03T11:00:00+08:00'}).json()
    assert client.post('/api/v1/changes/'+change['id']+'/apply',headers=h,json={'expected_revision':change['base_revision']}).status_code==200
    rid=record(client,s['id'],before,'course_change')
    apply(client,s['id'],prepare(client,s['id'],rid))
    assert client.get(path+'/timetable?week=1',headers=h).json()['events'][0]['start_at']==old['start_at']
    with Session(client.app.state.engine) as db:
        original=db.get(RealityChange,change['id'])
        assert original.applied_revision is not None and original.payload['request']['source_text']=='正式调课通知'
        assert len(list(db.scalars(select(RealityChange))))==2
    # The same occurrence changes again; its earlier move must not overwrite it.
    before=capture(client,s['id'])
    first=client.post(path+'/changes',headers=h,json={'kind':'move','targets':[old['id']],
        'title':old['title'],'source_text':'第二通知','start_at':'2026-09-04T10:00:00+08:00',
        'end_at':'2026-09-04T11:00:00+08:00'}).json()
    assert client.post('/api/v1/changes/'+first['id']+'/apply',headers=h,json={'expected_revision':first['base_revision']}).status_code==200
    rid=record(client,s['id'],before,'course_change')
    later=client.post(path+'/changes',headers=h,json={'kind':'cancel','targets':[old['id']],
        'title':old['title'],'source_text':'最新停课通知'}).json()
    assert client.post('/api/v1/changes/'+later['id']+'/apply',headers=h,json={'expected_revision':later['base_revision']}).status_code==200
    with pytest.raises(HTTPException) as failure: prepare(client,s['id'],rid)
    assert failure.value.detail['code']=='UNDO_DEPENDENCY_CHANGED'


def test_exam_undo_restores_aligned_review_and_reminders(client):
    _,h=register(client); s=semester(client,h)
    exam=item(client,h,s['id'],kind='exam',certainty='formal',time={'precision':'exact',
        'at':'2026-12-01T09:00:00+08:00','end_at':'2026-12-01T11:00:00+08:00'},
        reminders=[{'mode':'relative','lead_minutes':60,'purpose':'item'}])
    review=client.post('/api/v1/exams/'+exam['id']+'/reviews',headers=h,json={
        'expected_exam_version':1,'remaining_minutes':120,'deadline_mode':'exam','start_policy':'now'}).json()
    before=capture(client,s['id'])
    body={'expected_version':1,'time':{'precision':'exact','at':'2026-12-02T09:00:00+08:00',
        'end_at':'2026-12-02T11:00:00+08:00'},'certainty':'formal','align_review_deadlines':True,
        'reason':'正式改期'}
    p=client.post('/api/v1/exams/'+exam['id']+'/reschedule/preview',headers=h,json=body).json()
    result=client.post('/api/v1/exams/'+exam['id']+'/reschedule',headers=h,json={**body,
        'expected_revision':p['base_revision'],'preview_token':p['preview_token']})
    assert result.status_code==200,result.text
    rid=record(client,s['id'],before,'exam_change')
    apply(client,s['id'],prepare(client,s['id'],rid))
    restored=client.get('/api/v1/items/'+exam['id'],headers=h).json()
    assert restored['time']==exam['time'] and restored['version']==3
    assert restored['reminders'][0]['version']==3
    assert client.get('/api/v1/items/'+review['id'],headers=h).json()['time']==review['time']


def test_plan_undo_reuses_atomic_command_and_preserves_reality(client, monkeypatch):
    from test_schedule_api import setup, proposal, accept
    h,s,saved=setup(client,monkeypatch,minutes=60)
    monkeypatch.setattr(undo_api(),'utcnow',lambda:datetime.fromisoformat('2026-09-21T08:00:00+08:00'))
    fixed=event(client,h,s['id'],time={'precision':'exact','at':'2026-09-22T09:00:00+08:00','end_at':'2026-09-22T10:00:00+08:00'})
    p=proposal(client,h,s,saved); before=capture(client,s['id'])
    assert accept(client,h,p).status_code==200
    rid=record(client,s['id'],before,'plan'); preview=prepare(client,s['id'],rid)
    # Even the delegated plan undo must not commit ahead of its agent receipt.
    with Session(client.app.state.engine) as db:
        user=db.get(User,db.get(Semester,s['id']).user_id)
        undo_api().apply_undo(db,user,preview)
        db.rollback()
    with Session(client.app.state.engine) as db:
        assert db.get(PlanProposal,p['id']).phase=='applied'
        assert all(b.status=='active' for b in db.scalars(select(PlanBlock)))
    apply(client,s['id'],preview)
    assert client.get('/api/v1/events/'+fixed['id'],headers=h).json()['lifecycle']=='active'
    with Session(client.app.state.engine) as db:
        assert db.get(PlanProposal,p['id']).phase=='undone'
        assert all(b.status=='cancelled' for b in db.scalars(select(PlanBlock)))


def test_restoring_cancelled_event_cannot_overlap_later_fixed_event(client):
    _,h=register(client); s=semester(client,h)
    when={'precision':'exact','at':'2026-12-01T09:00:00+08:00','end_at':'2026-12-01T10:00:00+08:00'}
    saved=event(client,h,s['id'],time=when)
    before=capture(client,s['id'])
    result=client.post('/api/v1/events/'+saved['id']+'/cancel',headers=h,json={
        'expected_version':1,'expected_revision':before['revision']})
    assert result.status_code==200,result.text
    rid=record(client,s['id'],before,'event')
    # Another real commitment now occupies the time that undo would restore.
    event(client,h,s['id'],title='后来确认的会议',time=when)
    with pytest.raises(HTTPException) as failure: prepare(client,s['id'],rid)
    assert failure.value.detail['code']=='UNDO_FIXED_CONFLICT'


def test_undo_title_change_does_not_treat_existing_overlap_as_new_conflict(client):
    _,h=register(client);s=semester(client,h)
    when={'precision':'exact','at':'2026-12-01T09:00:00+08:00','end_at':'2026-12-01T10:00:00+08:00'}
    a=event(client,h,s['id'],title='A',time=when)
    event(client,h,s['id'],title='B',time=when)
    before=capture(client,s['id'])
    result=client.patch('/api/v1/events/'+a['id'],headers=h,json={
        'semester_id':s['id'],'title':'改名后的A','time':when,'certainty':'formal',
        'expected_version':1,'expected_revision':before['revision'],'change_reason':'仅改标题'})
    assert result.status_code==200,result.text
    rid=record(client,s['id'],before,'event')
    apply(client,s['id'],prepare(client,s['id'],rid))
    assert client.get('/api/v1/events/'+a['id'],headers=h).json()['title']=='A'


def test_old_plan_endpoint_cannot_bypass_agent_undo_confirmation(client,monkeypatch):
    from test_schedule_api import setup, proposal, accept
    h,s,saved=setup(client,monkeypatch,minutes=60)
    p=proposal(client,h,s,saved)
    result=accept(client,h,p); assert result.status_code==200
    with Session(client.app.state.engine) as db:
        row=db.get(PlanProposal,p['id']); row.payload={**row.payload,'agent_run_id':'server-owned-run'}; db.commit()
    response=client.post('/api/v1/plan-proposals/'+p['id']+'/undo',headers=h,json={
        'expected_version':2,'expected_revision':result.json()['revision']})
    assert response.status_code==409 and response.json()['code']=='AGENT_CONFIRMATION_REQUIRED'


@pytest.mark.skipif(not os.environ.get('POSTGRES_TEST_URL'), reason='PostgreSQL row locks required')
def test_concurrent_undo_same_receipt_only_advances_once(client):
    _,h=register(client); s=semester(client,h)
    before=capture(client,s['id']); saved=item(client,h,s['id']); rid=record(client,s['id'],before)
    preview=prepare(client,s['id'],rid)
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses=list(pool.map(lambda _:apply(client,s['id'],preview),range(2)))
    assert responses[0]==responses[1]
    assert client.get('/api/v1/items/'+saved['id'],headers=h).json()['version']==2
