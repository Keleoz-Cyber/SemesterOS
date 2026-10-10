import '../../ui/app_loading.dart';
import '../../ui/app_controls.dart';
import '../../core/api.dart' show ApiFailure, userError;
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';
import '../timetable/timetable_layout.dart';
import '../semester/semester_page.dart';
import '../../ui/app_number_picker.dart';
import '../items/item_widgets.dart' show displayInstant;
import '../centers/academic_visuals.dart';
import '../../ui/v2/shiri_tokens.dart' as v2;
import 'package:flutter_svg/flutter_svg.dart';

Future<bool> showImportPreview(
  BuildContext context,
  AppController controller,
  List<Map<String, dynamic>> courses,
  String source, {
  String sourceTerm = '',
  List<Map<String, dynamic>> extras = const [],
  String? sourceFirstMonday,
  Map<String, dynamic> metadata = const {},
  List<String> warnings = const [],
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .94,
        child: ImportPreview(
          controller: controller,
          courses: courses,
          source: source,
          sourceTerm: sourceTerm,
          extras: extras,
          sourceFirstMonday: sourceFirstMonday,
          metadata: metadata,
          warnings: warnings,
        ),
      ),
    ) ??
    false;

class ImportPreview extends StatefulWidget {
  final AppController controller;
  final List<Map<String, dynamic>> courses;
  final String source;
  final String sourceTerm;
  final List<Map<String, dynamic>> extras;
  final String? sourceFirstMonday;
  final Map<String, dynamic> metadata;
  final List<String> warnings;
  const ImportPreview({
    super.key,
    required this.controller,
    required this.courses,
    required this.source,
    this.sourceTerm = '',
    this.extras = const [],
    this.sourceFirstMonday,
    this.metadata = const {},
    this.warnings = const [],
  });
  @override
  State<ImportPreview> createState() => _ImportPreviewState();
}

