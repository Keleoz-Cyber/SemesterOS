import 'package:flutter/material.dart';
import '../../ui/app_controls.dart';
import '../../ui/campus_theme.dart';
import 'insights_controller.dart';

class StudentInsightSummary extends StatelessWidget {
  final Map<String, dynamic> data;
  final ValueChanged<String> onDate;
  const StudentInsightSummary({
    super.key,
    required this.data,
    required this.onDate,
  });
  @override
  Widget build(BuildContext context) {
    final activity = Map<String, dynamic>.from(data['task_activity'] ?? {});
    final tasks = activity.isNotEmpty
        ? activity
        : Map<String, dynamic>.from(
            data['task_summary'] ?? data['summary']?['tasks'] ?? {},
          );
    final courses = insightRows(data['course_summary']);
    final deadlines = <String, int>{};
    for (final r in insightRows(data['records'])) {
      if (r['resource_type'] != 'deadline' || r['lifecycle'] != 'active') {
        continue;
      }
      final date = '${r['date'] ?? r['due_at'] ?? ''}';
      if (date.length >= 10) {
        deadlines.update(
          date.substring(0, 10),
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final dates = deadlines.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tasks.isNotEmpty) ...[
          Text(
            activity.isNotEmpty
                ? '任务完成情况'
                : '${tasks['scope_label'] ?? '范围内任务状态'}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final e in [
                (
                  activity.isNotEmpty ? 'completed_in_range' : 'completed',
                  activity.isNotEmpty ? '期间完成' : '已完成',
                  CampusColors.teal,
                ),
                (
                  activity.isNotEmpty ? 'active_current' : 'active',
                  activity.isNotEmpty ? '当前待办' : '待完成',
                  CampusColors.primary,
                ),
                (
                  activity.isNotEmpty ? 'overdue_current' : 'overdue',
                  activity.isNotEmpty ? '当前逾期' : '已逾期',
                  CampusColors.error,
                ),
              ])
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${tasks[e.$1] ?? 0}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: e.$3,
                        ),
                      ),
                      Text(
                        e.$2,
                        style: const TextStyle(
                          fontSize: 13,
                          color: CampusColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const Divider(height: 32, color: CampusColors.line),
        ],
        if (dates.isNotEmpty) ...[
          const Text(
            '截止分布',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final date in dates)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () => onDate(date),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 64,
                          minHeight: 70,
                        ),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: deadlines[date]! > 1
                              ? CampusColors.warningSoft
                              : CampusColors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${DateTime.parse(date).month}/${DateTime.parse(date).day}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: CampusColors.muted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${deadlines[date]}项',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
        ],
        if (dates.isEmpty && tasks.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              '所选日期内没有已记录的截止事项',
              style: TextStyle(fontSize: 13, color: CampusColors.muted),
            ),
          ),
        if (courses.isNotEmpty) ...[
          AppDisclosure(
            title: Text('课程时间 · ${courses.length}门'),
            tilePadding: EdgeInsets.zero,
            children: [
              for (final r in courses)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r['title']}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if ((r['course_scheduled_minutes'] as num? ?? 0) > 0 ||
                          (r['personal_planned_minutes'] as num? ?? 0) > 0 ||
                          r['actual_minutes'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          [
                            if ((r['course_scheduled_minutes'] as num? ?? 0) >
                                0)
                              '上课 ${insightHours(r['course_scheduled_minutes'])}',
                            if ((r['personal_planned_minutes'] as num? ?? 0) >
                                0)
                              '学习安排 ${insightHours(r['personal_planned_minutes'])}',
                            if (r['actual_minutes'] != null)
                              '实际记录 ${insightHours(r['actual_minutes'])}',
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 13,
                            color: CampusColors.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
          const Divider(height: 28, color: CampusColors.line),
        ],
      ],
    );
  }
}
