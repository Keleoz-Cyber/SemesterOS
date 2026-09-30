import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';
import 'timetable_layout.dart';

String courseTime(Map<String, dynamic> event) =>
    '${hhmm(schoolTime(event['start_at']))}—${hhmm(schoolTime(event['end_at']))}';
String courseState(Map<String, dynamic> event, DateTime now) {
  final start = DateTime.parse(event['start_at']),
      end = DateTime.parse(event['end_at']);
  if (!now.isBefore(end)) return '已结束';
  if (!now.isBefore(start)) return '进行中';
  return start.difference(now).inMinutes <= 30 ? '即将开始' : '待开始';
}

class CourseCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final DateTime now;
  final VoidCallback onTap;
  final bool showStatus;
  const CourseCard({
    super.key,
    required this.event,
    required this.now,
    required this.onTap,
    this.showStatus = true,
  });
  @override
  Widget build(BuildContext context) {
    final palette = CoursePalette.forTitle('${event['title']}');
    final conflict = event['conflict'] == true;
    return Material(
      color: palette.background,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: palette.accent, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    courseTime(event),
                    style: TextStyle(
                      fontSize: 14,
                      color: palette.ink,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (conflict)
                    const StatusPill(
                      '时间冲突',
                      foreground: CampusColors.error,
                      background: CampusColors.errorSoft,
                    )
                  else if (showStatus)
                    Text(
                      courseState(event, now),
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${event['title']}',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: CampusColors.ink,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: palette.ink,
                  ),
                ],
              ),
              if ('${event['location'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '${event['location']}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: CampusColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showCourseDetails(
  BuildContext context,
  Map<String, dynamic> event,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) {
    final palette = CoursePalette.forTitle('${event['title']}');
    Widget detail(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: CampusColors.muted),
          const SizedBox(width: 12),
          SizedBox(
            width: 54,
            child: Text(
              label,
              style: const TextStyle(color: CampusColors.muted, fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(
              event['reality_kind'] == 'activity' ? '固定活动' : '固定课程',
              icon: Icons.school_outlined,
              foreground: palette.ink,
              background: palette.background,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${event['title']}',
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          CampusPanel(
            child: Column(
              children: [
                detail(
                  Icons.today_outlined,
                  '日期',
                  '${event['start_at']}'.substring(0, 10),
                ),
                detail(Icons.schedule_rounded, '时间', courseTime(event)),
                if ('${event['location'] ?? ''}'.trim().isNotEmpty)
                  detail(Icons.place_outlined, '地点', '${event['location']}'),
                if ('${event['teacher'] ?? ''}'.trim().isNotEmpty)
                  detail(
                    Icons.person_outline_rounded,
                    '教师',
                    '${event['teacher']}',
                  ),
                if (event['changed'] == true ||
                    (event['weeks'] as List? ?? []).isNotEmpty)
                  detail(
                    Icons.date_range_outlined,
                    '周次',
                    event['changed'] == true
                        ? '本次已确认的安排'
                        : compactWeeks(event['weeks'] as List),
                  ),
                if ((event['sections'] as List? ?? []).isNotEmpty)
                  detail(
                    Icons.view_agenda_outlined,
                    '节次',
                    (event['sections'] as List).isEmpty
                        ? '以起止时刻为准'
                        : '第${(event['sections'] as List).join('、')}节',
                  ),
              ],
            ),
          ),
          if (event['conflict'] == true) ...[
            const SizedBox(height: 14),
            const SoftNotice('这次课程与另一项安排重叠，请核对原始课表。', warning: true),
          ],
          const SizedBox(height: 18),
          const Text(
            '学校的固定安排不会被个人规划自动移动。',
            style: TextStyle(fontSize: 13, color: CampusColors.muted),
          ),
          const SizedBox(height: 18),
          AppButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回课表'),
          ),
        ],
      ),
    );
  },
);
