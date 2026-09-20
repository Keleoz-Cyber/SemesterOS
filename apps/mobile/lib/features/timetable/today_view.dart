import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';
import 'course_widgets.dart';

class TodayView extends StatelessWidget {
  final Map<String, dynamic> semester;
  final List<Map<String, dynamic>> events;
  final DateTime now;
  final int week;
  final bool hasData;
  final VoidCallback onTimetable, onImport, onManual;
  final void Function(Map<String, dynamic>) onCourse;
  const TodayView({
    super.key,
    required this.semester,
    required this.events,
    required this.now,
    required this.week,
    required this.hasData,
    required this.onTimetable,
    required this.onImport,
    required this.onManual,
    required this.onCourse,
  });

  @override
  Widget build(BuildContext context) {
    final local = schoolTime(now.toIso8601String());
    final today = events.where((e) {
      final d = schoolTime(e['start_at']);
      return d.year == local.year &&
          d.month == local.month &&
          d.day == local.day;
    }).toList();
    final remaining = today
        .where((e) => DateTime.parse(e['end_at']).isAfter(now))
        .toList();
    final counts = List.generate(
      7,
      (i) => events.where((e) => e['weekday'] == i + 1).length,
    );
    final maxCount = counts.fold<int>(1, (a, b) => a > b ? a : b);
    Widget metric(String value, String label, IconData icon, Color color) =>
        Expanded(
          child: CampusPanel(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: CampusColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampusHero(
          eyebrow:
              '${local.month}月${local.day}日 · 周${'一二三四五六日'[local.weekday - 1]}',
          title: '今天的安排',
          subtitle: '第$week周\n把时间留给重要的事',
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            metric(
              hasData ? '${today.length}' : '—',
              '今日课次',
              Icons.calendar_today_outlined,
              CampusColors.primary,
            ),
            const SizedBox(width: 12),
            metric(
              hasData ? '${remaining.length}' : '—',
              '尚未结束',
              Icons.schedule_rounded,
              const Color(0xFF328774),
            ),
          ],
        ),
        SectionHeading('固定安排', action: '完整课表', onAction: onTimetable),
        if (!hasData)
          EmptyPanel(
            title: '课表还没有加载',
            message: '联网同步后，就能看到这周的课程。',
            action: '查看周课表',
            onAction: onTimetable,
          )
        else if (today.isEmpty)
          EmptyPanel(
            title: '今天没有已记录的课程',
            message: '给自己留一点从容，也可以提前看看本周安排。',
            action: '查看周课表',
            onAction: onTimetable,
            icon: Icons.wb_sunny_outlined,
          )
        else
          for (final event in today) ...[
            CourseCard(event: event, now: now, onTap: () => onCourse(event)),
            const SizedBox(height: 12),
          ],
        const SectionHeading('这一周'),
        CampusPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hasData ? '${events.length}次课程安排' : '课次分布待同步',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  StatusPill('第$week周'),
                ],
              ),
              const SizedBox(height: 7),
              const Text(
                '按当前周课表统计',
                style: TextStyle(fontSize: 12, color: CampusColors.muted),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(
                  7,
                  (i) => Expanded(
                    child: Semantics(
                      label:
                          '周${'一二三四五六日'[i]}${hasData ? '${counts[i]}次课程' : '待同步'}',
                      child: Column(
                        children: [
                          Text(
                            hasData ? '${counts[i]}' : '—',
                            style: const TextStyle(
                              fontSize: 12,
                              color: CampusColors.muted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: hasData ? 8 + counts[i] / maxCount * 32 : 8,
                            width: 20,
                            decoration: BoxDecoration(
                              color: i + 1 == local.weekday
                                  ? CampusColors.primary
                                  : const Color(0xFFE8E7FB),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            '一二三四五六日'[i],
                            style: const TextStyle(
                              fontSize: 12,
                              color: CampusColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SectionHeading('快捷入口'),
        Row(
          children: [
            Expanded(
              child: _QuickAction(
                icon: Icons.cloud_download_outlined,
                title: '导入课表',
                subtitle: '连接学校教务',
                onTap: onImport,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickAction(
                icon: Icons.edit_calendar_outlined,
                title: '补充课程',
                subtitle: '手工核对添加',
                onTap: onManual,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(19),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: CampusColors.primary, size: 24),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: CampusColors.muted),
            ),
          ],
        ),
      ),
    ),
  );
}
