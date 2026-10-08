"""Internal business snapshots and conservative, transaction-owned agent undo.

Snapshots are server state only. Public previews expose a summary, never these
payloads. New resources retain their identity/history and are cancelled/disabled.
"""
from copy import deepcopy

from sqlalchemy import select

from .academics import owned_semester, fingerprint
from .auth import error
from .models import (AgentRun, AgentThread, CalendarEvent, CourseMeeting, PlanBlock,
    PlanProposal, ProgressEntry, RealityChange, ReminderRule, StudyItem)
from .reminder_rules import instant, utcnow, SHANGHAI

MODELS = {'items': StudyItem, 'events': CalendarEvent, 'reminders': ReminderRule,
    'plans': PlanBlock, 'progress': ProgressEntry, 'reality': RealityChange, 'proposals': PlanProposal}


def row_value(row):
    return deepcopy({c.name: getattr(row, c.name) for c in row.__table__.columns})


def capture(db, user, sid):
    """Capture under the semester lock; the caller owns commit/rollback."""
    s = owned_semester(db, user, sid, lock=True)
    db.refresh(s)
    db.flush()
    entities = {}
    for name, model in MODELS.items():
        query = select(model).where(model.user_id == user.id)
        if name in ('reminders', 'progress'):
            query = query.join(StudyItem, model.item_id == StudyItem.id).where(
                StudyItem.semester_id == sid, StudyItem.user_id == user.id)
        else:
            query = query.where(model.semester_id == sid)
        if name == 'reality':
            query = query.where(RealityChange.applied_revision.is_not(None))
        if name == 'proposals':
            query = query.where(PlanProposal.phase == 'applied')
        entities[name] = {r.id: row_value(r) for r in db.scalars(query.order_by(model.id)
            .execution_options(populate_existing=True))}
    courses = {r.id: row_value(r) for r in db.scalars(select(CourseMeeting).where(
        CourseMeeting.user_id == user.id, CourseMeeting.semester_id == sid))}
    return {'owner_id': user.id, 'semester_id': sid, 'revision': s.revision, 'entities': entities,
        'calendar': {'first_monday': s.first_monday, 'total_weeks': s.total_weeks, 'periods': deepcopy(s.periods)},
        'courses': courses}


def changes(before, after):
    """Return only server-owned undo material, or None for no supported change."""
    if (before['owner_id'], before['semester_id']) != (after['owner_id'], after['semester_id']):
        raise ValueError('undo snapshots must have the same owner and semester')
    if before['calendar'] != after['calendar'] or before['courses'] != after['courses']:
        return None  # Imports and semester setup are not agent undo operations.
    entries = []
    for table in MODELS:
        old, new = before['entities'][table], after['entities'][table]
        for rid in sorted(set(old) | set(new)):
            if old.get(rid) != new.get(rid):
                if rid not in new:
                    return None  # Do not recreate deleted identities or old proposals.
                if table == 'progress' and rid in old:
                    return None  # Historic progress is immutable except undo markers.
                entries.append({'table': table, 'id': rid, 'before': old.get(rid), 'after': new[rid]})
    if not entries:
        return None
    return {'version': 1, 'owner_id': after['owner_id'], 'semester_id': after['semester_id'],
        'entries': entries, 'baseline': after}


def source_run(db, user, sid, rid, lock=False):
    query = select(AgentRun).join(AgentThread, AgentRun.thread_id == AgentThread.id).where(
        AgentRun.id == rid, AgentRun.user_id == user.id, AgentThread.user_id == user.id,
        AgentThread.semester_id == sid)
    if lock:
        query = query.with_for_update(of=AgentRun)
    row = db.scalar(query.execution_options(populate_existing=True))
    if row is None:
        error(404, 'NOT_FOUND', '找不到本学期的这次操作')
    return row


def undo_data(row, user, sid):
    data = row.state.get('undo_data')
    if row.status != 'applied' or (row.state.get('preview') or {}).get('kind') == 'undo' or not data:
        error(409, 'UNDO_UNAVAILABLE', '这次旧操作没有可核验的撤销记录，请手动修改相关安排')
    if data.get('version') != 1 or data.get('owner_id') != user.id or data.get('semester_id') != sid:
        error(409, 'UNDO_UNAVAILABLE', '撤销记录与当前账号或学期不一致')
    if row.state.get('undone_by'):
        error(409, 'ALREADY_UNDONE', '这次操作已经撤销')
    return data


