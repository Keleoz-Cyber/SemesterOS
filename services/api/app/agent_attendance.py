"""User-selected attendance resolutions saved atomically with event previews."""
from copy import deepcopy
from .auth import error
from .academics import owned_semester
from .models import new_id
from .occurrences import expand, effective_courses


def conflict_courses(calendar, courses, conflicts):
    ids = {rid for conflict in conflicts for rid in conflict.get('item_ids', [])}
    return [{'occurrence_id': e['id'], 'title': e['title'],
             'start_at': e['start_at'], 'end_at': e['end_at'],
             'location': e.get('location', ''),
             'attendance_status': e.get('attendance_status', 'attend')}
            for e in expand(calendar, courses)
            if e['id'] in ids and e.get('reality_kind') == 'course'
            and e.get('attendance_status') != 'leave' and not e.get('attendance_exempt')]


def apply_with_course_leave(db, user, preview, targets, *, run_id,
                           selected_group_ids=None, confirm_fixed_conflicts=False):
    from .agent_tools import apply_preview
    from .agent_batches import selected_groups, simulate, children
    from .changes import preview_change_command
    from .change_schemas import ChangeInput
    if not targets:
        return apply_preview(db, user, preview, selected_group_ids=selected_group_ids,
                             confirm_fixed_conflicts=confirm_fixed_conflicts)
    if len(targets) != len(set(targets)):
        error(422, 'INVALID_ATTENDANCE', '请假课次不能重复')
    personal_exam = preview['kind'] in ('item', 'item_state') and (preview.get('after') or {}).get('kind') == 'exam'
    if preview['kind'] == 'item_state' and preview['action'] != 'active':
        personal_exam = False
    if preview['kind'] not in ('event', 'batch') and not personal_exam:
        error(422, 'INVALID_ATTENDANCE', '请在活动安排预览中核对需要请假的课次')
    s = owned_semester(db, user, preview['semester_id'], lock=True)
    if s.revision != preview['expected_revision']:
        error(409, 'PREVIEW_STALE', '安排已更新，请重新核对请假课次')
    if preview['kind'] == 'batch':
        groups = deepcopy(selected_groups(preview, selected_group_ids))
    else:
        groups = [{'id': new_id(), 'title': (preview.get('after') or {}).get('title', '日程'),
                   'operations': [deepcopy(preview)]}]
    modified = {e['id'] for p in children({'groups': groups})
                if p['kind'] == 'course_change' for e in p.get('before', [])}
    if modified.intersection(targets):
        error(422, 'INVALID_ATTENDANCE', '这些课次还有其他修改，请先核对实际安排')
    summary = simulate(db, user, s, groups, s.revision)
    courses = effective_courses(db, user, s)
    eligible = conflict_courses({'first_monday': s.first_monday, 'periods': s.periods},
                                courses, summary['new_fixed_conflicts'])
    by_id = {e['occurrence_id']: e for e in eligible}
    if not set(targets).issubset(by_id):
        error(422, 'INVALID_ATTENDANCE', '只能标记这次所选安排实际冲突的课次')
    value = preview_change_command(db, user, s.id,
        ChangeInput(kind='leave', targets=targets, title='已请假课程',
                    source_text='用户在保存安排时确认这些具体课次已请假'), agent_run_id=run_id)
    leave = {'kind': 'course_change', 'action': 'leave', 'change_id': value['id'],
             'title': '已请假课程', 'before': value['patch']['before'], 'after': value['patch']['after'],
             'body': {'expected_revision': s.revision}, 'agent_run_id': run_id,
             'semester_id': s.id, 'expected_revision': s.revision}
    attendance_id = new_id()
    combined = {**deepcopy(preview), 'kind': 'batch', 'action': 'batch',
                'groups': [{'id': attendance_id, 'title': '本次课程请假', 'operations': [leave]}, *groups]}
    receipt = apply_preview(db, user, combined,
                           selected_group_ids=[g['id'] for g in combined['groups']],
                           confirm_fixed_conflicts=confirm_fixed_conflicts)
    # Keep the existing event receipt shape and original visible group IDs.
    result = receipt if preview['kind'] == 'batch' else receipt['groups'][1]['receipts'][0]
    return {**result, 'impact': receipt['impact'],
            'course_attendance': [{**by_id[rid], 'attendance_status': 'leave'} for rid in targets]}
