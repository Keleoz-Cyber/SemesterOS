import '../../ui/app_controls.dart';
import '../../ui/app_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../../core/api.dart' show userError;
import '../items/items_controller.dart';
import 'haut_parser.dart';
import 'preview.dart';
import '../../ui/detail_widgets.dart';

class ManualPage extends StatefulWidget {
  final AppController? controller;
  final ItemsController? items;
  final Map<String, dynamic>? existing;
  final int? revision;
  final String? courseId;
  const ManualPage({super.key, required AppController this.controller})
    : items = null,
      existing = null,
      revision = null,
      courseId = null;
  const ManualPage.edit({
    super.key,
    required ItemsController this.items,
    required this.existing,
    required this.revision,
    required this.courseId,
  }) : controller = null;
  @override
  State<ManualPage> createState() => _ManualPageState();
}

class _ManualPageState extends State<ManualPage> {
  late final TextEditingController title, teacher, location, weeks, sections;
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
    weeks = TextEditingController(
      text: course == null
          ? ''
          : List<int>.from(course['weeks'] as List).join(','),
    );
    sections = TextEditingController(
      text: course == null
          ? ''
          : List<int>.from(course['sections'] as List).join(','),
    );
    weekday = course?['weekday'] as int? ?? 1;
  }

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
      if (widget.existing != null) {
        final before = widget.existing!;
        final after = rows.single;
        final yes = await showDialog<bool>(
          context: context,
          builder: (dialog) => AppDialog(
            title: const Text('确认修改课程？'),
            content: Text(
              '原：${before['title']} · 周${'一二三四五六日'[(before['weekday'] as int) - 1]} · 第${(before['sections'] as List).join('、')}节\n'
              '新：${after['title']} · 周${'一二三四五六日'[(after['weekday'] as int) - 1]} · 第${(after['sections'] as List).join('、')}节\n'
              '保存后课表会重新计算。',
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
        EditorSection(
          title: '课程信息',
          icon: Icons.school_outlined,
          children: [
            AppField(
              key: const Key('course-title'),
              controller: title,
              decoration: const InputDecoration(labelText: '课程名称'),
            ),
            const SizedBox(height: 14),
            AppField(
              controller: teacher,
              decoration: const InputDecoration(labelText: '教师（可留空）'),
            ),
            const SizedBox(height: 14),
            AppField(
              controller: location,
              decoration: const InputDecoration(labelText: '上课地点（可留空）'),
            ),
            const SizedBox(height: 14),
          ],
        ),
        EditorSection(
          title: '上课时间',
          icon: Icons.calendar_view_week_outlined,
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
              onChanged: (v) => setState(() => weekday = v!),
            ),
            const SizedBox(height: 14),
            AppField(
              controller: weeks,
              decoration: const InputDecoration(
                labelText: '周次',
                hintText: '例如 1-16周(单) 或 1-8,10-16',
              ),
            ),
            const SizedBox(height: 14),
            AppField(
              controller: sections,
              decoration: const InputDecoration(
                labelText: '节次',
                hintText: '例如 1-2 或 1,3',
              ),
            ),
            const SizedBox(height: 20),
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
