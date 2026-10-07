import '../notices/notice_fields.dart' show noticeMap;

List<Map<String, dynamic>> _records(dynamic value) => value is List
    ? value.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
    : [];

/// Preview shapes vary by operation: a course change contains occurrence lists,
/// an item/event contains a record, and a plan contains solver output.
String savedActionMessage(Map<String, dynamic> run) {
  final preview = noticeMap(run['preview']);
  final receipt = noticeMap(run['receipt']);
  final kind = preview['kind'], action = preview['action'];
  if (kind == 'undo') return '已撤销';
  if (kind == 'batch') {
    final savedIds = _records(
      receipt['groups'],
    ).where((g) => g['status'] != 'skipped').map((g) => g['id']).toSet();
    final operations = _records(preview['groups'])
        .where((g) => savedIds.contains(g['id']))
        .expand((g) => _records(g['operations']))
        .toList();
    final leaveCount =
        _records(receipt['course_attendance']).length +
        operations
            .where(
              (p) => p['kind'] == 'course_change' && p['action'] == 'leave',
            )
            .fold<int>(0, (n, p) => n + _records(p['after']).length);
    if (leaveCount > 0) {
      final events = operations.where((p) => p['kind'] == 'event').length;
      return '${events > 0 ? '已保存 $events 项日程\n' : ''}已标记 $leaveCount 次课程请假';
    }
    final count = _records(
      receipt['groups'],
    ).where((g) => g['status'] != 'skipped').length;
    return count > 0 ? '已保存 $count 项安排' : '已保存';
  }
  if (kind == 'course_change') {
    if (action == 'suspend' || action == 'cancel') {
      final count = _records(preview['before']).length;
      return count > 0 ? '已停课 $count 次' : '已停课';
    }
    final occurrences = _records(preview['after']);
    final title =
        preview['title'] ??
        (occurrences.isEmpty ? null : occurrences.first['title']);
    final verb = action == 'add' ? '已添加补课' : '已调整课程';
    return title == null || '$title'.isEmpty ? verb : '$verb · $title';
  }
  if (kind == 'plan') return action == 'replan' ? '已调整学习安排' : '已保存学习安排';
  if (action == 'restore') {
    return '已恢复 ${noticeMap(preview['after'])['title'] ?? preview['title'] ?? '日程'}';
  }
  final after = noticeMap(preview['after']),
      before = noticeMap(preview['before']);
  final title = after['title'] ?? before['title'] ?? preview['title'];
  final name = title == null || '$title'.isEmpty ? '' : ' $title';
  final leaveCount = _records(receipt['course_attendance']).length;
  if (kind == 'event' && leaveCount > 0) {
    return '${action == 'create' ? '已添加' : '已更新'}$name\n已标记 $leaveCount 次课程请假';
  }
  if (kind == 'item_state') {
    return '${{'completed': '已完成', 'cancelled': '已取消', 'active': '已恢复'}[action] ?? '已更新'}$name';
  }
  if (action == 'update_reminder') {
    return after['enabled'] == false ? '已关闭提醒$name' : '已更新提醒$name';
  }
  if (action == 'cancel') return '已取消$name';
  return '${action == 'create' ? '已添加' : '已更新'}$name';
}
