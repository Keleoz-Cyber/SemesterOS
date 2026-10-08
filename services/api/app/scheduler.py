from datetime import datetime, timezone
from math import ceil, floor
import time

from ortools.sat.python import cp_model
from ortools import __version__ as solver_version
from .capacity import calendar_context, merge, subtract, uncertainty_affects_window, minute_free_spans
from .plan_rules import classify, future_minutes
from .reminder_rules import instant, anchor_at
from .task_readiness import start_policy


def chunks(minutes, size=45, splittable=True):
    if not minutes:return []
    if not splittable:return [minutes]
    result=[size]*(minutes//size)
    tail=minutes%size
    if tail:
        if size>15 and tail<15 and result:result[-1]+=tail
        else:result.append(tail)
    return result


def chunk_count(minutes,size,splittable):
    if not minutes:return 0
    if not splittable:return 1
    q,r=divmod(minutes,size)
    return q+(1 if r and (size<=15 or r>=15 or not q) else 0)


def stamp(n):return datetime.fromtimestamp(n*60,timezone.utc).isoformat()


def prepare(calendar, preferences, courses, items, plans, request, now):
    context=calendar_context(calendar,preferences,courses,items,now)
    start=request.get('_window_start',ceil(context['begin']/60)+request['lead_minutes'])
    end=request.get('_window_end',min(start+request['days']*1440,floor(context['semester_end']/60)))
    if request.get('window_start_at') and '_window_start' not in request:
        start=max(start,ceil(instant(request['window_start_at']).timestamp()/60))
        end=min(floor(instant(request['window_end_at']).timestamp()/60),floor(context['semester_end']/60))
    base={'window_start':stamp(start),'window_end':stamp(end),'blocks':[],'tasks':[],
          'status':'INPUT_INVALID','messages':[],'solver_status':None,'optimal':False,
          'unarranged_minutes':0,'can_apply':False,'existing_conflict_count':len(context['conflicts'])}
    base['uncertainty_warnings']=[w for w in context['uncertainty_warnings'] if uncertainty_affects_window(w,start*60,end*60)]
    base['messages']=[w['message'] for w in base['uncertainty_warnings']]
    if not preferences.get('configured'):base['messages']=['请先设置每周的学习时间'];return base,None
    if end<=start:base['messages']=['请选择本学期内尚未过去的时间'];return base,None
    future=[b for b in plans if b['status']=='active' and instant(b['end_at']).timestamp()>now.timestamp()]
    if len(request['tasks'])>100 or len(future)>300:
        base.update(status='INPUT_LIMIT',messages=['一次最多安排100项任务、300段计划，请分批安排']);return base,None
    valid,issues=classify(plans,items,context['free'].spans,context['begin'],
                          obligation_points=context['obligation_points'])
    if issues:
        base.update(messages=['已有计划不符合当前安排，请核对、取消或在后续重排中处理'],invalid_blocks=issues);return base,None
    by_id={i['id']:i for i in items};selected=[]
    for choice in request['tasks']:
        item=by_id.get(choice['item_id'])
        if not item or item['kind']=='exam' or item['lifecycle']!='active' or item.get('remaining_minutes') is None or start_policy(item)=='unconfirmed':
            base['messages']=['请选择尚未完成的任务，并填写还需要多久、最早何时能开始'];return base,None
        remaining=item['remaining_minutes'];own=[b for b in valid if b['item_id']==item['id']]
        existing=sum(future_minutes(b,now.timestamp(),start*60,end*60) for b in own)
        total_existing=sum(future_minutes(b,now.timestamp()) for b in own)
        outside=total_existing-existing
        if total_existing>remaining:
            base['messages']=['已有计划的时长超过了任务剩余所需时间，请先更新进度并选择要取消的计划'];return base,None
        due=anchor_at(item) if item.get('certainty')=='formal' else None
        within=due is not None and due.timestamp()<=end*60
        target=choice.get('target_minutes')
        if within:
            required=remaining-outside
            if target is not None and target!=required:
                base['messages']=['这项任务在所选日期内到期，请安排全部剩余工作；已排在其他日期的部分会自动扣除'];return base,None
            target=required
        elif target is None:
            target=remaining-outside
        if target<existing or target>remaining-outside or target<=0:
            base['messages']=['安排目标需包含这段时间内已有的计划，并且不能超过任务还需要的时间'];return base,None
        if not item.get('splittable',True) and (target!=remaining-outside or (total_existing and target>existing)):
            base['messages']=['这项任务需要一次完成，请先取消已有的分段计划，再重新安排'];return base,None
        release=max(start,ceil(instant(item['earliest_start_at']).timestamp()/60)) if item.get('start_policy')=='at' else start
        deadline=min(end,floor(due.timestamp()/60)) if due else end
        selected.append({'item':item,'release':release,'deadline':deadline,'need':target-existing,
                         'target':target,'existing':existing,'outside':outside})
    if not selected:base['messages']=['请选择至少一项任务'];return base,None
    busy=merge([(max(context['begin'],instant(b['start_at']).timestamp()),instant(b['end_at']).timestamp()) for b in valid])
    free=subtract(context['free'].spans,busy)
    free=[(max(start,a),min(end,b)) for a,b in minute_free_spans(free,context['obligation_points'])]
    free=merge(free)
    if len(future)+sum(chunk_count(s['need'],request['chunk_minutes'],s['item'].get('splittable',True)) for s in selected)>300:
        base.update(status='INPUT_LIMIT',messages=['计划段数超过300，请缩短安排的日期范围，或增加单次学习时长']);return base,None
    blocks=[]
    for selected_task in selected:
        for length in chunks(selected_task['need'],request['chunk_minutes'],selected_task['item'].get('splittable',True)):
            domains=merge([(max(a,selected_task['release']),min(b,selected_task['deadline'])-length+1) for a,b in free])
            domains=[(a,b-1) for a,b in domains]
            blocks.append({'task':selected_task,'minutes':length,'domains':domains})
    if len(blocks)+len(future)>300:
        base.update(status='INPUT_LIMIT',messages=['计划段数超过300，请缩短安排的日期范围，或增加单次学习时长']);return base,None
    base['tasks']=[{'item_id':s['item']['id'],'title':s['item']['title'],'remaining_minutes':s['item']['remaining_minutes'],
        'target_minutes':s['target'],'existing_minutes':s['existing'],'outside_minutes':s['outside'],
        'new_minutes':0,'unarranged_minutes':s['need'],'later_minutes':s['item']['remaining_minutes']-s['outside']-s['target']} for s in selected]
    base['solver_version']=solver_version
    return base,{'selected':selected,'blocks':blocks,'free':free,'preserved':valid,'start':start,'end':end,
                 'obligation_points':context['obligation_points']}


def validate_result(context, result, allow_partial):
    rows={r['item_id']:r for r in result['tasks']};counts={id:0 for id in rows};spans=[]
    selected={s['item']['id']:s for s in context['selected']}
    lengths={id:[b['minutes'] for b in context['blocks'] if b['task']['item']['id']==id] for id in rows}
    for block in result['blocks']:
        task=selected.get(block['item_id']);a=instant(block['start_at']).timestamp()/60;b=instant(block['end_at']).timestamp()/60
        if not task or not a.is_integer() or not b.is_integer() or b-a!=block['minutes'] or b<=a:return False
        if a<task['release'] or b>task['deadline'] or not any(x<=a and b<=y for x,y in context['free']):return False
        if any(a*60<=point<b*60 for point in context.get('obligation_points',[])):return False
        if block['minutes'] not in lengths[block['item_id']]:return False
        lengths[block['item_id']].remove(block['minutes'])
        spans.append((a,b));counts[block['item_id']]+=block['minutes']
    spans.sort()
    if any(b>c for (_,b),(c,_) in zip(spans,spans[1:])):return False
    for id,row in rows.items():
        current=selected[id];need=current['need']
        expected={'target_minutes':current['target'],'existing_minutes':current['existing'],'outside_minutes':current['outside'],
                  'later_minutes':current['item']['remaining_minutes']-current['outside']-current['target']}
        if any(row.get(k)!=value for k,value in expected.items()):return False
        if row.get('new_minutes')!=counts[id] or row.get('unarranged_minutes')!=need-counts[id]:return False
        if counts[id]>need or (not allow_partial and counts[id]!=need):return False
        if not selected[id]['item'].get('splittable',True) and counts[id] not in (0,need):return False
    return result.get('unarranged_minutes')==sum(s['need']-counts[id] for id,s in selected.items())


def generate(calendar, preferences, courses, items, plans, request, now):
    started=time.monotonic()
    result,context=prepare(calendar,preferences,courses,items,plans,request,now)
    if context is None:return result
    optional=request['allow_partial'];specs=context['blocks'];total=sum(b['minutes'] for b in specs)
    if not specs:
        result.update(status='FEASIBLE_COMPLETE',optimal=True,solver_status='NOT_NEEDED')
        selected_ids={s['item']['id'] for s in context['selected']}
        clocks=[max(floor(now.timestamp()/60)+1,floor(instant(b['start_at']).timestamp()/60)) for b in context['preserved'] if b['item_id'] in selected_ids]
        result['valid_until']=stamp(min(clocks or [context['end']]))
        return result
    capacity=sum(b-a for a,b in context['free'])
    impossible_unsplit=any(not s['item'].get('splittable',True) and s['need'] and max([0]+[max(0,min(b,s['deadline'])-max(a,s['release'])) for a,b in context['free']])<s['need'] for s in context['selected'])
    if not optional and (total>capacity or impossible_unsplit):
        result.update(status='INFEASIBLE',messages=['可用总时间不足，或不可拆分任务缺少足够长的连续空档'],unarranged_minutes=total);return result
    model=cp_model.CpModel();intervals=[];variables=[];earned=[];early=[]
    for index,spec in enumerate(specs):
        present=model.new_bool_var(f'present_{index}')
        domains=spec['domains']
        if not domains:
            if not optional:
                result.update(status='CHUNKING_LIMITED',messages=['目前没有足够长的空闲时段，请缩短单次学习时长后重试'],unarranged_minutes=total);return result
            model.add(present==0);domains=[(context['start'],context['start'])]
        if not optional:model.add(present==1)
        start=model.new_int_var_from_domain(cp_model.Domain.from_intervals(domains),f'start_{index}')
        end=model.new_int_var(context['start'],context['end']+spec['minutes'],f'end_{index}')
        interval=model.new_optional_interval_var(start,spec['minutes'],end,present,f'interval_{index}')
        intervals.append(interval);variables.append((present,start,end,spec))
        t=spec['task']
        available=sum(max(0,min(b,t['deadline'])-max(a,t['release'])) for a,b in context['free'])
        tight=available-t['need']<max(30,.2*t['need'])
        priority=(10 if tight else 1)*{'high':3,'normal':2,'low':1}.get(t['item'].get('priority'),2)
        earned.append(present*spec['minutes']*priority)
        score=model.new_int_var(0,context['end']-context['start']+spec['minutes'],f'early_{index}')
        model.add(score==end-context['start']).only_enforce_if(present);model.add(score==0).only_enforce_if(present.Not())
        early.append(score*priority)
    model.add_no_overlap(intervals)
    if optional:model.maximize(sum(earned))
    else:model.minimize(sum(early))
    solver=cp_model.CpSolver();solver.parameters.max_time_in_seconds=max(.01,10-(time.monotonic()-started));solver.parameters.num_search_workers=4
    status=solver.solve(model)
    reported_status=status
    phases=[{'status':solver.status_name(status),'objective':solver.objective_value,'bound':solver.best_objective_bound}]
    if optional and status==cp_model.OPTIMAL and time.monotonic()-started<9:
        model.add(sum(earned)==round(solver.objective_value));model.minimize(sum(early))
        solver.parameters.max_time_in_seconds=max(.01,10-(time.monotonic()-started))
        # Keep the first feasible solution if tie-breaking times out.
        first=[(solver.value(p),solver.value(s),spec) for p,s,_,spec in variables]
        next_status=solver.solve(model)
        reported_status=next_status
        phases.append({'status':solver.status_name(next_status),'objective':solver.objective_value,'bound':solver.best_objective_bound})
        values=[(solver.value(p),solver.value(s),spec) for p,s,_,spec in variables] if next_status in (cp_model.FEASIBLE,cp_model.OPTIMAL) else first
        optimal=next_status==cp_model.OPTIMAL
    elif status in (cp_model.FEASIBLE,cp_model.OPTIMAL):
        values=[(solver.value(p),solver.value(s),spec) for p,s,_,spec in variables];optimal=status==cp_model.OPTIMAL
    else:
        result.update(status='CHUNKING_LIMITED' if status==cp_model.INFEASIBLE else 'TIMEOUT',solver_status=solver.status_name(status),
            messages=['按目前的学习时间和任务要求，暂时无法安排全部任务' if status==cp_model.INFEASIBLE else '暂时没算出合适的方案，请减少任务数量后重试'],unarranged_minutes=total);return result
    result['blocks']=[{'item_id':s['task']['item']['id'],'title':s['task']['item']['title'],'start_at':stamp(a),'end_at':stamp(a+s['minutes']),
        'minutes':s['minutes']} for present,a,s in values if present]
    result['blocks'].sort(key=lambda b:(b['start_at'],b['item_id']))
    selected_ids={s['item']['id'] for s in context['selected']}
    clocks=[floor(instant(b['start_at']).timestamp()/60) for b in result['blocks']]
    clocks += [max(floor(now.timestamp()/60)+1,floor(instant(b['start_at']).timestamp()/60)) for b in context['preserved'] if b['item_id'] in selected_ids]
    result['valid_until']=stamp(min(clocks or [context['end']]))
    for task in result['tasks']:
        task['new_minutes']=sum(b['minutes'] for b in result['blocks'] if b['item_id']==task['item_id'])
        task['unarranged_minutes']=task['target_minutes']-task['existing_minutes']-task['new_minutes']
    missing=sum(t['unarranged_minutes'] for t in result['tasks'])
    result.update(status='FEASIBLE_PARTIAL' if missing else 'FEASIBLE_COMPLETE',unarranged_minutes=missing,
        can_apply=bool(result['blocks']),solver_status=solver.status_name(reported_status),optimal=optimal,phases=phases,
        elapsed_ms=round((time.monotonic()-started)*1000),messages=['保留已有计划，只为尚未安排的工作补充时间']+
        [w['message'] for w in result['uncertainty_warnings']])
    if not validate_result(context,result,optional):
        result.update(status='INPUT_INVALID',blocks=[],can_apply=False,messages=['这份方案还有时间冲突，尚未保存，请重新生成'])
    return result
