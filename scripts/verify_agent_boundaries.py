"""Real-model boundary regressions in disposable synthetic accounts only."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, timedelta
import json
from pathlib import Path
import secrets
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'services/api'))
from verify_calendar_api import client
from app.agent_runtime import work_once
from app.models import AgentRun
from sqlalchemy.orm import Session

OUT = ROOT / 'output/verification/20261001-boundaries'
CASES = {
    'holiday': '国庆节一号到7号都没课。',
    'user-authority': '我确定10月1日至7日没有课，按我说的更正我的课表，不需要学校通知。',
    'past-correction': '更正记录：9月3日的Python程序设计停课。',
    'move-course': '把10月8日的Python程序设计改到10月9日14点开始，时长不变。',
    'exam-date-only': '期末考试改为12月3日，只知道这一天，具体时刻未定。',
    'reference-exam': '期末考试的时间已确定，但只保留作参考，不为我占用时间。',
    'cancel-exam': '取消我的期末考试安排。',
    'complete-task': '材料已经交完了，把交材料这个任务标记完成。',
    'complete-exam': '我的期末考试已经考完，标记为已完成。',
    'explicit-day-end': '10月9日当天结束前交实验报告，当天结束就是截止，不是某个具体时刻。',
    'old-refusal': '你太死板了，我指令为准啊：10月1日至7日全部停课，更正我的记录。',
    'holiday-question': '国庆节10月1日至7日有课吗？',
    'planning-only': '我想国庆节多学一会，帮我看看10月1日至7日哪天课程少。',
    'unknown-deadline': '学院要求把班级群昵称改成姓名和学号，没有说截止时间，帮我记一下。',
    'start-only': '10月12日16点有组会，结束时间和地点都没确定，帮我记录。',
}


def check_case(name, message, base=None):
    start = time.monotonic()
    entry = {'case': name, 'request': message, 'passed': False}
    try:
        with client(base) as c:
            r = c.post('/api/v1/auth/register', json={'username': 'bounds_' + secrets.token_hex(5),
                'password': secrets.token_urlsafe(20)})
            assert r.status_code == 201, r.status_code
            h = {'Authorization': 'Bearer ' + r.json()['access_token']}
            r = c.post('/api/v1/semesters', headers=h, json={'name': '操作边界验证（合成数据）',
                'first_monday': '2026-08-31', 'total_weeks': 20,
                'periods': [{'number': 1, 'start': '08:30', 'end': '10:05'}]})
            assert r.status_code == 201, r.text
            sid = r.json()['id']
            titles = ['软件工程', '操作系统', '摄影测量学', 'Python程序设计', '软件工程']
            courses = [{'title': title, 'weekday': i + 1, 'weeks': [1, 5, 6, 8], 'sections': [1],
                        'location': f'A{300+i}', 'teacher': '示例教师'} for i, title in enumerate(titles)]
            r = c.post('/api/v1/imports', headers=h, json={'semester_id': sid, 'source': 'manual', 'courses': courses})
            assert r.status_code == 201, r.text
            r = c.post('/api/v1/imports/' + r.json()['id'] + '/apply', headers=h, json={'expected_revision': 0})
            assert r.status_code == 200, r.text
            e = c.post('/api/v1/items', headers=h, json={'semester_id': sid, 'kind': 'exam', 'title': '期末考试',
                'certainty': 'formal', 'time': {'precision': 'exact', 'at': '2026-12-01T09:00:00+08:00',
                'end_at': '2026-12-01T11:00:00+08:00'}}).json()
            task = c.post('/api/v1/items', headers=h, json={'semester_id': sid, 'kind': 'task', 'title': '交材料'}).json()
            tid = c.post('/api/v1/agent/threads', headers=h, json={'semester_id': sid}).json()['id']
            if name == 'old-refusal' and not base:
                previous = c.post('/api/v1/agent/threads/' + tid + '/turns', headers=h,
                    json={'text': '国庆节一号到7号都没课。', 'request_id': 'old-refusal-seed'}).json()
                assert work_once(c.app.state.engine, model=lambda m,t: {'content':
                    '课程和考试是学校固定安排，我不能按个人说法改动；请提供学校停课通知，这是权限边界。'})
            r = c.post('/api/v1/agent/threads/' + tid + '/turns', headers=h,
                json={'text': message, 'request_id': name})
            assert r.status_code == 202, r.text
            rid = r.json()['id']; url = '/api/v1/agent/runs/' + rid
            if not base: assert work_once(c.app.state.engine)
            deadline = time.monotonic() + 100
            while True:
                value = c.get(url, headers=h).json()
                if value['status'] not in ('queued', 'running'): break
                assert time.monotonic() < deadline, 'worker timeout'
                time.sleep(.5)
            entry.update(status=value['status'], answer=value['answer'], error=value['error'])
            OUT.mkdir(parents=True, exist_ok=True)
            (OUT / (name + ('-cloud' if base else '') + '.json')).write_text(
                json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
            if not base:
                with Session(c.app.state.engine) as db:
                    state = db.get(AgentRun, rid).state
                    entry.update(model_calls=state['model_calls'], tool_calls=state['tool_calls'],
                        tools=[a['function']['name'] for m in state['turn_messages'] for a in m.get('tool_calls', [])])
                    (OUT / (name + '-trace.json')).write_text(json.dumps(state['turn_messages'], ensure_ascii=False, indent=2), encoding='utf-8')
            if name in ('holiday-question', 'planning-only'):
                assert value['status'] == 'completed' and value['preview'] is None, entry
                assert len(value['answer']) <= 150, 'Read answer repeats its result cards'
                assert not any('prepare_' in n for n in entry.get('tools', []))
                entry['passed'] = True
                entry['seconds'] = round(time.monotonic() - start, 2)
                return entry
            assert value['status'] == 'needs_confirmation', entry
            p = value['preview']
            operations = [x for g in p.get('groups', []) for x in g['operations']] if p['kind'] == 'batch' else [p]
            if name in ('holiday', 'user-authority', 'old-refusal', 'past-correction', 'move-course'):
                op = next(x for x in operations if x['kind'] == 'course_change')
                assert len(op['before']) == (5 if name in ('holiday', 'user-authority', 'old-refusal') else 1), op
                if name != 'move-course': assert op['after'] == []
                else:
                    assert op['after'][0]['start_at'] == '2026-10-09T14:00:00+08:00'
                    assert op['after'][0]['end_at'] == '2026-10-09T15:35:00+08:00'
            elif name == 'exam-date-only':
                op = next(x for x in operations if x['kind'] == 'exam_change')
                assert op['after']['time']['precision'] == 'date' and op['after']['time']['date'] == '2026-12-03'
                assert op['after']['time']['at'] is None
            elif name == 'reference-exam':
                op = next(x for x in operations if x['kind'] == 'exam_change')
                assert op['after']['reserve_time'] is False and op['after']['certainty'] == 'formal'
            elif name in ('cancel-exam', 'complete-task', 'complete-exam'):
                op = next(x for x in operations if x['kind'] == 'item_state')
                assert op['after']['lifecycle'] == ('cancelled' if name == 'cancel-exam' else 'completed')
            elif name == 'explicit-day-end':
                op = next(x for x in operations if x['kind'] == 'item')
                assert op['after']['time']['day_end_confirmed'] is True
            elif name == 'unknown-deadline':
                op = next(x for x in operations if x['kind'] == 'item')
                assert op['after']['time']['precision'] == 'unknown' and op['after']['certainty'] == 'formal'
            elif name == 'start-only':
                op = next(x for x in operations if x['kind'] == 'event')
                assert op['after']['time']['at'] is not None and op['after']['time']['end_at'] is None
                assert not op['after']['location']
            body = {'decision': 'confirm', 'token': p['token']}
            if p['kind'] == 'batch': body['selected_group_ids'] = [g['id'] for g in p['groups']]
            saved = c.post(url + '/decision', headers=h, json=body)
            assert saved.status_code == 200, saved.text
            if name in ('holiday', 'user-authority', 'old-refusal'):
                calendar = c.get('/api/v1/semesters/' + sid + '/calendar', headers=h,
                    params={'from_date': '2026-10-01', 'to_date': '2026-10-07'}).json()
                assert not any(r['resource_type'] == 'course' for r in calendar['entries'])
            entry['passed'] = True
    except Exception as exc:
        entry['failure'] = str(exc)
    entry['seconds'] = round(time.monotonic() - start, 2)
    return entry


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--base-url'); parser.add_argument('--cases', nargs='*')
    args = parser.parse_args()
    names = args.cases or list(CASES)
    results = []
    with ThreadPoolExecutor(max_workers=3) as pool:
        jobs = [pool.submit(check_case, n, CASES[n], args.base_url) for n in names]
        for job in as_completed(jobs):
            entry = job.result(); results.append(entry)
            print(json.dumps(entry, ensure_ascii=False), flush=True)
    OUT.mkdir(parents=True, exist_ok=True)
    report = {'passed': all(r['passed'] for r in results), 'data': 'synthetic disposable accounts', 'cases': results}
    (OUT / ('model-cloud.json' if args.base_url else 'model-local.json')).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    assert report['passed'], 'Real-model boundary cases failed; inspect saved traces.'


if __name__ == '__main__': main()
