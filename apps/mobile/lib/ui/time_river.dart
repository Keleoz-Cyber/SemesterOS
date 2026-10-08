import 'package:flutter/material.dart';
import '../app/controller.dart';
import '../features/calendar/calendar_repository.dart';
import '../features/calendar/time_track.dart';
import 'campus_theme.dart';

/// `now` and `day` are already school wall-clock values. Only server instants
/// pass through trackTime, once. The compact rail grows with actual content.
class TimeRiverView extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  final DateTime now;
  final DateTime day;
  final ValueChanged<Map<String, dynamic>> onEventTap;
  final bool showNow;
  const TimeRiverView({
    super.key,
    required this.events,
    required this.now,
    required this.day,
    required this.onEventTap,
    this.showNow = true,
  });

  @override
  Widget build(BuildContext context) {
    final rows =
        events.map(calendarDisplayEntry).where((row) {
          final start = trackTime(row['start_at']);
          final end = trackTime(row['end_at']);
          final from = DateTime.utc(day.year, day.month, day.day);
          final until = from.add(const Duration(days: 1));
          if (start == null) return false;
          return start.isBefore(until) &&
              (end == null ? !start.isBefore(from) : end.isAfter(from));
        }).toList()..sort(
          (a, b) =>
              trackTime(a['start_at'])!.compareTo(trackTime(b['start_at'])!),
        );
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '今天没有已记录的课程或活动',
          style: TextStyle(color: CampusColors.muted, fontSize: 16),
        ),
      );
    }
    final railX = MediaQuery.textScalerOf(context).scale(52) + 5;
    final featured = rows
        .where(
          (row) =>
              calendarReservesTime(row) &&
              (trackTime(row['start_at'])!.isAfter(now) ||
                  (trackTime(row['end_at'])?.isAfter(now) ?? false)),
        )
        .firstOrNull;
    return TimeTrack(
      rows: rows,
      date: day,
      now: now,
      showNow: showNow,
      railX: railX,
      rowBuilder: (row, last, clock) => _RiverRow(
        row: row,
        now: now,
        last: last,
        clock: clock,
        featured: featured != null && row['id'] == featured['id'],
        onTap: () => onEventTap(row),
      ),
    );
  }
}

class _RiverRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final DateTime now;
  final bool last;
  final bool featured;
  final Widget? clock;
  final VoidCallback onTap;
  const _RiverRow({
    required this.row,
    required this.now,
    required this.last,
    required this.onTap,
    this.clock,
    this.featured = false,
  });
  @override
  Widget build(BuildContext context) {
    final start = trackTime(row['start_at'])!;
    final end = trackTime(row['end_at']);
    final past = end != null && !end.isAfter(now);
    final running =
        calendarReservesTime(row) &&
        end != null &&
        !start.isAfter(now) &&
        end.isAfter(now);
    final palette = CoursePalette.forTitle('${row['title']}');
    final media = MediaQuery.of(context);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final animate =
        running &&
        !media.disableAnimations &&
        !media.accessibleNavigation &&
        TickerMode.valuesOf(context).enabled &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    final details = <String>[
      switch (row['resource_type']) {
        'course' => '课程',
        'exam' => '考试',
        'plan' => '计划',
        _ => '活动',
      },
      if (calendarParticipationLabel(row).isNotEmpty)
        calendarParticipationLabel(row),
      if (calendarArrivalLabel(row).isNotEmpty) calendarArrivalLabel(row),
      if ('${row['location'] ?? ''}'.trim().isNotEmpty) '${row['location']}',
      if (running && !featured) '进行中' else if (past) '已结束',
    ].join(' · ');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: MediaQuery.textScalerOf(context).scale(52),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hhmm(start),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: running ? CampusColors.teal : CampusColors.ink,
                    ),
                  ),
                  if (end != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        hhmm(end),
                        style: const TextStyle(
                          fontSize: 12,
                          color: CampusColors.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 16,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  bottom: last ? 30 : 0,
                  left: 4,
                  child: Container(width: 2, color: CampusColors.line),
                ),
                Positioned(
                  top: 18,
                  left: 0,
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(
                      'river-dot-${row['id']}-${now.hour}-${now.minute}',
                    ),
                    tween: Tween(begin: animate ? .45 : 1, end: 1),
                    duration: animate
                        ? const Duration(milliseconds: 240)
                        : Duration.zero,
                    builder: (_, opacity, child) =>
                        Opacity(opacity: opacity, child: child),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: running ? CampusColors.teal : palette.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: featured ? CampusColors.surface : Colors.transparent,
                elevation: featured ? 2 : 0,
                shadowColor: CampusColors.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    decoration: BoxDecoration(
                      border: !featured && !last
                          ? const Border(
                              bottom: BorderSide(color: CampusColors.line),
                            )
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (featured) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  running ? '进行中' : '下一安排',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: CampusColors.teal,
                                  ),
                                ),
                              ),
                              if (!running &&
                                  start.difference(now).inMinutes < 60)
                                Text(
                                  '${start.difference(now).inMinutes.clamp(1, 60)}分钟后',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: CampusColors.muted,
                                  ),
                                ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: CampusColors.teal,
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                        ],
                        Text(
                          '${row['title'] ?? ''}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: past ? CampusColors.muted : CampusColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          details,
                          style: const TextStyle(
                            fontSize: 12,
                            color: CampusColors.muted,
                          ),
                        ),
                        ?clock,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
