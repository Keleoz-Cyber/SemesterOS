import '../../ui/app_controls.dart';
import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/campus_theme.dart';
import '../../ui/app_selection.dart';
import '../../ui/app_picker_field.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import 'risk_widgets.dart';
import 'proposal_page.dart';

class SchedulePage extends StatefulWidget {
  final ItemsController controller;
  const SchedulePage({super.key, required this.controller});
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  int days = 7, chunk = 45, lead = 5;
  bool busy = false;
  String? error;
  late final String? owner, semester;
  late final int generation;
  final selected = <String>{}, targets = <String, TextEditingController>{};
  late final List<Map<String, dynamic>> tasks;
  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    owner = c.owner;
    semester = c.semesterId;
    generation = c.api.generation;
    tasks = c.items
        .where((i) => i['kind'] != 'exam' && i['lifecycle'] == 'active')
        .toList();
    for (final t in tasks) {
      targets[t['id']] = TextEditingController();
      if (t['remaining_minutes'] != null &&
          t['start_policy'] != 'unconfirmed' &&
          t['start_policy'] != null) {
        selected.add(t['id']);
      }
    }
  }

  @override
  void dispose() {
    for (final c in targets.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get same =>
      owner == widget.controller.owner &&
      semester == widget.controller.semesterId &&
      generation == widget.controller.api.generation;
  Future<void> generate() async {
    if (!same) {
      setState(() => error = '账号或学期已切换，请重新打开');
      return;
    }
    final choices = <Map<String, dynamic>>[];
    for (final id in selected) {
      final text = targets[id]!.text.trim();
      final value = text.isEmpty ? null : int.tryParse(text);
      if (text.isNotEmpty && (value == null || value < 1)) {
        setState(() => error = '请输入大于0的分钟数；所选日期内到期的任务也可以留空。');
        return;
      }
      choices.add({'item_id': id, 'target_minutes': value});
    }
    if (choices.isEmpty || choices.length > 100) {
      setState(() => error = '请选1至100项任务');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final p = await widget.controller.generateSchedule({
        'days': days,
        'lead_minutes': lead,
        'chunk_minutes': chunk,
        'allow_partial': false,
        'tasks': choices,
      });
      if (!mounted || !same) return;
      final applied = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ProposalPage(controller: widget.controller, proposal: p),
        ),
      );
      if (mounted && applied == true) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('安排任务')),
    bottomNavigationBar: ActionFooter(
      label: busy ? '正在生成…' : '生成计划方案',
      icon: Icons.auto_awesome_outlined,
      onPressed: busy || selected.isEmpty ? null : generate,
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        EditorSection(
          title: '安排范围',
          icon: Icons.date_range_outlined,
          children: [
            AppSegmentedControl<int>(
              value: days,
              enabled: !busy,
              options: const {7: '未来7天', 14: '未来14天', 28: '未来28天'},
              onChanged: (value) => setState(() => days = value),
            ),
            const SizedBox(height: 14),
            AppDisclosure(
              tilePadding: EdgeInsets.zero,
              title: const Text('开始时间与分段设置'),
              subtitle: Text('$lead分钟后开始 · 每段$chunk分钟'),
              children: [
                AppPickerField<int>(
                  initialValue: lead,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '最早从什么时候开始'),
                  items: [
                    for (final n in [0, 5, 10, 15])
                      DropdownMenuItem(value: n, child: Text('$n分钟后开始')),
                  ],
                  onChanged: busy ? null : (v) => setState(() => lead = v!),
                ),
                const SizedBox(height: 14),
                AppPickerField<int>(
                  initialValue: chunk,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '每次想学习多久'),
                  items: [
                    for (final n in [15, 30, 45, 60, 90])
                      DropdownMenuItem(value: n, child: Text('$n分钟')),
                  ],
                  onChanged: busy ? null : (v) => setState(() => chunk = v!),
                ),
                const SizedBox(height: 12),
                const SoftNotice(
                  '系统会尽量按你选择的时长分段，最后一段可稍作调整。需要一次完成的任务会安排在同一个时段。',
                ),
              ],
            ),
          ],
        ),
        SectionHeading('任务 · 已选${selected.length}项'),
        const Text(
          '范围内到期的任务可留空，安排全部剩余工作；其他任务填写目标时长。已安排时间计入目标。',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        for (final task in tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: CampusPanel(
              color: selected.contains(task['id'])
                  ? CampusColors.blueSoft
                  : CampusColors.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCheckRow(
                    contentPadding: EdgeInsets.zero,
                    title: Text(task['title']),
                    subtitle: Text(
                      '${itemTimeLabel(task)}\n剩余：${minutesLabel(task['remaining_minutes'])}',
                    ),
                    value: selected.contains(task['id']),
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            if (v == true) {
                              selected.add(task['id']);
                            } else {
                              selected.remove(task['id']);
                            }
                          }),
                  ),
                  if (task['remaining_minutes'] == null ||
                      task['start_policy'] == null ||
                      task['start_policy'] == 'unconfirmed')
                    Text(
                      '需先在事项详情补齐耗时和最早开始',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (selected.contains(task['id']))
                    AppField(
                      controller: targets[task['id']],
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '本次安排（分钟）'),
                    ),
                ],
              ),
            ),
          ),
        if (tasks.isEmpty)
          const CampusPanel(child: Text('先记录一项作业或个人任务。考试复习请单独建任务。')),
        if (busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          const Text('正在结合课表和空闲时间安排，请稍候…'),
        ],
        if (error != null) ...[
          SoftNotice(error!, warning: true),
          const SizedBox(height: 12),
        ],
      ],
    ),
  );
}
