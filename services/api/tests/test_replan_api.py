from test_foundation import client
from test_schedule_api import setup,proposal,accept


def test_replan_preview_apply_keeps_identity_and_undo_checks_new_reality(client,monkeypatch):
    from app import changes
    from datetime import datetime
    monkeypatch.setattr(changes,'utcnow',lambda:datetime.fromisoformat('2026-09-21T08:00:00+08:00'))
    h,s,item=setup(client,monkeypatch,minutes=60);p=proposal(client,h,s,item);accept(client,h,p)
    path=f"/api/v1/semesters/{s['id']}"
    original=client.get(path+'/plans',headers=h).json()['blocks']
    change=client.post(path+'/changes',headers=h,json={'kind':'block','title':'临时活动','source_text':'确认通知',
        'start_at':'2026-09-21T09:00:00+08:00','end_at':'2026-09-21T10:00:00+08:00'}).json()
    applied=client.post(f"/api/v1/changes/{change['id']}/apply",headers=h,json={'expected_revision':change['base_revision']})
    assert applied.status_code==200,applied.text
    r=client.post(path+'/replan-proposals',headers=h,json={'lead_minutes':0})
    assert r.status_code==201,r.text
    r=r.json();assert r['moved_tasks']==1
    # Both apply calls share the frozen clock. Force the later proposal's UUID
    # below the earlier one's so a timestamp/UUID ordering cannot pass by chance.
    from sqlalchemy.orm import Session
    from app.models import PlanProposal
    with Session(client.app.state.engine) as db:
        candidate=db.get(PlanProposal,r['id'])
        candidate.id='00000000-0000-0000-0000-000000000000'
        db.commit()
        r['id']='00000000-0000-0000-0000-000000000000'
    assert client.get(path+'/plans',headers=h).json()['blocks']==original
    receipt=accept(client,h,r);assert receipt.status_code==200,receipt.text
    feed=client.get(path+'/plans',headers=h).json()
    assert {b['id'] for b in feed['blocks']}=={b['id'] for b in original}
    assert accept(client,h,r).json()==receipt.json()
    # Restoring the old plan would overlap the new activity, so undo must refuse.
    undo=client.post(f"/api/v1/plan-proposals/{r['id']}/undo",headers=h,json={'expected_version':2,'expected_revision':feed['revision']})
    assert undo.status_code==409
    assert client.get(path+'/plans',headers=h).json()['blocks']==feed['blocks']
    # Once the activity is explicitly cancelled, restoring the old slots is legal.
    activity=client.get(path+'/changes',headers=h).json()['occurrences'][0]
    cancel=client.post(path+'/changes',headers=h,json={'kind':'cancel','targets':[activity['id']],'title':'活动取消','source_text':'新通知取消活动'}).json()
    applied=client.post(f"/api/v1/changes/{cancel['id']}/apply",headers=h,json={'expected_revision':cancel['base_revision']}).json()
    undo=client.post(f"/api/v1/plan-proposals/{r['id']}/undo",headers=h,json={'expected_version':2,'expected_revision':applied['revision']})
    assert undo.status_code==200,undo.text
    restored=client.get(path+'/plans',headers=h).json()['blocks']
    assert [(b['id'],b['start_at'],b['end_at']) for b in restored]==[(b['id'],b['start_at'],b['end_at']) for b in original]
