import '../../ui/app_controls.dart';
import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import 'dart:async';
import '../../ui/campus_widgets.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import '../items/task_surfaces.dart';
import 'risk_widgets.dart';
import '../agent/agent_widgets.dart' show PlanWarningNote;

String proposalStatus(String? status) => switch (status) {
  'FEASIBLE_COMPLETE' => '可以安排这次的任务',
  'FEASIBLE_PARTIAL' => '可以先安排一部分',
  'INFEASIBLE' => '现有时间安排不下',
  'CHUNKING_LIMITED' => '单次学习时间太长，试试缩短一些',
  'TIMEOUT' => '暂时没算出合适的方案',
  'INPUT_LIMIT' => '任务较多，请分批安排',
  _ => '需要补齐或核对信息',
};

class ProposalPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> proposal;
  const ProposalPage({
    super.key,
    required this.controller,
    required this.proposal,
  });
  @override
  State<ProposalPage> createState() => _ProposalPageState();
}

class _ProposalPageState extends State<ProposalPage> {
  Timer? clock;
  late Map<String, dynamic> p;
  late final String? owner;
  late final int generation;
  bool busy = false, partialConfirmed = false;
  String? error;
  @override
  void initState() {
    super.initState();
    p = widget.proposal;
    owner = widget.controller.owner;
    generation = widget.controller.api.generation;
    widget.controller.addListener(onControllerChanged);
    clock = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(onControllerChanged);
    clock?.cancel();
    super.dispose();
  }

  void onControllerChanged() {
    if (mounted) setState(() {});
  }

