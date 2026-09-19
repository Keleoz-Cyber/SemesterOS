import 'package:flutter/material.dart';
import '../../app/controller.dart';

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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '核对导入课表',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Text(
          '${widget.controller.user['username']} · ${widget.controller.semester?['name']}',
        ),
        Text(widget.source == 'haut_webview' ? '来源：学校原始网页' : '来源：手工填写'),
        if (batch != null)
          Text(
            '新增 ${batch!['new_count']} 条 · 已有 ${batch!['unchanged_count']} 条 · 待核对变更 ${batch!['changed_count']} 条',
          ),
        if (widget.sourceTerm.isNotEmpty)
          Text('学校页面的学期：${widget.sourceTerm}；请与上方目标学期核对'),
        const SizedBox(height: 12),
        const Text(
          '请核对周次、单双周、节次和地点。只有确认后才会保存。',
          style: TextStyle(fontSize: 14, color: Color(0xFF667085)),
        ),
        if (busy) const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            itemCount: widget.courses.length,
            itemBuilder: (_, i) {
              final c = widget.courses[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${c['title']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '周${'一二三四五六日'[(c['weekday'] as int) - 1]} · 第${(c['sections'] as List).join('、')}节 · ${c['location']}',
                      ),
                      Text(
                        '周次：${(c['weeks'] as List).join('、')}\n教师：${c['teacher']}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (error != null)
          TextButton(
            onPressed: busy ? null : load,
            child: const Text('重新校验预览'),
          ),
        FilledButton(
          onPressed: busy || batch == null || batch!['changed_count'] != 0
              ? null
              : apply,
          child: Text(busy ? '请稍候…' : '确认保存课表'),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('返回核对'),
        ),
      ],
    ),
  );
}
