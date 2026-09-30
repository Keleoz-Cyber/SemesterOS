import '../../ui/app_controls.dart';
import '../../ui/detail_widgets.dart';
import '../../core/api.dart' show ApiFailure, userError;
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';
import '../timetable/timetable_layout.dart';
import '../semester/semester_page.dart';

Future<bool> showImportPreview(
  BuildContext context,
  AppController controller,
  List<Map<String, dynamic>> courses,
  String source, {
  String sourceTerm = '',
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
        ),
      ),
    ) ??
    false;

class ImportPreview extends StatefulWidget {
  final AppController controller;
  final List<Map<String, dynamic>> courses;
  final String source;
  final String sourceTerm;
  const ImportPreview({
    super.key,
    required this.controller,
    required this.courses,
    required this.source,
    this.sourceTerm = '',
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
  List<Map<String, dynamic>> get changedCourses =>
      List<Map<String, dynamic>>.from(batch?['changed_courses'] ?? []);
  bool get hasChangeDetails =>
      batch != null && changedCourses.length == batch!['changed_count'];
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

  Future<void> editCalendar() async {
    final semester = widget.controller.semester;
    if (semester == null) return;
    final saved = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SemesterPage(
          controller: widget.controller,
          existing: Map<String, dynamic>.from(semester),
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
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: CampusColors.blueSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.fact_check_outlined,
                color: CampusColors.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '核对这份课表',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '读取到 ${widget.courses.length} 条课程记录',
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
      if (busy) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            const WorkflowHeader(steps: ['读取课表', '核对课程', '保存'], current: 1),
            CampusPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '保存到',
                    style: TextStyle(fontSize: 12, color: CampusColors.muted),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${widget.controller.semester?['name']}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '账号  ${widget.controller.user['username']}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: CampusColors.muted,
                    ),
                  ),
                  const Divider(height: 24),
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
                          widget.source == 'haut_webview'
                              ? '学校原始网页${widget.sourceTerm.isEmpty ? '' : '\n来源学期：${widget.sourceTerm}'}'
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
            if (batch != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(
                    '新增 ${batch!['new_count']}',
                    background: CampusColors.tealSoft,
                    foreground: CampusColors.teal,
                  ),
                  StatusPill(
                    '已有 ${batch!['unchanged_count']}',
                    background: CampusColors.background,
                    foreground: CampusColors.muted,
                  ),
                  if (batch!['changed_count'] != 0)
                    StatusPill(
                      '需核对 ${batch!['changed_count']}',
                      background: CampusColors.warningSoft,
                      foreground: CampusColors.warning,
                    ),
                  if ((batch!['missing_count'] as int? ?? 0) > 0)
                    StatusPill(
                      '旧课表未出现 ${batch!['missing_count']}',
                      background: CampusColors.warningSoft,
                      foreground: CampusColors.warning,
                    ),
                ],
              ),
            const SectionHeading('课程明细'),
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text(
                '请核对周次、节次和地点，确认后才会保存。',
                style: TextStyle(fontSize: 13, color: CampusColors.muted),
              ),
            ),
            for (final course in widget.courses) ...[
              _ImportCourseTile(course: course),
              const SizedBox(height: 11),
            ],
            if (batch != null && batch!['changed_count'] != 0) ...[
              const SectionHeading('需要核对的变化'),
              if (!hasChangeDetails)
                const SoftNotice(
                  '服务暂时没有返回完整的旧／新课程差异，请重新读取课表后再试。',
                  warning: true,
                ),
              for (final change in changedCourses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: CampusColors.warning, width: 3),
                      ),
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
                        Text(
                          '原：${_courseLine(change['before'])}',
                          style: const TextStyle(color: CampusColors.muted),
                        ),
                        Text(
                          '新：${_courseLine(change['after'])}',
                          style: const TextStyle(color: CampusColors.ink),
                        ),
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
                  title: const Text('我已核对，替换这些旧课次'),
                ),
            ],
            if (batch != null &&
                (batch!['missing_count'] as int? ?? 0) > 0) ...[
              const SectionHeading('本次未出现的旧教务课程'),
              const Text(
                '默认保留这些课程。若确认学校课表已不再包含它们，可以在保存时一并移除；关联任务会保留并解除课程关联。',
                style: TextStyle(fontSize: 13, color: CampusColors.muted),
              ),
              const SizedBox(height: 8),
              if (!hasMissingDetails)
                const SoftNotice('旧课程明细尚未完整读取，本次不会移除旧课程。', warning: true),
              for (final missing in missingCourses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• ${missing['before']['title']} · ${_courseLine(missing['before'])}',
                  ),
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
          ],
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
              if (error != null) ...[
                SoftNotice(error!, warning: true),
                if (calendarMismatch)
                  AppOutlineButton(
                    onPressed: busy ? null : editCalendar,
                    child: const Text('修改学期周数或节次'),
                  ),
                AppTextButton(
                  onPressed: busy ? null : load,
                  child: const Text('重新检查课表'),
                ),
              ],
              AppButton(
                onPressed:
                    busy ||
                        batch == null ||
                        (batch!['changed_count'] != 0 &&
                            (!hasChangeDetails || !confirmChanged))
                    ? null
                    : apply,
                child: Text(busy ? '正在核对…' : '确认保存课表'),
              ),
              AppTextButton(
                onPressed: busy ? null : () => Navigator.pop(context, false),
                child: const Text('返回核对'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

String _courseLine(dynamic value) {
  final course = Map<String, dynamic>.from(value as Map);
  final weekday = course['weekday'] as int;
  final sections = List<int>.from(course['sections'] as List);
  final location = '${course['location'] ?? ''}'.trim();
  return '周${'一二三四五六日'[weekday - 1]} · 第${sections.join('、')}节 · '
      '${compactWeeks(course['weeks'] as List)}'
      '${location.isEmpty ? '' : ' · $location'}';
}

class _ImportCourseTile extends StatelessWidget {
  final Map<String, dynamic> course;
  const _ImportCourseTile({required this.course});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CampusColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: const Border(bottom: BorderSide(color: CampusColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${course['title']}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            '周${'一二三四五六日'[(course['weekday'] as int) - 1]}  ·  第${(course['sections'] as List).join('、')}节',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: CampusColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            compactWeeks(course['weeks'] as List),
            style: const TextStyle(fontSize: 13, color: CampusColors.muted),
          ),
          if ('${course['location']}'.isNotEmpty) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 15,
                  color: CampusColors.muted,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '${course['location']}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: CampusColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if ('${course['teacher']}'.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              '教师  ${course['teacher']}',
              style: const TextStyle(fontSize: 13, color: CampusColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}