  bool get same =>
      owner == widget.controller.owner &&
      generation == widget.controller.api.generation &&
      p['semester_id'] == widget.controller.semesterId;
  Future<void> regenerate(bool partial) async {
    if (!same) {
      setState(() => error = '账号或学期已切换，请返回重新打开');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.controller.generateSchedule({
        ...Map<String, dynamic>.from(p['request']),
        if (p['mode'] != 'replan') 'allow_partial': partial,
      });
      if (mounted) {
        setState(() {
          p = result;
          partialConfirmed = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> accept() async {
    if (!same) {
      setState(() => error = '账号或学期已切换，请返回重新打开');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.acceptSchedule(p, partialConfirmed);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final replan = p['mode'] == 'replan';
    final partial = p['status'] == 'FEASIBLE_PARTIAL',
        missing = p['unarranged_minutes'] ?? 0;
    final blocks = List<Map<String, dynamic>>.from(p['blocks'] ?? []);
    final taskRows = widget.controller.rows(p['tasks']);
    final simple =
        !replan &&
        !partial &&
        blocks.length == 1 &&
        taskRows.length == 1 &&
        (taskRows.single['existing_minutes'] ?? 0) == 0 &&
        (taskRows.single['later_minutes'] ?? 0) == 0;
    final expired =
        p['phase'] == 'expired' ||
        (p['valid_until'] != null &&
            !DateTime.parse(p['valid_until']).isAfter(DateTime.now()));
    final stale = widget.controller.revisionIsStale(
      p['semester_id'],
      p['base_revision'],
    );
    final canApply =
        p['can_apply'] == true &&
        p['phase'] == 'ready' &&
        !expired &&
        !stale &&
        same;
    return Scaffold(
      appBar: AppBar(title: Text(replan ? '调整安排' : '安排预览')),
      bottomNavigationBar: canApply
          ? ActionFooter(
              label: partial
                  ? '保存已安排部分'
                  : replan
                  ? '确认调整'
                  : '保存学习安排',
              icon: Icons.check_rounded,
              onPressed: busy || (partial && !partialConfirmed) ? null : accept,
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          RecordHeading(
            icon: Icons.fact_check_outlined,
            label: p['phase'] == 'ready'
                ? '待确认'
                : p['phase'] == 'applied'
                ? '已保存'
                : p['phase'] == 'undone'
                ? '已撤销'
                : '历史方案',
            title: simple
                ? '${blocks.single['title']}'
                : replan && p['status'] == 'FEASIBLE_COMPLETE'
                ? (p['moved_tasks'] == 0 ? '现有安排无需移动' : '已生成调整方案')
                : proposalStatus(p['status']),
            subtitle: simple
                ? null
                : '${displayInstant(p['window_start'])}\n至 ${displayInstant(p['window_end'])}',
          ),
          if (expired) const SoftNotice('方案中的时间已经过去，请重新生成。', warning: true),
          if (p['phase'] == 'stale' || stale)
            const SoftNotice('你的安排已有变化，请重新生成计划。', warning: true),
          if (p['phase'] == 'applied' || p['phase'] == 'undone')
            SoftNotice(p['phase'] == 'applied' ? '这个方案已保存到日程' : '这个方案已撤销'),
          for (final message in (p['messages'] as List? ?? []).where(
            (m) =>
                m != '保留已有计划，只为尚未安排的工作补充时间' &&
                !widget.controller
                    .rows(p['uncertainty_warnings'])
                    .any((w) => w['message'] == m),
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SoftNotice(
                '$message',
                warning: !('${p['status']}'.startsWith('FEASIBLE')),
              ),
            ),
          if ((p['existing_conflict_count'] ?? 0) > 0)
            const SoftNotice('课程或考试存在时间冲突，请先核实。生成计划不会移动这些安排。', warning: true),
          if (partial)
            SoftNotice(
              '仍有 ${minutesLabel(missing)}的工作还没安排。保存这部分计划后，剩余工作仍需另行安排。',
              warning: true,
            ),
          for (final warning in widget.controller.rows(
            p['uncertainty_warnings'],
          ))
            PlanWarningNote(message: '${warning['message']}'),
          if (p['optimal'] == false && '${p['status']}'.startsWith('FEASIBLE'))
            const Text(
              '这份方案符合当前时间要求，但可能还有更合适的安排。',
              style: TextStyle(fontSize: 13),
            ),
          if (replan) ...[
            Text(
              '移动 ${p['moved_tasks'] ?? 0} 项任务 · ${p['moved_blocks'] ?? 0} 段计划\n开始时间共调整了 ${p['shift_minutes'] ?? 0} 分钟',
            ),
            for (final b in p['locked_conflicts'] ?? [])
              SoftNotice(
                '${b['title'] ?? '学习安排'} · ${displayInstant(b['start_at'])}\n这段计划目前不能移动：可能已固定、即将开始，或不在本次选择范围内。请到计划详情处理。',
                warning: true,
              ),
          ] else if (!simple)
            const SectionHeading('任务安排'),
          for (final task in simple ? [] : taskRows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: CampusColors.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task['title'],
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TaskDurationBalance(
                      target: task['target_minutes'] as num?,
                      existing: task['existing_minutes'] as num? ?? 0,
                      added: task['new_minutes'] as num? ?? 0,
                      unarranged: task['unarranged_minutes'] as num? ?? 0,
                    ),
                    const SizedBox(height: 8),
                    if ((task['outside_minutes'] ?? 0) > 0)
                      Text('其他日期已安排 ${minutesLabel(task['outside_minutes'])}'),
                    if ((task['later_minutes'] ?? 0) > 0)
                      Text('之后还需安排 ${minutesLabel(task['later_minutes'])}'),
                  ],
                ),
              ),
            ),
          if (!simple)
            SectionHeading('${replan ? '调整前后' : '新增安排'}（${blocks.length}段）'),
          for (final b in blocks)
            Stack(
              children: [
                const Positioned(
                  top: 28,
                  bottom: 20,
                  left: 11,
                  width: 2,
                  child: ColoredBox(color: CampusColors.line),
                ),
                const Positioned(
                  top: 0,
                  left: 2,
                  child: Icon(
                    Icons.schedule_rounded,
                    size: 20,
                    color: CampusColors.teal,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(30, 0, 0, 16),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: CampusColors.line),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          displayInterval(b['start_at'], b['end_at']),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: CampusColors.teal,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (!simple)
                          Text(
                            b['title'],
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          minutesLabel(b['minutes']),
                          style: const TextStyle(
                            fontSize: 14,
                            color: CampusColors.muted,
                          ),
                        ),
                        if (replan) ...[
                          const Divider(height: 24),
                          TaskChangeFacts(
                            beforeLabel: '原安排',
                            afterLabel: '本次安排',
                            before:
                                DateTime.parse(b['start_at']) ==
                                    DateTime.parse(b['before_start_at'])
                                ? '保持原位${b['locked'] == true ? ' · 已固定' : ''}'
                                : displayInterval(
                                    b['before_start_at'],
                                    b['before_end_at'],
                                  ),
                            after: displayInterval(b['start_at'], b['end_at']),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          if (blocks.isEmpty)
            CampusPanel(
              child: Text(
                replan
                    ? '暂时没有合适的调整方案，原计划保留。原因见上方说明。'
                    : '这次没有新增安排，原计划保留。尚未安排的任务见上方说明。',
              ),
            ),
          if (partial && canApply)
            AppCheckRow(
              contentPadding: EdgeInsets.zero,
              title: Text('我确认仅保存已安排部分，仍有${minutesLabel(missing)}未安排'),
              value: partialConfirmed,
              onChanged: busy
                  ? null
                  : (v) => setState(() => partialConfirmed = v!),
            ),
          if (error != null) ...[
            SoftNotice(error!, warning: true),
            const SizedBox(height: 12),
          ],

          if (!replan &&
              [
                'INFEASIBLE',
                'CHUNKING_LIMITED',
                'TIMEOUT',
              ].contains(p['status']) &&
              p['request']['allow_partial'] != true)
            AppOutlineButton(
              onPressed: busy ? null : () => regenerate(true),
              child: const Text('查看可安排部分'),
            ),
          if (p['phase'] != 'applied' && p['phase'] != 'undone')
            AppTextButton(
              onPressed: busy
                  ? null
                  : () => regenerate(p['request']['allow_partial'] == true),
              child: const Text('重新生成方案'),
            ),
          if (!simple || !canApply)
            AppTextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回修改要求'),
            ),
        ],
      ),
    );
  }
}
