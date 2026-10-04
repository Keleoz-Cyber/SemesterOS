import '../../ui/app_controls.dart';
import '../../ui/app_picker_field.dart';
import '../../ui/app_number_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../../core/api.dart' show userError;
import '../items/items_controller.dart';
import 'preview.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/campus_theme.dart';
import '../centers/academic_visuals.dart';

class ManualPage extends StatefulWidget {
  final AppController? controller;
  final ItemsController? items;
  final Map<String, dynamic>? existing;
  final int? revision;
  final String? courseId;
  final Map<String, dynamic>? semester;
  const ManualPage({super.key, required AppController this.controller})
    : items = null,
      existing = null,
      revision = null,
      courseId = null,
      semester = null;
  const ManualPage.edit({
    super.key,
    required ItemsController this.items,
    required this.existing,
    required this.revision,
    required this.courseId,
    this.semester,
  }) : controller = null;
  @override
  State<ManualPage> createState() => _ManualPageState();
}

class _ManualPageState extends State<ManualPage> {
  late final TextEditingController title, teacher, location;
  late List<int> weeks, sections;
  int weekday = 1;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final course = widget.existing;
    title = TextEditingController(text: '${course?['title'] ?? ''}');
    teacher = TextEditingController(text: '${course?['teacher'] ?? ''}');
    location = TextEditingController(text: '${course?['location'] ?? ''}');
    weeks = List<int>.from(course?['weeks'] ?? []);
    sections = List<int>.from(course?['sections'] ?? []);
    weekday = course?['weekday'] as int? ?? 1;
  }

  @override
  void dispose() {
    for (final c in [title, teacher, location]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic>? get semester =>
      widget.semester ?? widget.controller?.semester;
  List<int> get weekOptions => List.generate(
    (semester?['total_weeks'] as int?) ??
        (weeks.isEmpty ? 20 : weeks.reduce((a, b) => a > b ? a : b)),
    (i) => i + 1,
  );
  List<Map<String, dynamic>> get periods =>
      List<Map<String, dynamic>>.from(semester?['periods'] ?? []);
  List<int> get sectionOptions => <int>{
    for (final period in periods) period['number'] as int,
    // An imported course can carry its own real clock range even when the
    // semester's bell schedule has fewer periods. Keep those existing slots.
    if (widget.existing?['start_time'] != null || semester == null) ...sections,
  }.toList()..sort();

  String? get clockSummary {
    final before = widget.existing;
    if (before != null && _sameNumbers(sections, before['sections'])) {
      if (before['start_time'] != null && before['end_time'] != null) {
        return '${before['start_time']}–${before['end_time']}';
      }
    }
    final chosen = periods.where((p) => sections.contains(p['number'])).toList()
      ..sort((a, b) => (a['number'] as int).compareTo(b['number'] as int));
    if (chosen.isEmpty || chosen.length != sections.length) return null;
    return '${chosen.first['start']}–${chosen.last['end']}';
  }

  bool _sameNumbers(List<int> values, dynamic other) {
    final previous = List<int>.from(other ?? []);
    return values.length == previous.length &&
        values.toSet().containsAll(previous);
  }

  Future<void> preview() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (title.text.trim().isEmpty) throw const FormatException('请填写课程名称');
      if (weeks.isEmpty) throw const FormatException('请选择上课周次');
      if (sections.isEmpty) throw const FormatException('请选择上课节次');
      if (weeks.any((week) => !weekOptions.contains(week))) {
        throw const FormatException('请选择本学期内的周次');
      }
      final before = widget.existing;
      final sameSections =
          before != null && _sameNumbers(sections, before['sections']);
      final keepSchoolClock =
          sameSections &&
          before['start_time'] != null &&
          before['end_time'] != null;
      if (semester != null &&
          !keepSchoolClock &&
          sections.any((n) => !periods.any((p) => p['number'] == n))) {
        throw const FormatException('请先在学期设置补齐所选节次的时间');
      }
      final rows = [
        {
          'title': title.text.trim(),
          'teacher': teacher.text.trim(),
          'location': location.text.trim(),
          'weekday': weekday,
          'weeks': weeks.toList()..sort(),
          'sections': sections.toList()..sort(),
          if (keepSchoolClock) ...{
            'start_time': before['start_time'],
            'end_time': before['end_time'],
          },
          if (before?['attendance_exempt'] == true) 'attendance_exempt': true,
        },
      ];
      if (widget.existing != null) {
        final after = rows.single;
        final yes = await showDialog<bool>(
          context: context,
          builder: (dialog) => AppDialog(
            title: const Text('确认修改课程？'),
            content: _CourseSaveSummary(
              before: before!,
              after: after,
              clock: clockSummary,
            ),
            actions: [
              AppTextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('返回核对'),
              ),
              AppButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('确认保存'),
              ),
            ],
          ),
        );
        if (yes != true || !mounted) return;
        final saved = Map<String, dynamic>.from(
          await widget.items!.api.request(
            'PATCH',
            '/courses/${widget.courseId}',
            data: {
              ...rows.single,
              'source_id': widget.existing!['source_id'] ?? '',
              'expected_revision': widget.revision,
            },
          ),
        );
        await widget.items!.onRealityChanged?.call(saved);
        await widget.items!.refresh();
        if (mounted) Navigator.pop(context, true);
      } else if (await showImportPreview(
            context,
            widget.controller!,
            rows,
            'manual',
          ) &&
          mounted) {
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = userError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.existing == null ? '手工添加课程' : '编辑课程')),
    bottomNavigationBar: ActionFooter(
      label: widget.existing == null ? '核对课程信息' : '保存课程',
      onPressed: busy ? null : preview,
      icon: widget.existing == null
          ? Icons.fact_check_outlined
          : Icons.save_outlined,
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AcademicEditorSection(
          title: '课程信息',
          icon: Icons.school_outlined,
          children: [
            AppField(
              key: const Key('course-title'),
              controller: title,
              enabled: !busy,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '课程名称'),
            ),
            const SizedBox(height: 4),
            AppField(
              controller: teacher,
              enabled: !busy,
              decoration: const InputDecoration(labelText: '教师'),
            ),
            const SizedBox(height: 4),
            AppField(
              controller: location,
              enabled: !busy,
              decoration: const InputDecoration(labelText: '上课地点'),
            ),
          ],
        ),
        AcademicEditorSection(
          title: '上课时间',
          icon: Icons.calendar_view_week_outlined,
          accent: CampusColors.teal,
          subtitle: widget.existing?['attendance_exempt'] == true ? '免听' : null,
          children: [
            AppPickerField<int>(
              initialValue: weekday,
              decoration: const InputDecoration(labelText: '上课星期'),
              items: List.generate(
                7,
                (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text('周${'一二三四五六日'[i]}'),
                ),
              ),
              onChanged: busy ? null : (v) => setState(() => weekday = v!),
            ),
            const SizedBox(height: 4),
            AppNumberPickerField(
              key: const Key('course-weeks'),
              label: '周次',
              unit: '周',
              values: weeks,
              options: weekOptions,
              weekShortcuts: true,
              enabled: !busy,
              onChanged: (value) => setState(() => weeks = value),
            ),
            const SizedBox(height: 4),
            AppNumberPickerField(
              key: const Key('course-sections'),
              label: '节次',
              unit: '节',
              values: sections,
              options: sectionOptions,
              description: clockSummary,
              errorText: sectionOptions.isEmpty ? '请先在学期设置添加节次' : null,
              enabled: !busy,
              onChanged: (value) => setState(() => sections = value),
            ),
          ],
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}

