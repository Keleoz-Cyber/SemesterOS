import 'package:flutter/material.dart';
import '../../app/controller.dart' show schoolTime, hhmm;
import '../../ui/app_controls.dart';
import '../items/task_surfaces.dart';
import '../../ui/campus_theme.dart';
import '../../ui/date_labels.dart';

List<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
    : const [];

/// The same course change arrives as a hub row, a manual preview, or an agent
/// preview. Keep those wire shapes out of the student-facing presentation.
class CourseChangeDisplay {
  final Map<String, dynamic> value;
  late final request = Map<String, dynamic>.from(value['request'] ?? value);
  late final patch = Map<String, dynamic>.from(value['patch'] ?? value);
  late final before = _rows(patch['before']);
  late final after = _rows(patch['after']);
  late final String kind = '${request['action'] ?? request['kind'] ?? ''}';
  CourseChangeDisplay(this.value);

  bool get suspension => kind == 'suspend' || kind == 'cancel';
  bool get restoration => kind == 'undo' || kind == 'restore';
  bool get attendance => {'leave', 'plan_leave', 'attend'}.contains(kind);
  String get action => switch (kind) {
    'suspend' || 'cancel' => '停课',
    'move' => '调课',
    'add' => '补课',
    'leave' => '已请假',
    'plan_leave' => '准备请假',
    'attend' => '恢复上课',
    'undo' || 'restore' => '恢复原安排',
    'block' => '活动调整',
    _ => '安排调整',
  };
  IconData get icon => suspension
      ? Icons.event_busy_outlined
      : restoration
      ? Icons.restore_rounded
      : Icons.swap_horiz_rounded;
  String get title {
    final title = '${request['title'] ?? ''}'
        .replaceFirst(RegExp(r'^撤销[：:]\s*'), '')
        .trim();
    return {'课程停课', '停课', '课程变更', '课次调整', '已请假课程', '课程听课状态'}.contains(title)
        ? ''
        : title;
  }

  String get source => '${request['source_text'] ?? ''}'.trim();
  List<Map<String, dynamic>> get affected => suspension ? before : after;
  String get scope {
    final rows = affected.isEmpty ? before : affected;
    final dates =
        rows
            .map((e) => _instant(e['start_at']))
            .whereType<DateTime>()
            .map((d) => DateTime(d.year, d.month, d.day))
            .toSet()
            .toList()
          ..sort();
    if (dates.isEmpty) return '';
    if (dates.length == 1) return studentDate(dates.first, weekday: true);
    return '${studentDate(dates.first)}—${studentDate(dates.last)}';
  }

  String get countLabel => suspension
      ? '停课 ${before.length} 次'
      : restoration
      ? '恢复 ${after.length} 次课'
      : kind == 'leave'
      ? '已请假 ${after.length} 次课'
      : kind == 'plan_leave'
      ? '待请假 ${after.length} 次课'
      : kind == 'attend'
      ? '恢复 ${after.length} 次课'
      : '涉及 ${before.isNotEmpty ? before.length : after.length} 次';
}

DateTime? _instant(dynamic value) {
  final raw = '${value ?? ''}'.trim();
  if (DateTime.tryParse(raw) == null) return null;
  return schoolTime(raw);
}

String _time(Map<String, dynamic> entry) {
  final start = _instant(entry['start_at']);
  final end = _instant(entry['end_at']);
  if (start == null) return '';
  final sameDay =
      end != null &&
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  return '${studentDate(start, weekday: true)} ${hhmm(start)}'
      '${end == null
          ? ''
          : sameDay
          ? '–${hhmm(end)}'
          : '—${studentDate(end)} ${hhmm(end)}'}';
}

