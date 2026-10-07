import '../../ui/app_loading.dart';
import '../../ui/app_time_range_picker.dart';
import 'package:flutter/material.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_selection.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/campus_theme.dart';
import '../../core/api.dart' show userError;
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import 'proposal_page.dart';
import 'schedule_setup_actions.dart';

class SchedulePage extends StatefulWidget {
  final ItemsController controller;
  const SchedulePage({super.key, required this.controller});
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  Map<String, dynamic>? setup;
  final selected = <String>{};
  final estimates = <String, TextEditingController>{};
  List<Map<String, dynamic>> tasks = [], weekly = [];
  late final String? sid, owner;
  late final int generation;
  bool loading = true, busy = false;
  int days = 7, chunk = 45;
  String? error;
  ItemsController get c => widget.controller;
  bool get same =>
      sid == c.semesterId && owner == c.owner && generation == c.api.generation;
  bool get needsHours => setup?['availability']?['needs_confirmation'] == true;
  @override
  void initState() {
    super.initState();
    sid = c.semesterId;
    owner = c.owner;
    generation = c.api.generation;
    load();
  }

  @override
  void dispose() {
    for (final e in estimates.values) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    try {
      final result = Map<String, dynamic>.from(
        await c.api.request('GET', '/semesters/$sid/schedule/setup'),
      );
      if (!mounted || !same) return;
      tasks = c.rows(result['tasks']);
      for (final t in tasks) {
        final id = '${t['id']}';
        estimates.putIfAbsent(id, () => TextEditingController());
        if (estimates[id]!.text.isEmpty) {
          estimates[id]!.text =
              '${t['remaining_minutes'] ?? t['duration_suggestion_minutes'] ?? 45}';
        }
        if (t['can_schedule'] != false) selected.add(id);
      }
      weekly = c
          .rows(
            (result['availability']?['needs_confirmation'] == true)
                ? (result['availability']?['candidate']?['weekly'])
                : (result['availability']?['current']?['weekly']),
          )
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      setState(() {
        setup = result;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = userError(e);
          loading = false;
        });
      }
    }
  }

  int minuteOf(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  Future<void> editHours(Map<String, dynamic> row) async {
    if (!same || busy) return;
    final previousStart = row['start'], previousEnd = row['end'];
    final value = await showAppClockRangePicker(
      context: context,
      title: '周${'一二三四五六日'[(row['weekday'] as int) - 1]}学习时段',
      initialStartMinutes: minuteOf('$previousStart'),
      initialEndMinutes: minuteOf('$previousEnd'),
      allowEndOfDay: true,
    );
    if (value == null ||
        !mounted ||
        !same ||
        !weekly.contains(row) ||
        row['start'] != previousStart ||
        row['end'] != previousEnd) {
      return;
    }
    setState(() {
      row['start'] = value.startText;
      row['end'] = value.endText;
    });
  }

  Widget hourSetting(Map<String, dynamic> row) => AppTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(
      Icons.schedule_outlined,
      size: 20,
      color: CampusColors.teal,
    ),
    title: Text(
      '周${'一二三四五六日'[(row['weekday'] as int) - 1]} · ${row['start']}—${row['end']}',
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    onTap: busy ? null : () => editHours(row),
    trailing: AppIconButton(
      tooltip: '移除此学习时段',
      onPressed: busy ? null : () => setState(() => weekly.remove(row)),
      icon: const Icon(Icons.close_rounded, size: 18),
    ),
  );

  Future<void> generate() async {
    if (!same || busy || setup == null) return;
    final chosen = tasks.where((t) => selected.contains('${t['id']}')).toList();
    if (chosen.isEmpty) {
      setState(() => error = '请选择任务');
      return;
    }
    for (final t in chosen) {
      final n = int.tryParse(estimates['${t['id']}']!.text);
      if (n == null || n < 1) {
        setState(() => error = '请填写预计分钟数');
        return;
      }
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (needsHours && weekly.isEmpty) {
        setState(() => error = '请选择至少一段可以学习的时间');
        return;
      }
      await confirmScheduleSetup(c, setup!, chosen, {
        for (final t in chosen)
          '${t['id']}': int.parse(estimates['${t['id']}']!.text),
      }, weekly: weekly);
      if (!mounted || !same) return;
      final p = await c.generateSchedule({
        'days': days,
        'lead_minutes': 5,
        'chunk_minutes': chunk,
        'allow_partial': true,
        'tasks': chosen.map((t) => {'item_id': t['id']}).toList(),
      });
      if (!mounted || !same) return;
      final applied = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ProposalPage(controller: c, proposal: p),
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
      onPressed: loading || busy || setup == null ? null : generate,
      icon: Icons.auto_awesome_outlined,
      label: busy
          ? '正在安排…'
          : needsHours
          ? '确认时段并生成安排'
          : '生成安排',
    ),
    body: AppLoadingOverlay(
      loading: loading,
      label: '正在读取',
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                error!,
                style: const TextStyle(color: CampusColors.warning),
              ),
            ),
          if (!loading && setup == null)
            AppTextButton(onPressed: load, child: const Text('重试')),
          if (setup != null) ...[
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '安排范围',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                AppTextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => days = days == 7 ? 14 : 7),
                  child: Text('未来$days天'),
                ),
              ],
            ),
            if (needsHours)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: CampusColors.tealSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '可以学习的时间',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '先用这些时段？可以直接修改。',
                      style: TextStyle(fontSize: 13, color: CampusColors.muted),
                    ),
                    for (final row in weekly) hourSetting(row),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Text(
              '任务 · ${selected.length}项',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              '预计用时可修改；保存后仍可调整。',
              style: TextStyle(fontSize: 13, color: CampusColors.muted),
            ),
            for (final t in tasks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: selected.contains('${t['id']}')
                            ? CampusColors.primary
                            : CampusColors.line,
                        width: selected.contains('${t['id']}') ? 3 : 1,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppCheckRow(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${t['title']}'),
                        value: selected.contains('${t['id']}'),
                        onChanged: busy || t['can_schedule'] == false
                            ? null
                            : (v) => setState(() {
                                v == true
                                    ? selected.add('${t['id']}')
                                    : selected.remove('${t['id']}');
                              }),
                      ),
                      if (selected.contains('${t['id']}'))
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: AppField(
                            controller: estimates['${t['id']}'],
                            enabled: !busy,
                            textInputAction: TextInputAction.next,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: t['remaining_minutes'] == null
                                  ? '建议用时'
                                  : '剩余用时',
                              suffixText: '分钟',
                              isDense: true,
                            ),
                          ),
                        ),
                      if (t['start_policy'] == 'at')
                        Text(
                          '从 ${displayInstant(t['earliest_start_at'])} 起安排',
                          style: const TextStyle(
                            fontSize: 13,
                            color: CampusColors.muted,
                          ),
                        ),
                      if (t['waiting_reason'] != null)
                        Text(
                          '${t['waiting_reason']}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: CampusColors.warning,
                          ),
                        ),
                      const Divider(height: 20, color: CampusColors.line),
                    ],
                  ),
                ),
              ),
            if (tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text('还没有待安排的任务'),
              ),
            AppDisclosure(
              title: const Text('每次学习时长'),
              children: [
                AppSegmentedControl<int>(
                  value: chunk,
                  options: const {30: '30分钟', 45: '45分钟', 60: '1小时'},
                  onChanged: (v) => setState(() => chunk = v),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}
