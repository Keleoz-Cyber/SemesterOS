import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../ui/app_controls.dart';
import '../../ui/week_heatmap.dart' as grid;
import '../calendar/calendar_repository.dart';
import '../calendar/time_track.dart';

/// Adapter from the complete weekly calendar response to the shared 7 × 24
/// grid. Date-only records remain labelled outside hour occupancy.
class WeekHeatmap extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final DateTime now;
  final ValueChanged<DateTime>? onDayTap;
  final bool available;
  final bool loading;
  final bool offline;
  final VoidCallback? onRetry;
  const WeekHeatmap({
    super.key,
    required this.items,
    required this.now,
    this.onDayTap,
    this.available = true,
    this.loading = false,
    this.offline = false,
    this.onRetry,
  });
  @override
  Widget build(BuildContext context) {
    final monday = DateTime.utc(now.year, now.month, now.day - now.weekday + 1);
    if (!available) {
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
            const Text('本周忙闲', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              loading ? '正在读取完整周日程…' : '暂时无法读取本周安排',
              style: const TextStyle(color: CampusColors.muted),
            ),
            if (!loading && onRetry != null)
              AppTextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
    }
    final blocks = <int, List<grid.TimeBlock>>{};
    final dateOnly = <int, int>{};
    for (final original in items) {
      final row = calendarDisplayEntry(original);
      final start = trackTime(row['occupancy_start_at'] ?? row['start_at']);
      final due = trackTime(row['due_at']);
      final point = start ?? due;
      if (point != null) {
        final reserves = calendarReservesTime(row);
        final end = reserves && due == null ? trackTime(row['end_at']) : null;
        // Store an interval once; the grid clips it independently per hour.
        final index = point.weekday;
        blocks
            .putIfAbsent(index, () => [])
            .add(
              grid.TimeBlock(
                start: point,
                end: end ?? point,
                title: '${row['title'] ?? ''}',
                type: row['resource_type'],
              ),
            );
      } else {
        final date = DateTime.tryParse(
          '${row['date'] ?? calendarTime(row)['date']}',
        );
        if (date != null &&
            !date.isBefore(monday) &&
            date.isBefore(monday.add(const Duration(days: 7)))) {
          dateOnly.update(date.weekday, (v) => v + 1, ifAbsent: () => 1);
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (offline)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '离线查看已保存的完整周日程',
              style: TextStyle(fontSize: 12, color: CampusColors.muted),
            ),
          ),
        grid.WeekHeatmap(
          weekData: blocks,
          currentWeek: monday,
          undatedTimes: dateOnly,
          onTap: onDayTap == null
              ? null
              : (weekday, hour) =>
                    onDayTap!(monday.add(Duration(days: weekday - 1))),
        ),
      ],
    );
  }
}
