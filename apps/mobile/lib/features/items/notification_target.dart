import 'dart:convert';

/// A notification points at an owned resource, rather than assuming every
/// reminder belongs to a task. Action data also carries the source version.
class NotificationTarget {
  final String ownerId, resourceType, resourceId;
  final String? semesterId;
  final String actionId;
  final int? notificationId;
  final Map<String, dynamic> data;
  const NotificationTarget({
    required this.ownerId,
    required this.resourceType,
    required this.resourceId,
    this.semesterId,
    this.actionId = '',
    this.notificationId,
    required this.data,
  });

  static NotificationTarget? decode(
    String? payload, {
    String actionId = '',
    int? notificationId,
  }) {
    try {
      final value = jsonDecode(payload ?? '{}');
      if (value is! Map) return null;
      final data = Map<String, dynamic>.from(value);
      if (data['owner_id'] is! String || data['owner_id'].isEmpty) return null;
      final legacyId = data['item_id'];
      final type =
          data['resource_type'] ??
          (legacyId is String && legacyId.startsWith('event:')
              ? 'event'
              : 'item');
      final id =
          data['resource_id'] ??
          (legacyId is String && legacyId.startsWith('event:')
              ? legacyId.substring(6)
              : legacyId);
      if (!{'item', 'exam', 'event', 'course'}.contains(type) ||
          id is! String ||
          id.isEmpty) {
        return null;
      }
      return NotificationTarget(
        ownerId: data['owner_id'],
        resourceType: type,
        resourceId: id,
        semesterId: data['semester_id'] is String ? data['semester_id'] : null,
        actionId: actionId,
        notificationId: notificationId ?? (data['notification_id'] as int?),
        data: data,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

String reminderBody(Map<String, dynamic> data) {
  final start = DateTime.tryParse('${data['start_at']}');
  // The academic calendar and API use Asia/Shanghai, independently of the
  // phone's time zone. Do not imply that an unknown time is a precise deadline.
  final school = start?.toUtc().add(const Duration(hours: 8));
  final label = switch (data['resource_type']) {
    'course' => '上课',
    'exam' => '考试',
    'event' => '日程',
    _ => switch (data['time_meaning']) {
      'start' => '开始',
      'window' => '窗口开始',
      _ => '截止',
    },
  };
  final parts = <String>[
    if (school != null)
      '$label ${school.month}月${school.day}日 '
          '${school.hour.toString().padLeft(2, '0')}:'
          '${school.minute.toString().padLeft(2, '0')}',
    if ('${data['place'] ?? ''}'.trim().isNotEmpty) '${data['place']}'.trim(),
    if (data['purpose'] == 'start_review') '开始复习',
    if (data['purpose'] == 'check_notice') '核实正式通知',
    if (data['snoozed'] == true) '稍后提醒',
  ];
  return parts.isEmpty ? '点击查看详情' : parts.join(' · ');
}
