"""Lexicographic reallocation of all existing future blocks; no work is dropped."""
from math import ceil,floor
from copy import deepcopy
import time
from ortools.sat.python import cp_model
from ortools import __version__
from .capacity import calendar_context,merge
from .plan_rules import classify,future_minutes
from .reminder_rules import instant,anchor_at
from .scheduler import stamp


def prepare(calendar,preferences,courses,items,plans,request,now):
    context=calendar_context(calendar,preferences,courses,items,now)
    begin=ceil(now.timestamp()/60)+request.get('lead_minutes',5);end=floor(context['semester_end']/60)
    base={'mode':'replan','status':'INPUT_INVALID','can_apply':False,'blocks':[],'tasks':[],'messages':[],
        'window_start':stamp(ceil(now.timestamp()/60)),'window_end':stamp(end),'optimal':False,'unarranged_minutes':0,
        'existing_conflict_count':len(context['conflicts']),'solver_version':__version__}
    future=[deepcopy(b) for b in plans if b['status']=='active' and instant(b['end_at'])>now]
    if not preferences.get('configured') or not future:
        base['messages']=['先确认学习时间并建立个人计划，再进行重排'];return base,None
    if len(future)>300 or len({b['item_id'] for b in future})>100:
        base.update(status='INPUT_LIMIT',messages=['一次最多调整100项任务、300段计划，请减少任务数量']);return base,None
    if any(missing and a<end*60 and b>now.timestamp() for a,b,missing,_ in context['uncertain']):
        base['messages']=['需预留的固定安排缺少完整时间，请先核对'];return base,None
    tasks={i['id']:i for i in items}
    _,issues=classify(future,items,context['free'].spans,context['begin'])
    bad={i['block_id']:i for i in issues}
    specs=[];locked=[]
    for b in future:
        item=tasks.get(b['item_id']);original=instant(b['start_at']).timestamp()/60
        fixed=b['locked'] or original<begin or (request.get('task_ids') is not None and b['item_id'] not in request['task_ids'])
        if fixed and any(r!='plan_overlap' for r in bad.get(b['id'],{}).get('reason_codes',[])):locked.append(b)
        invalid=[r for r in bad.get(b['id'],{}).get('reason_codes',[]) if r not in ('outside_free_time','after_deadline','before_release','plan_overlap')]
        if not item or invalid or not original.is_integer():
            base['messages']=['计划关联任务或时长信息无效，请先核对'];return base,None
        release=max(begin,ceil(instant(item['earliest_start_at']).timestamp()/60)) if item.get('start_policy')=='at' else begin
        due=anchor_at(item) if item.get('certainty')=='formal' else None
        deadline=min(end,floor(due.timestamp()/60)) if due else end
        domains=[(int(original),int(original))] if fixed else [(a,z-1) for a,z in merge([
            (max(release,ceil(a/60)),min(deadline,floor(z/60))-b['minutes']+1) for a,z in context['free'].spans])]
        specs.append({'before':b,'fixed':fixed,'original':int(original),'domains':domains})
    if locked:
        base.update(locked_conflicts=locked,messages=['锁定、已开始、即将开始或未选中的计划与现实安排冲突，请明确处理或调整范围后再重排']);return base,None
    for id in {b['item_id'] for b in future}:
        item=tasks[id];coverage=sum(future_minutes(b,now.timestamp()) for b in future if b['item_id']==id)
        if item.get('remaining_minutes') is None or coverage>item['remaining_minutes']:
            base['messages']=['任务进度尚未确认，或已安排的时长过多，请先更新进度'];return base,None
    base['valid_until']=stamp(min(max(floor(now.timestamp()/60)+1,s['original']) for s in specs))
    return base,{'specs':specs,'calendar':calendar,'preferences':preferences,'courses':courses,'items':items,'now':now}


