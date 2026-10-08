import '../../ui/app_sheet.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/app_controls.dart';
import '../../ui/campus_theme.dart';
import 'calendar_repository.dart';
import 'time_track.dart';
import 'timetable_scale.dart';
import '../../ui/date_labels.dart';
import '../../ui/v2/shiri_tokens.dart' as v2;
import '../../ui/v2/widgets/schedule_block.dart';
import '../../ui/v2/widgets/dashed_border.dart';
import '../../ui/v2/motion/now_pulse.dart';
import '../../ui/v2/motion/pressable.dart';
import '../../ui/v2/motion/skeleton.dart';

class ScheduleGrid extends StatefulWidget {
  final DateTime firstDay;
  final DateTime? minDay, maxDay, selectedDay;
  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> periods;
  final ValueChanged<Map<String, dynamic>> onOpen;

  /// Presentation identity of the clicked day-part; never added to the row.
  final void Function(Map<String, dynamic> row, String surfaceTag)?
  onOpenSurface;
  final ValueChanged<DateTime>? onDay, onWeek;
  final bool loading, showHeader, visible;
  final String resourceFilter;
  final int? revision;
  final DateTime Function()? now;
  final bool refreshClock;
  const ScheduleGrid({
    super.key,
    required this.firstDay,
    required this.entries,
    this.periods = const [],
    required this.onOpen,
    this.onOpenSurface,
    this.onDay,
    this.onWeek,
    this.minDay,
    this.maxDay,
    this.selectedDay,
    this.loading = false,
    this.showHeader = true,
    this.visible = true,
    this.resourceFilter = 'all',
    this.revision,
    this.now,
    this.refreshClock = true,
  });
  @override
  State<ScheduleGrid> createState() => _ScheduleGridState();
}

class _GridPart {
  final String id;
  final int day, start, end;
  final Map<String, dynamic> source;
  const _GridPart(this.id, this.day, this.start, this.end, this.source);
  bool get point => source['end_at'] == null || !calendarReservesTime(source);
}

