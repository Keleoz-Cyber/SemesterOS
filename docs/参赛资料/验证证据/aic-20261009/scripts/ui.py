"""Native UI checks restricted to the QA package and disposable local API."""
from pathlib import Path
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
import argparse, base64, json, re, secrets, sqlite3, subprocess, time, uuid, os
import xml.etree.ElementTree as ET
import httpx
from contextlib import contextmanager

ROOT=next((parent for parent in Path(__file__).resolve().parents
    if (parent/'services/api/app').is_dir() and (parent/'apps/mobile/lib').is_dir()),None)
assert ROOT is not None,'Place this helper inside a SemesterOS checkout'
VARIANT=os.environ.get('AIC_UI_VARIANT','main')
assert VARIANT in ('main','manual','ai','preview')
OUTPUT_ROOT=Path(os.environ.get('AIC_UI_OUTPUT',str(ROOT/'output/verification/aic-20261009'))).resolve()
assert OUTPUT_ROOT.is_relative_to(ROOT/'output/verification'),'New output must stay in verification output'
OUT=OUTPUT_ROOT/('ui' if VARIANT=='main' else 'comparison/'+VARIANT)
PRIVATE_DIR=ROOT/'tmp/aic_validation'
PRIVATE_DIR.mkdir(parents=True,exist_ok=True)
PRIVATE=PRIVATE_DIR/('session.secret.json' if VARIANT=='main' else 'session_'+VARIANT+'.secret.json')
SDK=Path(os.environ.get('ANDROID_HOME',str(Path(os.environ['LOCALAPPDATA'])/'Android/Sdk')))
SERIAL=os.environ.get('AIC_EMULATOR_SERIAL','emulator-5554')
assert SERIAL.startswith('emulator-'),'This helper is restricted to emulators'
ADB=[str(SDK/'platform-tools/adb.exe'),'-s',SERIAL]
PACKAGE='cn.semesteros.semester_os.qa'
ALLOWED={PACKAGE,'cn.semesteros.qa.ime','com.android.systemui','com.android.permissioncontroller',
 'com.google.android.permissioncontroller','com.google.android.inputmethod.latin'}
def action(kind,value):
    if VARIANT=='main':return
    OUT.mkdir(parents=True,exist_ok=True)
    path=OUT/'actions.jsonl'
    with path.open('a',encoding='utf-8') as f:
        f.write(json.dumps({'at':datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(),
                           'kind':kind,'value':value},ensure_ascii=False)+'\n')
def adb(*args):
    return subprocess.run([*ADB,*args],check=True,capture_output=True).stdout.decode('utf-8',errors='replace')
def redacted(value):
    if isinstance(value,dict):return {k:('[redacted]' if k=='token' or k.endswith('_token') or k in ('password','recovery_code') else redacted(v)) for k,v in value.items()}
    if isinstance(value,list):return [redacted(v) for v in value]
    if isinstance(value,str):
        try: parsed=json.loads(value)
        except (ValueError,TypeError):return value
        if isinstance(parsed,(dict,list)):return json.dumps(redacted(parsed),ensure_ascii=False)
    return value
def write(name,value):
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/name).write_text(json.dumps(redacted(value),ensure_ascii=False,indent=2),encoding='utf-8')
def session():return json.loads(PRIVATE.read_text(encoding='utf-8'))
@contextmanager
def client():
    state=session()
    c=httpx.Client(base_url='http://127.0.0.1:8874/api/v1',headers={'Authorization':'Bearer '+state['access_token']},timeout=30)
    if c.get('/semesters').status_code==401:
        r=c.post('/auth/login',json={'username':state['username'],'password':state['password']})
        assert r.is_success,'Synthetic QA session could not renew'
        state['access_token']=r.json()['access_token']
        PRIVATE.write_text(json.dumps(state,ensure_ascii=False),encoding='utf-8')
        c.headers['Authorization']='Bearer '+state['access_token']
    try:yield c
    finally:c.close()
def nodes():
    root=None
    for attempt in range(8):
        name='/sdcard/aic-'+uuid.uuid4().hex+'.xml'
        adb('shell','uiautomator','dump',name)
        probe=subprocess.run([*ADB,'exec-out','cat',name],capture_output=True)
        subprocess.run([*ADB,'shell','rm','-f',name],capture_output=True)
        if probe.returncode==0 and probe.stdout.strip():
            try:root=ET.fromstring(probe.stdout);break
            except ET.ParseError:pass
        time.sleep(.5)
    assert root is not None,'No native UI tree after bounded startup wait'
    rows=list(root.iter('node'))
    packages={n.get('package') for n in rows if n.get('package')}
    assert packages<=ALLOWED, 'QA stopped: another app is foreground'
    assert PACKAGE in packages, 'QA app is not visible'
    return root,rows