def scope(data):
    item_ids, course_ids, occurrence_ids = set(), set(), set()
    for entry in data['entries']:
        for value in (entry['before'], entry['after']):
            if value is None:
                continue
            if entry['table'] == 'items':
                item_ids.add(value['id'])
                if value['payload'].get('review_exam_id'):
                    item_ids.add(value['payload']['review_exam_id'])
                if value['payload'].get('course_id'):
                    course_ids.add(value['payload']['course_id'])
            if entry['table'] in ('reminders', 'progress', 'plans'):
                item_ids.add(value['item_id'])
            if entry['table'] == 'reality':
                for occurrence in value['payload']['patch']['before'] + value['payload']['patch']['after']:
                    occurrence_ids.add(occurrence['id'])
                    if occurrence.get('course_id'):
                        course_ids.add(occurrence['course_id'])
    return item_ids, course_ids, occurrence_ids


def dependencies(snapshot, item_ids, course_ids, occurrence_ids):
    entities = snapshot['entities']
    result = {'items': {rid: value for rid, value in entities['items'].items()
        if rid in item_ids or value['payload'].get('review_exam_id') in item_ids}}
    for table in ('reminders', 'progress', 'plans'):
        result[table] = {rid: value for rid, value in entities[table].items() if value['item_id'] in item_ids}
    result['courses'] = {rid: value for rid, value in snapshot['courses'].items() if rid in course_ids}
    result['reality'] = {rid: value for rid, value in entities['reality'].items() if occurrence_ids.intersection(
        e['id'] for e in value['payload']['patch']['before'] + value['payload']['patch']['after'])}
    return result


def validate(db, user, s, data, current):
    for entry in data['entries']:
        if current['entities'][entry['table']].get(entry['id']) != entry['after']:
            error(409, 'UNDO_STALE', '相关记录已被后续操作修改，不能覆盖这些变化')
    if current['calendar'] != data['baseline']['calendar']:
        error(409, 'UNDO_STALE', '学期时间设置已经变化，请手动核对')
    selected = scope(data)
    if dependencies(current, *selected) != dependencies(data['baseline'], *selected):
        error(409, 'UNDO_DEPENDENCY_CHANGED', '相关提醒、进度、复习、课次或计划已有后续变化，不能整批撤销')
    now = utcnow()
    for entry in data['entries']:
        if entry['table'] == 'plans':
            if entry['after']['locked'] or any(instant(v['start_at']) <= now for v in
                    (entry['before'], entry['after']) if v and v['status'] == 'active'):
                error(409, 'UNDO_BLOCK_CHANGED', '相关计划已开始或已锁定，请逐项核对')
    validate_restore(db, user, s, data)


def restored_snapshot(db, user, s, data):
    from .schedule_api import snapshot
    from .occurrences import apply_patch, expand
    source = list(deepcopy(snapshot(db, user, s)))
    for entry in reversed(data['entries']):
        table, before, after = entry['table'], entry['before'], entry['after']
        if table in ('items', 'events'):
            rows = source[3] if table == 'items' else source[0]['fixed_events']
            rows[:] = [r for r in rows if r['id'] != entry['id']]
            if before is not None and (table == 'items' or before['lifecycle'] == 'active'):
                rows.append({**deepcopy(before['payload']), 'id': before['id'],
                    'version': after['version'] + 1, 'lifecycle': before['lifecycle']})
        if table == 'plans':
            source[4] = [r for r in source[4] if r['id'] != entry['id']]
            if before is not None and before['status'] == 'active':
                source[4].append(deepcopy(before))
        if table == 'reality':
            patch = after['payload']['patch']
            source[2] = [{'occurrences': apply_patch(expand(source[0], source[2]),
                {'before': patch['after'], 'after': patch['before']})}]
    return source


def validate_restore(db, user, s, data):
    """A reverse operation must not silently invalidate later plans/fixed facts."""
    from .schedule_api import snapshot
    from .capacity import calendar_context
    from .plan_rules import classify
    current = snapshot(db, user, s)
    restored = restored_snapshot(db, user, s, data)
    before_context = calendar_context(*current[:4], utcnow())
    after_context = calendar_context(*restored[:4], utcnow())
    _, before_issues = classify(current[4], current[3], before_context['free'].spans, before_context['begin'])
    _, after_issues = classify(restored[4], restored[3], after_context['free'].spans, after_context['begin'])
    if {fingerprint(i) for i in after_issues} - {fingerprint(i) for i in before_issues}:
        error(409, 'UNDO_REALITY_CONFLICT', '恢复后会影响当前个人计划，请先核对或重新规划')
    from .conflict_changes import introduced_conflicts
    if introduced_conflicts(before_context['conflicts'], after_context['conflicts']):
        error(409, 'UNDO_FIXED_CONFLICT', '恢复后与当前固定安排冲突，请先核对这些安排')