def validate(context,blocks):
    expected={s['before']['id']:s for s in context['specs']}
    if len(blocks)!=len(expected) or {b['id'] for b in blocks}!=set(expected):return False
    for b in blocks:
        spec=expected[b['id']];old=spec['before'];a=instant(b['start_at']).timestamp()/60;z=instant(b['end_at']).timestamp()/60
        if any(b.get(k)!=old[k] for k in ('item_id','minutes','locked','version','status')):return False
        if not a.is_integer() or z-a!=old['minutes'] or not any(x<=a<=y for x,y in spec['domains']):return False
    c=calendar_context(context['calendar'],context['preferences'],context['courses'],context['items'],context['now'])
    _,issues=classify(blocks,context['items'],c['free'].spans,c['begin'])
    return not issues


def generate(calendar,preferences,courses,items,plans,request,now):
    started=time.monotonic();base,context=prepare(calendar,preferences,courses,items,plans,request,now)
    if context is None:return base
    specs=context['specs']
    if any(not s['domains'] for s in specs):
        base.update(status='INFEASIBLE',messages=['现有学习时段放不下这些计划，原计划已保留。请检查学习时间、任务截止，或调整分段时长']);return base
    model=cp_model.CpModel();variables=[];intervals=[];moves={};offsets=[]
    span=ceil((instant(base['window_end'])-now).total_seconds()/60)+525600
    for index,spec in enumerate(specs):
        b=spec['before'];start=model.new_int_var_from_domain(cp_model.Domain.from_intervals(spec['domains']),f's{index}')
        intervals.append(model.new_fixed_size_interval_var(start,b['minutes'],f'b{index}'))
        moved=model.new_bool_var(f'm{index}');model.add(start!=spec['original']).only_enforce_if(moved);model.add(start==spec['original']).only_enforce_if(moved.Not())
        delta=model.new_int_var(0,span,f'd{index}');model.add_abs_equality(delta,start-spec['original'])
        moves.setdefault(b['item_id'],[]).append(moved);offsets.append(delta);variables.append(start)
    model.add_no_overlap(intervals);task_moves=[]
    for id,flags in moves.items():
        flag=model.new_bool_var('task'+id);model.add_max_equality(flag,flags);task_moves.append(flag)
    objectives=[('moved_tasks',sum(task_moves)),('shift_minutes',sum(offsets)),('earlier',sum(variables))]
    phases=[];values=None;optimal=False
    for name,objective in objectives:
        budget=10-(time.monotonic()-started)
        if budget<=0:break
        model.minimize(objective);solver=cp_model.CpSolver();solver.parameters.max_time_in_seconds=budget;solver.parameters.num_search_workers=4
        status=solver.solve(model);phases.append({'name':name,'status':solver.status_name(status),'objective':solver.objective_value,'bound':solver.best_objective_bound})
        if status not in (cp_model.FEASIBLE,cp_model.OPTIMAL):
            if values is None:base.update(status='INFEASIBLE' if status==cp_model.INFEASIBLE else 'TIMEOUT',phases=phases,messages=['本次未得到完整重排方案，原计划保持']);return base
            break
        values=[solver.value(v) for v in variables]
        if status!=cp_model.OPTIMAL:break
        model.add(objective==round(solver.objective_value))
        if name=='earlier':optimal=True
    if values is None:base.update(status='TIMEOUT',messages=['重排超时，原计划保持']);return base
    blocks=[{**s['before'],'start_at':stamp(a),'end_at':stamp(a+s['before']['minutes']),
        'before_start_at':s['before']['start_at'],'before_end_at':s['before']['end_at']} for a,s in zip(values,specs)]
    moved=[b for b in blocks if instant(b['start_at'])!=instant(b['before_start_at'])]
    if not validate(context,blocks):base['messages']=['调整后的计划还有冲突，原计划已保留，请重新生成'];return base
    base.update(status='FEASIBLE_COMPLETE',can_apply=bool(moved),blocks=blocks,moved_tasks=len({b['item_id'] for b in moved}),
        moved_blocks=len(moved),shift_minutes=sum(abs(a-s['original']) for a,s in zip(values,specs)),optimal=optimal,
        phases=phases,solver_status=phases[-1]['status'],elapsed_ms=round((time.monotonic()-started)*1000),
        messages=['已检查本学期的后续个人计划，只调整允许移动的部分。'])
    base['valid_until']=stamp(min([floor(instant(base['valid_until']).timestamp()/60)]+[a for a,s in zip(values,specs) if not s['fixed']]))
    return base
