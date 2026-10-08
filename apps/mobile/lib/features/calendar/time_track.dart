import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import 'calendar_repository.dart';
import '../../ui/v2/shiri_tokens.dart' as v2;
import '../../ui/v2/motion/now_pulse.dart';

/// Refresh at the wall-clock minute boundary, with one timer while visible.
class MinuteClock {
  final VoidCallback onTick;
  final DateTime Function() now;
  Timer? _timer;
  bool _closed = false;
  bool get isActive => !_closed && (_timer?.isActive ?? false);
  MinuteClock(this.onTick, {DateTime Function()? now})
    : now = now ?? DateTime.now {
    _schedule();
  }
  void _schedule() {
    final value = now();
    _timer = Timer(
      Duration(milliseconds: 60000 - value.second * 1000 - value.millisecond),
      () {
        if (_closed) return;
        onTick();
        if (!_closed) _schedule();
      },
    );
  }

  void cancel() {
    _closed = true;
    _timer?.cancel();
  }
}

/// Position on the displayed rail. Unknown ends remain points, never intervals.
class TrackPosition {
  final int index;
  final double fraction;
  final bool inOccurrence;
  const TrackPosition(this.index, this.fraction, this.inOccurrence);
}

DateTime? trackTime(dynamic value) =>
    value is String && DateTime.tryParse(value) != null
    ? schoolTime(value)
    : null;

TrackPosition? trackPosition(
  List<Map<String, dynamic>> rows,
  DateTime date,
  DateTime now,
) {
  if (calendarDate(date) != calendarDate(now)) return null;
  final day = DateTime.utc(date.year, date.month, date.day);
  final until = day.add(const Duration(days: 1));
  double fraction(DateTime a, DateTime b) => b.isAfter(a)
      ? (now.difference(a).inMilliseconds / b.difference(a).inMilliseconds)
            .clamp(0.0, 1.0)
      : 0;
  for (var i = 0; i < rows.length; i++) {
    if (!calendarReservesTime(rows[i])) continue;
    final start = trackTime(
          rows[i]['end_at'] == null || !calendarReservesTime(rows[i])
              ? rows[i]['start_at']
              : rows[i]['occupancy_start_at'] ?? rows[i]['start_at'],
        ),
        end = trackTime(rows[i]['end_at']);
    if (start != null &&
        end != null &&
        !now.isBefore(start) &&
        now.isBefore(end)) {
      return TrackPosition(
        i,
        fraction(
          start.isBefore(day) ? day : start,
          end.isAfter(until) ? until : end,
        ),
        true,
      );
    }
  }
  var previous = day;
  for (var i = 0; i < rows.length; i++) {
    final start = trackTime(
      rows[i]['end_at'] == null
          ? rows[i]['start_at']
          : rows[i]['occupancy_start_at'] ?? rows[i]['start_at'],
    );
    if (start == null) continue;
    if (start.isAfter(now)) {
      return TrackPosition(i, fraction(previous, start), false);
    }
    final end = calendarReservesTime(rows[i])
        ? trackTime(rows[i]['end_at']) ?? start
        : start;
    if (end.isAfter(previous) && !end.isAfter(now)) previous = end;
  }
  return TrackPosition(rows.length, fraction(previous, until), false);
}

/// A chronological agenda, rather than an evenly scaled hour grid. The current
/// clock belongs to its event or gap; unknown durations never receive progress.
class TimeTrack extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final DateTime date, now;
  final Widget Function(Map<String, dynamic> row, bool last, Widget? clock)
  rowBuilder;
  final double railX;
  final bool showNow;
  const TimeTrack({
    super.key,
    required this.rows,
    required this.date,
    required this.now,
    required this.rowBuilder,
    this.railX = 64,
    this.showNow = true,
  });

  Widget clock(
    BuildContext context,
    TrackPosition position, {
    required bool before,
    required bool after,
  }) {
    final height = MediaQuery.textScalerOf(context).scale(14) * 1.5 + 22;
    return SizedBox(
      key: ValueKey(
        position.inOccurrence
            ? 'time-track-current-active'
            : 'time-track-current-gap',
      ),
      height: height,
      child: CustomPaint(
        painter: TimeTrackMarkerPainter(
          position.fraction,
          railX,
          before: before,
          after: after,
        ),
        child: Padding(
          padding: EdgeInsets.only(left: railX + 17, right: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              label: '现在 ${hhmm(now)}',
              child: Text(
                '现在 ${hhmm(now)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: v2.ShiriBrand.sunInk,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget activeClock(TrackPosition position) => Padding(
    key: const ValueKey('time-track-current-active'),
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Semantics(
      label: '现在 ${hhmm(now)}，当前安排的时间进度',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              NowDot(time: now, size: 12),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '现在 ${hhmm(now)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: v2.ShiriBrand.sunInk,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              key: const ValueKey('time-track-event-progress'),
              value: position.fraction,
              minHeight: 2,
              color: v2.ShiriBrand.sun500,
              backgroundColor: CampusColors.line,
              semanticsLabel: '当前安排的时间进度',
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final position = showNow ? trackPosition(rows, date, now) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (position != null && !position.inOccurrence && position.index == i)
            clock(context, position, before: i > 0, after: true),
          rowBuilder(
            rows[i],
            i == rows.length - 1 && (position == null || position.index < i),
            position != null && position.inOccurrence && position.index == i
                ? activeClock(position)
                : null,
          ),
        ],
        if (position != null &&
            !position.inOccurrence &&
            position.index == rows.length)
          clock(context, position, before: true, after: false),
      ],
    );
  }
}

class TimeTrackMarkerPainter extends CustomPainter {
  final double fraction, railX;
  final bool before, after;
  const TimeTrackMarkerPainter(
    this.fraction,
    this.railX, {
    this.before = true,
    this.after = true,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final rail = Paint()
      ..color = CampusColors.line
      ..strokeWidth = 2;
    if (before) canvas.drawLine(Offset(railX, 0), Offset(railX, y), rail);
    if (after) {
      canvas.drawLine(Offset(railX, y), Offset(railX, size.height), rail);
    }
    final paint = Paint()
      ..color = v2.ShiriBrand.sun500
      ..strokeWidth = 2;
    canvas.drawCircle(
      Offset(railX, y),
      5,
      Paint()..color = CampusColors.background,
    );
    canvas.drawCircle(Offset(railX, y), 4, paint);
    canvas.drawCircle(
      Offset(railX, y),
      4,
      Paint()
        ..color = v2.ShiriBrand.sunInk.withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawLine(Offset(railX + 5, y), Offset(railX + 12, y), paint);
  }

  @override
  bool shouldRepaint(covariant TimeTrackMarkerPainter old) =>
      old.fraction != fraction ||
      old.railX != railX ||
      old.before != before ||
      old.after != after;
}
