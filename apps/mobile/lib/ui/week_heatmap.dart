import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'campus_theme.dart';

/// Occupancy is measured against each actual hour, including cross-midnight
/// intervals. Unknown ends are point markers, never invented occupied hours.
class TimeBlock {
  final DateTime start;
  final DateTime end;
  final String title;
  final String? type;
  const TimeBlock({
    required this.start,
    required this.end,
    required this.title,
    this.type,
  });
}

class HeatmapHour {
  final int minutes;
  final int count;
  final int points;
  const HeatmapHour(this.minutes, this.count, this.points);
}

HeatmapHour heatmapHour(Iterable<TimeBlock> blocks, DateTime hour) {
  final until = hour.add(const Duration(hours: 1));
  var minutes = 0, count = 0, points = 0;
  for (final block in blocks) {
    final end = block.end;
    if (!end.isAfter(block.start)) {
      if (!block.start.isBefore(hour) && block.start.isBefore(until)) points++;
      continue;
    }
    if (!block.start.isBefore(until) || !end.isAfter(hour)) continue;
    final from = block.start.isAfter(hour) ? block.start : hour;
    final to = end.isBefore(until) ? end : until;
    minutes += to.difference(from).inMinutes;
    count++;
  }
  return HeatmapHour(minutes, count, points);
}

class WeekHeatmap extends StatelessWidget {
  final Map<int, List<TimeBlock>> weekData;
  final DateTime currentWeek;
  final void Function(int weekday, int hour)? onTap;
  final Map<int, int> undatedTimes;
  const WeekHeatmap({
    super.key,
    required this.weekData,
    required this.currentWeek,
    this.onTap,
    this.undatedTimes = const {},
  });
  Color _color(HeatmapHour data) {
    if (data.count >= 2 || data.minutes > 60) return CampusColors.primary;
    if (data.minutes >= 30) return CampusColors.primary.withValues(alpha: .48);
    if (data.minutes > 0) return CampusColors.primary.withValues(alpha: .22);
    return CampusColors.background;
  }

  @override
  Widget build(BuildContext context) {
    final monday = DateTime.utc(
      currentWeek.year,
      currentWeek.month,
      currentWeek.day - currentWeek.weekday + 1,
    );
    // The horizontal rail keeps every date/hour reachable at a readable size.
    final cellWidth = math.max(
      22.0,
      MediaQuery.textScalerOf(context).scale(18),
    );
    final all = weekData.values.expand((blocks) => blocks).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CampusColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CampusColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '本周忙闲',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            '左右滑动 · 点日期查看日程',
            style: TextStyle(fontSize: 12, color: CampusColors.muted),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(width: MediaQuery.textScalerOf(context).scale(72)),
                    for (var hour = 0; hour < 24; hour++)
                      SizedBox(
                        width: cellWidth,
                        child: Text(
                          hour % 3 == 0 ? '$hour' : '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: CampusColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
                for (var day = 0; day < 7; day++)
                  _dayRow(context, monday, all, day, cellWidth),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '空闲',
                style: TextStyle(fontSize: 12, color: CampusColors.muted),
              ),
              for (final amount in [.15, .35, .65, .9])
                Container(
                  width: 14,
                  height: 8,
                  decoration: BoxDecoration(
                    color: CampusColors.primary.withValues(alpha: amount),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              const Text(
                '较忙',
                style: TextStyle(fontSize: 12, color: CampusColors.muted),
              ),
              const Text(
                '● 仅记录时刻',
                style: TextStyle(fontSize: 12, color: CampusColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayRow(
    BuildContext context,
    DateTime monday,
    List<TimeBlock> all,
    int day,
    double width,
  ) {
    final date = monday.add(Duration(days: day));
    final dateOnly = undatedTimes[day + 1] ?? 0;
    final hours = [
      for (var hour = 0; hour < 24; hour++)
        heatmapHour(all, date.add(Duration(hours: hour))),
    ];
    final occupied = hours.where((h) => h.minutes > 0).length;
    final points = hours.fold<int>(0, (n, h) => n + h.points);
    final overlaps = hours.where((h) => h.count >= 2).length;
    final label =
        '周${'一二三四五六日'[day]} ${date.month}月${date.day}日，'
        '$occupied小时有安排，$overlaps小时重叠，$points项仅记录时刻，'
        '$dateOnly项只记录日期';
    return Semantics(
      label: label,
      button: onTap != null,
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(day + 1, 0),
        child: ExcludeSemantics(
          child: SizedBox(
            height: math.max(
              48.0,
              MediaQuery.textScalerOf(context).scale(dateOnly > 0 ? 30 : 18) *
                      1.35 +
                  8,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: MediaQuery.textScalerOf(context).scale(72),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '周${'一二三四五六日'[day]} ${date.month}/${date.day}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: CampusColors.ink,
                        ),
                      ),
                      if (dateOnly > 0)
                        Text(
                          '$dateOnly项按日期',
                          style: const TextStyle(
                            fontSize: 10,
                            color: CampusColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                for (var hour = 0; hour < 24; hour++)
                  Tooltip(
                    message:
                        '${date.month}/${date.day} $hour时：${hours[hour].minutes}占用分钟，'
                        '${hours[hour].count}个安排，${hours[hour].points}个时刻标记',
                    child: Container(
                      width: width - 2,
                      height: 24,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: _color(hours[hour]),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: hours[hour].points > 0
                          ? const Center(
                              child: Text(
                                '●',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: CampusColors.teal,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