def summary(data):
    result = []
    for entry in data['entries']:
        table, before, after = entry['table'], entry['before'], entry['after']
        if table in ('items', 'events'):
            detail = '取消这次新增，保留来源与历史记录'
            if before is not None:
                labels = {'title': '标题', 'remaining_minutes': '剩余分钟', 'location': '地点', 'notes': '备注'}
                fields = [f"{label}：{field_label(after['payload'].get(key))} → {field_label(before['payload'].get(key))}"
                    for key, label in labels.items() if before['payload'].get(key) != after['payload'].get(key)]
                if before['payload'].get('time') != after['payload'].get('time'):
                    fields.append(f"时间：{time_label(after['payload'].get('time'))} → {time_label(before['payload'].get('time'))}")
                if before['lifecycle'] != after['lifecycle']:
                    lifecycle = {'active': '进行中', 'cancelled': '已取消', 'completed': '已完成'}
                    fields.append('状态恢复为' + lifecycle.get(before['lifecycle'], '修改前状态'))
                detail = '；'.join(fields) or '恢复本次修改前的内容，保留后续审计记录'
            result.append({'title': after['payload']['title'], 'detail':
                detail})
        elif table == 'reminders':
            item=data['baseline']['entities']['items'].get(after['item_id'],{})
            title=item.get('payload',{}).get('title','事项')+'的提醒'
            result.append({'title': title, 'detail': '停用本次新增提醒：'+reminder_label(after['payload']) if before is None
                           else reminder_label(after['payload'])+' → '+reminder_label(before['payload'])})
        elif table == 'progress':
            result.append({'title': '本次进度', 'detail': '标记撤销并从投入统计排除，保留原记录'})
        elif table == 'reality':
            patch = after['payload']['patch']
            restored = '、'.join(local_stamp(e['start_at']) + ' 至 ' + local_stamp(e['end_at']) for e in patch['before'])
            result.append({'title': after['payload']['request'].get('title', '课程安排'),
                'detail': ('恢复课次：' + restored if restored else '取消本次新增的课次') + '；保留通知与变更历史'})
        elif table == 'proposals':
            result.append({'title': '本次个人计划', 'detail': '仅撤销这次个人计划调整，保留已确认的现实安排'})
        elif table == 'plans' and not any(e['table'] == 'proposals' for e in data['entries']):
            result.append({'title': '相关个人计划', 'detail': '恢复本次操作前的计划状态与时段'})
    return result


def time_label(value):
    value = value or {}
    if value.get('at'):
        return local_stamp(value['at']) + (' 至 ' + local_stamp(value['end_at']) if value.get('end_at') else '')
    if value.get('date'):
        return value['date'] + (' 至 ' + value['end_date'] if value.get('end_date') else '')
    if value.get('week'):
        return f"第{value['week']}周"
    return '待确认'


def local_stamp(value):
    return instant(value).astimezone(SHANGHAI).strftime('%Y-%m-%d %H:%M')


def reminder_label(value):
    if not value.get('enabled',True):return '已关闭'
    if value.get('mode')=='absolute':return local_stamp(value['trigger_at'])+'提醒'
    minutes=value.get('lead_minutes',0)
    amount=f'{minutes//1440}天' if minutes and minutes%1440==0 else f'{minutes//60}小时' if minutes and minutes%60==0 else f'{minutes}分钟'
    return '提前'+amount+'提醒' if minutes else '到时提醒'


def field_label(value):
    return '未填写' if value is None or value == '' else str(value)


def prepare_undo(db, user, s, source_run_id):
    # No source-run lock before Semester: confirmation lock order is new run,
    # semester, source run. Preparation only reads source run after capture.
    current = capture(db, user, s.id)
    row = source_run(db, user, s.id, source_run_id)
    data = undo_data(row, user, s.id)
    validate(db, user, s, data, current)
    return {'kind': 'undo', 'action': 'undo', 'body': {}, 'semester_id': s.id,
        'expected_revision': current['revision'], 'source_run_id': source_run_id,
        'summary': summary(data)}


