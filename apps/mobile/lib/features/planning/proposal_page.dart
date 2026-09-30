import '../../ui/app_controls.dart';
import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import 'dart:async';
import '../../ui/campus_widgets.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import 'risk_widgets.dart';

String proposalStatus(String? status) => switch (status) {
  'FEASIBLE_COMPLETE' => '已安排好这次的任务',
  'FEASIBLE_PARTIAL' => '目前只能安排一部分',
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
      appBar: AppBar(title: Text(replan ? '查看调整方案' : '查看计划方案')),
      bottomNavigationBar: canApply
          ? ActionFooter(
              label: partial
                  ? '保存已安排部分（仍有${minutesLabel(missing)}未安排）'
                  : replan
                  ? '确认调整计划'
                  : '确认保存计划',
              icon: Icons.check_rounded,
              onPressed: busy || (partial && !partialConfirmed) ? null : accept,
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          RecordHeading(
            icon: Icons.fact_check_outlined,
            label: p['phase'] == 'ready' ? '待确认' : '历史方案',
            title: replan && p['status'] == 'FEASIBLE_COMPLETE'
                ? (p['moved_tasks'] == 0 ? '现有安排无需移动' : '已生成调整方案')
                : proposalStatus(p['status']),
            subtitle:
                '${displayInstant(p['window_start'])}\n至 ${displayInstant(p['window_end'])}',
          ),
          if (expired) const SoftNotice('方案中的时间已经过去，请重新生成。', warning: true),
          if (p['phase'] == 'stale' || stale)
            const SoftNotice('你的安排已有变化，请重新生成计划。', warning: true),
          if (p['phase'] == 'applied' || p['phase'] == 'undone')
            SoftNotice(p['phase'] == 'applied' ? '这个方案已保存到日程' : '这个方案已撤销'),
          for (final message in p['messages'] ?? [])
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
                '${b['title'] ?? '个人计划'} · ${displayInstant(b['start_at'])}\n这段计划目前不能移动：可能已锁定、即将开始，或不在本次选择范围内。请到计划详情处理。',
                warning: true,
              ),
          ] else
            const SectionHeading('任务安排'),
          for (final task in p['tasks'] ?? [])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CampusPanel(
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
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        _proposalMetric('目标时长', task['target_minutes']),
                        _proposalMetric('原有安排', task['existing_minutes']),
                        _proposalMetric('本次新增', task['new_minutes']),
                        _proposalMetric(
                          '未安排',
                          task['unarranged_minutes'],
                          attention:
                              (task['unarranged_minutes'] as num? ?? 0) > 0,
                        ),
                      ],
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
          SectionHeading('${replan ? '调整前后' : '新增安排'}（${blocks.length}段）'),
          for (final b in blocks)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 24,
                    child: Column(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 20,
                          color: CampusColors.teal,
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Container(width: 2, color: CampusColors.line),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: CampusColors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              displayInstant(b['start_at']),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: CampusColors.teal,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              b['title'],
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '至 ${displayInstant(b['end_at'])} · ${minutesLabel(b['minutes'])}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: CampusColors.muted,
                              ),
                            ),
                            if (replan) ...[
                              const Divider(height: 24),
                              Text(
                                DateTime.parse(b['start_at']) ==
                                        DateTime.parse(b['before_start_at'])
                                    ? '保持原位${b['locked'] == true ? ' · 已锁定' : ''}'
                                    : '原安排：${displayInstant(b['before_start_at'])} — ${displayInstant(b['before_end_at'])}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: CampusColors.muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
          if (busy) const LinearProgressIndicator(),
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
          AppTextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回修改要求'),
          ),
        ],
      ),
    );
  }
}

Widget _proposalMetric(String label, dynamic value, {bool attention = false}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: CampusColors.muted),
        ),
        const SizedBox(height: 4),
        Text(
          minutesLabel(value),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: attention ? CampusColors.warning : CampusColors.ink,
          ),
        ),
      ],
    );
