import 'package:flutter/material.dart';

import '../../ui/app_controls.dart';
import '../../ui/campus_theme.dart';
import '../../ui/app_sheet.dart';
import '../items/item_widgets.dart';

List<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
    : [];

/// Conflicts describe an overlap, never an invented event duration.
List<Map<String, dynamic>> eventConflicts(Map<String, dynamic> impact) =>
    _rows(impact['new_fixed_conflicts'] ?? impact['fixed_conflicts']);

List<Map<String, dynamic>> eventConflictCourses(Map<String, dynamic> impact) {
  final ids = eventConflicts(
    impact,
  ).expand((r) => r['item_ids'] as List? ?? []).toSet();
  return _rows(
    impact['course_conflicts'],
  ).where((r) => ids.contains(r['occurrence_id'])).toList();
}

List<Map<String, dynamic>> unresolvedEventConflicts(
  Map<String, dynamic> impact,
  Set<String> leaveTargets,
) => eventConflicts(impact).where((r) {
  final ids = r['item_ids'] as List? ?? [];
  return ids.isEmpty ||
      ids.where((id) => !leaveTargets.contains(id)).length +
              (r['pending_record'] == true ? 1 : 0) >=
          2;
}).toList();

bool eventConflictIsPossible(Map<String, dynamic> conflict) =>
    conflict['certainty'] == 'possible';

bool _hasUnknownEnd(Map<String, dynamic> conflict) =>
    (conflict['uncertainty_reasons'] as List? ?? []).contains('end_unknown');

/// Shared by assistant previews and manual event editing. Attendance choices
/// stay explicit and refer to individual occurrences, not entire courses.
class EventConflictReview extends StatelessWidget {
  final Map<String, dynamic> impact;
  final Set<String> leaveTargets;
  final bool acknowledged, enabled;
  final void Function(String id, bool selected)? onLeaveChanged;
  final ValueChanged<bool>? onAcknowledged;
  final VoidCallback? onAdjustTime;

  const EventConflictReview({
    super.key,
    required this.impact,
    required this.leaveTargets,
    required this.acknowledged,
    this.enabled = true,
    this.onLeaveChanged,
    this.onAcknowledged,
    this.onAdjustTime,
  });

  @override
  Widget build(BuildContext context) {
    final conflicts = eventConflicts(impact);
    if (conflicts.isEmpty) return const SizedBox.shrink();
    final courses = eventConflictCourses(impact);
    final unresolved = unresolvedEventConflicts(impact, leaveTargets);
    final possible = conflicts.any(eventConflictIsPossible);
    final editable = onAcknowledged != null || onLeaveChanged != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              unresolved.isEmpty && leaveTargets.isNotEmpty
                  ? Icons.check_circle_outline_rounded
                  : Icons.event_busy_rounded,
              color: unresolved.isEmpty && leaveTargets.isNotEmpty
                  ? CampusColors.teal
                  : CampusColors.warning,
              size: 21,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                unresolved.isEmpty && leaveTargets.isNotEmpty
                    ? '已选请假处理'
                    : possible
                    ? '可能有时间冲突'
                    : '有时间冲突',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        if (possible) ...[
          const SizedBox(height: 8),
          Text(
            conflicts.any(_hasUnknownEnd)
                ? '结束时间未明确，以下安排可能受影响。建议补充结束时间后重新核对。'
                : '具体时间尚不完整，以下安排可能受影响。建议补充时间后重新核对。',
          ),
        ],
        const SizedBox(height: 10),
        for (final conflict in conflicts.take(6))
          _ConflictLine(conflict: conflict, courses: courses),
        if (conflicts.length > 6)
          AppDisclosure(
            tilePadding: EdgeInsets.zero,
            title: Text('其余 ${conflicts.length - 6} 处冲突'),
            children: [
              for (final conflict in conflicts.skip(6))
                _ConflictLine(conflict: conflict, courses: courses),
            ],
          ),
        if (courses.isNotEmpty && (!editable || onLeaveChanged == null)) ...[
          const SizedBox(height: 8),
          const Text('涉及课程', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final course in courses)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${course['title']} · ${displayInterval(course['start_at'], course['end_at'])}',
              ),
            ),
        ],
        if (editable) ...[
          const SizedBox(height: 14),
          const Text('先选择处理方式', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            courses.isNotEmpty
                ? onLeaveChanged != null
                      ? '能调整时间时，建议避开课程；必须参加时，先办理对应课次的请假。'
                      : '能调整时间时，建议避开课程；若已办好请假，先在课程详情记录本次已请假，再重新核对。'
                : '建议调整时间，避免同时保留无法兼顾的安排。',
          ),
          if (onAdjustTime != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: AppTextButton.icon(
                onPressed: enabled ? onAdjustTime : null,
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: Text(possible ? '补充或调整时间' : '调整时间重新核对'),
              ),
            ),
          ],
          if (courses.isNotEmpty && onLeaveChanged != null) ...[
            const SizedBox(height: 8),
            const Text(
              '仅勾选已办好请假的课次；准备请假仍保留占用。这里不代办或审批请假。',
              style: TextStyle(fontSize: 13, color: CampusColors.muted),
            ),
            for (final course in courses)
              AppCheckRow(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('${course['title']} · 我已请假'),
                subtitle: Text(
                  displayInterval(course['start_at'], course['end_at']),
                ),
                value: leaveTargets.contains(course['occurrence_id']),
                onChanged: !enabled
                    ? null
                    : (v) => onLeaveChanged!(
                        course['occurrence_id'] as String,
                        v == true,
                      ),
              ),
            if (leaveTargets.isNotEmpty)
              const Text(
                '保存时仅标记所选课次已请假，原课程和其他周次保留。',
                style: TextStyle(fontSize: 13, color: CampusColors.teal),
              ),
          ],
          if (unresolved.isNotEmpty && onAcknowledged != null)
            AppCheckRow(
              contentPadding: EdgeInsets.zero,
              title: const Text('保留这些重叠安排'),
              subtitle: const Text('我已核对并自行处理冲突，课程保持原状态。'),
              value: acknowledged,
              onChanged: !enabled ? null : (v) => onAcknowledged!(v == true),
            ),
        ],
      ],
    );
  }
}

