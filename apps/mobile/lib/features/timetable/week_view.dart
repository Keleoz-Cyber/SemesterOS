import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';
import 'course_widgets.dart';
import 'timetable_layout.dart';

class WeekView extends StatelessWidget {
  final Map<String, dynamic> semester;
  final List<Map<String, dynamic>> events;
  final DateTime now;
  final int week;
  final bool grid, hasData;
  final void Function(bool) onMode;
  final void Function(int) onWeek;
  final VoidCallback onCurrent, onImport;
  final void Function(Map<String, dynamic>) onCourse;
  const WeekView({
    super.key,
    required this.semester,
    required this.events,
    required this.now,
    required this.week,
    required this.grid,
    required this.hasData,
    required this.onMode,
    required this.onWeek,
    required this.onCurrent,
    required this.onImport,
    required this.onCourse,
  });

  @override
  Widget build(BuildContext context) {
    final start = DateTime.parse(
      semester['first_monday'],
    ).add(Duration(days: (week - 1) * 7));
    final end = start.add(const Duration(days: 6));
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final showGrid = grid && !largeText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampusHero(
          eyebrow: '${semester['name']}',
          title: '本周课表',
          subtitle: '${start.month}月${start.day}日—${end.month}月${end.day}日',
        ),
        const SizedBox(height: 17),
        CampusPanel(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Row(
            children: [
              IconButton(
                onPressed: week > 1 ? () => onWeek(week - 1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: '上一周',
              ),
              Expanded(
                child: InkWell(
                  onTap: onCurrent,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Text(
                        '第 $week 周',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: week < semester['total_weeks']
                    ? () => onWeek(week + 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: '下一周',
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: Text(
                hasData
                    ? '${events.length}次课程 · ${events.map((e) => e['weekday']).toSet().length}天有课'
                    : '等待同步课表',
                style: const TextStyle(fontSize: 13, color: CampusColors.muted),
              ),
            ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: true,
                  label: const Text('周视图'),
                  enabled: !largeText,
                ),
                const ButtonSegment(value: false, label: Text('日程')),
              ],
              selected: {showGrid},
              onSelectionChanged: (v) => onMode(v.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(
                  Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (largeText) ...[
          const SoftNotice('已按较大字号显示日程列表，完整保留课程信息。'),
          const SizedBox(height: 14),
        ],
        if (!hasData)
          EmptyPanel(
            title: '这周课表待同步',
            message: '当前没有可用缓存，联网后再试。',
            action: '回到当前周',
            onAction: onCurrent,
          )
        else if (events.isEmpty)
          EmptyPanel(
            title: '这一周还没有课程',
            message: '可以切换周次，或导入学校课表。',
            action: '导入课表',
            onAction: onImport,
          )
        else if (showGrid) ...[
          TimetableGrid(
            semester: semester,
            week: week,
            events: events,
            now: now,
            onCourse: onCourse,
          ),
          const SizedBox(height: 10),
          const Text(
            '左右滑动查看完整七天 · 点击课程查看详情',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: CampusColors.muted),
          ),
        ] else
          for (var day = 1; day <= 7; day++)
            if (events.any((e) => e['weekday'] == day)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
                child: Text(
                  '周${'一二三四五六日'[day - 1]}  ${start.add(Duration(days: day - 1)).month}/${start.add(Duration(days: day - 1)).day}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              for (final event in events.where((e) => e['weekday'] == day)) ...[
                CourseCard(
                  event: event,
                  now: now,
                  onTap: () => onCourse(event),
                ),
                const SizedBox(height: 12),
              ],
            ],
        if (hasData && events.any((e) => e['conflict'] == true)) ...[
          const SizedBox(height: 14),
          const SoftNotice('存在重叠课程，已并列显示。请点击课程核对原始安排。', warning: true),
        ],
      ],
    );
  }
}

class TimetableGrid extends StatelessWidget {
  final Map<String, dynamic> semester;
  final int week;
  final List<Map<String, dynamic>> events;
  final DateTime now;
  final void Function(Map<String, dynamic>) onCourse;
  const TimetableGrid({
    super.key,
    required this.semester,
    required this.week,
    required this.events,
    required this.now,
    required this.onCourse,
  });

  @override
  Widget build(BuildContext context) {
    final periods = List<Map<String, dynamic>>.from(semester['periods']);
    final begin = events.fold<int>(
      int.parse(periods.first['start'].split(':')[0]),
      (value, e) => math.min(value, schoolTime(e['start_at']).hour),
    );
    final end = events
        .fold<int>(int.parse(periods.last['end'].split(':')[0]) + 1, (
          value,
          e,
        ) {
          final a = schoolTime(e['start_at']), b = schoolTime(e['end_at']);
          return math.max(
            value,
            a.day != b.day ? 24 : b.hour + (b.minute > 0 ? 1 : 0),
          );
        })
        .clamp(begin + 1, 24);
    const scale = .85;
    final height = (end - begin) * 60.0 * scale;
    final start = DateTime.parse(
      semester['first_monday'],
    ).add(Duration(days: (week - 1) * 7));
    final today = schoolTime(now.toIso8601String());
    final days = List.generate(
      7,
      (i) => arrangeDayCourses(
        events.where((e) => e['weekday'] == i + 1).toList(),
      ),
    );
    final lanes = days
        .expand((e) => e)
        .fold<int>(1, (n, p) => math.max(n, p.laneCount));
    return LayoutBuilder(
      builder: (context, bounds) {
        final width = math.max(56.0 * lanes, (bounds.maxWidth - 32) / 7);
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: CampusColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    const SizedBox(
                      height: 60,
                      child: Center(
                        child: Text(
                          '时间',
                          style: TextStyle(
                            fontSize: 10,
                            color: CampusColors.muted,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: height,
                      child: Stack(
                        children: [
                          for (var hour = begin; hour < end; hour++)
                            Positioned(
                              top: (hour - begin) * 60 * scale + 4,
                              left: 2,
                              child: Text(
                                '${hour.toString().padLeft(2, '0')}:00',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: CampusColors.muted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(7, (day) {
                      final date = start.add(Duration(days: day));
                      final selected =
                          date.year == today.year &&
                          date.month == today.month &&
                          date.day == today.day;
                      return SizedBox(
                        width: width,
                        child: Column(
                          children: [
                            Container(
                              height: 60,
                              width: width,
                              color: selected
                                  ? const Color(0xFFF0EEFF)
                                  : day >= 5
                                  ? const Color(0xFFF8FAFD)
                                  : Colors.white,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '周${'一二三四五六日'[day]}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? CampusColors.primary
                                          : CampusColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${date.month}/${date.day}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: selected
                                          ? CampusColors.primary
                                          : CampusColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              height: height,
                              decoration: BoxDecoration(
                                color: day >= 5
                                    ? const Color(0xFFFBFCFE)
                                    : Colors.white,
                                border: const Border(
                                  left: BorderSide(
                                    color: CampusColors.line,
                                    width: .7,
                                  ),
                                ),
                              ),
                              child: Stack(
                                children: [
                                  for (var hour = begin; hour < end; hour++)
                                    Positioned(
                                      top: (hour - begin) * 60 * scale,
                                      left: 0,
                                      right: 0,
                                      child: const Divider(
                                        height: 1,
                                        thickness: .7,
                                      ),
                                    ),
                                  for (final placed in days[day])
                                    Positioned(
                                      top:
                                          ((schoolTime(placed.event['start_at'])
                                                          .hour -
                                                      begin) *
                                                  60 +
                                              schoolTime(
                                                placed.event['start_at'],
                                              ).minute) *
                                          scale,
                                      left:
                                          placed.lane *
                                              width /
                                              placed.laneCount +
                                          2,
                                      width: width / placed.laneCount - 4,
                                      height:
                                          DateTime.parse(placed.event['end_at'])
                                              .difference(
                                                DateTime.parse(
                                                  placed.event['start_at'],
                                                ),
                                              )
                                              .inMinutes *
                                          scale,
                                      child: _GridCourse(
                                        placement: placed,
                                        onTap: () => onCourse(placed.event),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GridCourse extends StatelessWidget {
  final CoursePlacement placement;
  final VoidCallback onTap;
  const _GridCourse({required this.placement, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final event = placement.event;
    final palette = CoursePalette.forTitle('${event['title']}');
    final conflict = placement.laneCount > 1 || event['conflict'] == true;
    return Semantics(
      button: true,
      label:
          '${event['title']} ${courseTime(event)} ${event['location']}${conflict ? '，时间冲突' : ''}',
      child: Material(
        color: palette.background,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: conflict ? const Color(0xFFD66D66) : palette.accent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
            child: LayoutBuilder(
              builder: (_, bounds) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${event['title']}',
                      maxLines: bounds.maxHeight > 75
                          ? 4
                          : bounds.maxHeight > 48
                          ? 3
                          : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: palette.ink,
                      ),
                    ),
                  ),
                  if (bounds.maxHeight >= 65)
                    Text(
                      '${event['location']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: palette.ink),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
