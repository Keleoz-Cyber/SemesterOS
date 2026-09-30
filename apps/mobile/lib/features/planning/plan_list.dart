import '../../ui/app_controls.dart';
import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import 'risk_widgets.dart';
import '../../ui/assistant_scope.dart';
import 'proposal_page.dart';

class PlanningEntry extends StatelessWidget {
  final ItemsController controller;
  final bool today;
  const PlanningEntry({
    super.key,
    required this.controller,
    this.today = false,
  });
  @override
  Widget build(BuildContext context) {
    final now = schoolNow();
    final blocks = controller.hasCurrentPlans
        ? controller.rows(controller.planFeed?['blocks']).where((b) {
            final d = schoolTime(b['start_at']);
            return !today ||
                (d.year == now.year &&
                    d.month == now.month &&
                    d.day == now.day);
          }).toList()
        : <Map<String, dynamic>>[];
    blocks.removeWhere(
      (b) => DateTime.parse(b['end_at']).isBefore(DateTime.now()),
    );
    blocks.sort(
      (a, b) => DateTime.parse(
        a['start_at'],
      ).compareTo(DateTime.parse(b['start_at'])),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          key: const ValueKey('learning-plan-header'),
          children: [
            const Icon(
              Icons.timeline_rounded,
              size: 20,
              color: CampusColors.teal,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                today ? '今日学习安排' : '学习安排',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: CampusColors.ink,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlanListPage(controller: controller),
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: CampusColors.primary,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('安排记录'),
            ),
          ],
        ),
        if (blocks.isNotEmpty)
          for (final b in blocks.take(3))
            _CompactPlanBlock(
              block: b,
              today: today,
              onTap: () => context.push('/items/${b['item_id']}'),
            )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              controller.hasCurrentPlans
                  ? (today ? '今天还没有学习安排' : '任务还没有安排到具体时间')
                  : controller.planNotice ?? '安排正在同步',
              style: const TextStyle(fontSize: 14, color: CampusColors.muted),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('learning-plan-action'),
            onPressed: () => AssistantScope.open(
              context,
              initialText: today
                  ? '请结合今天的日程和任务，帮我安排今天的学习时间。'
                  : '请结合现有日程和任务，帮我安排接下来的学习时间；有冲突的安排请一起调整，先给我方案。',
              autoSubmit: true,
            ),
            style: TextButton.styleFrom(
              foregroundColor: CampusColors.primary,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('安排任务'),
          ),
        ),
      ],
    );
  }
}

