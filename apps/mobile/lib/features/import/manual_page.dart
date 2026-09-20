import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import 'haut_parser.dart';
import 'preview.dart';

class ManualPage extends StatefulWidget {
  final AppController controller;
  const ManualPage({super.key, required this.controller});
  @override
  State<ManualPage> createState() => _ManualPageState();
}

class _ManualPageState extends State<ManualPage> {
  final title = TextEditingController(),
      teacher = TextEditingController(),
      location = TextEditingController();
  final weeks = TextEditingController(), sections = TextEditingController();
  int weekday = 1;
  String? error;
  bool busy = false;
  @override
  void dispose() {
    for (final c in [title, teacher, location, weeks, sections]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> preview() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (title.text.trim().isEmpty) throw const FormatException('请填写课程名称');
      final rows = [
        {
          'title': title.text.trim(),
          'teacher': teacher.text.trim(),
          'location': location.text.trim(),
          'weekday': weekday,
          'weeks': parseWeeks(weeks.text),
          'sections': parseSections(sections.text),
        },
      ];
      if (await showImportPreview(context, widget.controller, rows, 'manual') &&
          mounted) {
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e is FormatException ? e.message : '$e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('手工添加课程')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          key: const Key('course-title'),
          controller: title,
          decoration: const InputDecoration(labelText: '课程名称'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: teacher,
          decoration: const InputDecoration(labelText: '教师（可留空）'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: location,
          decoration: const InputDecoration(labelText: '上课地点（可留空）'),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          initialValue: weekday,
          decoration: const InputDecoration(labelText: '上课星期'),
          items: List.generate(
            7,
            (i) =>
                DropdownMenuItem(value: i + 1, child: Text('周${'一二三四五六日'[i]}')),
          ),
          onChanged: (v) => setState(() => weekday = v!),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: weeks,
          decoration: const InputDecoration(
            labelText: '周次',
            hintText: '例如 1-16周(单) 或 1-8,10-16',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: sections,
          decoration: const InputDecoration(
            labelText: '节次',
            hintText: '例如 1-2 或 1,3',
          ),
        ),
        const SizedBox(height: 20),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton(
          onPressed: busy ? null : preview,
          child: const Text('核对课程信息'),
        ),
      ],
    ),
  );
}
