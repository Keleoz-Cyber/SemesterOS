import 'package:flutter/material.dart';
import '../../ui/campus_widgets.dart';
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
        setState(() => error = '本轮目标请填写正整数分钟，或留空由确定截止计算');
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
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('生成个人计划')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const CampusHero(
          eyebrow: 'PLAN / 先预览再确认',
          title: '把任务放进时间',
          subtitle: '已有安排保持原位\n本轮补充尚未覆盖的工作',
        ),
        const SectionHeading('本轮范围'),
        Wrap(
          spacing: 8,
          children: [
            for (final d in [7, 14, 28])
              ChoiceChip(
                label: Text('未来$d天'),
                selected: days == d,
                onSelected: busy ? null : (_) => setState(() => days = d),
              ),
          ],
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          initialValue: lead,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '开始前留出核对时间'),
          items: [
            for (final n in [0, 5, 10, 15])
              DropdownMenuItem(value: n, child: Text('$n分钟后开始')),
          ],
          onChanged: busy ? null : (v) => setState(() => lead = v!),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          initialValue: chunk,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '可拆分任务的建议块长'),
          items: [
            for (final n in [15, 30, 45, 60, 90])
              DropdownMenuItem(value: n, child: Text('$n分钟')),
          ],
          onChanged: busy ? null : (v) => setState(() => chunk = v!),
        ),
        const SizedBox(height: 12),
        const SoftNotice('尾段不足15分钟会并入前一块；总工作量不足15分钟保留实际长度。不可拆分任务会安排成连续一段。'),
        const SectionHeading('选择任务与本轮目标'),
        const Text(
          '窗口内有确定截止的任务，留空即安排全部剩余工作量。无确定截止或截止在窗口外时，请明确本轮目标。目标包含已有覆盖，不是额外加时。',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        for (final task in tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: CampusPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckboxListTile(
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
                    const Text(
                      '需先在事项详情补齐耗时和最早开始',
                      style: TextStyle(color: Colors.deepOrange),
                    ),
                  if (selected.contains(task['id']))
                    TextField(
                      controller: targets[task['id']],
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '本轮覆盖目标（分钟，可留空）',
                      ),
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
          const Text('正在读取约束并求解候选，求解预算约10秒…'),
        ],
        if (error != null) ...[
          SoftNotice(error!, warning: true),
          const SizedBox(height: 12),
        ],
        FilledButton(
          onPressed: busy || selected.isEmpty ? null : generate,
          child: Text(busy ? '正在生成…' : '生成候选计划'),
        ),
        const SizedBox(height: 10),
        const Text('生成不会写入正式日程，核对后再确认应用。', style: TextStyle(fontSize: 12)),
      ],
    ),
  );
}
