import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../ui/app_controls.dart';
import '../calendar/calendar_repository.dart';
import '../calendar/time_track.dart';

class RecordedTimeStats {
  final int minutes, timedEntries, unknownDuration;
  const RecordedTimeStats(
    this.minutes,
    this.timedEntries,
    this.unknownDuration,
  );
}

/// Sum the union of known occupied intervals within the requested period.
/// Markers and unknown ends have no invented duration; overlaps count once.
RecordedTimeStats recordedTimeStats(
  List<Map<String, dynamic>> entries,
  DateTime from,
  DateTime until,
) {
  final intervals = <(DateTime, DateTime)>[];
  var unknown = 0;
  for (final row in entries) {
    if (!calendarReservesTime(row)) continue;
    final start = trackTime(row['occupancy_start_at'] ?? row['start_at']);
    final end = trackTime(row['end_at']);
    if (start == null) continue;
    if (end == null) {
      if (!start.isBefore(from) && start.isBefore(until)) unknown++;
      continue;
    }
    if (!end.isAfter(start) || !start.isBefore(until) || !end.isAfter(from)) {
      continue;
    }
    intervals.add((
      start.isBefore(from) ? from : start,
      end.isAfter(until) ? until : end,
    ));
  }
  final count = intervals.length;
  intervals.sort((a, b) => a.$1.compareTo(b.$1));
  var minutes = 0;
  DateTime? left, right;
  for (final interval in intervals) {
    if (left == null || interval.$1.isAfter(right!)) {
      if (left != null) minutes += right!.difference(left).inMinutes;
      left = interval.$1;
      right = interval.$2;
    } else if (interval.$2.isAfter(right)) {
      right = interval.$2;
    }
  }
  if (left != null) minutes += right!.difference(left).inMinutes;
  return RecordedTimeStats(minutes, count, unknown);
}

/// Optional compact summary of recorded schedule time, not an inferred workload
/// or completed study time. The caller supplies a complete weekly response.
class TimeStatsCard extends StatelessWidget {
  final List<Map<String, dynamic>> todayItems;
  final List<Map<String, dynamic>> weekItems;
  final DateTime now;
  const TimeStatsCard({
    super.key,
    required this.todayItems,
    required this.weekItems,
    required this.now,
  });
  String _duration(int minutes) => minutes < 60
      ? '$minutes分钟'
      : '${minutes ~/ 60}小时${minutes % 60 == 0 ? '' : '${minutes % 60}分'}';
  @override
  Widget build(BuildContext context) {
    final day = DateTime.utc(now.year, now.month, now.day);
    final monday = day.subtract(Duration(days: day.weekday - 1));
    final today = recordedTimeStats(
      todayItems,
      day,
      day.add(const Duration(days: 1)),
    );
    final week = recordedTimeStats(
      weekItems,
      monday,
      monday.add(const Duration(days: 7)),
    );
    Widget metric(String label, RecordedTimeStats value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: CampusColors.muted),
        ),
        const SizedBox(height: 5),
        Text(
          value.timedEntries == 0 && value.unknownDuration > 0
              ? '时长不明确'
              : _duration(value.minutes),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: CampusColors.ink,
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CampusColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CampusColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '日程时长',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) =>
                MediaQuery.textScalerOf(context).scale(16) > 22 ||
                    box.maxWidth < 280
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      metric('今天', today),
                      const SizedBox(height: 14),
                      metric('本周', week),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: metric('今天', today)),
                      const SizedBox(width: 16),
                      Expanded(child: metric('本周', week)),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          AppDisclosure(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 6),
            title: const Text(
              '统计范围',
              style: TextStyle(fontSize: 13, color: CampusColors.muted),
            ),
            children: [
              Text(
                '本周${week.timedEntries}项有起止时间的安排，重叠时间只计一次。',
                style: const TextStyle(fontSize: 13, color: CampusColors.muted),
              ),
              if (week.unknownDuration > 0)
                Text(
                  '${week.unknownDuration}项没有结束时间，未计入总时长。',
                  style: const TextStyle(
                    fontSize: 13,
                    color: CampusColors.muted,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
