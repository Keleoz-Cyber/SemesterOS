import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';

class SemesterPage extends StatefulWidget {
  final AppController controller;
  const SemesterPage({super.key, required this.controller});
  @override
  State<SemesterPage> createState() => _SemesterPageState();
}

class _SemesterPageState extends State<SemesterPage> {
  final name = TextEditingController(text: '2026—2027学年第一学期');
  final monday = TextEditingController(),
      weeks = TextEditingController(text: '20');
  final times = TextEditingController(
    text:
        '1 08:00 08:50\n2 09:00 09:50\n3 10:10 11:00\n4 11:10 12:00\n5 14:00 14:50\n6 15:00 15:50\n7 16:10 17:00\n8 17:10 18:00\n9 19:00 19:50\n10 20:00 20:50',
  );
  bool confirmed = false, busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in [name, monday, weeks, times]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final periods = times.text.trim().split('\n').map((line) {
        final p = line.trim().split(RegExp(r'\s+'));
        if (p.length != 3) throw const FormatException('每行填写：节次 开始时间 结束时间');
        return {'number': int.parse(p[0]), 'start': p[1], 'end': p[2]};
      }).toList();
      final created = await widget.controller.api.request(
        'POST',
        '/semesters',
        data: {
          'name': name.text.trim(),
          'first_monday': monday.text.trim(),
          'total_weeks': int.parse(weeks.text.trim()),
          'periods': periods,
        },
      );
      await widget.controller.openSession(null, '${created['id']}');
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('建立我的学期')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '先确认时间骨架',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const Text('课程会按你的校历和节次显示。下面的作息仅为可编辑示例，请与学校核对。'),
        const SizedBox(height: 20),
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: '学期名称'),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('first-monday'),
          controller: monday,
          decoration: const InputDecoration(
            labelText: '第一周周一',
            hintText: '例如 2026-08-31',
          ),
          keyboardType: TextInputType.datetime,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: weeks,
          decoration: const InputDecoration(labelText: '学期总周数'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: times,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(
            labelText: '节次与时间（示例，可修改）',
            helperText: '每行：节次 开始时间 结束时间',
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: confirmed,
          onChanged: busy
              ? null
              : (v) => setState(() => confirmed = v ?? false),
          title: const Text('我已核对学期起始日与节次时间'),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: confirmed && !busy ? save : null,
          child: Text(busy ? '正在保存…' : '确认创建学期'),
        ),
      ],
    ),
  );
}
