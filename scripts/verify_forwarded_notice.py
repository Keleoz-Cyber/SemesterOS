"""Replay findings1's meeting notice, anonymizing only the tagged nickname.

Uses a disposable local DB and the configured model; does not deploy or access
the user's calendar. This verifies reviewed text, not image recognition.
"""
import json
import sys
import time
from pathlib import Path
from datetime import datetime
from sqlalchemy.orm import Session

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'services/api'))
from verify_calendar_api import client
from app.agent_runtime import work_once
from app.models import AgentRun, MediaSource
from app.reminder_rules import utcnow, instant

NOTICE = '本周三下午开组会哈，请大家注意下时间。@小林，你去约一下会议室吧？6412，周三下午17:00~18:00'


def main():
    evidence = []
    with client(None) as c:
        for n in range(3):
            account = c.post('/api/v1/auth/register', json={
                'username': f'notice_check_{n}', 'password': 'synthetic-password'}).json()
            h = {'Authorization': 'Bearer ' + account['access_token']}
            semester = c.post('/api/v1/semesters', headers=h, json={
                'name': '转发通知验证', 'first_monday': '2026-08-31', 'total_weeks': 20,
                'periods': [{'number': 1, 'start': '08:00', 'end': '08:50'}]}).json()
            sid = semester['id']
            tid = c.post('/api/v1/agent/threads', headers=h, json={'semester_id': sid}).json()['id']
            with Session(c.app.state.engine, expire_on_commit=False) as db:
                source = MediaSource(user_id=account['user']['id'], semester_id=sid,
                    upload_key='forwarded-notice', input_hash='0' * 64, kind='image',
                    mime='image/png', size=1, storage_key='synthetic.png', status='recognized',
                    text=NOTICE, original_text=NOTICE, reference_at='2026-09-21T23:13:00+08:00',
                    created_at=utcnow().isoformat())
                db.add(source); db.commit()
                source_id, version = source.id, source.version
            r = c.post(f'/api/v1/agent/threads/{tid}/turns', headers=h, json={
                'text': '请根据这份通知整理安排，先给我预览', 'request_id': f'forwarded-{n}',
                'source_id': source_id, 'source_version': version})
            assert r.status_code == 202, r.text
            rid = r.json()['id']; start = time.monotonic()
            assert work_once(c.app.state.engine)
            result = c.get(f'/api/v1/agent/runs/{rid}', headers=h).json()
            with Session(c.app.state.engine) as db:
                state = db.get(AgentRun, rid).state
                tools = [tool['function']['name'] for m in state['turn_messages'] for tool in m.get('tool_calls', [])]
            row = {'case': n + 1, 'status': result['status'], 'tools': tools,
                   'seconds': round(time.monotonic() - start, 2)}
            evidence.append(row); print(json.dumps(row, ensure_ascii=False), flush=True)
            assert result['status'] == 'needs_confirmation', result
            preview = result['preview']; assert preview['kind'] == 'event', preview
            event = preview['after']
            assert event['location'] == '6412', event
            assert instant(event['time']['at']) == datetime.fromisoformat('2026-09-23T17:00:00+08:00'), event
            assert instant(event['time']['end_at']) == datetime.fromisoformat('2026-09-23T18:00:00+08:00'), event
            assert 'prepare_item' not in tools, 'A task addressed to someone else must not become mine'
            saved = c.post(f'/api/v1/agent/runs/{rid}/decision', headers=h, json={
                'decision': 'confirm', 'token': preview['token']})
            assert saved.status_code == 200, saved.text
            assert saved.json()['receipt']['event']['source_id'] == source_id
            day = c.get(f'/api/v1/semesters/{sid}/day-brief?day=2026-09-23', headers=h).json()
            events = [e for e in day['entries'] if e['resource_type'] == 'event']
            assert len(events) == 1 and events[0]['location'] == '6412'
    report = {'passed': True, 'scope': 'anonymized findings1 meeting text, reviewed-source input; not OCR', 'runs': evidence}
    out = ROOT / 'output/verification/forwarded-notice.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
