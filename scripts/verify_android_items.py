"""Synthetic Android/UI smoke. Requires the app to already be on its login screen.
Never logs out an existing user or reads their credentials. A new QA session is
created, exercised and logged out. No passwords/tokens are printed or persisted.
"""
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import time
import xml.etree.ElementTree as ET

import httpx

ROOT = Path(__file__).resolve().parents[1]
ADB = Path(os.environ['LOCALAPPDATA']) / 'Android/sdk/platform-tools/adb.exe'
DEVICE = 'emulator-5554'
DUMP = '/sdcard/semesteros-items-qa.xml'


def shell(*args):
    return subprocess.run([str(ADB), '-s', DEVICE, 'shell', *args], check=True, capture_output=True,
                          text=True, encoding='utf-8', errors='replace').stdout


def nodes():
    shell('uiautomator', 'dump', DUMP)
    return list(ET.fromstring(shell('cat', DUMP)).iter('node'))


def label(n):
    return (n.get('text', '') + '\n' + n.get('content-desc', '')).strip()


def tap(n):
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', n.get('bounds')))
    shell('input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))


def wait_for(text, exact=False):
    for _ in range(12):
        matches = [n for n in nodes() if (label(n) == text if exact else text in label(n))]
        if matches:
            return matches[-1]
        time.sleep(.5)
    raise AssertionError('Expected QA screen element missing: ' + text)


def main():
    initial = nodes()
    fields = [n for n in initial if n.get('class') == 'android.widget.EditText']
    assert len(fields) == 2 and any(label(n) == '登录' for n in initial), 'Login screen required; existing session untouched'
    username, password = 'qa_ui_' + secrets.token_hex(5), 'qa-' + secrets.token_hex(16)
    now = datetime.now(timezone.utc)
    with httpx.Client(base_url='http://127.0.0.1:8871/api/v1', timeout=20) as api:
        response = api.post('/auth/register', json={'username':username, 'password':password})
        assert response.status_code == 201
        session = response.json()
        api.headers['Authorization'] = 'Bearer ' + session['access_token']
        semester = api.post('/semesters', json={'name':'QA界面验证（合成）','first_monday':(now.date()-timedelta(days=now.weekday())).isoformat(),
            'total_weeks':20,'periods':[{'number':1,'start':'08:00','end':'08:50'}]}).json()
        saved = api.post('/items', json={'semester_id':semester['id'],'kind':'task','title':'QA Native synthetic task',
            'time':{'precision':'exact','at':(now+timedelta(days=3)).isoformat()},'remaining_minutes':90,'source_text':'合成UI验证数据'})
        assert saved.status_code == 201
        api.post('/auth/logout', json={'logout_token':session['logout_token']})
    for index,value in enumerate([username,password]):
        # The keyboard resizes and scrolls the Flutter form; never reuse old bounds.
        fields = [n for n in nodes() if n.get('class') == 'android.widget.EditText']
        fields.sort(key=lambda n:int(re.findall(r'\d+',n.get('bounds'))[1]))
        field = fields[index]
        tap(field)
        shell('input', 'keyevent', '123')
        count = len(field.get('text',''))
        if count:
            shell('input', 'keyevent', *(['67'] * (count + 5)))
            time.sleep(.2)
        shell('input','text',value)
        current = [n for n in nodes() if n.get('class') == 'android.widget.EditText' and n.get('focused') == 'true']
        assert current, 'Input focus lost during QA typing'
        if index == 0:
            assert current[0].get('text') == value, 'QA username entry was not exact'
        else:
            assert len(current[0].get('text','')) == len(value), 'QA password entry length mismatch'
    shell('input','keyevent','4')  # Dismiss keyboard.
    tap(wait_for('登录', exact=True))
    tap(wait_for('记录', exact=True))
    menu = [label(n) for n in nodes()]
    assert all(any(name in value for value in menu) for name in ['文字快速记录','记录作业','记录考试','记录个人任务'])
    shell('input','keyevent','4')
    tap(wait_for('计划'))
    wait_for('QA Native synthetic task')
    picture = subprocess.run([str(ADB),'-s',DEVICE,'exec-out','screencap','-p'],capture_output=True,check=True).stdout
    (ROOT/'output/verification/items-native.png').write_bytes(picture)
    tap(wait_for('账户',exact=True))
    tap(wait_for('退出登录'))
    wait_for('登录',exact=True)
    shell('rm',DUMP)
    report={'source':'synthetic','passed':True,'at':now.isoformat(),'account':username,
        'checks':['native_login','record_menu','server_items_in_plan','logout_back_to_login']}
    (ROOT/'output/verification/items-native.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Native app: login, four record entries, persisted task display and logout passed')


if __name__ == '__main__':
    main()
