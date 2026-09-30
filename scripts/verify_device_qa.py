"""Operate only the isolated QA package using synthetic data; never install it.

The user launches the QA app. Init requires its empty login screen and keeps
generated credentials in memory only. Evidence contains UI and timing data.
"""
import argparse
from datetime import datetime, timedelta
import json
import re
import secrets
import subprocess
import time
from pathlib import Path
from zoneinfo import ZoneInfo
import httpx
from verify_android_items import shell, nodes as raw_nodes, label, tap, ADB, DEVICE

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/verification/device-qa'
PACKAGE = 'cn.semesteros.semester_os.qa'


def nodes():
    found=raw_nodes()
    allowed={PACKAGE,'com.android.systemui','com.android.permissioncontroller',
             'com.google.android.permissioncontroller','com.android.documentsui','com.google.android.documentsui'}
    packages={n.get('package') for n in found if n.get('package')}
    assert packages <= allowed, 'Another application is foreground; QA stopped without interacting'
    return found


def wait_for(text, exact=False):
    for _ in range(12):
        matches = [n for n in nodes() if
                   (all(part == text for part in label(n).splitlines()) and bool(label(n))
                    if exact else text in label(n))]
        if matches: return matches[-1]
        time.sleep(.5)
    raise AssertionError('Expected QA element missing: '+text)


def screenshot(name):
    OUT.mkdir(parents=True, exist_ok=True)
    data = subprocess.run([str(ADB), '-s', DEVICE, 'exec-out', 'screencap', '-p'],
                          check=True, capture_output=True).stdout
    (OUT / f'{name}.png').write_bytes(data)


def inspect():
    for n in nodes():
        if n.get('password') == 'true': continue
        text = label(n)
        if text: print(text[:200], n.get('bounds'), n.get('class'))


def metrics(reset=False):
    pid = shell('pidof', PACKAGE).strip()
    assert pid and ' ' not in pid, 'QA app must be running'
    log = shell('logcat', '--pid='+pid, '-d', '-s', 'flutter')
    matches = re.findall(r'The Dart VM service is listening on http://127.0.0.1:(\d+)/([^\s]+)', log)
    assert matches, 'Profile VM service was not advertised'
    port, auth = matches[-1]
    forwarded = subprocess.run([str(ADB), '-s', DEVICE, 'forward', 'tcp:0', 'tcp:'+port],
                               check=True, capture_output=True, text=True).stdout.strip()
    try:
        with httpx.Client(base_url=f'http://127.0.0.1:{forwarded}/{auth}', timeout=20) as c:
            vm = c.get('getVM').json()['result']
            isolate = next(i['id'] for i in vm['isolates'] if i.get('name') == 'main')
            result = c.get('ext.semesteros.frames', params={'isolateId': isolate, 'reset': str(reset).lower()}).json()
            assert 'error' not in result, result
            return result['result']
    finally:
        subprocess.run([str(ADB), '-s', DEVICE, 'forward', '--remove', 'tcp:'+forwarded], check=True, capture_output=True)


