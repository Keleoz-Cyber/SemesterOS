"""Bounded independent notice groups, prepared and applied in one DB transaction."""
from copy import deepcopy
from .academics import fingerprint
from .auth import error
from .models import OperationProposal, new_id


def children(preview):
    return [p for g in preview['groups'] for p in g['operations']]


def impact(db,user,s):
    from .schedule_api import snapshot
    from .capacity import calendar_context
    from .reminder_rules import utcnow
    from .plan_rules import classify
    data=snapshot(db,user,s)
    context=calendar_context(*data[:4],utcnow())
    _,issues=classify(data[4],data[3],context['free'].spans,context['begin'])
    # No simulated IDs escape the savepoint as actionable records.
    conflicts=[{k:c[k] for k in ('start_at','end_at','titles')} for c in context['conflicts']]
    return {'fixed_conflicts':conflicts,'affected_plan_count':len({i['block_id'] for i in issues})}


def guard_dependencies(db,user,s,previews):
    from .operations import dependencies
    from .exam_planning import owned_exam, exam_change_context
    from .exam_schemas import ExamChangeInput
    for p in previews:
        if p['kind']=='operation':
            row=db.get(OperationProposal,p['operation_id'])
            if row is None or row.user_id!=user.id or row.phase!='ready' or dependencies(db,user,row,s)!=row.payload['dependency']:
                error(409,'PREVIEW_STALE','事项或提醒已有变化，请重新核对通知')
        elif p['kind']=='exam_change':
            request=ExamChangeInput.model_validate({k:v for k,v in p['body'].items() if k in ExamChangeInput.model_fields})
            value=exam_change_context(db,user,owned_exam(db,user,p['target_id']),request)[3]
            if fingerprint({'agent_run_id':p['agent_run_id'],'exam_preview':value['preview_token']})!=p['body']['preview_token']:
                error(409,'PREVIEW_STALE','考试或复习安排已有变化，请重新核对')


def run_children(db,user,s,groups,base):
    from .agent_tools import apply_preview
    from .operations import dependencies
    results=[]
    for g in groups:
        receipts=[]
        for original in g['operations']:
            p=deepcopy(original);p['expected_revision']=s.revision
            if 'expected_revision' in p['body']:p['body']['expected_revision']=s.revision
            if p['kind']=='operation':
                row=db.get(OperationProposal,p['operation_id'])
                row.payload={**row.payload,'dependency':dependencies(db,user,row,s)}
            receipts.append(apply_preview(db,user,p,confirm_fixed_conflicts=True,prepared_base_revision=base))
            db.flush()
        results.append({'id':g['id'],'title':g['title'],'receipts':receipts})
    return results


def simulate(db,user,s,groups,base):
    transaction=db.begin_nested()
    try:
        run_children(db,user,s,groups,base)
        return impact(db,user,s)
    finally:
        transaction.rollback()


def prepare_batch(db,user,thread,s,state,args,source):
    from .agent_tools import execute_tool
    groups=[]; touched=set()
    for group in args.groups:
        previews=[]
        for operation in group.operations:
            local=deepcopy(state);local.pop('preview',None);local['cards']=[]
            execute_tool(operation.tool,operation.arguments.model_dump(mode='json',exclude_unset=True),db,user,thread,local,source)
            p=local['preview']
            targets={p['target_id']} if p.get('target_id') else set()
            if p['kind']=='course_change':targets.update(e['id'] for e in p['before'])
            if p['kind']=='exam_change':targets.update(r['id'] for r in p.get('reviews',[]))
            if touched&targets:error(422,'BATCH_TARGET_OVERLAP','同一事项在通知中出现了多次修改，请合并后再预览')
            touched.update(targets);previews.append(p)
        groups.append({'id':new_id(),'title':group.title,'operations':previews})
    all_previews=[p for g in groups for p in g['operations']]
    guard_dependencies(db,user,s,all_previews)
    summary=simulate(db,user,s,groups,s.revision)
    return {'kind':'batch','action':'batch','groups':groups,'impact':summary,'body':{},'source_text':source}


def selected_groups(preview,ids):
    if not ids or len(ids)!=len(set(ids)) or not set(ids).issubset({g['id'] for g in preview['groups']}):
        error(422,'CHOOSE_GROUPS','请至少选择一组要保存的安排')
    return [g for g in preview['groups'] if g['id'] in ids]


def apply_batch(db,user,s,preview,ids,confirm_fixed_conflicts):
    groups=selected_groups(preview,ids)
    guard_dependencies(db,user,s,[p for g in groups for p in g['operations']])
    summary=simulate(db,user,s,groups,preview['expected_revision'])
    if summary['fixed_conflicts'] and not confirm_fixed_conflicts:
        error(422,'CONFIRM_FIXED_CONFLICTS','这些安排存在时间冲突，请核对后勾选确认')
    results=run_children(db,user,s,groups,preview['expected_revision'])
    return {'semester_id':s.id,'revision':s.revision,'groups':results,'impact':summary}
