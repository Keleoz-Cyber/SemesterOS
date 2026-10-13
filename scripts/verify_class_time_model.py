"""Exercise class-period questions and spoken corrections with the configured model."""
from datetime import datetime
from copy import deepcopy
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'services/api'))
sys.path.insert(0, str(ROOT / 'services/api/tests'))
from verify_calendar_api import client
from test_agent_class_time_provenance import setup, spoken, ORIGINAL, CORRECTION
from app.agent_runtime import work_once
from app.models import AgentRun
from sqlalchemy.orm import Session


def main():
    report = {'passed': False, 'data': 'synthetic account and isolated SQLite; real configured model', 'turns': []}
    output = ROOT / 'output/verification/class-time-model.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        with client(None) as c:
            account, h, sid, tid = setup(c)
            # The only Friday afternoon course is 5-6; it must not redefine "second".
            imported = c.post('/api/v1/imports', headers=h, json={'semester_id': sid, 'source': 'manual',
                'courses': [{'title': '形势与政策', 'weekday': 5, 'sections': [5, 6], 'weeks': [7]}]}).json()
            applied = c.post('/api/v1/imports/'+imported['id']+'/apply', headers=h, json={'expected_revision': 0})
            assert applied.status_code == 200, applied.text

            def ask(text, key):
                req, source_id = spoken(c, account, h, sid, tid, text, key)
                begin = time.monotonic()
                assert work_once(c.app.state.engine)
                result = c.get('/api/v1/agent/runs/'+req['id'], headers=h).json()
                with Session(c.app.state.engine) as db:
                    state = db.get(AgentRun, req['id']).state
                entry = {'input': text, 'status': result['status'], 'answer': result['answer'],
                    'seconds': round(time.monotonic()-begin, 2), 'preview': result['preview'],
                    'trace': state['turn_messages']}
                report['turns'].append(entry)
                print(json.dumps({k:entry[k] for k in ('input','status','answer','seconds')}, ensure_ascii=False), flush=True)
                assert result['status'] in ('completed', 'needs_confirmation'), result
                return result, source_id

            first, source_id = ask(ORIGINAL, 'first')
            assert first['status'] == 'needs_confirmation', first
            assert first['preview']['body']['time']['at'].startswith('2026-10-16T08:25'), first
            assert first['preview']['body']['time']['end_at'] is None
            question, _ = ask('不是下午第二节课吗', 'question')
            assert '没有记错' not in question['answer'], question
            assert '小节' not in question['answer'], question
            corrected, _ = ask(CORRECTION, 'correction')
            history = c.get('/api/v1/agent/threads/'+tid, headers=h).json()['runs']
            pending = [r for r in history if r['status'] == 'needs_confirmation']
            assert len(pending) == 1, history
            final = pending[0]
            preview = final['preview']
            assert preview and preview['kind'] == 'event', corrected
            assert datetime.fromisoformat(preview['body']['time']['at']).hour in (8, 16)
            assert datetime.fromisoformat(preview['body']['time']['at']).minute == 25
            assert preview['body']['time']['end_at'] is None
            assert preview['body']['source_text'] == ORIGINAL, preview
            assert preview['source']['id'] == source_id, preview
            saved = c.post('/api/v1/agent/runs/'+final['id']+'/decision', headers=h,
                json={'decision': 'confirm', 'token': preview['token']})
            assert saved.status_code == 200, saved.text
            event = saved.json()['receipt']['event']
            assert event['source_text'] == ORIGINAL and event['source_id'] == source_id
            assert datetime.fromisoformat(event['time']['at']).isoformat().startswith('2026-10-16T08:25')
            explanation, _ = ask('现在保存的是哪天几点？原文是哪一句？', 'verify')
            assert explanation['status'] == 'completed' and explanation['preview'] is None
            report['saved_event'] = event
            # Replay an old, wrong, UNCONFIRMED preview. This is a local fixture,
            # not a change to any user data or a way to bypass confirmation.
            tid = c.post('/api/v1/agent/threads', headers=h, json={'semester_id': sid}).json()['id']
            old, old_source = spoken(c, account, h, sid, tid, ORIGINAL, 'legacy-first')
            from test_agent import call
            assert work_once(c.app.state.engine, model=lambda m,t: call('prepare_event', {
                'action':'create','fields':{'title':'旧预览开会','time':{'precision':'date','date':'2026-10-16'}}}))
            with Session(c.app.state.engine) as db:
                row = db.get(AgentRun, old['id']); state = deepcopy(row.state)
                for field in ('body', 'after'):
                    state['preview'][field]['time'] = {'precision':'exact','at':'2026-10-16T06:30:00+00:00','end_at':None}
                row.state = state; db.commit()
            fixed, _ = ask('不是下午第二节课吗？', 'legacy-question')
            assert fixed['status'] == 'needs_confirmation', fixed
            assert fixed['preview']['body']['time']['at'].startswith('2026-10-16T08:25'), fixed
            assert fixed['preview']['body']['source_text'] == ORIGINAL
            assert fixed['preview']['source']['id'] == old_source
            report['passed'] = True
    finally:
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('PASS: real-model follow-up retained the original notice and used the semester bell time.', flush=True)


if __name__ == '__main__':
    main()
