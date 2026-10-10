"""Fresh HTTP prerequisite/rejection samples, separate from original reports."""
import argparse
import json
from datetime import datetime
from pathlib import Path
import sys
import time

from backend_cases import Evidence, TZ, LOCAL_BASE, write_json

ROOT = next((parent for parent in Path(__file__).resolve().parents
    if (parent / "services/api/app").is_dir() and (parent / "apps/mobile/lib").is_dir()), None)
if ROOT is None:
    raise RuntimeError("Place this anonymous experiment script inside a SemesterOS checkout.")


def create_task(e, title, remaining_minutes=None, condition=None):
    body={'semester_id':e.sid,'kind':'task','title':title,'certainty':'formal',
        'time':{'precision':'exact','at':e.at(21)},'remaining_minutes':remaining_minutes,
        'start_policy':'unconfirmed','earliest_start_at':None,'splittable':False}
    if condition:body['details']={'conditions':[condition]}
    return e.request('POST','/items',body,expected=201)


def request_plan(e, task):
    return e.request('POST',e.path+'/plan-proposals',{'days':7,'lead_minutes':0,'chunk_minutes':30,
        'allow_partial':False,'tasks':[{'item_id':task['id']}],
        'window_start_at':e.at(19),'window_end_at':e.at(21)},expected=201)


def missing_remaining(e):
    e.setup(availability=('19:00','21:00'))
    task=create_task(e,'合成尚未估计耗时任务')
    e.expect(task['remaining_minutes'] is None,'ordinary task saves without remaining work estimate',task)
    before=e.revision()
    result=request_plan(e,task)
    e.expect(result['status']=='INPUT_INVALID' and not result['can_apply'] and not result['blocks'],
        'missing remaining estimate yields INPUT_INVALID/can_apply=false/no candidate blocks',result)
    e.request('POST','/plan-proposals/'+result['id']+'/accept',
        {'expected_version':result['version'],'expected_revision':result['base_revision']},expected=409)
    restored=e.request('GET','/items/'+task['id'])
    e.expect(restored['remaining_minutes'] is None and restored['version']==task['version'],
        'failed planning does not invent workload or change task version',restored)
    e.expect(e.revision()==before and not e.request('GET',e.path+'/plans')['blocks'],
        'failed planning/acceptance leaves business revision and formal plans unchanged')
    e.value['actual_summary']={'record_saved':True,'remaining_minutes':None,'plan_status':result['status'],
        'can_apply':result['can_apply'],'formal_block_count':0}


def unconfirmed_start(e):
    e.setup(availability=('19:00','21:00'))
    waiting=create_task(e,'合成等待审批任务',30,'收到审批结果后开始')
    e.expect(waiting['start_policy']=='unconfirmed' and waiting['earliest_start_at'] is None,
        'explicit waiting task saves unconfirmed start without invented timestamp',waiting)
    before=e.revision()
    result=request_plan(e,waiting)
    e.expect(result['status']=='INPUT_INVALID' and not result['can_apply'] and not result['blocks'],
        'explicit approval dependency remains unconfirmed and refuses scheduling',result)
    checked=e.request('GET','/items/'+waiting['id'])
    e.expect(checked['start_policy']=='unconfirmed' and checked['earliest_start_at'] is None and
        checked['details']['conditions']==['收到审批结果后开始'] and checked['remaining_minutes']==30,
        'failed scheduling preserves actual dependency, start state and work',checked)
    e.expect(e.revision()==before and not e.request('GET',e.path+'/plans')['blocks'],
        'unresolved dependency refusal writes no plans or business revision')
    # The current readiness policy treats an ordinary task with no stated waiting
    # condition as eligible now, while preserving its original stored fields.
    ordinary=create_task(e,'合成普通未确认开始任务',30)
    ordinary_before=e.revision()
    candidate=request_plan(e,ordinary)
    e.expect(candidate['status']=='FEASIBLE_COMPLETE' and candidate['can_apply'] and
        sum(b['minutes'] for b in candidate['blocks'])==30,
        'ordinary task without waiting condition can have a feasible 30-minute candidate',candidate)
    unchanged=e.request('GET','/items/'+ordinary['id'])
    e.expect(unchanged['start_policy']=='unconfirmed' and unchanged['earliest_start_at'] is None and
        unchanged['version']==ordinary['version'] and unchanged['remaining_minutes']==30,
        'candidate does not rewrite unconfirmed record into an asserted now/start timestamp',unchanged)
    e.expect(e.revision()==ordinary_before and not e.request('GET',e.path+'/plans')['blocks'],
        'ordinary candidate remains unsaved and does not alter business revision')
    e.value['actual_summary']={'waiting_condition':'收到审批结果后开始','waiting_plan_status':result['status'],
        'ordinary_unconfirmed_plan_status':candidate['status'],'ordinary_start_policy_after':'unconfirmed',
        'ordinary_earliest_start_after':None,'formal_block_count':0}


