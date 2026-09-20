"""Live localhost API smoke check using a new synthetic QA account, never a real student's session."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import secrets

import httpx


def main():
    now = datetime.now(timezone.utc)
    due = (now + timedelta(days=3)).replace(second=0, microsecond=0).astimezone(timezone(timedelta(hours=8)))
    monday = now.date() - timedelta(days=now.weekday())
    with httpx.Client(base_url='http://127.0.0.1:8871/api/v1', timeout=60) as api:
        username = 'qa_items_' + secrets.token_hex(5)
        response = api.post('/auth/register', json={'username':username, 'password':secrets.token_urlsafe(24)})
        assert response.status_code == 201
        session = response.json()
        api.headers['Authorization'] = 'Bearer ' + session['access_token']
        semester = api.post('/semesters', json={'name':'QA事项与提醒验证（合成）','first_monday':monday.isoformat(),'total_weeks':20,
            'periods':[{'number':1,'start':'08:00','end':'08:50'}]}).json()
        source = f"{due.year}年{due.month}月{due.day}日{due:%H:%M}前交合成实验报告，预计3小时"
        parsed = api.post('/capture/text', json={'semester_id':semester['id'],'text':source,'reference_at':now.isoformat()})
        assert parsed.status_code == 200, 'Live parse did not succeed'
        candidate = parsed.json()
        assert candidate['intent'] == 'create_item' and candidate['item']['remaining_minutes'] == 180
        assert api.get(f"/semesters/{semester['id']}/items").json()['items'] == []
        item = api.post('/items', json={**candidate['item'],'semester_id':semester['id'],'candidate_id':candidate['id'],
            'reminders':[{'mode':'relative','lead_minutes':120}]})
        assert item.status_code == 201, 'Confirmed save did not succeed'
        item = item.json()
        assert item['reminders'][0]['schedule_state'] == 'scheduled'
        assert len(api.get('/reminders').json()['reminders']) == 1
        done = api.post(f"/items/{item['id']}/lifecycle", json={'expected_version':item['version'],'lifecycle':'completed'})
        assert done.status_code == 200
        assert api.get('/reminders').json()['reminders'] == []
        assert len(api.get(f"/items/{item['id']}/history").json()) == 2
        api.post('/auth/logout', json={'logout_token':session['logout_token']})
    report = {'passed':True,'account':username,'source':'synthetic','checks':['real_deepseek_parse','candidate_not_applied','confirmed_save','relative_reminder','completion_cancels','history'], 'at':now.isoformat()}
    path = Path(__file__).resolve().parents[1] / 'output/verification/items-api-smoke.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'passed':True,'checks':len(report['checks'])}))


if __name__ == '__main__': main()