def login_and_seed():
    initial = nodes()
    assert len([n for n in initial if n.get('class') == 'android.widget.EditText']) == 2
    assert any(label(n) == '登录' and n.get('package') == PACKAGE for n in initial), 'Empty QA login required'
    username, password = 'device_' + secrets.token_hex(5), secrets.token_hex(12)
    today = datetime.now(ZoneInfo('Asia/Shanghai')).date()
    monday = today - timedelta(days=today.weekday() + 21)
    with httpx.Client(base_url='http://127.0.0.1:8872/api/v1', timeout=30) as c:
        def post(path, value):
            r = c.post(path, json=value)
            assert r.is_success, (path, r.status_code, r.text)
            return r.json() if r.content else {}
        user = post('/auth/register', {'username': username, 'password': password})
        c.headers['Authorization'] = 'Bearer ' + user['access_token']
        periods = [{'number':i+1,'start':a,'end':b} for i,(a,b) in enumerate([
            ('08:00','08:50'),('09:00','09:50'),('10:10','11:00'),('11:10','12:00'),('14:00','14:50'),('15:00','15:50')])]
        s = post('/semesters', {'name':'设备验证学期 · 合成数据','first_monday':str(monday),'total_weeks':20,'periods':periods})
        sid = s['id']
        courses = [{'title': ['概率论','软件工程','大学英语'][j], 'teacher':'示例教师', 'location':f'A{d}0{j+1}',
                    'weekday':d, 'weeks':list(range(1,21)), 'sections':[2*j+1,2*j+2]} for d in range(1,8) for j in range(3)]
        batch = post('/imports', {'semester_id':sid,'source':'manual','courses':courses})
        post('/imports/'+batch['id']+'/apply', {'expected_revision':batch['base_revision']})
        for i,title in enumerate(['Java实验报告','整理调研材料','复习概率论','社团报名']):
            post('/items', {'semester_id':sid,'title':title,'kind':'task','certainty':'formal','remaining_minutes':60+i*30,
                 'start_policy':'now','priority':'high' if i==0 else 'normal','category_id':'study' if i<3 else 'affairs',
                 'tags':['设备验证'],'time':{'precision':'exact','at':f'{today+timedelta(days=i+2)}T20:00:00+08:00'}})
        availability={'expected_version':0,'weekly':[{'weekday':d,'start':'19:00','end':'22:00'} for d in range(1,8)],'exclusions':[]}
        preview=post(f'/semesters/{sid}/availability/preview',availability)
        saved=c.put(f'/semesters/{sid}/availability',json={**availability,'expected_revision':preview['base_revision']})
        assert saved.is_success,saved.text
        revision=c.get('/semesters').json()[0]['revision']
        post('/events',{'semester_id':sid,'expected_revision':revision,'title':'项目讨论','location':'A301',
            'time':{'precision':'exact','at':f'{today}T17:00:00+08:00','end_at':f'{today}T18:00:00+08:00'}})
        # Only non-secret identifiers are persisted for read-only DB verification.
        OUT.mkdir(parents=True,exist_ok=True)
        (OUT/'scenario.json').write_text(json.dumps({'username':username,'user_id':user['user']['id'],'semester_id':sid,
            'date':str(today),'data':'synthetic'},ensure_ascii=False,indent=2),encoding='utf-8')
        post('/auth/logout', {'logout_token':user['logout_token']})
    for i,value in enumerate([username,password]):
        fields=sorted([n for n in nodes() if n.get('class')=='android.widget.EditText'],key=lambda n:int(re.findall(r'\d+',n.get('bounds'))[1]))
        tap(fields[i]); shell('input','text',value)
    shell('input','keyevent','4')
    tap(wait_for('登录',exact=True))
    wait_for('今日课程'); screenshot('today-native')
    print('QA synthetic account login and server calendar displayed')


def navigation():
    metrics(reset=True)
    for _ in range(3):
        for title in ['日程','计划','学期','今日']:
            tap(wait_for(title,exact=True)); time.sleep(.35)
    result=metrics()
    (OUT/'navigation-frames.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result))


def main():
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['init','inspect','frames','reset','navigation','screenshot','tap','type'])
    parser.add_argument('value',nargs='?',default='native')
    args=parser.parse_args()
    if args.action=='init':login_and_seed()
    elif args.action=='inspect':inspect()
    elif args.action=='navigation':navigation()
    elif args.action in ('frames','reset'):print(json.dumps(metrics(reset=args.action=='reset')))
    elif args.action=='screenshot':screenshot(args.value)
    elif args.action=='tap':tap(wait_for(args.value,exact=True))
    elif args.action=='type':
        assert args.value.isascii(),'ADB text supports ASCII here; use image input for Chinese notices'
        fields=[n for n in nodes() if n.get('class')=='android.widget.EditText']
        assert len(fields)==1, 'Only one visible composer expected'
        tap(fields[0]);shell('input','text',args.value.replace(' ','%s'))


if __name__=='__main__':main()