class _ScheduleGridState extends State<ScheduleGrid>
    with WidgetsBindingObserver {
  final scroll = ScrollController();
  final pages = <String, List<Map<String, dynamic>>>{};
  MinuteClock? clock;
  bool active = true, foreground = true;
  DateTime get now => widget.now?.call() ?? schoolNow();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    cachePage();
  }

  void cachePage() {
    if (!widget.loading) pages[calendarDate(widget.firstDay)] = widget.entries;
  }

  void updateClock() {
    if (!active || !foreground || !widget.visible || !widget.refreshClock) {
      clock?.cancel();
      clock = null;
    } else {
      clock ??= MinuteClock(() {
        if (mounted && active && foreground && widget.visible) setState(() {});
      }, now: () => now);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    active = TickerMode.valuesOf(context).enabled;
    updateClock();
  }

  @override
  void didUpdateWidget(covariant ScheduleGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) pages.clear();
    cachePage();
    updateClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() => foreground = state == AppLifecycleState.resumed);
    updateClock();
  }

  @override
  void dispose() {
    clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    scroll.dispose();
    super.dispose();
  }

  List<_GridPart> parts() {
    final result = <_GridPart>[];
    for (final row in calendarScheduleEntries(
      pages[calendarDate(widget.firstDay)] ?? widget.entries,
    )) {
      if (row['resource_type'] == 'deadline' ||
          calendarMeaning(row) == 'window' ||
          (widget.resourceFilter != 'all' &&
              row['resource_type'] != widget.resourceFilter)) {
        continue;
      }
      if (row['start_at'] == null) continue;
      final begin = schoolTime(row['start_at']);
      if (row['end_at'] == null || !calendarReservesTime(row)) {
        for (var day = 0; day < 7; day++) {
          final date = widget.firstDay.add(Duration(days: day));
          if (calendarDate(date) == calendarDate(begin)) {
            result.add(
              _GridPart(
                '${row['id']}/${calendarDate(date)}',
                day,
                begin.hour * 60 + begin.minute,
                begin.hour * 60 + begin.minute,
                row,
              ),
            );
          }
        }
      } else {
        for (final segment in calendarGridEntries([row], widget.firstDay)) {
          final start = schoolTime(segment['start_at']),
              end = schoolTime(segment['end_at']);
          final date = DateTime.utc(start.year, start.month, start.day);
          result.add(
            _GridPart(
              segment['id'],
              (segment['weekday'] as int) - 1,
              start.difference(date).inMinutes,
              end.difference(date).inMinutes,
              row,
            ),
          );
        }
      }
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  String surfaceTag(_GridPart part) => 'course-surface-${part.id}';

  void openPart(_GridPart part) {
    final openSurface = widget.onOpenSurface;
    if (openSurface != null && part.source['resource_type'] == 'course') {
      openSurface(part.source, surfaceTag(part));
    } else {
      widget.onOpen(part.source);
    }
  }

  Future<void> openGroup(List<_GridPart> group) async {
    if (group.length == 1) {
      openPart(group.first);
      return;
    }
    await showAppSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${group.length}项${overlaps(group) ? '时间重叠' : '安排'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final part in group)
                AppTile(
                  title: Text('${part.source['title']}'),
                  subtitle: Text(calendarTimeLabel(part.source)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(context);
                    openPart(part);
                  },
                ),
              if (widget.onDay != null)
                AppTextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onDay!(
                      widget.firstDay.add(Duration(days: group.first.day)),
                    );
                  },
                  child: const Text('查看这一天'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget tile(List<_GridPart> group, bool compact, double scaled) {
    final part = group.first;
    final isShort = part.point || part.end - part.start < 25;
    final label = group.length > 1
        ? '${group.length}项${overlaps(group) ? '重叠' : ''}'
        : '${part.source['title']}';
    final kind = switch (part.source['resource_type']) {
      'event' => v2.ScheduleKind.event,
      'plan' => v2.ScheduleKind.plan,
      'exam' => v2.ScheduleKind.exam,
      _ => v2.ScheduleKind.course,
    };
    final visual = v2.KindStyle.of(
      kind,
      palette: v2.CoursePalette.forTitle(
        '${part.source['title']}'.replaceFirst(
          RegExp(r'^(?:已请假|待请假|免听)\s*·\s*'),
          '',
        ),
      ),
      brightness: Theme.of(context).brightness,
    );
    return Semantics(
      button: true,
      label: group
          .map(
            (p) =>
                '${p.source['title']}，${calendarTimeLabel(p.source)}${p.point ? '，开始' : ''}',
          )
          .join('；'),
      child: Tooltip(
        message: group
            .map((p) => '${p.source['title']} ${calendarTimeLabel(p.source)}')
            .join('\n'),
        child: LayoutBuilder(
          key: ValueKey(
            '${part.point ? 'schedule-start' : 'schedule-tile'}-${part.id}',
          ),
          builder: (context, bounds) {
            final participation = calendarParticipationLabel(part.source);
            if (!isShort && bounds.maxHeight >= 64 * scaled) {
              return HeroMode(
                enabled: widget.visible && active && foreground,
                child: ScheduleBlock(
                  title: label,
                  kind: kind,
                  palette: v2.CoursePalette.forTitle(
                    '${part.source['title']}'.replaceFirst(
                      RegExp(r'^(?:已请假|待请假|免听)\s*·\s*'),
                      '',
                    ),
                  ),
                  location:
                      group.length == 1 &&
                          '${part.source['location'] ?? ''}'.trim().isNotEmpty
                      ? shortCampusLocation('${part.source['location']}')
                      : null,
                  heroTag:
                      group.length == 1 &&
                          part.source['resource_type'] == 'course'
                      ? surfaceTag(part)
                      : null,
                  onTap: () => openGroup(group),
                ),
              );
            }
            Widget body = Pressable(
              onPressed: () => openGroup(group),
              pressedScale: .96,
              excludeChildSemantics: true,
              semanticLabel: label,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: overlaps(group)
                        ? CampusColors.errorSoft
                        : visual.fill,
                    border: Border(
                      left: BorderSide(color: visual.accent, width: 3),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            maxLines: scaled > 1.3
                                ? 5
                                : bounds.maxHeight > 45 * scaled
                                ? 3
                                : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 11 : 14,
                              fontWeight: FontWeight.w700,
                              color: visual.foreground,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (part.point && bounds.maxHeight > 38 * scaled)
                          Text(
                            participation.isNotEmpty
                                ? participation
                                : hhmm(schoolTime(part.source['start_at'])),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: visual.foreground,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            if (visual.border != null) {
              body = visual.dashed
                  ? CustomPaint(
                      foregroundPainter: DashedRRectPainter(
                        color: visual.border!,
                        strokeWidth: visual.borderWidth,
                        dash: visual.dash,
                        gap: visual.gap,
                        radius: 11,
                      ),
                      child: body,
                    )
                  : DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: visual.border!,
                          width: visual.borderWidth,
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: body,
                    );
            }
            if (group.length == 1 && part.source['resource_type'] == 'course') {
              body = HeroMode(
                enabled: widget.visible && active && foreground,
                child: Hero(tag: surfaceTag(part), child: body),
              );
            }
            return body;
          },
        ),
      ),
    );
  }

  bool overlaps(List<_GridPart> group) {
    if (group.length < 2 || group.any((part) => part.point)) return false;
    return group.any(
      (part) => group.any(
        (other) =>
            !identical(part, other) &&
            part.start < other.end &&
            part.end > other.start,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final entries = parts(),
          scaled = MediaQuery.textScalerOf(context).scale(1);
      final compact = box.maxWidth < 540;
      final timeWidth = (compact ? 40.0 : 52.0) + 12 * scaled;
      final minuteHeight = scaled > 1.3 ? 1.4 : .95;
      final markerHeight = scaled > 1.3 ? 72.0 : 44.0;
      final current = now;
      final today = List.generate(
        7,
        (i) => widget.firstDay.add(Duration(days: i)),
      ).indexWhere((date) => calendarDate(date) == calendarDate(current));
      final minute = current.hour * 60 + current.minute;
      final firstEvent =
          entries.fold<int>(
            widget.periods.isEmpty
                ? 8 * 60
                : _clockMinute(widget.periods.first['start']),
            (value, part) => math.min(value, part.start),
          ) ~/
          60 *
          60;
      final lastEvent =
          ((entries.fold<int>(
                        widget.periods.isEmpty
                            ? 20 * 60
                            : _clockMinute(widget.periods.last['end']),
                        (value, part) => math.max(
                          value,
                          part.point ? part.start + 1 : part.end,
                        ),
                      ) +
                      59) ~/
                  60 *
                  60)
              .clamp(60, 1440);
      final first = today >= 0
          ? math.min(firstEvent, current.hour * 60)
          : firstEvent;
      final last = today >= 0
          ? math.max(lastEvent, (current.hour + 1) * 60)
          : lastEvent;
      final scale = TimetableScale.build(
        first,
        last,
        widget.periods,
        minuteHeight,
        scaled,
        entries
            .where((p) => !p.point)
            .map((p) => (start: p.start, end: p.end))
            .toList(),
      );
      final height = scale.at(last);
      final weights = [
        for (var i = 0; i < 7; i++)
          compact && scaled <= 1.2 && i >= 5 && !entries.any((p) => p.day == i)
              ? .65
              : 1.0,
      ];
      final totalWeight = weights.reduce((a, b) => a + b);
      final widths = weights
          .map((w) => (box.maxWidth - timeWidth) * w / totalWeight)
          .toList();
      final offsets = <double>[0];
      for (final w in widths) {
        offsets.add(offsets.last + w);
      }
      final children = <Widget>[
        for (var i = 0; i < 7; i++)
          if (i == today || i >= 5)
            Positioned(
              top: 0,
              left: timeWidth + offsets[i],
              width: widths[i],
              height: height,
              child: IgnorePointer(
                child: ColoredBox(
                  color: i == today
                      ? v2.ShiriColors.light.primarySoft.withValues(alpha: .72)
                      : CampusColors.background.withValues(alpha: .45),
                ),
              ),
            ),
        Positioned.fill(
          child: CustomPaint(
            painter: _GridLines(
              timeWidth,
              widths,
              scale,
              first,
              last,
              widget.periods,
            ),
          ),
        ),
        if (widget.loading && entries.isEmpty)
          for (final day in [0, 2, 4])
            Positioned(
              top: 16.0 + day * 12,
              left: timeWidth + offsets[day] + 3,
              width: widths[day] - 6,
              height: 72,
              child: const IgnorePointer(
                child: SkeletonBox(
                  height: 72,
                  borderRadius: BorderRadius.all(Radius.circular(11)),
                ),
              ),
            ),
        for (
          var hour = first ~/ 60;
          widget.periods.isEmpty && hour < last ~/ 60;
          hour++
        )
          Positioned(
            top: scale.at(hour * 60) + 2,
            left: 12,
            width: timeWidth - 16,
            child: Text(
              scaled > 1.3 ? '$hour时' : '${hour.toString().padLeft(2, '0')}:00',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: compact ? 10 : 12,
                color: CampusColors.muted,
              ),
            ),
          ),
        for (final period in widget.periods)
          if (period['start'] is String)
            Positioned(
              top: scale.at(_clockMinute(period['start'])) + 2,
              left: 12,
              width: timeWidth - 15,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${period['number']}节',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: CampusColors.muted,
                    ),
                  ),
                  Text(
                    '${period['start']}',
                    style: const TextStyle(
                      fontSize: 9,
                      color: CampusColors.muted,
                    ),
                  ),
                ],
              ),
            ),
      ];
      for (var day = 0; day < 7; day++) {
        final width = widths[day];
        final dayParts = entries.where((p) => p.day == day).toList();
        final groups = <List<_GridPart>>[];
        for (final part in dayParts) {
          if (groups.isNotEmpty &&
              groups.last.any(
                (p) =>
                    math.max(
                      scale.at(p.end),
                      scale.at(p.start) + markerHeight,
                    ) >
                    scale.at(part.start),
              )) {
            groups.last.add(part);
          } else {
            groups.add([part]);
          }
        }
        for (final group in groups) {
          final top = group.first.start;
          final bottom = group.map((p) => p.end).reduce(math.max);
          for (var lane = 0; lane < (compact ? 1 : group.length); lane++) {
            final visible = compact ? group : [group[lane]];
            final part = visible.first;
            final lanes = compact ? 1 : group.length;
            final y = compact ? top : part.start,
                finish = compact ? bottom : part.end;
            children.add(
              Positioned(
                top: scale.at(y) + 1,
                left: timeWidth + offsets[day] + lane * width / lanes + 1,
                width: width / lanes - 2,
                height: math.max(
                  part.point || part.end - part.start < 25
                      ? markerHeight
                      : 24.0,
                  scale.at(finish) - scale.at(y) - 3,
                ),
                child: tile(visible, compact, scaled),
              ),
            );
          }
        }
      }
      if (today >= 0 && minute >= first && minute < last) {
        children.add(
          Positioned(
            top: 0,
            left: 5,
            width: 2,
            height: scale.at(minute),
            child: IgnorePointer(
              child: const DecoratedBox(
                decoration: BoxDecoration(gradient: v2.ShiriGradients.brand),
              ),
            ),
          ),
        );
        children.add(
          Positioned(
            key: const ValueKey('schedule-current-time'),
            top: (scale.at(minute) - 5).clamp(0.0, math.max(0.0, height - 10)),
            left: 1,
            width: 10,
            height: 10,
            child: IgnorePointer(
              child: Semantics(
                label: '现在 ${hhmm(current)}',
                child: NowDot(time: current, size: 10),
              ),
            ),
          ),
        );
      }
      return Offstage(
        offstage: !active || !foreground || !widget.visible,
        child: Column(
          children: [
            if (widget.showHeader)
              SizedBox(
                height: 64 * scaled,
                child: Row(
                  children: [
                    SizedBox(
                      width: timeWidth,
                      child: Center(
                        child: today < 0
                            ? const Text(
                                '时间',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: CampusColors.muted,
                                ),
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    '现在',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: v2.ShiriBrand.sunInk,
                                    ),
                                  ),
                                  Text(
                                    hhmm(current),
                                    key: const Key('schedule-current-clock'),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: v2.ShiriBrand.sunInk,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        flex: (weights[i] * 100).round(),
                        child: Builder(
                          builder: (context) {
                            final date = widget.firstDay.add(Duration(days: i));
                            // In a weekly overview the highlighted column is
                            // today's actual date, never a remembered weekday.
                            // Tapping a date opens the day view, so there is no
                            // selected-day state to paint on another week.
                            final selected = i == today;
                            return Semantics(
                              button: true,
                              selected: selected,
                              label:
                                  '${date.month}月${date.day}日${i == today ? '，今天' : ''}',
                              child: Material(
                                color: selected
                                    ? CampusColors.blueSoft
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  key: ValueKey(
                                    'calendar-day-${calendarDate(date)}',
                                  ),
                                  onTap: () => widget.onDay?.call(date),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '周${'一二三四五六日'[i]}',
                                          maxLines: 1,
                                          softWrap: false,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            height: 1.2,
                                            color: CampusColors.muted,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${date.day}',
                                          maxLines: 1,
                                          softWrap: false,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            height: 1.2,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (i == today)
                                          const Text(
                                            '今天',
                                            maxLines: 1,
                                            softWrap: false,
                                            style: TextStyle(
                                              fontSize: 11,
                                              height: 1.2,
                                              color: v2.ShiriBrand.sunInk,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: GestureDetector(
                onHorizontalDragEnd: widget.onWeek == null
                    ? null
                    : (details) {
                        if ((details.primaryVelocity ?? 0).abs() < 150) return;
                        final next = widget.firstDay.add(
                          Duration(days: details.primaryVelocity! < 0 ? 7 : -7),
                        );
                        if ((widget.minDay == null ||
                                !next.isBefore(widget.minDay!)) &&
                            (widget.maxDay == null ||
                                !next.isAfter(widget.maxDay!))) {
                          widget.onWeek!(next);
                        }
                      },
                child: SingleChildScrollView(
                  key: const ValueKey('schedule-grid-scroll'),
                  controller: scroll,
                  child: SizedBox(
                    width: box.maxWidth,
                    height: height,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: children,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _GridLines extends CustomPainter {
  final double timeWidth;
  final List<double> dayWidths;
  final TimetableScale scale;
  final List<Map<String, dynamic>> periods;
  final int first, last;
  const _GridLines(
    this.timeWidth,
    this.dayWidths,
    this.scale,
    this.first,
    this.last,
    this.periods,
  );
  @override
  void paint(Canvas canvas, Size size) {
    // Compressed, genuinely unoccupied breaks keep their real clock bounds.
    // A quiet pair of hairlines marks the skipped space without a shaded band.
    for (var i = 1; i < scale.minutes.length; i++) {
      final a = scale.minutes[i - 1], b = scale.minutes[i];
      final top = scale.positions[i - 1], bottom = scale.positions[i];
      if (b - a < 45 || bottom - top > 24) continue;
      final separator = Paint()
        ..color = CampusColors.line.withValues(alpha: .75)
        ..strokeWidth = .6;
      final center = (top + bottom) / 2;
      canvas.drawLine(
        Offset(timeWidth, center - 1.5),
        Offset(size.width, center - 1.5),
        separator,
      );
      canvas.drawLine(
        Offset(timeWidth, center + 1.5),
        Offset(size.width, center + 1.5),
        separator,
      );
    }
    final paint = Paint()
      ..color = CampusColors.line
      ..strokeWidth = .6;
    for (var day = 0; day <= 7; day++) {
      final x =
          timeWidth + dayWidths.take(day).fold<double>(0, (a, b) => a + b);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (final minute
        in periods.isEmpty
            ? [for (var n = first; n <= last; n += 60) n]
            : [for (final p in periods) _clockMinute(p['start']), last]) {
      final y = scale.at(minute);
      for (double x = timeWidth; x < size.width; x += 7) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, size.width), y),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridLines old) =>
      old.timeWidth != timeWidth ||
      old.dayWidths != dayWidths ||
      old.scale != scale ||
      old.first != first ||
      old.last != last;
}

int _clockMinute(dynamic value) {
  final parts = '$value'.split(':');
  return parts.length < 2
      ? 0
      : (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
}
