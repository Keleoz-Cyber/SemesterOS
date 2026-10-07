import '../../ui/app_sheet.dart';
import '../centers/academic_visuals.dart';
import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/app_number_picker.dart' show formatNumberSelection;
import '../../ui/date_labels.dart' show studentDate;
import 'timetable_layout.dart';

String courseTitle(Map<String, dynamic> event) {
  final title = '${event['title'] ?? ''}';
  if (event['attendance_status'] == 'leave') return '已请假 · $title';
  if (event['attendance_status'] == 'plan_leave') return '待请假 · $title';
  return event['attendance_exempt'] == true && !title.contains('免听')
      ? '免听 · $title'
      : title;
}

String courseTime(Map<String, dynamic> event) =>
    '${hhmm(schoolTime(event['start_at']))}—${hhmm(schoolTime(event['end_at']))}';
Future<void> showCourseDetails(
  BuildContext context,
  Map<String, dynamic> event,
) => showAppSheet<void>(
  context: context,
  builder: (context) {
    final palette = CoursePalette.forTitle('${event['title']}');
    Widget detail(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final caption = Text(
            label,
            style: const TextStyle(color: CampusColors.muted, fontSize: 14),
          );
          final content = Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          );
          if (bounds.maxWidth < 300 &&
              MediaQuery.textScalerOf(context).scale(1) > 1.3) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: CampusColors.muted),
                    const SizedBox(width: 8),
                    caption,
                  ],
                ),
                const SizedBox(height: 6),
                content,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: CampusColors.muted),
              const SizedBox(width: 12),
              SizedBox(width: 54, child: caption),
              const SizedBox(width: 8),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AcademicRecordHeading(
            label: event['reality_kind'] == 'activity' ? '固定活动' : '固定课程',
            title: courseTitle(event),
            icon: Icons.school_outlined,
            color: palette.ink,
          ),
          Column(
            children: [
              detail(
                Icons.today_outlined,
                '日期',
                studentDate(schoolTime(event['start_at']), weekday: true),
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
                  formatNumberSelection(
                    (event['sections'] as List).cast<int>(),
                    unit: '节',
                  ),
                ),
            ],
          ),
          if (event['conflict'] == true) ...[
            const SizedBox(height: 14),
            const SoftNotice('这次课程与另一项安排重叠，请核对原始课表。', warning: true),
          ],
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