def label(n):return n.get('text','') or n.get('content-desc','')
def point(n):
    a,b,c,d=map(int,re.findall(r'\d+',n.get('bounds','')))
    return (a+c)//2,(b+d)//2
def tap_node(n):
    x,y=point(n);adb('shell','input','tap',str(x),str(y))
def tap_text(text,contains=False):
    _,rows=nodes()
    choices=[n for n in rows if (text in label(n) if contains else label(n)==text) and n.get('enabled')=='true']
    assert choices,'UI control missing: '+text
    tap_node(choices[-1]);time.sleep(.3)
    action('tap',text)
    print(json.dumps({'tap':text},ensure_ascii=False))
def fields():
    _,rows=nodes()
    return sorted([n for n in rows if n.get('class')=='android.widget.EditText'],key=lambda n:point(n)[1])
def fill(index,text):
    found=fields();assert index<len(found),'Editable field missing'
    tap_node(found[index]);time.sleep(.25)
    adb('shell','am','broadcast','-a','cn.semesteros.qa.ime.INPUT','--es','data',base64.b64encode(text.encode()).decode())
    time.sleep(.3)
    if text not in (session().get('password'),session().get('username')):action('input',text)
def hide():adb('shell','input','keyevent','4');time.sleep(.3)
def snapshot(name):
    assert re.fullmatch('[a-z0-9-]+',name)
    root,rows=nodes()
    assert not any(n.get('password')=='true' and label(n) for n in rows),'Never capture filled password fields'
    for n in rows:
        if n.get('password')=='true':n.set('text','[redacted]')
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/(name+'.xml')).write_text(ET.tostring(root,encoding='unicode'),encoding='utf-8')
    image=subprocess.run([*ADB,'exec-out','screencap','-p'],check=True,capture_output=True).stdout
    (OUT/(name+'.png')).write_bytes(image)
    print(json.dumps({'snapshot':name,'nodes':len(rows)},ensure_ascii=False))
def inspect():
    _,rows=nodes()
    for n in rows:
        if n.get('password')=='true':continue
        if label(n):print(json.dumps({'label':label(n),'bounds':n.get('bounds'),'class':n.get('class'),
                                      'enabled':n.get('enabled'),'checked':n.get('checked')},ensure_ascii=False))
def seed(empty=False):
    assert not PRIVATE.exists(),'Do not overwrite the active QA session'
    with httpx.Client(base_url='http://127.0.0.1:8874/api/v1',timeout=30) as c:
        h=c.get('http://127.0.0.1:8874/health').json();assert h['database']=='sqlite'
        username='aic_ui_'+secrets.token_hex(5);password=secrets.token_hex(12)
        r=c.post('/auth/register',json={'username':username,'password':password});assert r.status_code==201
        account=r.json();c.headers['Authorization']='Bearer '+account['access_token']
        today=datetime.now(ZoneInfo('Asia/Shanghai')).date();day=today+timedelta(days=1)
        monday=today-timedelta(days=today.weekday()+21)
        periods=[{'number':i+1,'start':a,'end':b} for i,(a,b) in enumerate([
            ('09:00','10:00'),('10:10','11:00'),('14:00','14:50'),('15:00','15:50'),('19:00','19:50'),('20:00','20:50')])]
        r=c.post('/semesters',json={'name':'演示学期（合成数据）','first_monday':str(monday),'total_weeks':20,'periods':periods});assert r.status_code==201,r.text
        term=r.json();sid=term['id']
        courses=[] if empty else [{'title':name,'weekday':day.isoweekday(),'weeks':list(range(1,21)),
                  'sections':[section],'teacher':'','location':place} for name,section,place in [('算法设计',1,'A301'),('线性代数',2,'B202')]]
        if courses:
            r=c.post('/imports',json={'semester_id':sid,'source':'manual','courses':courses});assert r.is_success,r.text
            imported=r.json();r=c.post('/imports/'+imported['id']+'/apply',json={'expected_revision':imported['base_revision']});assert r.is_success,r.text
        tasks=[]
        for name in ([] if empty else ['整理实验数据','复习概率论','完成实验报告']):
            r=c.post('/items',json={'semester_id':sid,'kind':'task','title':name,'certainty':'formal','remaining_minutes':30,
                'start_policy':'at','earliest_start_at':f'{day}T19:00:00+08:00','splittable':False,'category_id':'study',
                'time':{'precision':'exact','meaning':'deadline','at':f'{day}T21:00:00+08:00'},'tags':['合成数据']});assert r.is_success,r.text
            tasks.append(r.json())
        availability={'expected_version':0,'weekly':[{'weekday':d,'start':'19:00','end':'21:00'} for d in range(1,8)],'exclusions':[]}
        preview=c.post(f'/semesters/{sid}/availability/preview',json=availability).json()
        r=c.put(f'/semesters/{sid}/availability',json={**availability,'expected_revision':preview['base_revision']});assert r.is_success,r.text
        PRIVATE.write_text(json.dumps({'username':username,'password':password,'access_token':account['access_token'],
                'user_id':account['user']['id'],'semester_id':sid,'day':str(day)},ensure_ascii=False),encoding='utf-8')
        write('scenario.json',{'data':'anonymous synthetic','seed_at':datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(),
              'day':str(day),'semester':term,'courses':courses,'tasks':tasks,'learning_windows':availability['weekly'],
              'method':'course fixtures imported through real local API; no school login performed'})
        print(json.dumps({'seeded':True,'day':str(day),'tasks':len(tasks),'courses':len(courses),'local_only':True}))