class _CompactPlanBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool today;
  final VoidCallback onTap;
  const _CompactPlanBlock({
    required this.block,
    required this.today,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final start = schoolTime(block['start_at']);
    final scaled = MediaQuery.textScalerOf(context).scale(16) > 22;
    return Material(
      key: ValueKey('learning-plan-${block['id']}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: scaled ? 76 : 62,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hhmm(start),
                        style: const TextStyle(
                          color: CampusColors.teal,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        today
                            ? minutesLabel(block['minutes'])
                            : '${start.month}/${start.day}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: CampusColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(width: 2, color: CampusColors.teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${block['title']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: CampusColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  block['locked'] == true
                      ? Icons.lock_outline_rounded
                      : Icons.chevron_right_rounded,
                  size: 20,
                  color: CampusColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlanListPage extends StatefulWidget {
  final ItemsController controller;
  const PlanListPage({super.key, required this.controller});
  @override
  State<PlanListPage> createState() => _PlanListPageState();
}

class _PlanListPageState extends State<PlanListPage> {
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.refresh();
    });
  }

  Future<void> act(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel(Map<String, dynamic> b) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: Text(b['locked'] == true ? '解锁并取消这段计划？' : '取消这段计划？'),
        content: Text(
          '${b['title']}\n${displayInstant(b['start_at'])}\n取消安排不会改变任务进度，你可以之后重新安排。',
        ),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          AppButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(b['locked'] == true ? '确认解锁并取消' : '确认取消'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await act(
        () => widget.controller.changePlanBlock(
          b,
          cancel: true,
          confirmLocked: b['locked'] == true,
        ),
      );
    }
  }

  Future<void> undo(Map<String, dynamic> p, int revision) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('撤销最近一轮计划？'),
        content: const Text(
          '撤销新增计划会删除本次新增的安排；撤销调整会尝试恢复原时间。只有尚未开始、之后没有修改且仍无冲突的计划才能撤销。课程、考试和任务进度不会改变。',
        ),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          AppButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认撤销'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await act(() => widget.controller.undoSchedule(p, revision));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('安排记录')),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final current = c.hasCurrentPlans;
        final feed = current ? c.planFeed : null;
        final blocks = c.rows(feed?['blocks']);
        final now = DateTime.now();
        final invalid = c
            .rows(feed?['invalid_blocks'])
            .map((r) => r['block_id'])
            .toSet();
        return RefreshIndicator(
          onRefresh: widget.controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              const RecordHeading(
                title: '已安排的学习时间',
                label: '安排记录',
                icon: Icons.event_note_outlined,
              ),
              AppButton.icon(
                onPressed: busy
                    ? null
                    : () => AssistantScope.open(
                        context,
                        initialText:
                            '请检查现有任务和学习安排，帮我安排接下来的学习时间，有冲突的安排一起调整，先给我方案。',
                        autoSubmit: true,
                      ),
                icon: const Icon(Icons.add_task_rounded),
                label: const Text('安排任务'),
              ),
              const SizedBox(height: 16),
              if (!current) SoftNotice(c.planNotice ?? '正在更新计划，请稍候'),
              if (feed?['latest_proposal'] != null ||
                  feed?['latest_applied'] != null)
                EditorSection(
                  title: '最近一轮方案',
                  icon: Icons.history_rounded,
                  children: [
                    if (feed?['latest_proposal'] != null)
                      AppTextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProposalPage(
                              controller: c,
                              proposal: Map<String, dynamic>.from(
                                feed!['latest_proposal'],
                              ),
                            ),
                          ),
                        ),
                        child: const Text('查看上次的计划方案'),
                      ),
                    if (feed?['latest_applied'] != null)
                      AppTextButton(
                        onPressed: busy
                            ? null
                            : () => undo(
                                Map<String, dynamic>.from(
                                  feed!['latest_applied'],
                                ),
                                feed['revision'],
                              ),
                        child: const Text('撤销最近一轮'),
                      ),
                  ],
                ),
              if (error != null) SoftNotice(error!, warning: true),
              if (busy) const LinearProgressIndicator(),
              for (final upcoming in [true, false]) ...[
                if (blocks.any(
                  (b) => DateTime.parse(b['end_at']).isAfter(now) == upcoming,
                ))
                  SectionHeading(upcoming ? '接下来的安排' : '近7天已结束的安排'),
                for (final b in blocks.where(
                  (b) => DateTime.parse(b['end_at']).isAfter(now) == upcoming,
                ))
                  _PlanTimelineRecord(
                    startAt: b['start_at'],
                    child: CampusPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (b['locked'] == true) ...[
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: StatusPill('已锁定'),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            '${b['title']}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '至 ${displayInstant(b['end_at'])} · ${minutesLabel(b['minutes'])}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: CampusColors.muted,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (invalid.contains(b['id']))
                            const SoftNotice(
                              '这段计划与当前安排冲突，可以取消后重新安排。',
                              warning: true,
                            ),
                          if (!DateTime.parse(b['end_at']).isAfter(now))
                            const Text('时间已过，尚未据此确认工作完成'),
                          if (DateTime.parse(b['end_at']).isAfter(now))
                            Wrap(
                              spacing: 8,
                              children: [
                                AppTextButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => act(
                                          () => c.changePlanBlock(
                                            b,
                                            locked: b['locked'] != true,
                                          ),
                                        ),
                                  icon: Icon(
                                    b['locked'] == true
                                        ? Icons.lock
                                        : Icons.lock_open,
                                  ),
                                  label: Text(
                                    b['locked'] == true ? '解锁' : '锁定',
                                  ),
                                ),
                                AppTextButton(
                                  onPressed: busy ? null : () => cancel(b),
                                  child: const Text('取消此段'),
                                ),
                              ],
                            ),
                          AppTextButton(
                            onPressed: () =>
                                context.push('/items/${b['item_id']}'),
                            child: const Text('查看关联任务'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (current && blocks.isEmpty)
                const CampusPanel(child: Text('还没有个人计划，点击“安排任务”选择学习时间。')),
            ],
          ),
        );
      },
    ),
  );
}

class _PlanTimelineRecord extends StatelessWidget {
  final String startAt;
  final Widget child;
  const _PlanTimelineRecord({required this.startAt, required this.child});
  @override
  Widget build(BuildContext context) {
    final at = schoolTime(startAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: MediaQuery.textScalerOf(context).scale(17) > 22 ? 92 : 76,
            child: Padding(
              padding: const EdgeInsets.only(top: 16, right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${at.month}/${at.day}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: CampusColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hhmm(at),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: CampusColors.teal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(width: 24, height: 2, color: CampusColors.teal),
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
