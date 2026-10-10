"""Read-only UI evidence assertions; no HTTP, device actions or original edits."""
import argparse
from datetime import datetime, timezone, timedelta
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

ROOT = next((parent for parent in Path(__file__).resolve().parents
    if (parent / "services/api/app").is_dir() and (parent / "apps/mobile/lib").is_dir()), None)
if ROOT is None:
    raise RuntimeError("Place this anonymous evidence verifier inside a SemesterOS checkout.")
TZ = timezone(timedelta(hours=8))


def at(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(TZ)


def clock(value):
    return at(value).strftime('%H:%M') if value else None


def entries(d):
    return d['calendar']['body']['entries']


def entry(d, title, kind):
    return next(e for e in entries(d) if e['title'] == title and e['resource_type'] == kind)


def blocks(d):
    return sorted(d['plans']['body']['blocks'], key=lambda b:b['id'])


def remaining(d):
    return {i['id']:i['remaining_minutes'] for i in d['items']['body']['items']}


def run(d):
    return d['runs'][0]


def state(d):
    return run(d)['state']


class Audit:
    def __init__(self, source):
        self.source=source
        self.report={'generated_at':datetime.now(TZ).isoformat(),'source_directory':str(source.resolve()),
            'method':'read-only emulator screen XML and same-account API/agent readbacks',
            'data':'synthetic','source_files':{},'checks':[],'cases':[],
            'boundaries':['No HTTP, device actions or original-file edits by verifier',
                'JSON proves candidate/stored state; XML proves visible screen semantics',
                'API retains leave course; hiding is client calendar projection',
                'No real-device/OEM delivery or human-efficiency conclusion']}

    def raw(self, filename):
        data=(self.source/filename).read_bytes()
        self.report['source_files'][filename]={'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}
        return data

    def load(self, filename):
        d=json.loads(self.raw(filename).decode('utf-8'))
        if filename!='scenario.json':
            for field in ('calendar','items','plans','courses'):
                self.check(d[field]['status']==200,'readbacks',field+' readback HTTP 200',[filename+':'+field+'.status'])
        return d

    def screen(self, filename):
        root=ET.fromstring(self.raw(filename))
        self.raw(str(Path(filename).with_suffix('.png')))
        return '\n'.join(v for n in root.iter() for k in ('text','content-desc') if (v:=n.attrib.get(k)))

    def check(self, ok, case, expected, sources, actual=None):
        self.report['checks'].append({'case':case,'expected':expected,'passed':bool(ok),'source_fields':sources,'actual':actual})

    def case(self, case, summary, kind='emulator screen + readback'):
        checks=[c for c in self.report['checks'] if c['case']==case]
        self.report['cases'].append({'case':case,'passed':bool(checks) and all(c['passed'] for c in checks),
            'check_count':len(checks),'summary':summary,'evidence_kind':kind})


def verify(a,args):
    files={'saved':'05-after-meeting-save.json','end':'08-known-meeting-end.json','location':'10-location-edited.json',
        'undo':'12-location-undo-readback.json','free':'13-free-query-readback.json','preview':'15-plan-before-confirm.json',
        'plan':'16-plan-applied.json','lock':'19-lock-state.json','new_preview':'20b-before-new-activity-save.json',
        'new':'21-new-activity-saved.json','replan_preview':'22-replan-before-confirm.json',
        'replan':args.replan_json,'refusal':args.refusal_json}
    scenario=a.load('scenario.json')
    d={k:a.load(f) for k,f in files.items()}
    xmlfiles={'selected':'04-selected-course-only.xml','saved':'05-event-and-leave-saved.xml',
        'projection':'06-leave-hidden-course-retained.xml','end':'07-end-time-correction-preview.xml',
        'undo_preview':'11-undo-location-preview.xml','undo':'12-location-undo-saved.xml',
        'settings':'14-learning-windows-19-21.xml','preview':'15-plan-preview.xml','plan':'16-plan-applied.xml',
        'lock':'19-plan-fixed.xml','replan_preview':'22-replan-preview.xml','replan_ready':'22b-replan-ready.xml',
        'replan':args.replan_xml,'refusal':args.refusal_xml}
    screen={k:a.screen(f) for k,f in xmlfiles.items()}
    def check(ok,case,expected,keys,actual=None):
        a.check(ok,case,expected,[files.get(k,xmlfiles.get(k,k)) for k in keys],actual)
    meeting=entry(d['saved'],'项目会议','event')
    ca=entry(d['saved'],'算法设计','course')
    cb=entry(d['saved'],'线性代数','course')
    eid=meeting['resource_id']
    case='start_only_meeting_and_selected_leave'
    p=state(d['saved'])['preview']
    impact=p['impact']
    check(clock(p['after']['time']['at'])=='09:15' and p['after']['time']['end_at'] is None,case,
        '09:15 start-only event preserves unknown end',['saved'],{'start':clock(meeting['start_at']),'end':meeting['end_at']})
    check([c['occurrence_id'] for c in impact['course_conflicts']]==[ca['id']] and
        all(c['evidence_kind']=='start_point' for c in impact['new_fixed_conflicts']),case,
        'only A occurrence conflicts; later B is not requested for leave',['saved'])
    receipt=state(d['saved'])['receipt']
    attendance=receipt['course_attendance']
    check(run(d['saved'])['status']=='applied' and len(attendance)==1 and
        attendance[0]['occurrence_id']==ca['id'] and attendance[0]['attendance_status']=='leave',case,
        'event and exactly selected occurrence leave share applied receipt',['saved'],attendance)
    check(ca['attendance_status']=='leave' and not ca['fixed'] and cb['attendance_status'] is None and cb['fixed'],case,
        'API source retains both courses; A occupancy exempted, B retained',['saved'])
    a.check('算法设计 · 我已请假' in screen['selected'] and '线性代数' not in screen['selected'] and
        '算法设计' not in screen['projection'] and '线性代数' in screen['projection'] and '项目会议' in screen['projection'],case,
        'UI selects only A and default calendar hides leave A while showing B and meeting',
        [xmlfiles['selected'],xmlfiles['projection']])
    a.check('已标记 1 次课程请假' in screen['saved'],case,'UI confirms one leave saved',[xmlfiles['saved']])
    a.case(case,{'start':'09:15','end':None,'leave':'算法设计','later_course':'线性代数',
        'API_source_retained':True,'client_projection_hides_leave':True})

    case='end_supplement_preserves_attendance'
    ended=entry(d['end'],'项目会议','event')
    check(ended['resource_id']==eid and clock(ended['start_at'])=='09:15' and clock(ended['end_at'])=='09:40',case,
        '09:40 correction updates same event, retaining start',['end'])
    check(entry(d['end'],'算法设计','course')['attendance_status']=='leave' and
        entry(d['end'],'线性代数','course')['attendance_status'] is None,case,'A leave and B attendance retained',['end'])
    a.check('09:40' in screen['end'] and '确认修改' in screen['end'],case,'UI shows explicit end correction',[xmlfiles['end']])
    a.case(case,{'same_event':True,'end':'09:40','leave_retained':True})

    case='location_edit_and_scoped_undo'
    edited=entry(d['location'],'项目会议','event');restored=entry(d['undo'],'项目会议','event')
    check(edited['resource_id']==restored['resource_id']==eid and edited['location']=='A302' and restored['location']=='A301',
        case,'same event changes location to A302, then restores A301',['location','undo'])
    check(at(edited['start_at'])==at(restored['start_at'])==at(ended['start_at']) and
        at(edited['end_at'])==at(restored['end_at'])==at(ended['end_at']) and
        entry(d['undo'],'算法设计','course')['attendance_status']=='leave' and
        entry(d['undo'],'线性代数','course')['attendance_status'] is None,case,
        'location undo preserves 09:15–09:40 and specific attendance states',['end','location','undo'])
    ur=state(d['undo'])['receipt']
    check(ur['undone'] and ur['source_run_id']==run(d['location'])['id'],case,'undo targets location edit run',['undo'])
    a.check('地点：A302 → A301' in screen['undo_preview'] and '确认撤销' in screen['undo_preview'] and
        '已撤销' in screen['undo'],case,'UI previews location-only scope and confirms undo',[xmlfiles['undo_preview'],xmlfiles['undo']])
    a.case(case,{'locations':['A301','A302','A301'],'end':'09:40','leave_preserved':True})

    case='ordinary_gap_vs_saved_study_window'
    fs=state(d['free']);w=next(c['data'] for c in fs['cards'] if c['kind']=='windows')
    check(run(d['free'])['status']=='completed' and not fs.get('preview') and w['scope']=='calendar' and
        any(clock(x['start_at'])=='12:00' and clock(x['end_at'])=='14:00' for x in w['windows']),case,
        'ordinary query returns 12:00–14:00 calendar gap without write preview',['free'])
    check(d['free']['calendar']['body']['revision']==d['undo']['calendar']['body']['revision'] and
        blocks(d['free'])==blocks(d['undo']),case,'ordinary query keeps business state unchanged',['free','undo'])
    a.check(all(x['start']=='19:00' and x['end']=='21:00' for x in scenario['learning_windows']) and
        '19:00—21:00' in screen['settings'] and '日程空档' in screen['plan'] and '12:00—14:00' in screen['plan'],case,
        'UI shows separate 19:00–21:00 study preference and 12:00–14:00 gap',
        ['scenario.json:learning_windows',xmlfiles['settings'],xmlfiles['plan']])
    a.case(case,{'ordinary_gap':'12:00–14:00','study_preference':'19:00–21:00','query_writes':False})

    case='candidate_then_plan_confirmation'
    candidate=state(d['preview'])['preview']['after']
    initial={i['id']:i['remaining_minutes'] for i in scenario['tasks']}
    formal=blocks(d['plan'])
    check(run(d['preview'])['status']=='needs_confirmation' and not blocks(d['preview']) and
        len(candidate['blocks'])==3 and all(b['minutes']==30 for b in candidate['blocks']),case,
        'candidate has three 30-minute blocks; formal blocks remain zero',['preview'])
    check(run(d['plan'])['status']=='applied' and len(formal)==3 and sum(b['minutes'] for b in formal)==90 and
        all(b['minutes']==30 for b in formal) and {b['id'] for b in formal}==set(state(d['plan'])['receipt']['block_ids']),case,
        'confirmation stores exactly three blocks and 90 minutes',['plan'])
    check(remaining(d['preview'])==remaining(d['plan'])==initial,case,'scheduling does not reduce remaining work',['preview','plan','scenario.json'])
    a.check('已保存学习安排' in screen['plan'],case,'UI shows saved-plan receipt',[xmlfiles['plan']])
    a.case(case,{'formal_before':0,'formal_after':3,'total_minutes':90,'remaining_minutes_each':30},
        'candidate JSON readback + confirmed UI receipt/readback')

    case='lock_preserves_plan_times'
    old=blocks(d['lock']);locked=[b for b in old if b['locked']]
    check(len(locked)==1 and locked[0]['title']=='完成实验报告' and clock(locked[0]['start_at'])=='19:00' and
        clock(locked[0]['end_at'])=='19:30',case,'only report block locked at 19:00–19:30',['lock'])
    check({(b['id'],b['start_at'],b['end_at'],b['minutes']) for b in old}==
        {(b['id'],b['start_at'],b['end_at'],b['minutes']) for b in formal},case,'lock preserves ids, times, work',['plan','lock'])
    a.check('已固定时间' in screen['lock'] and '19:00–19:30' in screen['lock'],case,'UI shows locked block detail',[xmlfiles['lock']])
    a.case(case,{'task':'完成实验报告','locked_time':'19:00–19:30'})

    case='new_reality_does_not_silently_replan'
    np=state(d['new_preview'])['preview'];activity=entry(d['new'],'项目讨论','event')
    check(run(d['new_preview'])['status']=='needs_confirmation' and clock(np['after']['time']['at'])=='19:30' and
        clock(np['after']['time']['end_at'])=='20:00' and not any(e['title']=='项目讨论' for e in entries(d['new_preview'])),
        case,'new 19:30–20:00 activity stays unsaved in preview',['new_preview'])
    check(run(d['new'])['status']=='applied' and clock(activity['start_at'])=='19:30' and
        clock(activity['end_at'])=='20:00' and activity['reserve_time'],case,'new fixed activity saved',['new'])
    check(blocks(d['new_preview'])==blocks(d['new'])==old,case,'activity preview and save keep original plans and lock unchanged',
        ['lock','new_preview','new'])
    probability=next(b for b in old if b['title']=='复习概率论')
    check(state(d['new'])['receipt']['affected_plan_ids']==[probability['id']],case,
        'only probability block is identified as affected',['new'])
    a.check('已添加 项目讨论' in screen['replan_preview'],case,
        'later UI screen shows saved activity receipt',[xmlfiles['replan_preview']])
    a.case(case,{'activity':'19:30–20:00','affected_task':'复习概率论','plans_unchanged':True},
        'emulator action followed by candidate/applied readback')

    case='minimal_replan_confirmation'
    rp=state(d['replan_preview'])['preview']['after']
    check(run(d['replan_preview'])['status']=='needs_confirmation' and blocks(d['replan_preview'])==blocks(d['new']),
        case,'replan candidate keeps saved blocks unchanged',['replan_preview','new'])
    check(rp['status']=='FEASIBLE_COMPLETE' and rp['optimal'] and rp['moved_tasks']==1 and rp['shift_minutes']==60,
        case,'optimal candidate moves one task by 60 minutes',['replan_preview'])
    a.check('1段计划将调整时间' in screen['replan_ready'] and '复习概率论' in screen['replan_ready'] and
        '19:30—20:00' in screen['replan_ready'] and '20:30—21:00' in screen['replan_ready'] and
        '确认调整' in screen['replan_ready'],case,'ready UI candidate shows one-block change and asks confirmation',[xmlfiles['replan_ready']])
    after=blocks(d['replan']);before={b['id']:b for b in old}
    check(run(d['replan'])['status']=='applied' and {b['id'] for b in after}==set(before) and
        sum(b['minutes'] for b in after)==90 and all(b['minutes']==30 for b in after),case,
        'confirmed replan keeps all ids and 90 minutes',['replan'])
    changed=[b for b in after if at(b['start_at'])!=at(before[b['id']]['start_at'])]
    check(len(changed)==1 and changed[0]['title']=='复习概率论' and clock(changed[0]['start_at'])=='20:30' and
        clock(changed[0]['end_at'])=='21:00',case,'only probability moves 19:30→20:30',['lock','replan'])
    target={b['id']:b for b in rp['blocks']}
    check(all(at(b['start_at'])==at(target[b['id']]['start_at']) and at(b['end_at'])==at(target[b['id']]['end_at'])
        and b['locked']==target[b['id']]['locked'] for b in after) and
        next(b for b in after if b['id']==locked[0]['id'])==locked[0],case,
        'confirmed times match candidate; locked block unchanged entirely',['replan_preview','replan'])
    check(remaining(d['replan'])==initial and not d['replan']['plans']['body']['invalid_blocks'],case,
        'remaining work retained and plan conflicts removed',['replan'])
    a.check(any(t in screen['replan'] for t in ('已保存','已调整','20:30')),case,'UI shows confirmed replan result',[xmlfiles['replan']])
    a.case(case,{'moved_task':'复习概率论','before':'19:30–20:00','after':'20:30–21:00',
        'moved_tasks':1,'shift_minutes':60,'work_minutes':90,'locked_retained':True})

    case='unsafe_undo_refused'
    text=screen['refusal']+'\n'+'\n'.join(str(x['state'].get('error',''))+'\n'+x['state'].get('answer','') for x in d['refusal']['runs'])
    for field in ('error','attempt','action','ui_error','undo_attempt'):
        if field in d['refusal']:text+='\n'+json.dumps(d['refusal'][field],ensure_ascii=False)
    a.check(any(t in text for t in ('不能恢复','不能撤销','无法撤销','不符合最新现实安排','旧计划',
        '恢复后会影响当前个人计划，请先核对或重新规划')),case,
        'UI/readback describes rejected restoration of conflicting old plan',[xmlfiles['refusal'],files['refusal']])
    check(blocks(d['refusal'])==after and d['refusal']['calendar']['body']['revision']==d['replan']['calendar']['body']['revision'],
        case,'refused undo leaves plan blocks and business revision unchanged',['refusal','replan'])
    retained=entry(d['refusal'],'项目讨论','event')
    check(retained['resource_id']==activity['resource_id'] and clock(retained['start_at'])=='19:30' and
        clock(retained['end_at'])=='20:00' and retained['reserve_time'],case,'conflicting reality remains after refusal',['refusal'])
    a.case(case,{'undo_refused':True,'plans_unchanged':True,'fixed_reality_retained':True,'http_status_claimed':None})
    a.report['capture_notes']=[{'file':xmlfiles[k],'actual_screen':'request still processing',
        'boundary':'candidate is proven by JSON readback; this screenshot does not yet show rendered candidate'}
        for k in ('preview','replan_preview') if '等待处理' in screen[k] and '停止' in screen[k]]
    a.report['summary']={'cases':len(a.report['cases']),'passed_cases':sum(c['passed'] for c in a.report['cases']),
        'assertions':len(a.report['checks']),
        'readback_assertions':sum(c['case']=='readbacks' for c in a.report['checks']),
        'behavior_assertions':sum(c['case']!='readbacks' for c in a.report['checks']),
        'all_assertions_passed':all(c['passed'] for c in a.report['checks'])}
    a.report['passed']=bool(a.report['cases']) and a.report['summary']['all_assertions_passed']


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,default=ROOT/'output/verification/aic-20261009/ui')
    p.add_argument('--output',type=Path,default=ROOT/'output/verification/aic-20261009/ui-report.json')
    for key in ('replan-json','replan-xml','refusal-json','refusal-xml'):p.add_argument('--'+key,required=True)
    args=p.parse_args()
    for filename in (args.replan_json,args.replan_xml,args.refusal_json,args.refusal_xml):
        if Path(filename).name!=filename:p.error('capture names must be plain files within source directory')
    a=Audit(args.source)
    try:verify(a,args)
    except Exception as exc:
        a.report['passed']=False
        a.report['verification_error']={'type':type(exc).__name__,'message':str(exc)}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(a.report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'passed':a.report.get('passed'),'summary':a.report.get('summary'),
        'failed_checks':[c for c in a.report['checks'] if not c['passed']],
        'verification_error':a.report.get('verification_error')},ensure_ascii=True))
    if not a.report.get('passed'):sys.exit(1)


if __name__=='__main__':main()