class _ImportPreviewState extends State<ImportPreview> {
  Map<String, dynamic>? batch;
  String? error;
  bool busy = true, calendarMismatch = false;
  bool confirmChanged = false;
  bool removeMissing = false;
  bool keepLocalCalendar = false;
  List<Map<String, dynamic>> get schoolPeriods => [
    for (final raw
        in (batch?['source_periods'] ?? widget.metadata['periods']) as List? ??
            [])
      if (raw is Map)
        for (final p in [
          {
            ...Map<String, dynamic>.from(raw),
            'section': raw['section'] ?? raw['number'],
          },
        ])
          if (p['section'] is int && p['start'] is String && p['end'] is String)
            Map<String, dynamic>.from(p),
  ];
  List<Map<String, dynamic>> get changedCourses =>
      List<Map<String, dynamic>>.from(batch?['changed_courses'] ?? []);
  List<Map<String, dynamic>> get changedExtras =>
      List<Map<String, dynamic>>.from(batch?['changed_extras'] ?? []);
  List<Map<String, dynamic>> get protectedExtras =>
      List<Map<String, dynamic>>.from(batch?['protected_extras'] ?? []);
  List<Map<String, dynamic>> get changes => [
    ...changedCourses,
    ...changedExtras,
  ];
  bool get hasChangeDetails =>
      batch != null && changes.length == batch!['changed_count'];
  bool get sourceCalendarDiffers =>
      widget.sourceFirstMonday != null &&
      widget.sourceFirstMonday != widget.controller.semester?['first_monday'];
  List<Map<String, dynamic>> get missingCourses =>
      List<Map<String, dynamic>>.from(batch?['missing_courses'] ?? []);
  bool get hasMissingDetails =>
      batch != null &&
      missingCourses.length == (batch!['missing_count'] as int? ?? 0);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
      calendarMismatch = false;
      confirmChanged = false;
      removeMissing = false;
      keepLocalCalendar = false;
      batch = null;
    });
    try {
      final result = Map<String, dynamic>.from(
        await widget.controller.api.request(
          'POST',
          '/imports',
          data: {
            'semester_id': widget.controller.semester!['id'],
            'source': widget.source,
            'source_term': widget.sourceTerm,
            'courses': widget.courses,
            if (widget.source == 'hlju_webview') ...{
              'extras': widget.extras,
              'source_first_monday': widget.sourceFirstMonday,
            },
          },
        ),
      );
      if (mounted) setState(() => batch = result);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = userError(e);
          calendarMismatch = e is ApiFailure && e.code == 'CALENDAR_MISMATCH';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editCalendar({bool alignSchoolDate = false}) async {
    final semester = widget.controller.semester;
    if (semester == null) return;
    final saved = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SemesterPage(
          controller: widget.controller,
          existing: {
            ...semester,
            if (alignSchoolDate) 'first_monday': widget.sourceFirstMonday,
          },
        ),
      ),
    );
    if (saved != null && mounted) await load();
  }

  Future<void> apply() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final receipt = Map<String, dynamic>.from(
        await widget.controller.api.request(
          'POST',
          '/imports/${batch!['id']}/apply',
          data: {
            'expected_revision': batch!['base_revision'],
            'replace_changed': confirmChanged,
            'remove_missing': removeMissing,
          },
        ),
      );
      await widget.controller.acknowledgeImport(receipt);
      await widget.controller.openSession();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Row(
                children: [
                  Icon(
                    Icons.fact_check_outlined,
                    size: 24,
                    color: CampusColors.primary,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '核对课表',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AppIconButton(
              onPressed: busy && batch != null
                  ? null
                  : () => Navigator.pop(context, false),
              icon: const Icon(Icons.close_rounded),
              tooltip: '返回核对',
            ),
          ],
        ),
      ),
      Expanded(
        child: AppLoadingOverlay(
          loading: busy && batch == null,
          label: '正在核对',
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              const AcademicStepRail(steps: ['读取课表', '核对课程', '保存'], current: 1),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: v2.ShiriGradients.brandSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '保存到',
                            style: TextStyle(
                              fontSize: 12,
                              color: CampusColors.muted,
                            ),
                          ),
                        ),
                        SvgPicture.asset(
                          'assets/illustrations/import-timetable.svg',
                          width: 32,
                          height: 24,
                          excludeFromSemantics: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${widget.controller.semester?['name']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if ('${widget.controller.user['username'] ?? ''}'
                        .trim()
                        .isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        '账号  ${widget.controller.user['username']}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: CampusColors.muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.verified_outlined,
                          size: 18,
                          color: CampusColors.teal,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.source.endsWith('_webview')
                                ? '学校原始网页${widget.sourceTerm.isEmpty || widget.sourceTerm == widget.controller.semester?['name'] ? '' : '\n来源学期 ${widget.sourceTerm}'}'
                                : '手工填写的课程',
                            style: const TextStyle(
                              fontSize: 13,
                              color: CampusColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (error != null) ...[
                SoftNotice(error!, warning: true),
                if (calendarMismatch)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: AppOutlineButton(
                      onPressed: busy ? null : () => editCalendar(),
                      child: const Text('修改学期周数或节次'),
                    ),
                  ),
                AppTextButton(
                  onPressed: busy ? null : load,
                  child: const Text('重新检查课表'),
                ),
              ],
              if (sourceCalendarDiffers) ...[
                CampusPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '第一周日期不同',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text('学校：${widget.sourceFirstMonday}'),
                      Text(
                        '当前：${widget.controller.semester?['first_monday'] ?? ''}',
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          AppOutlineButton(
                            onPressed: busy
                                ? null
                                : () => editCalendar(alignSchoolDate: true),
                            child: const Text('按学校日期调整'),
                          ),
                          AppTextButton(
                            onPressed: busy
                                ? null
                                : () =>
                                      setState(() => keepLocalCalendar = true),
                            child: Text(
                              keepLocalCalendar ? '已保留当前日期' : '保留当前日期',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              for (final warning in widget.warnings) ...[
                SoftNotice(warning, warning: true),
                const SizedBox(height: 8),
              ],
              if (schoolPeriods.isNotEmpty) ...[
                CampusPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '每天的节次 · ${schoolPeriods.length}节',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (widget.source == 'haut_webview')
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('已按学校作息填好，确认导入时一并保存。'),
                        ),
                      for (final p in schoolPeriods)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            children: [
                              Expanded(child: Text('第${p['section']}节')),
                              Text(
                                '${p['start']}—${p['end']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (batch != null)
                AcademicStatStrip(
                  stats: [
                    (
                      label: '新增',
                      value:
                          (batch!['new_count'] as int? ?? 0) +
                          (batch!['new_extra_count'] as int? ?? 0),
                      color: CampusColors.teal,
                    ),
                    (
                      label: '已有',
                      value:
                          (batch!['unchanged_count'] as int? ?? 0) +
                          (batch!['unchanged_extra_count'] as int? ?? 0),
                      color: CampusColors.muted,
                    ),
                    if ((batch!['changed_count'] as int? ?? 0) > 0)
                      (
                        label: '需核对',
                        value: batch!['changed_count'] as int? ?? 0,
                        color: CampusColors.primary,
                      ),
                    if ((batch!['missing_count'] as int? ?? 0) > 0)
                      (
                        label: '本次未出现',
                        value: batch!['missing_count'] as int,
                        color: CampusColors.warning,
                      ),
                  ],
                ),
              if (protectedExtras.isNotEmpty) ...[
                const SectionHeading('保留你修改的安排'),
                for (final extra in protectedExtras)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${extra['after']?['title'] ?? extra['before']?['title'] ?? ''}',
                    ),
                  ),
              ],
              if (batch != null && batch!['changed_count'] != 0) ...[
                const SectionHeading('需要核对的变化'),
                if (!hasChangeDetails)
                  const SoftNotice('没有读取到完整差异，请重新读取课表后再试。', warning: true),
                for (final change in changes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        color: CampusColors.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${change['after']['title']}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ..._importChangeFacts(change),
                        ],
                      ),
                    ),
                  ),
                if (hasChangeDetails)
                  AppCheckRow(
                    value: confirmChanged,
                    onChanged: busy
                        ? null
                        : (value) =>
                              setState(() => confirmChanged = value ?? false),
                    title: Text(
                      changedExtras.isEmpty ? '我已核对，替换这些旧课次' : '我已核对，更新这些安排',
                    ),
                  ),
              ],
              if (batch != null &&
                  (batch!['missing_count'] as int? ?? 0) > 0) ...[
                const SectionHeading('本次未出现的旧教务课程'),
                const Text(
                  '默认保留。确认移除后，关联任务仍保留。',
                  style: TextStyle(fontSize: 13, color: CampusColors.muted),
                ),
                const SizedBox(height: 8),
                if (!hasMissingDetails)
                  const SoftNotice('旧课程明细尚未完整读取，本次不会移除旧课程。', warning: true),
                for (final missing in missingCourses)
                  _ImportCourseTile(
                    course: Map<String, dynamic>.from(missing['before']),
                  ),
                if (hasMissingDetails)
                  AppCheckRow(
                    value: removeMissing,
                    onChanged: busy
                        ? null
                        : (value) =>
                              setState(() => removeMissing = value ?? false),
                    title: const Text('同时移除这些旧教务课程'),
                  ),
              ],
              if (widget.courses.isNotEmpty) ...[
                SectionHeading('课程明细 · ${widget.courses.length}'),
                for (final course in widget.courses.take(
                  widget.courses.length <= 4 ? 4 : 3,
                ))
                  _ImportCourseTile(course: course),
                if (widget.courses.length > 4)
                  AppDisclosure(
                    title: Text('其余 ${widget.courses.length - 3} 个课次'),
                    children: [
                      for (final course in widget.courses.skip(3))
                        _ImportCourseTile(course: course),
                    ],
                  ),
              ],
              if (widget.extras.isNotEmpty) ...[
                SectionHeading('考试与实践安排 · ${widget.extras.length}'),
                for (final extra in widget.extras)
                  _ImportExtraTile(extra: extra),
              ],
            ],
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: CampusColors.line)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppButton(
                onPressed:
                    busy ||
                        batch == null ||
                        (sourceCalendarDiffers && !keepLocalCalendar) ||
                        (batch!['changed_count'] != 0 &&
                            (!hasChangeDetails || !confirmChanged))
                    ? null
                    : apply,
                child: Text(busy ? '正在核对…' : '确认保存课表'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

String _extraLine(dynamic value) {
  final extra = Map<String, dynamic>.from(value as Map);
  final parts = <String>[];
  final start = DateTime.tryParse('${extra['start_at'] ?? ''}');
  final end = DateTime.tryParse('${extra['end_at'] ?? ''}');
  if (start != null) {
    final local = schoolTime(extra['start_at']);
    parts.add(
      '${local.year}/${local.month}/${local.day} ${hhmm(local)}'
      '${end == null ? '' : '—${hhmm(schoolTime(extra['end_at']))}'}',
    );
  } else if ('${extra['date'] ?? ''}'.isNotEmpty) {
    parts.add('${extra['date']}');
  }
  final weeks = extra['weeks'] as List? ?? const [];
  if (weeks.isNotEmpty) parts.add(compactWeeks(weeks));
  final location = '${extra['location'] ?? ''}'.trim();
  if (location.isNotEmpty) parts.add(location);
  final teacher = '${extra['teacher'] ?? ''}'.trim();
  if (teacher.isNotEmpty) parts.add('教师 $teacher');
  return parts.join(' · ');
}

List<Widget> _importChangeFacts(Map<String, dynamic> change) {
  final before = Map<String, dynamic>.from(change['before']);
  final after = Map<String, dynamic>.from(change['after']);
  String value(Map<String, dynamic> row, String key) {
    if (key == 'weeks' || key == 'sections') {
      final values = (row[key] as List? ?? []).whereType<int>().toList();
      return values.isEmpty
          ? ''
          : formatNumberSelection(values, unit: key == 'weeks' ? '周' : '节');
    }
    if (key == 'weekday') {
      final day = row[key];
      return day is int && day >= 1 && day <= 7 ? '周${'一二三四五六日'[day - 1]}' : '';
    }
    if (key == 'clock') {
      return [
        row['start_time'],
        row['end_time'],
      ].whereType<String>().where((s) => s.isNotEmpty).join('—');
    }
    if (key == 'time') {
      return [
        if (row['start_at'] != null)
          displayInstant(row['start_at'])
        else if (row['date'] != null)
          '${row['date']}',
        if (row['end_at'] != null) displayInstant(row['end_at']),
      ].join('—');
    }
    if (key == 'attendance_exempt') return row[key] == true ? '免听' : '正常上课';
    return '${row[key] ?? ''}'.trim();
  }

  final facts = <Widget>[];
  for (final field in const {
    'title': '课程名称',
    'weekday': '上课星期',
    'weeks': '周次',
    'sections': '节次',
    'clock': '上课时间',
    'time': '日期与时间',
    'teacher': '教师',
    'location': '地点',
    'attendance_exempt': '听课安排',
    'notes': '补充说明',
  }.entries) {
    final old = value(before, field.key), next = value(after, field.key);
    if (old == next) continue;
    facts.add(
      _ImportChangeRow(
        label: old.isEmpty ? '添加${field.value}' : field.value,
        before: old,
        after: next,
      ),
    );
  }
  return facts;
}

class _ImportChangeRow extends StatelessWidget {
  const _ImportChangeRow({
    required this.label,
    required this.before,
    required this.after,
  });
  final String label, before, after;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: CampusColors.muted),
        ),
        if (before.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            before,
            style: const TextStyle(fontSize: 14, color: CampusColors.muted),
          ),
        ],
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: 18,
              color: CampusColors.teal,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                after.isEmpty ? '移除' : after,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: CampusColors.teal,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ImportExtraTile extends StatelessWidget {
  final Map<String, dynamic> extra;
  const _ImportExtraTile({required this.extra});

  @override
  Widget build(BuildContext context) {
    final details = _extraLine(extra);
    final notes = '${extra['notes'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: extra['kind'] == 'exam'
            ? v2.ShiriColors.light.dangerSoft
            : CampusColors.tealSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                extra['kind'] == 'exam'
                    ? Icons.assignment_outlined
                    : Icons.school_outlined,
                size: 18,
                color: extra['kind'] == 'exam'
                    ? v2.ShiriColors.light.danger
                    : CampusColors.teal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  extra['kind'] == 'exam' ? '考试' : '实践课',
                  style: TextStyle(
                    fontSize: 12,
                    color: extra['kind'] == 'exam'
                        ? v2.ShiriColors.light.danger
                        : CampusColors.teal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${extra['title']}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(details, style: const TextStyle(color: CampusColors.muted)),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(notes, style: const TextStyle(color: CampusColors.muted)),
          ],
        ],
      ),
    );
  }
}

