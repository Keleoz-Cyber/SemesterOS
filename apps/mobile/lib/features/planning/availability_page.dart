import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../ui/campus_widgets.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import 'date_time_picker.dart';

class AvailabilityPage extends StatefulWidget {
  final ItemsController controller;
  const AvailabilityPage({super.key, required this.controller});
  @override
  State<AvailabilityPage> createState() => _AvailabilityPageState();
}

class _AvailabilityPageState extends State<AvailabilityPage> {
  List<Map<String, dynamic>> weekly = [], exclusions = [];
  int? version;
  bool busy = false;
  String? error, lastBody, requestKey;
  late final String? openedSemester, openedOwner;
  late final int openedGeneration;
  bool get sameContext =>
      widget.controller.semesterId == openedSemester &&
      widget.controller.owner == openedOwner &&
      widget.controller.api.generation == openedGeneration;
  @override
  void initState() {
    super.initState();
    openedSemester = widget.controller.semesterId;
    openedOwner = widget.controller.owner;
    openedGeneration = widget.controller.api.generation;
    load();
  }

  Future<void> load() async {
    if (!sameContext) {
      setState(() => error = '账号或学期已切换，请返回后重新打开设置');
      return;
    }
    try {
      final data = await widget.controller.getAvailability();
      if (mounted) {
        setState(() {
          version = data['version'];
          weekly = List<Map<String, dynamic>>.from(data['weekly']);
          exclusions = List<Map<String, dynamic>>.from(data['exclusions']);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  String clock(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  Future<void> editWindow(int day, [Map<String, dynamic>? original]) async {
    TimeOfDay parse(String value) => TimeOfDay(
      hour: int.parse(value.split(':')[0]) % 24,
      minute: int.parse(value.split(':')[1]),
    );
    final start = await showTimePicker(
      context: context,
      initialTime: parse(original?['start'] ?? '19:00'),
      helpText: '可学习时段开始',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: parse(original?['end'] ?? '21:00'),
      helpText: '可学习时段结束（00:00表示当天结束）',
    );
    if (end == null || !mounted) return;
    final endMinutes = end.hour * 60 + end.minute == 0
        ? 1440
        : end.hour * 60 + end.minute;
    if (endMinutes <= start.hour * 60 + start.minute) {
      setState(() => error = '同日结束应晚于开始；跨天请分别设置两天。');
      return;
    }
    setState(() {
      if (original != null) weekly.remove(original);
      weekly.add({
        'weekday': day,
        'start': clock(start),
        'end': endMinutes == 1440 ? '24:00' : clock(end),
      });
      weekly.sort(
        (a, b) => '${a['weekday']}${a['start']}'.compareTo(
          '${b['weekday']}${b['start']}',
        ),
      );
      error = null;
    });
  }

  Future<void> editExclusion([Map<String, dynamic>? original]) async {
    final start = await pickSchoolDateTime(
      context,
      initial: original == null ? null : DateTime.parse(original['start_at']),
    );
    if (start == null || !mounted) return;
    final end = await pickSchoolDateTime(
      context,
      initial: original == null ? start : DateTime.parse(original['end_at']),
    );
    if (end == null || !mounted) return;
    if (!end.isAfter(start)) {
      setState(() => error = '禁排结束必须晚于开始');
      return;
    }
    final label = TextEditingController(text: original?['label'] ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('禁排原因（可留空）'),
        content: TextField(
          controller: label,
          maxLength: 120,
          decoration: const InputDecoration(hintText: '例如：社团活动、休息'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, label.text.trim()),
            child: const Text('添加到待保存设置'),
          ),
        ],
      ),
    );
    if (mounted && name != null) {
      setState(() {
        if (original != null) exclusions.remove(original);
        exclusions.add({
          'start_at': start.toIso8601String(),
          'end_at': end.toIso8601String(),
          'label': name,
        });
        error = null;
      });
    }
    // Keep the controller alive through the dialog's reverse transition.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    label.dispose();
  }

  List<Widget> summary(Map<String, dynamic> data) => [
    for (final row in data['weekly'])
      Text(
        '周${'一二三四五六日'[(row['weekday'] as int) - 1]}  ${row['start']}—${row['end']}',
      ),
    if ((data['weekly'] as List).isEmpty)
      Text(
        data['configured'] == false ? '尚未确认学习时间，暂不计算容量' : '确认没有可学习时段，容量按0计算',
      ),
    const SizedBox(height: 8),
    Text('${(data['exclusions'] as List).length}条临时禁排'),
    for (final row in data['exclusions'])
      Text(
        '${displayInstant(row['start_at'])} 至 ${displayInstant(row['end_at'])} ${row['label']}',
        style: const TextStyle(fontSize: 12),
      ),
  ];
  Future<void> save() async {
    if (!sameContext) {
      setState(() => error = '账号或学期已切换，请返回后重新打开设置');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final input = {
        'expected_version': version,
        'weekly': weekly,
        'exclusions': exclusions,
      };
      final preview = await widget.controller.previewAvailability(input);
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认新的可学习时间'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '原设置',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                ...summary(Map<String, dynamic>.from(preview['before'])),
                const Divider(),
                const Text(
                  '确认后采用',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                ...summary(Map<String, dynamic>.from(preview['after'])),
                const SizedBox(height: 12),
                const Text('重叠学习时段会合并，保存后重新计算余量。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认保存学习时间'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
      if (!sameContext) {
        setState(() => error = '账号或学期已切换，请返回后重新打开设置');
        return;
      }
      final data = {...input, 'expected_revision': preview['base_revision']};
      final encoded = jsonEncode(data);
      if (lastBody != encoded) {
        lastBody = encoded;
        requestKey =
            'availability-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
      }
      await widget.controller.saveAvailability(
        data,
        idempotencyKey: requestKey,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('可学习时间')),
    body: version == null
        ? Center(
            child: error == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      TextButton(onPressed: load, child: const Text('重试')),
                    ],
                  ),
          )
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const CampusHero(
                eyebrow: 'TIME / 给自己留出时间',
                title: '什么时候能学习',
                subtitle: '只在你确认的时段内\n计算可规划时间',
              ),
              const SizedBox(height: 16),
              const SoftNotice('以下时间均为北京时间。没有课不一定有空，先确认你愿意用于学习的时段。'),
              const SectionHeading('每周学习时段'),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(
                        () => weekly = List.generate(
                          7,
                          (i) => {
                            'weekday': i + 1,
                            'start': '19:00',
                            'end': '21:00',
                          },
                        ),
                      ),
                child: const Text('填入可编辑示例：每天19:00—21:00'),
              ),
              for (var day = 1; day <= 7; day++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CampusPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '周${'一二三四五六日'[day - 1]}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: busy ? null : () => editWindow(day),
                              child: const Text('添加时段'),
                            ),
                          ],
                        ),
                        if (!weekly.any((r) => r['weekday'] == day))
                          const Text('未设置学习时段', style: TextStyle(fontSize: 13)),
                        for (final row in weekly.where(
                          (r) => r['weekday'] == day,
                        ))
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => editWindow(day, row),
                                  child: Text('${row['start']}—${row['end']}'),
                                ),
                              ),
                              IconButton(
                                tooltip: '移除此时段',
                                onPressed: busy
                                    ? null
                                    : () => setState(() => weekly.remove(row)),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              SectionHeading(
                '临时禁排',
                action: '添加',
                onAction: busy ? null : () => editExclusion(),
              ),
              if (exclusions.isEmpty)
                const CampusPanel(child: Text('活动、休息等不能学习的时间，可以单独排除。')),
              for (final row in exclusions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CampusPanel(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      title: Text(
                        '${displayInstant(row['start_at'])}\n至 ${displayInstant(row['end_at'])}',
                      ),
                      subtitle: Text('${row['label']}'),
                      onTap: busy ? null : () => editExclusion(row),
                      trailing: IconButton(
                        tooltip: '移除此禁排',
                        onPressed: busy
                            ? null
                            : () => setState(() => exclusions.remove(row)),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              if (error != null) ...[
                SoftNotice(error!, warning: true),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? '正在核对…' : '核对并保存学习时间'),
              ),
            ],
          ),
  );
}
