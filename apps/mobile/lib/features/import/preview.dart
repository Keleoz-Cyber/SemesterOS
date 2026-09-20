import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';
import '../timetable/timetable_layout.dart';

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
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
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
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
          data: {'expected_revision': batch!['base_revision']},
        ),
      );
      await widget.controller.acknowledgeImport(receipt);
      await widget.controller.openSession();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
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
                color: const Color(0xFFE8E5FF),
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
                        color: Color(0xFF328774),
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
                    background: const Color(0xFFE0F5EB),
                    foreground: const Color(0xFF287B5E),
                  ),
                  StatusPill(
                    '已有 ${batch!['unchanged_count']}',
                    background: const Color(0xFFEDF1F7),
                    foreground: CampusColors.muted,
                  ),
                  if (batch!['changed_count'] != 0)
                    StatusPill(
                      '需核对 ${batch!['changed_count']}',
                      background: const Color(0xFFFFF0D2),
                      foreground: const Color(0xFF825C1D),
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
            if (batch != null && batch!['changed_count'] != 0)
              const SoftNotice('部分课次与已保存信息不同，请返回核对变更后再保存。', warning: true),
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
                TextButton(
                  onPressed: busy ? null : load,
                  child: const Text('重新校验预览'),
                ),
              ],
              FilledButton(
                onPressed: busy || batch == null || batch!['changed_count'] != 0
                    ? null
                    : apply,
                child: Text(busy ? '正在核对…' : '确认保存课表'),
              ),
              TextButton(
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

class _ImportCourseTile extends StatelessWidget {
  final Map<String, dynamic> course;
  const _ImportCourseTile({required this.course});
  @override
  Widget build(BuildContext context) {
    final palette = CoursePalette.forTitle('${course['title']}');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border(left: BorderSide(color: palette.accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${course['title']}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              StatusPill(
                '周${'一二三四五六日'[(course['weekday'] as int) - 1]}',
                background: palette.background,
                foreground: palette.ink,
              ),
              StatusPill(
                '第${(course['sections'] as List).join('、')}节',
                background: const Color(0xFFF2F5FA),
                foreground: CampusColors.muted,
              ),
            ],
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