class _ImportCourseTile extends StatelessWidget {
  final Map<String, dynamic> course;
  const _ImportCourseTile({required this.course});
  @override
  Widget build(BuildContext context) {
    final location = '${course['location'] ?? ''}'.trim();
    final teacher = '${course['teacher'] ?? ''}'.trim();
    final palette = CoursePalette.forTitle('${course['title']}');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              Text(
                '周${'一二三四五六日'[(course['weekday'] as int) - 1]}',
                style: const TextStyle(
                  fontSize: 13,
                  color: CampusColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                formatNumberSelection(
                  List<int>.from(course['sections']),
                  unit: '节',
                ),
                style: const TextStyle(fontSize: 13, color: CampusColors.muted),
              ),
              if (course['attendance_exempt'] == true)
                const Text(
                  '免听',
                  style: TextStyle(
                    fontSize: 13,
                    color: CampusColors.teal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${course['title']}',
            style: TextStyle(
              fontSize: 17,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: palette.ink,
            ),
          ),
          if (course['start_time'] != null && course['end_time'] != null) ...[
            const SizedBox(height: 6),
            Text(
              '${course['start_time']}—${course['end_time']}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: CampusColors.primary,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            compactWeeks(course['weeks'] as List),
            style: const TextStyle(fontSize: 14, color: CampusColors.muted),
          ),
          if (location.isNotEmpty || teacher.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (location.isNotEmpty) location,
                if (teacher.isNotEmpty) '教师 $teacher',
              ].join(' · '),
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: CampusColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
