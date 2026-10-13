"""Real-model, multi-turn everyday language checks on synthetic local accounts."""
from datetime import datetime
import json
from pathlib import Path
import secrets
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'services/api'))
from verify_calendar_api import client
from app.agent_runtime import work_once
from app.school_periods import HAUT_PERIODS


CASES = [
    {'name': 'only_start_and_location', 'turns': [
        ('2026年10月20日早上9点开班会，其他还没说', {'kind': 'event', 'clock': '09:00', 'no_end': True}),
        ('补一下，在6108', {'kind': 'event', 'clock': '09:00', 'no_end': True, 'location': '6108'}),
    ]},
    {'name': 'unknown_deadline_then_correct', 'turns': [
        ('记一下要交实验报告，截止时间还没通知', {'kind': 'item', 'precision': 'unknown'}),
        ('截止是2026年10月20日，只说了日期', {'kind': 'item', 'date': '2026-10-20'}),
        ('不对，是21日，其他不变', {'kind': 'item', 'date': '2026-10-21'}),
    ]},
    {'name': 'reference_then_participating', 'turns': [
        ('记下2026年10月20日19点到20点的讲座，地点A101，我还没决定去，先当参考', {'kind': 'event', 'reserve_time': False}),
        ('我决定去了，给我预留这段时间', {'kind': 'event', 'reserve_time': True}),
    ]},
]


def main():
    results = []
    for case in CASES:
        record = {'name': case['name'], 'passed': False, 'turns': []}
        try:
            with client(None) as c:
                account = c.post('/api/v1/auth/register', json={'username': 'qa_' + secrets.token_hex(6), 'password': secrets.token_urlsafe(20)}).json()
                h = {'Authorization': 'Bearer ' + account['access_token']}
                s = c.post('/api/v1/semesters', headers=h, json={'name': '合成口语验证', 'first_monday': '2026-08-31', 'total_weeks': 20, 'periods': HAUT_PERIODS}).json()
                tid = c.post('/api/v1/agent/threads', headers=h, json={'semester_id': s['id']}).json()['id']
                for index, (text, expected) in enumerate(case['turns']):
                    r = c.post(f'/api/v1/agent/threads/{tid}/turns', headers=h, json={'text': text, 'request_id': str(index)})
                    assert r.status_code == 202, r.text
                    begin = time.monotonic()
                    assert work_once(c.app.state.engine)
                    result = c.get('/api/v1/agent/runs/' + r.json()['id'], headers=h).json()
                    record['turns'].append({'input': text, 'seconds': round(time.monotonic()-begin, 2), 'result': result})
                    assert result['status'] == 'needs_confirmation', result.get('answer')
                    preview = result['preview']; after = preview['after']; t = after['time']
                    assert preview['kind'] == expected['kind']
                    for field in ('location', 'reserve_time'):
                        if field in expected: assert after[field] == expected[field], (field, after)
                    if expected.get('no_end'): assert t.get('end_at') is None, t
                    for field in ('precision', 'date'):
                        if field in expected: assert t[field] == expected[field], t
                    if 'clock' in expected:
                        from app.reminder_rules import SHANGHAI
                        assert datetime.fromisoformat(t['at']).astimezone(SHANGHAI).strftime('%H:%M') == expected['clock'], t
                    assert preview['body']['source_text'] == case['turns'][0][0], preview['body']['source_text']
                record['passed'] = True
        except Exception as exc: record['error'] = str(exc)
        results.append(record)
        print(json.dumps({'case': case['name'], 'passed': record['passed']}, ensure_ascii=False), flush=True)
    path = ROOT / 'output/verification/everyday-conversations.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({'passed': all(r['passed'] for r in results), 'cases': results,
        'data': 'isolated database and synthetic notices; configured real model'}, ensure_ascii=False, indent=2), encoding='utf-8')
    assert all(r['passed'] for r in results), f'Inspect {path}'


if __name__ == '__main__': main()