class _CourseSaveSummary extends StatelessWidget {
  const _CourseSaveSummary({
    required this.before,
    required this.after,
    required this.clock,
  });
  final Map<String, dynamic> before, after;
  final String? clock;

  String slot(Map<String, dynamic> course) =>
      '周${'一二三四五六日'[(course['weekday'] as int) - 1]} · '
      '${formatNumberSelection(List<int>.from(course['sections']), unit: '节')}';

  @override
  Widget build(BuildContext context) {
    final oldSlot = slot(before), newSlot = slot(after);
    final changedWeeks =
        formatNumberSelection(List<int>.from(before['weeks']), unit: '周') !=
        formatNumberSelection(List<int>.from(after['weeks']), unit: '周');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${after['title']}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        if (oldSlot != newSlot) ...[
          const Text(
            '修改前',
            style: TextStyle(fontSize: 12, color: CampusColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            oldSlot,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: CampusColors.tealSoft,
            border: Border(
              left: BorderSide(color: CampusColors.teal, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                oldSlot != newSlot ? '修改后' : '上课安排',
                style: const TextStyle(fontSize: 12, color: CampusColors.teal),
              ),
              const SizedBox(height: 6),
              Text(
                newSlot,
                style: const TextStyle(
                  color: CampusColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (clock != null) ...[
                const SizedBox(height: 6),
                Text(
                  clock!,
                  style: const TextStyle(
                    color: CampusColors.teal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                formatNumberSelection(
                  List<int>.from(after['weeks']),
                  unit: '周',
                ),
                style: const TextStyle(fontSize: 14, color: CampusColors.muted),
              ),
            ],
          ),
        ),
        if (changedWeeks) ...[
          const SizedBox(height: 12),
          Text(
            '原周次 ${formatNumberSelection(List<int>.from(before['weeks']), unit: '周')}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ],
        for (final key in ['teacher', 'location'])
          if (before[key] != after[key]) ...[
            const SizedBox(height: 8),
            Text(
              '${after[key]}'.isEmpty
                  ? '移除${key == 'teacher' ? '教师' : '地点'}'
                  : '${key == 'teacher' ? '教师' : '地点'}：${after[key]}',
            ),
          ],
      ],
    );
  }
}
