import 'package:flutter/material.dart';
import 'campus_theme.dart';

enum DeadlineUrgency { critical, soon, approaching, future }

/// Exact deadline only. Starts, windows and candidate dates never count down.
DateTime? itemDeadline(Map<String, dynamic> item, {bool schoolClock = false}) {
  if (item['kind'] == 'exam') return null;
  final time = item['time'] is Map
      ? Map<String, dynamic>.from(item['time'])
      : <String, dynamic>{};
  final meaning = time['meaning'] ?? item['meaning'];
  if (meaning != null && meaning != 'deadline' && meaning != 'unspecified') {
    return null;
  }
  final precision = time['precision'] ?? item['time_precision'];
  DateTime? deadline;
  if (precision == 'date') {
    // An unspecified date is not an invented midnight deadline.
    if (time['day_end_confirmed'] != true) return null;
    deadline = DateTime.tryParse('${item['anchor_at']}')?.toUtc();
    final date = DateTime.tryParse('${time['date'] ?? item['date']}');
    if (deadline == null && date != null) {
      // Server reminder_rules.anchor_at uses the next local midnight.
      deadline = DateTime.utc(
        date.year,
        date.month,
        date.day + 1,
      ).subtract(const Duration(hours: 8));
    }
  } else if (precision == null || precision == 'exact') {
    deadline = DateTime.tryParse(
      '${item['due_at'] ?? item['anchor_at'] ?? time['at']}',
    )?.toUtc();
  }
  return schoolClock ? deadline?.add(const Duration(hours: 8)) : deadline;
}

class TimeUrgency {
  static DeadlineUrgency? level(int? remainingMinutes) =>
      remainingMinutes == null
      ? null
      : remainingMinutes < 120
      ? DeadlineUrgency.critical
      : remainingMinutes < 720
      ? DeadlineUrgency.soon
      : remainingMinutes < 4320
      ? DeadlineUrgency.approaching
      : DeadlineUrgency.future;

  static Color getColor(int? remainingMinutes) =>
      switch (level(remainingMinutes)) {
        DeadlineUrgency.critical => CampusColors.error,
        DeadlineUrgency.soon => CampusColors.warning,
        DeadlineUrgency.approaching => CampusColors.teal,
        DeadlineUrgency.future => CampusColors.primary,
        null => CampusColors.muted,
      };

  static String getLabel(int? remainingMinutes) {
    if (remainingMinutes == null) return '';
    if (remainingMinutes < 0) return '已逾期 ${_duration(-remainingMinutes)}';
    if (remainingMinutes == 0) return '即将截止';
    return '剩 ${_duration(remainingMinutes)}';
  }

  static String _duration(int minutes) {
    if (minutes < 60) return '$minutes分钟';
    if (minutes < 1440) {
      return '${minutes ~/ 60}小时${minutes % 60 == 0 ? '' : '${minutes % 60}分'}';
    }
    return '${minutes ~/ 1440}天${minutes % 1440 ~/ 60 == 0 ? '' : '${minutes % 1440 ~/ 60}小时'}';
  }

  /// Only a real start and end define progress; unknown starts return zero.
  static double getProgressPercentage(
    DateTime? deadline,
    DateTime? startTime, {
    DateTime? now,
  }) {
    if (deadline == null || startTime == null) return 0;
    final total = deadline.difference(startTime).inMilliseconds;
    if (total <= 0) return 0;
    return ((now ?? DateTime.now()).difference(startTime).inMilliseconds /
            total)
        .clamp(0.0, 1.0);
  }
}
