import 'package:flutter/material.dart';
import 'package:calendar_view/calendar_view.dart' as cv;
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import 'calendar_repository.dart';

class ScheduleGrid extends StatefulWidget {
  final DateTime firstDay;
  final List<Map<String, dynamic>> entries;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final ValueChanged<DateTime>? onDay;
  const ScheduleGrid({
    super.key,
    required this.firstDay,
    required this.entries,
    required this.onOpen,
    this.onDay,
  });
  @override
  State<ScheduleGrid> createState() => _ScheduleGridState();
}

class _Tile {
  final String id;
  final Map<String, dynamic> source;
  _Tile(this.id, this.source);
}

class _ScheduleGridState extends State<ScheduleGrid> {
  final controller = cv.EventController<_Tile>();
  final horizontal = ScrollController();
  int firstHour = 8, lastHour = 20;
  @override
  void initState() {
    super.initState();
    populate();
  }

  DateTime wall(DateTime d) =>
      DateTime(d.year, d.month, d.day, d.hour, d.minute, d.second);
  void populate() {
    final events = <cv.CalendarEventData<_Tile>>[];
    firstHour = 8;
    lastHour = 20;
    for (final entry in widget.entries) {
      for (final segment in calendarGridEntries([entry], widget.firstDay)) {
        final a = wall(schoolTime(segment['start_at'])),
            b = wall(schoolTime(segment['end_at']));
        final date = DateTime(a.year, a.month, a.day);
        firstHour = a.hour < firstHour ? a.hour : firstHour;
        final end = b.day != a.day ? 24 : b.hour + (b.minute > 0 ? 1 : 0);
        lastHour = end > lastHour ? end : lastHour;
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
    controller.removeAll(controller.allEvents.toList());
    controller.addAll(events);
  }

  @override
  void didUpdateWidget(covariant ScheduleGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    populate();
  }

  @override
  void dispose() {
    controller.dispose();
    horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // Seven columns need enough room for Chinese titles and simultaneous events.
      // Horizontal panning moves within this week; outer buttons change weeks.
      final width = box.maxWidth < 700 ? 700.0 : box.maxWidth;
      final scaled = MediaQuery.textScalerOf(context).scale(1);
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Scrollbar(
          controller: horizontal,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: cv.WeekView<_Tile>(
                key: ValueKey(
                  '${calendarDate(widget.firstDay)}/$firstHour/$lastHour',
                ),
                controller: controller,
                initialDay: widget.firstDay,
                minDay: widget.firstDay,
                maxDay: widget.firstDay.add(const Duration(days: 6)),
                width: width,
                heightPerMinute: scaled > 1.3 ? 1.45 : 1.12,
                startHour: firstHour,
                endHour: lastHour,
                pageViewPhysics: const NeverScrollableScrollPhysics(),
                backgroundColor: Colors.white,
                pageTransitionDuration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                weekPageHeaderBuilder: (_, _) => const SizedBox(),
                weekNumberBuilder: (_) => const Center(child: Text('时间', style: TextStyle(fontSize:10,color:CampusColors.muted))),
                weekTitleHeight: 50 * scaled.clamp(1, 2),
                timeLineWidth: 44,
                weekTitleBackgroundColor: const Color(0xFFF0EDFF),
                eventArranger: const cv.SideEventArranger<_Tile>(
                  includeEdges: false,
                ),
                hourIndicatorSettings: const cv.HourIndicatorSettings(
                  color: CampusColors.line,
                  height: 0.7,
                ),
                liveTimeIndicatorSettings: cv.LiveTimeIndicatorSettings(
                  color: CampusColors.primary,
                  showTime: false,
                  currentTimeProvider: () => wall(schoolNow()),
                  onlyShowToday: true,
                ),
                weekDayBuilder: (d) => InkWell(
                  onTap: () => widget.onDay?.call(d),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '周${'一二三四五六日'[d.weekday - 1]}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: CampusColors.muted,
                          ),
                        ),
                        Text(
                          '${d.month}/${d.day}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                timeLineBuilder: (d) => Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Text(
                    hhmm(d),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 10,
                      color: CampusColors.muted,
                    ),
                  ),
                ),
                onEventTap: (events, _) {
                  if (events.isNotEmpty) {
                    widget.onOpen(events.first.event!.source);
                  }
                },
                eventTileBuilder: (date, events, rect, start, end) {
                  final event = events.first;
                  final tile = event.event!;
                  final palette = CoursePalette.forTitle(event.title);
                  return Semantics(
                    label:
                        '${event.title}，${calendarTimeLabel(tile.source)}，${tile.source['location'] ?? ''}',
                    button: true,
                    child: Container(
                      key: ValueKey('schedule-tile-${tile.id}'),
                      margin: const EdgeInsets.fromLTRB(1, 1, 2, 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 5,
                      ),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: palette.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border(
                          left: BorderSide(color: palette.accent, width: 3),
                        ),
                      ),
                      child: LayoutBuilder(
                        builder: (context, bounds) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                              event.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: palette.ink,
                                ),
                              ),
                            ),
                            if (bounds.maxHeight > 64 && bounds.maxWidth > 48)
                              Text(
                                '${tile.source['location'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: palette.ink,
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
                      TextButton(
                        onPressed: () => widget.onOpen(e.event!.source),
                        child: Text(e.title),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
