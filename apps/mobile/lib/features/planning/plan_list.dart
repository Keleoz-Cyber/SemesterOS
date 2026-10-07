import '../../ui/app_loading.dart';
import '../../ui/app_controls.dart';
import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import '../items/task_surfaces.dart';
import 'risk_widgets.dart';
import '../../ui/assistant_scope.dart';
import 'proposal_page.dart';
import 'plan_block_sheet.dart';
import 'schedule_page.dart';
import '../../ui/date_labels.dart';

class PlanningEntry extends StatelessWidget {
  final ItemsController controller;
  final bool today;
  final bool showAction;
  const PlanningEntry({
    super.key,
    required this.controller,
    this.today = false,
    this.showAction = true,
  });
  @override
  Widget build(BuildContext context) {
    final now = schoolNow();
    final hasPendingTask = controller.items.any(
      (item) => item['lifecycle'] == 'active',
    );
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
        LayoutBuilder(
          builder: (context, box) {
            final scaler = MediaQuery.textScalerOf(context);
            final title = today ? '今日学习安排' : '学习安排';
            final compact =
                box.maxWidth <
                scaler.scale(17) * title.length + scaler.scale(13) * 4 + 72;
            void openAll() => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlanListPage(controller: controller),
              ),
            );
            return Row(
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
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: CampusColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (compact)
                  AppIconButton(
                    onPressed: openAll,
                    guardAsync: false,
                    tooltip: '查看全部安排',
                    icon: const Icon(Icons.view_agenda_outlined, size: 21),
                  )
                else
                  AppTextButton.icon(
                    onPressed: openAll,
                    guardAsync: false,
                    style: AppTextButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    iconAlignment: IconAlignment.end,
                    label: const Text('全部安排'),
                  ),
              ],
            );
          },
        ),
        if (blocks.isNotEmpty)
          for (final b in blocks.take(3))
            _CompactPlanBlock(
              block: b,
              today: today,
              onTap: () => context.push('/items/${b['item_id']}'),
            )
        else if (!controller.hasCurrentPlans || hasPendingTask)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              controller.hasCurrentPlans
                  ? (today ? '今天还没有学习安排' : '任务还没有安排到具体时间')
                  : controller.planNotice ?? '安排正在同步',
              style: const TextStyle(fontSize: 14, color: CampusColors.muted),
            ),
          ),
        if (showAction && (hasPendingTask || blocks.isNotEmpty))
          Align(
            alignment: Alignment.centerLeft,
            child: AppTextButton.icon(
              key: const ValueKey('learning-plan-action'),
              onPressed: () => AssistantScope.open(
                context,
                initialText: today
                    ? '请结合今天的日程和任务，帮我安排今天的学习时间。'
                    : '请结合现有日程和任务，帮我安排接下来的学习时间；有冲突的安排请一起调整，先给我方案。',
                autoSubmit: true,
              ),
              guardAsync: false,
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
  final bool grouped;
  final VoidCallback onTap;
  const _CompactPlanBlock({
    required this.block,
    required this.today,
    this.grouped = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final start = schoolTime(block['start_at']);
    final end = schoolTime(block['end_at']);
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
                        grouped
                            ? DateUtils.isSameDay(start, end)
                                  ? hhmm(end)
                                  : '${end.month}/${end.day}\n${hhmm(end)}'
                            : today
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
        title: Text(b['locked'] == true ? '取消这段固定安排？' : '取消这段安排？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${b['title']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TaskFactStrip(
              label: '取消的时间段',
              value: displayInterval(b['start_at'], b['end_at']),
              icon: Icons.event_busy_outlined,
              accent: CampusColors.teal,
            ),
            const Text(
              '任务进度保留，可以重新安排。',
              style: TextStyle(fontSize: 14, color: CampusColors.muted),
            ),
          ],
        ),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          AppButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(b['locked'] == true ? '确认取消' : '确认取消'),
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
        title: const Text('撤销最近一次安排？'),
        content: const Text('撤销本次新增或调整的学习安排。已开始或后来修改过的安排会保留。'),
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

  Future<void> openBlock(Map<String, dynamic> block, bool conflict) async {
    final choice = await showPlanBlock(context, block, conflict: conflict);
    if (!mounted) return;
    if (choice == 'cancel') await cancel(block);
    if (choice == 'lock') {
      await act(
        () => widget.controller.changePlanBlock(
          block,
          locked: block['locked'] != true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('学习安排')),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller,
            feed = c.hasCurrentPlans ? c.planFeed : null;
        final blocks = c.rows(feed?['blocks'])
          ..sort((a, b) => '${a['start_at']}'.compareTo('${b['start_at']}'));
        final invalid = c
            .rows(feed?['invalid_blocks'])
            .map((r) => r['block_id'])
            .toSet();
        return RefreshIndicator(
          onRefresh: c.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final scaler = MediaQuery.textScalerOf(context);
                  final compact =
                      box.maxWidth <
                      scaler.scale(18) * 4 + scaler.scale(14) * 4 + 96;
                  Future<void> arrange() async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SchedulePage(controller: c),
                      ),
                    );
                    if (mounted) await c.refresh();
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${blocks.length}段安排',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      AppLoadingIndicator(
                        compact: true,
                        visible: busy,
                        label: '正在更新安排',
                      ),
                      const SizedBox(width: 8),
                      if (compact)
                        AppIconButton.filled(
                          onPressed: busy ? null : arrange,
                          tooltip: '安排任务',
                          icon: const Icon(Icons.add_rounded, size: 20),
                        )
                      else
                        AppButton.icon(
                          onPressed: busy ? null : arrange,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('安排任务'),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              if (!c.hasCurrentPlans) Text(c.planNotice ?? '正在读取安排'),
              if (error != null) SoftNotice(error!, warning: true),
              for (var i = 0; i < blocks.length; i++) ...[
                if (i == 0 ||
                    !DateUtils.isSameDay(
                      schoolTime(blocks[i]['start_at']),
                      schoolTime(blocks[i - 1]['start_at']),
                    ))
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: Text(
                      studentDate(
                        schoolTime(blocks[i]['start_at']),
                        weekday: true,
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CampusColors.muted,
                      ),
                    ),
                  ),
                _CompactPlanBlock(
                  block: blocks[i],
                  today: false,
                  grouped: true,
                  onTap: busy
                      ? () => {}
                      : () => openBlock(
                          blocks[i],
                          invalid.contains(blocks[i]['id']),
                        ),
                ),
                if (invalid.contains(blocks[i]['id']))
                  const Padding(
                    padding: EdgeInsets.only(left: 68, bottom: 6),
                    child: Text(
                      '时间重叠',
                      style: TextStyle(
                        fontSize: 12,
                        color: CampusColors.warning,
                      ),
                    ),
                  ),
                const Divider(height: 1, color: CampusColors.line),
              ],
              if (c.hasCurrentPlans && blocks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Text(
                    '暂无学习安排',
                    style: TextStyle(color: CampusColors.muted),
                  ),
                ),
              if (feed?['latest_proposal'] != null ||
                  feed?['latest_applied'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: AppDisclosure(
                    title: const Text('最近一次安排'),
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
                          child: const Text('查看方案'),
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
                          child: const Text('撤销这次安排'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