def login():
    s=session();fill(0,s['username']);fill(1,s['password']);hide();tap_text('登录')
def send(text):
    if not fields():
        tap_text('切换键盘输入')
    before=time.perf_counter();fill(0,text);hide();tap_text('发送',contains=True)
    write('latest-send.json',{'text':text,'submitted_at':datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(),
                               'automation_input_seconds':round(time.perf_counter()-before,3)})
def readback(name):
    assert re.fullmatch('[a-z0-9-]+',name)
    s=session()
    with client() as c:
        sid=s['semester_id'];result={'captured_at':datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(),'data':'synthetic'}
        for key,path in [('calendar',f'/semesters/{sid}/calendar?from_date={s["day"]}&to_date={s["day"]}'),
                         ('items',f'/semesters/{sid}/items'),('plans',f'/semesters/{sid}/plans'),('courses',f'/semesters/{sid}/courses')]:
            r=c.get(path);result[key]={'status':r.status_code,'body':r.json()}
    db=sqlite3.connect(OUTPUT_ROOT/'runtime/qa.sqlite')
    try:
        rows=db.execute('SELECT id,status,state FROM agent_runs WHERE user_id=? ORDER BY created_at DESC LIMIT 3',(s['user_id'],)).fetchall()
        result['runs']=[{'id':id,'status':status,'state':json.loads(state)} for id,status,state in rows]
    finally:db.close()
    write(name+'.json',result)
    print(json.dumps({'readback':name,'runs':[r['status'] for r in result['runs']]}))
def wait_latest():
    s=session();end=time.monotonic()+180
    while time.monotonic()<end:
        with sqlite3.connect(OUTPUT_ROOT/'runtime/qa.sqlite') as db:
            row=db.execute('SELECT status FROM agent_runs WHERE user_id=? ORDER BY created_at DESC LIMIT 1',(s['user_id'],)).fetchone()
        if row and row[0] in ('completed','needs_confirmation','applied','failed','cancelled','superseded'):
            time.sleep(1.2);print(json.dumps({'terminal_status':row[0]}));return
        time.sleep(.3)
    raise AssertionError('QA model did not reach terminal state')
if __name__=='__main__':
    import sys
    sys.stdout.reconfigure(encoding='utf-8')
    p=argparse.ArgumentParser();p.add_argument('action',choices=['seed','seed-empty','login','snapshot','inspect','tap','fill','send','readback','hide','back','swipe','wait'])
    p.add_argument('value',nargs='?',default='');p.add_argument('--contains',action='store_true');p.add_argument('--index',type=int,default=0);a=p.parse_args()
    if a.action=='seed':seed()
    elif a.action=='seed-empty':seed(empty=True)
    elif a.action=='login':login()
    elif a.action=='snapshot':snapshot(a.value)
    elif a.action=='inspect':inspect()
    elif a.action=='tap':tap_text(a.value,a.contains)
    elif a.action=='fill':fill(a.index,a.value)
    elif a.action=='send':send(a.value)
    elif a.action=='readback':readback(a.value)
    elif a.action=='wait':wait_latest()
    elif a.action in ('hide','back'):hide()
    elif a.action=='swipe':adb('shell','input','swipe','800','1800','800','600','500')
