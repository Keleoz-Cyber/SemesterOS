import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:calendar_view/calendar_view.dart' as cv;
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import 'calendar_repository.dart';

class ScheduleGrid extends StatefulWidget {
  final DateTime firstDay;
  final DateTime? minDay, maxDay, selectedDay;
  final List<Map<String, dynamic>> entries;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final ValueChanged<DateTime>? onDay, onWeek;
  final bool loading, showHeader, visible;
  final String resourceFilter;
  final int? revision;
  const ScheduleGrid({
    super.key,
    required this.firstDay,
    required this.entries,
    required this.onOpen,
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
  });
  @override
  State<ScheduleGrid> createState() => _ScheduleGridState();
}

class _Tile {
  final String id;
  final Map<String, dynamic> source;
  _Tile(this.id, this.source);
}

class _ScheduleGridState extends State<ScheduleGrid>
    with WidgetsBindingObserver {
  bool active = true, foreground = true;
  double savedOffset = 0, initialOffset = 0;
  final controller = cv.EventController<_Tile>();
  final weekKey = GlobalKey<cv.WeekViewState<_Tile>>();
  final pages = <String, List<Map<String, dynamic>>>{};
  int firstHour = 8, lastHour = 20;
  DateTime wall(DateTime d) =>
      DateTime(d.year, d.month, d.day, d.hour, d.minute, d.second);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    populate();
  }

  void rememberOffset() {
    initialOffset = savedOffset;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = TickerMode.valuesOf(context).enabled;
    if (active && !next) rememberOffset();
    active = next;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) rememberOffset();
    if (mounted) {
      setState(() => foreground = state == AppLifecycleState.resumed);
    }
  }

  void populate() {
    if (!widget.loading) pages[calendarDate(widget.firstDay)] = widget.entries;
    final events = <cv.CalendarEventData<_Tile>>[];
    firstHour = 8;
    lastHour = 20;
    for (final page in pages.entries) {
      final first = DateTime.parse('${page.key}T00:00:00Z');
      for (final entry in page.value.where(
        (r) =>
            widget.resourceFilter == 'all' ||
            r['resource_type'] == widget.resourceFilter,
      )) {
        if (entry['resource_type'] == 'deadline') continue;
        for (final segment in calendarGridEntries([entry], first)) {
          final a = wall(schoolTime(segment['start_at'])),
              b = wall(schoolTime(segment['end_at']));
          if (page.key == calendarDate(widget.firstDay)) {
            firstHour = a.hour < firstHour ? a.hour : firstHour;
            final end = b.day != a.day ? 24 : b.hour + (b.minute > 0 ? 1 : 0);
            lastHour = end > lastHour ? end : lastHour;
          }
          final date = DateTime(a.year, a.month, a.day);
          events.add(
            cv.CalendarEventData<_Tile>(
              date: date,
              endDate: date,
              startTime: a,
              endTime: b,
              title: entry['title'] ?? '日程',
              event: _Tile(segment['id'], entry),
            ),
          );
        }
      }
    }
    controller.removeAll(controller.allEvents.toList());
    controller.addAll(events);
  }

  @override
  void didUpdateWidget(covariant ScheduleGrid old) {
    super.didUpdateWidget(old);
    if (old.visible && !widget.visible) rememberOffset();
    if (old.revision != widget.revision) pages.clear();
    if (old.revision != widget.revision ||
        old.firstDay != widget.firstDay ||
        old.loading != widget.loading ||
        old.resourceFilter != widget.resourceFilter ||
        !listEquals(old.entries, widget.entries)) {
      populate();
    }
    if (old.firstDay != widget.firstDay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final state = weekKey.currentState, date = wall(widget.firstDay);
        if (state != null &&
            calendarDate(state.currentDate) != calendarDate(date)) {
          if (MediaQuery.disableAnimationsOf(context) ||
              !TickerMode.valuesOf(context).enabled) {
            state.jumpToWeek(date);
          } else {
            state.animateToWeek(
              date,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          }
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (!active || !foreground || !widget.visible) {
        return const SizedBox.expand();
      }
      final compact = box.maxWidth < 540,
          scaled = MediaQuery.textScalerOf(context).scale(1);
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis == Axis.vertical) savedOffset = n.metrics.pixels;
            return false;
          },
          child: cv.WeekView<_Tile>(
            key: weekKey,
            controller: controller,
            scrollOffset: initialOffset,
            initialDay: wall(widget.firstDay),
            minDay: wall(widget.minDay ?? widget.firstDay),
            maxDay: wall(
              widget.maxDay ?? widget.firstDay.add(const Duration(days: 6)),
            ),
            width: box.maxWidth,
            heightPerMinute: scaled > 1.3 ? 1.6 : 1.25,
            startHour: firstHour,
            endHour: lastHour,
            onPageChange: (date, _) => widget.onWeek?.call(
              DateTime.utc(date.year, date.month, date.day),
            ),
            pageViewPhysics: widget.onWeek == null
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            pageTransitionDuration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 260),
            backgroundColor: Colors.white,
            weekPageHeaderBuilder: (_, _) => const SizedBox(),
            weekTitleHeight: widget.showHeader ? 84 * scaled.clamp(1, 2) : 0,
            timeLineWidth: compact ? 40 : 52,
            keepScrollOffset: true,
            weekTitleBackgroundColor: Colors.white,
            weekNumberBuilder: (_) => widget.showHeader
                ? const Center(
                    child: Text(
                      '时间',
                      style: TextStyle(fontSize: 11, color: CampusColors.muted),
                    ),
                  )
                : const SizedBox(),
            weekDayBuilder: (d) {
              if (!widget.showHeader) return const SizedBox();
              final today = calendarDate(d) == calendarDate(schoolNow());
              final selected =
                  widget.selectedDay != null &&
                  calendarDate(d) == calendarDate(widget.selectedDay!);
              return Semantics(
                button: true,
                selected: selected,
                label: '${d.month}月${d.day}日${today ? '，今天' : ''}',
                child: InkWell(
                  key: ValueKey('calendar-day-${calendarDate(d)}'),
                  onTap: () => widget.onDay?.call(d),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 2,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? CampusColors.primary
                            : today
                            ? CampusColors.tealSoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '周${'一二三四五六日'[d.weekday - 1]}',
                            style: TextStyle(
                              fontSize: 11,
                              color: selected
                                  ? Colors.white
                                  : CampusColors.muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: selected ? Colors.white : CampusColors.ink,
                            ),
                          ),
                          if (today)
                            Text(
                              '今天',
                              style: TextStyle(
                                fontSize: 11,
                                color: selected
                                    ? Colors.white
                                    : CampusColors.teal,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
            eventArranger: compact
                ? const cv.MergeEventArranger<_Tile>(includeEdges: false)
                : const cv.SideEventArranger<_Tile>(includeEdges: false),
            hourIndicatorSettings: const cv.HourIndicatorSettings(
              color: CampusColors.line,
              height: .6,
            ),
            liveTimeIndicatorSettings: cv.LiveTimeIndicatorSettings(
              color: CampusColors.teal,
              height: 2,
              bulletRadius: 4,
              showTime: true,
              showTimeBackgroundView: true,
              timeBackgroundViewWidth: compact ? 40 : 52,
              currentTimeProvider: () => wall(schoolNow()),
              onlyShowToday: true,
            ),
            timeLineBuilder: (d) => Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Text(
                hhmm(d),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: compact ? 10 : 12,
                  color: CampusColors.muted,
                ),
              ),
            ),
            onEventTap: (events, date) {
              if (events.length > 1 && widget.onDay != null) {
                widget.onDay!(date);
              } else if (events.isNotEmpty) {
                widget.onOpen(events.first.event!.source);
              }
            },
            eventTileBuilder: (date, events, rect, start, end) {
              final event = events.first,
                  tile = event.event!,
                  palette = CoursePalette.forTitle(event.title);
              final type = tile.source['resource_type'];
              final accent = type == 'event'
                  ? CampusColors.teal
                  : type == 'plan'
                  ? CampusColors.primary
                  : type == 'exam'
                  ? CampusColors.warning
                  : palette.accent;
              final background = type == 'event'
                  ? CampusColors.tealSoft
                  : type == 'plan'
                  ? CampusColors.blueSoft
                  : type == 'exam'
                  ? CampusColors.warningSoft
                  : palette.background;
              return Semantics(
                button: true,
                label: events
                    .map(
                      (e) => '${e.title}，${calendarTimeLabel(e.event!.source)}',
                    )
                    .join('；'),
                child: Container(
                  key: ValueKey('schedule-tile-${tile.id}'),
                  margin: const EdgeInsets.fromLTRB(1, 1, 1, 2),
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 3 : 6,
                    vertical: 6,
                  ),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: events.length > 1
                        ? const Color(0xFFFFE6DB)
                        : background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border(left: BorderSide(color: accent, width: 3)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, bounds) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (events.length == 1 &&
                            type != 'course' &&
                            bounds.maxHeight > 74 * scaled)
                          Text(
                            type == 'event'
                                ? '活动'
                                : type == 'plan'
                                ? '计划'
                                : '考试',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            events.length > 1
                                ? '${events.length}项重叠'
                                : event.title,
                            maxLines: compact ? 4 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 11 : 14,
                              fontWeight: FontWeight.w700,
                              color: type == 'course'
                                  ? palette.ink
                                  : CampusColors.ink,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (events.length == 1 &&
                            bounds.maxHeight > 90 * scaled &&
                            bounds.maxWidth > 55)
                          Text(
                            '${tile.source['location'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: CampusColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
            fullDayEventBuilder: (events, date) => Wrap(
              children: [
                for (final e in events)
                  AppTextButton(
                    onPressed: () => widget.onOpen(e.event!.source),
                    child: Text(e.title),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