def reject_valid_agent_candidate(e):
    e.setup(availability=('19:00','21:00'))
    task=create_task(e,'合成可拒绝排程任务',30)
    before=e.revision()
    value=e.ask(f"请把合成可拒绝排程任务安排在{e.day:%Y年%m月%d日}19点到21点之间，完整30分钟，只生成候选，保持任务剩余工作不变。")
    e.expect(value['status']=='needs_confirmation' and value['preview']['kind']=='plan',
        'real agent creates legal plan candidate requiring confirmation',value)
    result=value['preview']['after']
    e.expect(result['status']=='FEASIBLE_COMPLETE' and result['can_apply'] and
        sum(b['minutes'] for b in result['blocks'])==30,
        'candidate is actually feasible and covers provided 30-minute work',result)
    e.expect(not e.request('GET',e.path+'/plans')['blocks'],'legal candidate has no formal blocks before choice')
    body={'decision':'reject','token':value['preview']['token']}
    url='/agent/runs/'+value['id']+'/decision'
    cancelled=e.request('POST',url,body)
    e.expect(cancelled['status']=='cancelled' and cancelled['receipt'] is None,
        'reject cancels candidate with no saved business receipt',cancelled)
    e.expect(e.request('POST',url,body)==cancelled,'duplicate reject is idempotent')
    e.request('POST',url,{'decision':'confirm','token':value['preview']['token']},expected=409)
    proposal=e.request('GET','/plan-proposals/'+value['preview']['target_id'])
    e.expect(proposal['phase']=='rejected' and not proposal['can_apply'],
        'underlying plan proposal becomes rejected and cannot apply',proposal)
    item=e.request('GET','/items/'+task['id'])
    e.expect(item['remaining_minutes']==30 and item['start_policy']=='unconfirmed' and item['earliest_start_at'] is None,
        'reject does not change remaining work or invent a start fact',item)
    e.expect(e.revision()==before and not e.request('GET',e.path+'/plans')['blocks'],
        'reject and stale confirm leave formal plans at zero and business revision unchanged')
    e.value['actual_summary']={'legal_candidate_minutes':30,'decision':'reject','run_status':cancelled['status'],
        'proposal_phase':proposal['phase'],'can_apply':False,'formal_block_count':0,'confirm_after_reject_http':409}


CASES=[
    ('prerequisite_missing_remaining',missing_remaining,'Can save task with null remaining; cannot create/apply a schedule by inventing work'),
    ('prerequisite_unconfirmed_start',unconfirmed_start,'Explicit approval dependency refuses plan; ordinary unconfirmed task may have a candidate without changing stored start facts'),
    ('prerequisite_reject_valid_candidate',reject_valid_agent_candidate,'Legal real-agent plan candidate can be rejected; no formal blocks, work changes or later stale confirmation'),
]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-local',action='store_true')
    parser.add_argument('--output',type=Path,default=ROOT/'output/verification/aic-20261009/backend')
    parser.add_argument('--database',type=Path)
    parser.add_argument('--model-name',default='deepseek-flash')
    parser.add_argument('--model-timeout',type=int,default=180)
    args=parser.parse_args()
    if not args.execute_local:
        print('No HTTP issued; requires --execute-local.')
        return
    report={'created_at':datetime.now(TZ).isoformat(),'source':'fresh local HTTP prerequisite/rejection samples',
        'base_url':LOCAL_BASE,'data':'random new synthetic accounts only','UI_tested':False,
        'boundaries':['Separate from original HTTP eight-case and UI nine-case reports',
            'Missing work estimate does not prevent recording but prevents schedule generation',
            'Unconfirmed ordinary tasks and explicitly waiting tasks are distinct under current readiness policy',
            'Reject tested via production agent decision HTTP API; no emulator interaction',
            'No human efficiency or general accuracy claims'],'cases':[]}
    for name,function,expected in CASES:
        e=Evidence(args,name,expected)
        try:
            function(e);e.value['passed']=True
        except Exception as exc:
            e.value['failure']={'type':type(exc).__name__,
                'message':str(exc) if isinstance(exc,(AssertionError,TimeoutError)) else 'inspect captured steps'}
        finally:e.close()
        e.value['seconds']=round(time.monotonic()-e.started,3)
        e.value['evidence_kind']='HTTP only, no UI interaction'
        write_json(args.output/(name+'.json'),e.value)
        report['cases'].append({k:v for k,v in e.value.items() if k not in ('steps','model_traces')})
        print(json.dumps({'case':name,'passed':e.value['passed'],'seconds':e.value['seconds'],
            'failure':e.value.get('failure')},ensure_ascii=True),flush=True)
        report['passed']=all(c['passed'] for c in report['cases'])
        report['finished_at']=datetime.now(TZ).isoformat()
        write_json(args.output/'prerequisites-report.json',report)
    if not report['passed']:sys.exit(1)


if __name__=='__main__':main()