/// A compact ledger entry: range/count first; individual lessons and the
/// original notice are disclosed only when requested. No repeated "原：" dump.
class CourseChangeSummary extends StatelessWidget {
  final Map<String, dynamic> change;
  final bool showTitle, showSource;
  final VoidCallback? onOpen;
  const CourseChangeSummary({
    super.key,
    required this.change,
    this.showTitle = true,
    this.showSource = true,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final data = CourseChangeDisplay(change);
    final many = data.before.length > 1 || data.after.length > 1;
    final lessonDetails = many || data.suspension && data.before.isNotEmpty;
    final hasDetails = lessonDetails || (showSource && data.source.isNotEmpty);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(data.icon, size: 20, color: CampusColors.teal),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.action,
                        style: const TextStyle(
                          fontSize: 13,
                          color: CampusColors.teal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (data.title.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          data.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: CampusColors.ink,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onOpen != null)
                  AppIconButton(
                    onPressed: onOpen,
                    tooltip: '查看变更记录',
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (data.suspension || many || data.attendance)
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (data.scope.isNotEmpty)
                  Text(
                    data.scope,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: CampusColors.ink,
                    ),
                  ),
                Text(
                  data.countLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    color: CampusColors.teal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else
            CourseChangeComparison(data: data),
          if (data.attendance) ...[
            const SizedBox(height: 8),
            Text(
              data.kind == 'leave'
                  ? '原课程保留，本次不再占用时间。'
                  : data.kind == 'plan_leave'
                  ? '尚未请假，课程继续占用时间。'
                  : '恢复本次课程的时间占用。',
              style: const TextStyle(fontSize: 14, color: CampusColors.muted),
            ),
          ],
          if (hasDetails)
            AppDisclosure(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              title: Text(
                lessonDetails
                    ? '查看 ${data.before.length > data.after.length ? data.before.length : data.after.length} 次课'
                    : '查看通知',
                style: const TextStyle(fontSize: 14, color: CampusColors.muted),
              ),
              children: [
                if (lessonDetails)
                  CourseChangeComparison(data: data, showCourse: true),
                if (showSource && data.source.isNotEmpty) ...[
                  if (lessonDetails) const SizedBox(height: 16),
                  const Text(
                    '通知内容',
                    style: TextStyle(fontSize: 13, color: CampusColors.muted),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    data.source,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: CampusColors.ink,
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class CourseChangeComparison extends StatelessWidget {
  final CourseChangeDisplay data;
  final bool showCourse;
  const CourseChangeComparison({
    super.key,
    required this.data,
    this.showCourse = false,
  });
  @override
  Widget build(BuildContext context) {
    if (data.attendance) {
      return CourseChangeOccurrences(
        entries: data.after,
        label: data.action,
        showCourse: showCourse,
      );
    }
    if (data.before.length == 1 &&
        data.after.length == 1 &&
        !showCourse &&
        _time(data.before.first).isNotEmpty &&
        _time(data.after.first).isNotEmpty) {
      return TaskChangeFacts(
        beforeLabel: '原安排',
        afterLabel: data.restoration ? '恢复后' : '新安排',
        before: _time(data.before.first),
        after: _time(data.after.first),
        beforeDetail: '${data.before.first['location'] ?? ''}',
        afterDetail: '${data.after.first['location'] ?? ''}',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.before.isNotEmpty)
          CourseChangeOccurrences(
            entries: data.before,
            label: data.suspension ? '' : '原安排',
            showCourse: showCourse,
          ),
        if (data.before.isNotEmpty && data.after.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Icon(
                Icons.arrow_downward_rounded,
                size: 18,
                color: CampusColors.teal,
              ),
            ),
          ),
        if (data.after.isNotEmpty)
          CourseChangeOccurrences(
            entries: data.after,
            label: data.restoration
                ? '恢复后'
                : data.before.isEmpty
                ? '上课安排'
                : '新安排',
            showCourse: showCourse,
            accent: true,
          ),
      ],
    );
  }
}

/// Date headings are shown once, even for a whole week of cancelled lessons.
class CourseChangeOccurrences extends StatelessWidget {
  final List<Map<String, dynamic>> entries;
  final String label;
  final bool showCourse, accent;
  const CourseChangeOccurrences({
    super.key,
    required this.entries,
    this.label = '',
    this.showCourse = true,
    this.accent = false,
  });
  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    final ordered = [...entries]
      ..sort(
        (a, b) => '${a['start_at'] ?? ''}'.compareTo('${b['start_at'] ?? ''}'),
      );
    for (final entry in ordered) {
      final date = _instant(entry['start_at']);
      final day = date == null ? '' : studentDate(date, weekday: true);
      groups.putIfAbsent(day, () => []).add(entry);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: CampusColors.muted),
          ),
          const SizedBox(height: 6),
        ],
        if (entries.length == 1) ...[
          if (showCourse && '${entries.first['title'] ?? ''}'.trim().isNotEmpty)
            Text(
              '${entries.first['title']}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          if (_time(entries.first).isNotEmpty)
            Text(
              _time(entries.first),
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: accent ? CampusColors.teal : CampusColors.muted,
              ),
            ),
          if ('${entries.first['location'] ?? ''}'.trim().isNotEmpty)
            Text(
              '${entries.first['location']}',
              style: const TextStyle(fontSize: 14, color: CampusColors.muted),
            ),
        ] else
          for (final group in groups.entries) ...[
            if (group.key.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  group.key,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            for (final entry in group.value)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_instant(entry['start_at'])
                        case final DateTime start) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hhmm(start),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: accent
                                  ? CampusColors.teal
                                  : CampusColors.muted,
                            ),
                          ),
                          if (_instant(entry['end_at']) case final DateTime end)
                            Text(
                              hhmm(end),
                              style: const TextStyle(
                                fontSize: 12,
                                color: CampusColors.muted,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ('${entry['title'] ?? ''}'.trim().isNotEmpty)
                            Text(
                              '${entry['title']}',
                              style: const TextStyle(fontSize: 14, height: 1.4),
                            ),
                          if ('${entry['location'] ?? ''}'.trim().isNotEmpty)
                            Text(
                              '${entry['location']}',
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
              ),
          ],
      ],
    );
  }
}
