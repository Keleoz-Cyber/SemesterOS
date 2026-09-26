"""Verify real model event parsing in an isolated database, or an explicit API URL.

Only synthetic notices and a newly registered test account are used.
"""
import argparse
from contextlib import contextmanager
from datetime import datetime
import json
import os
from pathlib import Path
import secrets
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'services/api'))


@contextmanager
def client(base):
    if base:
        import httpx
        with httpx.Client(base_url=base.rstrip('/'), timeout=65) as c:
            yield c
    else:
        from dotenv import dotenv_values
        from fastapi.testclient import TestClient
        from app.main import create_app
        for key, value in dotenv_values(ROOT / '.env').items():
            if key in ('DEEPSEEK_API_KEY', 'DEEPSEEK_MODEL', 'DEEPSEEK_BASE_URL') and value:
                os.environ[key] = value
        with tempfile.TemporaryDirectory(prefix='semester-events-') as d:
            with TestClient(create_app('sqlite:///' + str(Path(d) / 'case.sqlite'), initialize=True)) as c:
                yield c


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url')
    base = parser.parse_args().base_url
    checks = []
    cases = [
        ('下周三17:00到18:00开组会，地点会议室6412。', 'create_event'),
        ('暂定第14周开项目总结会，具体日期等通知。', 'create_event'),
        ('下周五交Java报告，大约还需要两小时。', 'create_item'),
    ]
    with client(base) as c:
        r = c.post('/api/v1/auth/register', json={'username': 'events_' + secrets.token_hex(6), 'password': secrets.token_urlsafe(20)})
        assert r.status_code == 201, r.status_code
        account = r.json(); h = {'Authorization': 'Bearer ' + account['access_token']}
        s = c.post('/api/v1/semesters', headers=h, json={'name': '合成验证学期', 'first_monday': '2026-08-31',
            'total_weeks': 20, 'periods': [{'number': 1, 'start': '08:00', 'end': '08:50'}]}).json()
        for source, expected in cases:
            r = c.post('/api/v1/capture/text', headers=h, json={'semester_id': s['id'], 'text': source,
                'reference_at': '2026-09-26T12:00:00+08:00'})
            assert r.status_code == 200, (r.status_code, r.text)
            data = r.json(); assert data['intent'] == expected, (expected, data['intent'])
            field = 'event' if expected == 'create_event' else 'item'
            t = data[field]['time']
            if expected == 'create_event':
                if '17:00' in source:
                    assert datetime.fromisoformat(t['at']) == datetime.fromisoformat('2026-09-30T09:00:00+00:00')
                    assert datetime.fromisoformat(t['end_at']) == datetime.fromisoformat('2026-09-30T10:00:00+00:00')
                else:
                    assert t['precision'] == 'week' and t['week'] == 14 and t['at'] is None
                rev = c.get('/api/v1/semesters', headers=h).json()[0]['revision']
                saved = c.post('/api/v1/events', headers=h, json={**data['event'], 'candidate_id': data['id'], 'expected_revision': rev})
                assert saved.status_code == 201, saved.text
                assert saved.json()['event']['source_text'] == source
            checks.append({'intent': expected, 'precision': t['precision']})
        c.post('/api/v1/auth/logout', json={'logout_token': account['logout_token']})
    report = {'passed': True, 'checks': checks, 'base_url': base or 'isolated database', 'data': 'synthetic notices; real model'}
    path = ROOT / 'output/verification/events-model.json'; path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
