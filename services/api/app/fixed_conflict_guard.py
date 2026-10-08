"""Read-only fixed-fact comparisons shared by manual and assistant writes."""
from copy import deepcopy

from fastapi import HTTPException

from .capacity import calendar_context
from .conflict_changes import introduced_conflicts, introduced_time_warnings, is_blocking_conflict
from .plan_rules import classify


def without_draft_ids(conflicts, draft_ids):
    """Preview IDs can describe a proposed record, never an actionable target."""
    drafts = set(draft_ids)
    result = []
    for value in conflicts:
        entry = deepcopy(value)
        pending = drafts.intersection(entry.get('item_ids', []))
        if pending:
            entry['pending_record'] = True
            entry['item_ids'] = [rid for rid in entry['item_ids'] if rid not in drafts]
            entry['uncertain_item_ids'] = [rid for rid in entry.get('uncertain_item_ids', []) if rid not in drafts]
        result.append(entry)
    return result


def fixed_change_impact(db, user, semester, *, calendar=None, items=None, now=None, draft_ids=()):
    from .schedule_api import snapshot
    from .reminder_rules import utcnow
    from .agent_attendance import conflict_courses
    from .academics import fingerprint
    source = snapshot(db, user, semester)
    now = now or utcnow()
    before = calendar_context(*source[:4], now)
    after_calendar = calendar if calendar is not None else source[0]
    after_items = items if items is not None else source[3]
    after = calendar_context(after_calendar, source[1], source[2], after_items, now)
    introduced = introduced_conflicts(before['conflicts'], after['conflicts'])
    new_warnings = introduced_time_warnings(before['time_warnings'], after['time_warnings'])
    old_issues = {fingerprint(issue) for issue in classify(source[4], source[3], before['free'].spans, before['begin'],
                                                          obligation_points=before['obligation_points'])[1]}
    new_issues = classify(source[4], after_items, after['free'].spans, after['begin'],
                         obligation_points=after['obligation_points'])[1]
    affected = {issue['block_id'] for issue in new_issues if fingerprint(issue) not in old_issues}
    blockers = without_draft_ids(after['conflicts'], draft_ids)
    new_blockers = without_draft_ids(introduced, draft_ids)
    return {'fixed_conflicts': blockers, 'new_fixed_conflicts': new_blockers,
            'blocking_fixed_conflicts': blockers, 'new_blocking_fixed_conflicts': new_blockers,
            'time_warnings': without_draft_ids(after['time_warnings'], draft_ids),
            'new_time_warnings': without_draft_ids(new_warnings, draft_ids),
            'course_conflicts': conflict_courses(after_calendar, source[2], introduced),
            'affected_plan_count': len(affected),
            'affected_blocks': [block for block in source[4] if block['id'] in affected]}


def require_fixed_confirmation(impact, confirmed):
    conflicts = [c for c in impact.get('new_blocking_fixed_conflicts', impact.get('new_fixed_conflicts', []))
                 if is_blocking_conflict(c)]
    if conflicts and not confirmed:
        point = any(c.get('evidence_kind') == 'start_point' for c in conflicts)
        message = ('开始时刻与课程或其他固定安排重叠，请明确处理后保存'
                   if point else '有课程或明确到场时间与固定安排重叠，请明确处理后保存')
        raise HTTPException(422, detail={'code': 'CONFIRM_FIXED_CONFLICTS', 'message': message,
            'new_fixed_conflicts': conflicts, 'course_conflicts': impact.get('course_conflicts', []),
            'impact': impact})
