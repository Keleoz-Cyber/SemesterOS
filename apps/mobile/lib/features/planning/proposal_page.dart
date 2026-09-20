import 'package:flutter/material.dart';
import 'dart:async';
import '../../ui/campus_widgets.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import 'risk_widgets.dart';

String proposalStatus(String? status) => switch (status) {
  'FEASIBLE_COMPLETE' => '本轮目标已排入候选',
  'FEASIBLE_PARTIAL' => '仅安排了可排部分',
  'INFEASIBLE' => '当前约束下排不下',
  'CHUNKING_LIMITED' => '当前分块方式排不下',
  'TIMEOUT' => '时限内未得到可行方案',
  'INPUT_LIMIT' => '超出本轮输入范围',
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
      if (mounted) setState(() => error = '$e');
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
      if (mounted) setState(() => error = '$e');
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
      appBar: AppBar(title: Text(replan ? '核对个人重排' : '核对候选计划')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CampusHero(
            eyebrow: p['phase'] == 'ready'
                ? 'PROPOSAL / 尚未应用'
                : 'PROPOSAL / 候选记录',
            title: replan && p['status'] == 'FEASIBLE_COMPLETE'
                ? (p['moved_tasks'] == 0 ? '现有安排无需移动' : '已生成个人重排方案')
                : proposalStatus(p['status']),
            subtitle:
                '${displayInstant(p['window_start'])}\n至 ${displayInstant(p['window_end'])}',
          ),
          const SizedBox(height: 16),
          if (p['valid_until'] != null)
            Text(
              '候选有效至 ${displayInstant(p['valid_until'])}',
              style: const TextStyle(fontSize: 12),
            ),
          if (expired) const SoftNotice('候选时间已过，请重新生成后确认。', warning: true),
          if (p['phase'] == 'stale' || stale)
            const SoftNotice('生成后安排已变化，此候选不能应用，请重新生成。', warning: true),
          if (p['phase'] == 'applied' || p['phase'] == 'undone')
            SoftNotice(p['phase'] == 'applied' ? '此候选已经应用' : '此候选已撤销'),
          for (final message in p['messages'] ?? [])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SoftNotice(
                '$message',
                warning: !('${p['status']}'.startsWith('FEASIBLE')),
              ),
            ),
          if ((p['existing_conflict_count'] ?? 0) > 0)
            const SoftNotice('固定安排已有冲突仍需核对，本轮不会移动课程或考试。', warning: true),
          if (partial)
            SoftNotice(
              '仍有 ${minutesLabel(missing)} 本轮工作未安排。应用部分方案不会把任务标记完成。',
              warning: true,
            ),
          if (p['optimal'] == false && '${p['status']}'.startsWith('FEASIBLE'))
            const Text('已通过约束校验，但未证明当前优化目标最优。', style: TextStyle(fontSize: 13)),
          if (replan) ...[
            Text(
              '移动 ${p['moved_tasks'] ?? 0} 项任务 · ${p['moved_blocks'] ?? 0} 段计划\n开始时刻偏移合计 ${p['shift_minutes'] ?? 0} 分钟',
            ),
            const SoftNotice('仅重排已有未来块。保持时长与锁定，不自动新增未覆盖工作；确认前原计划保持。'),
            for (final b in p['locked_conflicts'] ?? [])
              SoftNotice(
                '${b['title'] ?? '个人计划'} · ${displayInstant(b['start_at'])}\n已锁定、开始、即将开始或未纳入移动范围，请明确处理。',
                warning: true,
              ),
          ] else
            const SectionHeading('每项工作量'),
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
                    Text(
                      '本轮目标 ${minutesLabel(task['target_minutes'])} · 已有覆盖 ${minutesLabel(task['existing_minutes'])}',
                    ),
                    Text(
                      '本轮新增 ${minutesLabel(task['new_minutes'])} · 本轮未安排 ${minutesLabel(task['unarranged_minutes'])}',
                    ),
                    if ((task['outside_minutes'] ?? 0) > 0)
                      Text('窗口外已有覆盖 ${minutesLabel(task['outside_minutes'])}'),
                    if ((task['later_minutes'] ?? 0) > 0)
                      Text('后续仍需安排 ${minutesLabel(task['later_minutes'])}'),
                  ],
                ),
              ),
            ),
          SectionHeading('${replan ? '重排对照' : '新增时间块'}（${blocks.length}段）'),
          for (final b in blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CampusPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b['title'],
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (replan)
                      Text(
                        DateTime.parse(b['start_at']) ==
                                DateTime.parse(b['before_start_at'])
                            ? '保持原位${b['locked'] == true ? ' · 已锁定' : ''}'
                            : '原安排：${displayInstant(b['before_start_at'])} — ${displayInstant(b['before_end_at'])}',
                      ),
                    Text(
                      '${displayInstant(b['start_at'])}\n至 ${displayInstant(b['end_at'])} · ${minutesLabel(b['minutes'])}',
                    ),
                  ],
                ),
              ),
            ),
          if (blocks.isEmpty)
            CampusPanel(
              child: Text(
                replan
                    ? '未得到可应用的重排，原计划保持，请查看上方原因。'
                    : '没有新增时间块。已有覆盖保持，未安排工作见上方说明。',
              ),
            ),
          if (partial && canApply)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('我确认仅应用部分方案，仍有${minutesLabel(missing)}未安排'),
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
          if (canApply)
            FilledButton(
              onPressed: busy || (partial && !partialConfirmed) ? null : accept,
              child: Text(
                partial
                    ? '应用部分方案（仍有${minutesLabel(missing)}未安排）'
                    : replan
                    ? '确认应用个人计划重排'
                    : '确认应用本轮计划',
              ),
            ),
          if (!replan &&
              [
                'INFEASIBLE',
                'CHUNKING_LIMITED',
                'TIMEOUT',
              ].contains(p['status']) &&
              p['request']['allow_partial'] != true)
            OutlinedButton(
              onPressed: busy ? null : () => regenerate(true),
              child: const Text('查看可安排部分'),
            ),
          if (p['phase'] != 'applied' && p['phase'] != 'undone')
            TextButton(
              onPressed: busy
                  ? null
                  : () => regenerate(p['request']['allow_partial'] == true),
              child: const Text('按当前条件重新生成'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回调整条件'),
          ),
        ],
      ),
    );
  }
}