def apply_undo(db, user, preview):
    s = owned_semester(db, user, preview['semester_id'], lock=True)
    db.refresh(s)
    row = source_run(db, user, s.id, preview['source_run_id'], lock=True)
    if row.state.get('undone_by'):
        if row.state['undone_by'] == preview.get('undo_run_id') and row.state.get('undo_receipt'):
            return row.state['undo_receipt']
        error(409, 'ALREADY_UNDONE', '这次操作已经撤销')
    data = undo_data(row, user, s.id)
    if s.revision != preview['expected_revision']:
        error(409, 'PREVIEW_STALE', '撤销预览后安排已有变化，请重新核对')
    if not preview.get('undo_run_id'):
        error(409, 'UNDO_CONFIRMATION_REQUIRED', '请通过助手中的撤销预览确认')
    current = capture(db, user, s.id)
    validate(db, user, s, data, current)
    proposals = [e for e in data['entries'] if e['table'] == 'proposals']
    now = utcnow(); now_text = now.isoformat()
    plan_receipt = None
    if proposals:
        extras=[e for e in data['entries'] if e['table'] not in ('plans','proposals')]
        updates={u['item_id']:u for u in proposals[0]['after']['payload'].get('remaining_updates',[])}
        def joint_remaining_entry(entry):
            before,after=entry['before'],entry['after']
            if entry['table']=='items' and before and after['id'] in updates:
                update=updates[after['id']]
                return (after['payload']=={**before['payload'],'remaining_minutes':update['remaining_minutes']}
                        and before['payload'].get('remaining_minutes')==update['before_remaining_minutes'])
            return (entry['table']=='progress' and before is None and after['item_id'] in updates
                    and after['payload']['remaining_minutes']==updates[after['item_id']]['remaining_minutes'])
        if len(proposals) != 1 or any(not joint_remaining_entry(e) for e in extras):
            error(409, 'UNDO_UNAVAILABLE', '这次混合操作需要逐项核对，不能自动撤销')
        from .schedule_api import undo_proposal_command
        from .schedule_schemas import ProposalAction
        p = proposals[0]['after']
        plan_receipt = undo_proposal_command(db, user, p['id'], ProposalAction(
            expected_version=p['version'], expected_revision=s.revision))
        for entry in extras:
            target=db.get(MODELS[entry['table']],entry['id'])
            if entry['table']=='items':
                target.payload=deepcopy(entry['before']['payload'])
                target.version+=1;target.updated_at=now_text
                from .items import audit
                audit(db,target,'用户确认撤销剩余量更正及安排')
            else:
                target.payload={**target.payload,'undone':True,'undone_at':now_text,
                    'undo_source_run_id':row.id,'undo_run_id':preview['undo_run_id']}
    else:
        changed_items, changed_events = set(), set()
        for entry in reversed(data['entries']):
            table, before, after = entry['table'], entry['before'], entry['after']
            target = db.get(MODELS[table], entry['id'])
            if table in ('items', 'events'):
                if before is None:
                    target.lifecycle = 'cancelled'
                else:
                    target.payload = deepcopy(before['payload']); target.lifecycle = before['lifecycle']
                target.version += 1; target.updated_at = now_text
                (changed_items if table == 'items' else changed_events).add(target.id)
            elif table == 'reminders':
                target.payload = deepcopy(before['payload']) if before else {**target.payload, 'enabled': False}
                target.version += 1; target.updated_at = now_text
                changed_items.add(target.item_id)
            elif table == 'plans':
                if before is None:
                    target.status = 'cancelled'; target.locked = False
                else:
                    for key in ('start_at', 'end_at', 'minutes', 'locked', 'status'):
                        setattr(target, key, before[key])
                target.version += 1; target.updated_at = now_text
            elif table == 'progress':
                target.payload = {**target.payload, 'undone': True, 'undone_at': now_text,
                    'undo_source_run_id': row.id, 'undo_run_id': preview['undo_run_id']}
            elif table == 'reality':
                from .changes import impact, source_snapshot
                patch = after['payload']['patch']
                reverse_patch = {'before': deepcopy(patch['after']), 'after': deepcopy(patch['before'])}
                reverse_impact = impact(source_snapshot(db, user, s), reverse_patch, now)
                reverse = RealityChange(user_id=user.id, semester_id=s.id, base_revision=s.revision,
                    applied_revision=s.revision + 1, created_at=now_text, payload={
                        'request': {'kind': 'undo', 'title': '撤销：' + after['payload']['request'].get('title', '课次调整'),
                            'source_text': '用户确认撤销这次操作', 'targets': [e['id'] for e in patch['after']]},
                        'patch': reverse_patch,
                        'base_calendar': {'first_monday': s.first_monday},
                        'undo_source_change_id': target.id, 'undo_source_run_id': row.id,
                        'impact': reverse_impact}, receipt={'undone': True, 'source_change_id': target.id,
                            'semester_id': s.id, 'revision': s.revision + 1})
                db.add(reverse)
        s.revision += 1
        db.flush()
        from .items import audit
        from .calendar_events import record as event_audit
        from .plan_store import record as plan_audit
        for rid in changed_items:
            audit(db, db.get(StudyItem, rid), '用户确认撤销助手操作')
        for rid in changed_events:
            event_audit(db, db.get(CalendarEvent, rid), '用户确认撤销助手操作')
        if any(e['table'] == 'plans' for e in data['entries']):
            plan_audit(db, user, s.id, 'agent_undo', {'source_run_id': row.id,
                'block_ids': [e['id'] for e in data['entries'] if e['table'] == 'plans']}, now)
    receipt = {'semester_id': s.id, 'revision': s.revision, 'undone': True,
        'source_run_id': row.id, 'summary': summary(data), 'plan_receipt': plan_receipt}
    row.state = {**row.state, 'undone_by': preview['undo_run_id'], 'undo_receipt': receipt,
                 'sequence':row.state.get('sequence',0)+1}
    return receipt
