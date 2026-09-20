"""Synthetic course -> exam -> review -> reschedule -> timeline live check."""
from datetime import datetime,timedelta,timezone
from pathlib import Path
import secrets,json
import httpx


def main():
    now=datetime.now(timezone(timedelta(hours=8)));tomorrow=(now+timedelta(days=1)).replace(hour=13,minute=0,second=0,microsecond=0)
    monday=now.date()-timedelta(days=now.weekday());username='qa_centers_'+secrets.token_hex(4)
    with httpx.Client(base_url='http://127.0.0.1:8871/api/v1',timeout=35) as api:
        session=api.post('/auth/register',json={'username':username,'password':secrets.token_urlsafe(24)}).json();api.headers['Authorization']='Bearer '+session['access_token']
        s=api.post('/semesters',json={'name':'QA课程考试时间轴（合成）','first_monday':monday.isoformat(),'total_weeks':20,'periods':[{'number':1,'start':'08:00','end':'09:00'}]}).json()
        path=f"/semesters/{s['id']}";week=(tomorrow.date()-monday).days//7+1
        batch=api.post('/imports',json={'semester_id':s['id'],'source':'manual','courses':[{'title':'合成概率论','source_id':'qa-probability','weekday':tomorrow.isoweekday(),'weeks':[week],'sections':[1]}]}).json()
        assert api.post(f"/imports/{batch['id']}/apply",json={'expected_revision':batch['base_revision']}).status_code==200
        course=api.get(path+'/courses').json()[0]
        preferences={'expected_version':0,'weekly':[{'weekday':tomorrow.isoweekday(),'start':'09:00','end':'15:00'}],'exclusions':[]}
        p=api.post(path+'/availability/preview',json=preferences).json()
        assert api.put(path+'/availability',json={**preferences,'expected_revision':p['base_revision']}).status_code==200
        exam=api.post('/items',json={'semester_id':s['id'],'kind':'exam','title':'合成概率论考试','course_id':course['id'],'certainty':'formal',
            'time':{'precision':'exact','at':tomorrow.isoformat(),'end_at':(tomorrow+timedelta(hours=1)).isoformat()},
            'reminders':[{'mode':'relative','lead_minutes':60}]}).json()
        review=api.post(f"/exams/{exam['id']}/reviews",json={'expected_exam_version':1,'remaining_minutes':180,'deadline_mode':'exam','start_policy':'now'})
        assert review.status_code==201;review=review.json()
        assert review['review_exam_id']==exam['id']
        assert api.post(f"/items/{review['id']}/reminders",json={'expected_item_version':1,'mode':'relative','lead_minutes':60}).status_code==201
        proposal=api.post(path+'/plan-proposals',json={'days':7,'tasks':[{'item_id':review['id']}]}).json()
        assert proposal['status']=='FEASIBLE_COMPLETE'
        assert api.post(f"/plan-proposals/{proposal['id']}/accept",json={'expected_version':1,'expected_revision':proposal['base_revision']}).status_code==200
        old_plans=api.get(path+'/plans').json()['blocks']
        course_data=api.get(f"/courses/{course['id']}/hub").json()
        assert {i['id'] for i in course_data['items']}=={exam['id'],review['id']}
        center=api.get(path+'/hub').json()
        assert center['exams'][0]['review_remaining_minutes']==180 and center['exams'][0]['review_planned_minutes']==180
        change={'expected_version':1,'time':{'precision':'exact','at':tomorrow.replace(hour=10).isoformat(),'end_at':tomorrow.replace(hour=11).isoformat()},
            'certainty':'formal','location':'示例楼A101','reason':'合成正式改期通知','align_review_deadlines':True}
        change_path=f"/exams/{exam['id']}/reschedule"
        preview=api.post(change_path+'/preview',json=change).json()
        assert preview['affected_blocks'] and preview['review_reminders_after']
        assert api.get(f"/items/{exam['id']}").json()['time']==exam['time']
        assert api.get(path+'/plans').json()['blocks']==old_plans
        # A new reminder changes preview dependencies without changing the semester.
        assert api.post(f"/items/{exam['id']}/reminders",json={'expected_item_version':1,'mode':'relative','lead_minutes':30}).status_code==201
        assert api.post(change_path,json={**change,'expected_revision':preview['base_revision'],'preview_token':preview['preview_token']}).status_code==409
        preview=api.post(change_path+'/preview',json=change).json()
        body={**change,'expected_revision':preview['base_revision'],'preview_token':preview['preview_token']}
        key={'Idempotency-Key':'centers-confirm-'+secrets.token_hex(8)}
        receipt=api.post(change_path,json=body,headers=key);assert receipt.status_code==200,receipt.status_code
        assert api.post(change_path,json=body,headers=key).json()==receipt.json()
        assert len(receipt.json()['changed_items'])==2
        after=api.get(path+'/hub').json()
        assert after['revision']==receipt.json()['revision']
        summary=after['exams'][0]
        assert summary['review_remaining_minutes']==180
        assert datetime.fromisoformat(summary['reviews'][0]['time']['at'])==tomorrow.replace(hour=10)
        assert len(after['weeks'][week-1]['items'])==2
        assert api.get(path+'/plans').json()['blocks']==old_plans
        assert api.get(path+'/plans').json()['invalid_blocks']
        assert all(i['reminders'][0]['trigger_at']!=exam['reminders'][0]['trigger_at'] for i in receipt.json()['changed_items'])
        api.post('/auth/logout',json={'logout_token':session['logout_token']})
    checks=['explicit_course_links','review_created_once','effort_and_coverage_separate','preview_readonly','exam_and_review_reminder_preview',
        'reminder_dependency_stale','confirm_idempotent','batch_item_receipts','review_deadline_explicit_sync','work_unchanged','old_plans_preserved','timeline_same_revision']
    report={'passed':True,'source':'synthetic','account':username,'at':now.isoformat(),'review_minutes':180,'checks':checks}
    out=Path(__file__).resolve().parents[1]/'output/verification/centers-api.json';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'passed':True,'checks':len(checks),'review_minutes':180}))


if __name__=='__main__':main()