class _ConflictLine extends StatelessWidget {
  final Map<String, dynamic> conflict;
  final List<Map<String, dynamic>> courses;
  const _ConflictLine({required this.conflict, required this.courses});

  bool get courseAtStart {
    final start = DateTime.tryParse('${conflict['event_start_at']}');
    if (start == null) return false;
    final ids = conflict['item_ids'] as List? ?? [];
    return courses.any((course) {
      final a = DateTime.tryParse('${course['start_at']}');
      final b = DateTime.tryParse('${course['end_at']}');
      return ids.contains(course['occurrence_id']) &&
          a != null &&
          b != null &&
          !start.isBefore(a) &&
          start.isBefore(b);
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (conflict['titles'] as List? ?? []).join(' / '),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          eventConflictIsPossible(conflict)
              ? '需核对的时段 · ${displayInterval(conflict['start_at'], conflict['end_at'])}'
              : '重叠时段 · ${displayInterval(conflict['start_at'], conflict['end_at'])}',
          style: const TextStyle(fontSize: 13, color: CampusColors.muted),
        ),
        if (conflict['overlap_at_start'] == true &&
            conflict['event_start_at'] != null)
          Text(
            '日程在 ${displayInstant(conflict['event_start_at'])} 开始时已有${courseAtStart ? '课程' : '安排'}${_hasUnknownEnd(conflict) ? '，结束时间未说明' : ''}。',
          ),
      ],
    ),
  );
}

class EventConflictDecision {
  final bool keepConflicts, adjustTime;
  final List<String> courseLeaveTargets;
  const EventConflictDecision({
    this.keepConflicts = false,
    this.adjustTime = false,
    this.courseLeaveTargets = const [],
  });
}

Future<EventConflictDecision?> confirmEventConflicts(
  BuildContext context,
  Map<String, dynamic> impact,
) => showAppSheet<EventConflictDecision>(
  context: context,
  heightFactor: .85,
  builder: (context) => _EventConflictSheet(impact: impact),
);

class _EventConflictSheet extends StatefulWidget {
  final Map<String, dynamic> impact;
  const _EventConflictSheet({required this.impact});
  @override
  State<_EventConflictSheet> createState() => _EventConflictSheetState();
}

class _EventConflictSheetState extends State<_EventConflictSheet> {
  final leaveTargets = <String>{};
  bool acknowledged = false;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '保存前核对冲突',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: SingleChildScrollView(
            child: EventConflictReview(
              impact: widget.impact,
              leaveTargets: leaveTargets,
              acknowledged: acknowledged,
              onAdjustTime: () => Navigator.pop(
                context,
                const EventConflictDecision(adjustTime: true),
              ),
              onLeaveChanged: (id, value) => setState(() {
                if (value) {
                  leaveTargets.add(id);
                } else {
                  leaveTargets.remove(id);
                }
                acknowledged = false;
              }),
              onAcknowledged: (value) => setState(() => acknowledged = value),
            ),
          ),
        ),
        const SizedBox(height: 16),
        AppButton(
          onPressed:
              unresolvedEventConflicts(
                    widget.impact,
                    leaveTargets,
                  ).isNotEmpty &&
                  !acknowledged
              ? null
              : () => Navigator.pop(
                  context,
                  EventConflictDecision(
                    keepConflicts: acknowledged,
                    courseLeaveTargets: leaveTargets.toList(),
                  ),
                ),
          child: const Text('确认处理并保存'),
        ),
        const SizedBox(height: 8),
        AppTextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回修改'),
        ),
      ],
    ),
  );
}
