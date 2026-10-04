"""Reproduce/verify refresh in the delay window of an inexact QA alarm.

Requires the isolated QA app to be running at its main screen. Creates only a
synthetic reminder via the visible assistant and leaves user/production apps alone.
"""
import argparse
from datetime import datetime, timedelta
import json
import re
import time
import httpx
from zoneinfo import ZoneInfo
from verify_device_qa import shell, nodes, label, tap, wait_for, wait_for_navigation, OUT, screenshot


def pending(target):
    alarms=re.findall(r'Alarm\{[^\n]*cn\.semesteros\.semester_os\.qa\}', shell('dumpsys', 'alarm'))
    return [a for a in alarms if f'origWhen {int(target.timestamp()*1000)} ' in a]


def delivery(title):
    text=shell('dumpsys','notification','--noredact')
    for block in re.split(r'(?=NotificationRecord\()',text):
        if (block.startswith('NotificationRecord(') and
            'cn.semesteros.semester_os.qa' in block.split('\n')[0] and
            f'android.title=String ({title})' in block):
            stamp=re.search(r'mCreationTimeMs=(\d+)',block)
            if stamp:return int(stamp.group(1))
    return None


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--expect',choices=['preserved','cancelled'],required=True)
    args=parser.parse_args()
    target=(datetime.now(ZoneInfo('Asia/Shanghai'))+timedelta(minutes=2)).replace(second=0,microsecond=0)
    title='QA delay window '+target.strftime('%H%M')
    tap(wait_for('输入通知或日程问题',exact=True));tap(wait_for('新对话',exact=True))
    fields=[n for n in nodes() if n.get('class')=='android.widget.EditText'];assert len(fields)==1
    text=f'Create a task titled {title}. Remind me at {target.isoformat()}. No deadline is known.'
    tap(fields[0]);shell('input','text',text.replace(' ','%s'));shell('input','keyevent','4');tap(wait_for('发送',exact=True))
    tap(wait_for('确认添加',exact=True));time.sleep(1);tap(wait_for('收起输入',exact=True));tap(wait_for_navigation('今日'))
    assert pending(target),'No pending QA alarm after confirmation'
    print('QA alarm queued for',target.isoformat(),flush=True)
    while datetime.now(ZoneInfo('Asia/Shanghai')).timestamp()<target.timestamp()+2:time.sleep(.5)
    before=pending(target)
    assert before,'Alarm already delivered; no delay window to test in this run'
    wait_for_navigation('今日')
    # Main list is at its beginning; a native downward drag invokes pull-refresh.
    refresh_started=time.time()
    shell('input','swipe','540','450','540','1500','450');time.sleep(2)
    after=pending(target)
    requests=httpx.get('http://127.0.0.1:8872/qa/requests',timeout=5).json()
    refreshed=any(r['path']=='/api/v1/reminders' and r['status']==200 and r['completed_at']>=refresh_started for r in requests)
    assert refreshed,'A successful reminder feed refresh was not observed'
    report={'target':target.isoformat(),'title':title,'expected':args.expect,'pending_before':len(before),'pending_after':len(after),'reminder_feed_refreshed':refreshed,'data':'synthetic'}
    (OUT/f'pending-refresh-{args.expect}.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    screenshot('pending-refresh-'+args.expect)
    print(json.dumps(report),flush=True)
    assert bool(after)==(args.expect=='preserved'),report
    if args.expect=='preserved':
        until=target.timestamp()+100
        shown=None
        while time.time()<until:
            shown=delivery(title)
            if shown:break
            time.sleep(3)
        report['delivered_epoch_ms']=shown
        report['delay_seconds']=None if shown is None else round(shown/1000-target.timestamp(),3)
        (OUT/'pending-refresh-preserved.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        print(json.dumps(report),flush=True)
        assert shown is not None,'Preserved alarm not delivered within this observation window'


if __name__=='__main__':main()
