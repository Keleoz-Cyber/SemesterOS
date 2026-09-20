import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../../ui/campus_widgets.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import 'risk_widgets.dart';
import 'schedule_page.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(
          today ? '今日个人计划' : '个人计划',
          action: today ? '查看全部' : '生成计划',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => today
                  ? PlanListPage(controller: controller)
                  : SchedulePage(controller: controller),
            ),
          ),
        ),
        CampusPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                controller.hasCurrentPlans
                    ? '${blocks.length}段${today ? '今日' : '未来及近7天'}计划'
                    : controller.planNotice ?? '个人计划待同步',
              ),
              for (final b in blocks.take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${displayInstant(b['start_at'])} · ${b['title']} · ${minutesLabel(b['minutes'])}',
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlanListPage(controller: controller),
                  ),
                ),
                child: const Text('查看、锁定或取消计划'),
              ),
            ],
          ),
        ),
      ],
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
    widget.controller.refresh();
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
      builder: (context) => AlertDialog(
        title: Text(b['locked'] == true ? '解锁并取消这段计划？' : '取消这段计划？'),
        content: Text(
          '${b['title']}\n${displayInstant(b['start_at'])}\n取消安排不会改变任务进度，你可以之后重新安排。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          FilledButton(
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
      builder: (context) => AlertDialog(
        title: const Text('撤销最近一轮计划？'),
        content: const Text(
          '撤销新增计划会删除本次新增的安排；撤销调整会尝试恢复原时间。只有尚未开始、之后没有修改且仍无冲突的计划才能撤销。课程、考试和任务进度不会改变。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          FilledButton(
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
    appBar: AppBar(
      title: const Text('个人计划'),
      actions: [
        IconButton(
          tooltip: '刷新计划',
          onPressed: busy ? null : () => widget.controller.refresh(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final current = c.hasCurrentPlans;
        final feed = current ? c.planFeed : null;
        final blocks = c.rows(feed?['blocks']);
        final invalid = c
            .rows(feed?['invalid_blocks'])
            .map((r) => r['block_id'])
            .toSet();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const CampusHero(
              eyebrow: '个人安排',
              title: '接下来做什么',
              subtitle: '安排好时间后\n记得按实际完成情况更新进度',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SchedulePage(controller: c),
                      ),
                    ),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('生成新的计划方案'),
            ),
            if (!current) SoftNotice(c.planNotice ?? '正在更新计划，请稍候'),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => act(() async {
                      final p = await c.generateSchedule({
                        'mode': 'replan',
                        'lead_minutes': 5,
                      });
                      if (!context.mounted) return;
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ProposalPage(controller: c, proposal: p),
                        ),
                      );
                    }),
              icon: const Icon(Icons.swap_vert),
              label: const Text('尽量少改动，重排已有计划'),
            ),
            if (feed?['latest_proposal'] != null)
              TextButton(
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
              TextButton(
                onPressed: busy
                    ? null
                    : () => undo(
                        Map<String, dynamic>.from(feed!['latest_applied']),
                        feed['revision'],
                      ),
                child: const Text('撤销最近一轮'),
              ),
            if (error != null) SoftNotice(error!, warning: true),
            if (busy) const LinearProgressIndicator(),
            const SectionHeading('未来安排与近7天记录'),
            for (final b in blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: CampusPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${b['title']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${displayInstant(b['start_at'])}\n至 ${displayInstant(b['end_at'])} · ${minutesLabel(b['minutes'])}',
                      ),
                      if (invalid.contains(b['id']))
                        const SoftNotice(
                          '这段计划与当前安排冲突，可以取消后重新安排。',
                          warning: true,
                        ),
                      if (!DateTime.parse(b['end_at']).isAfter(DateTime.now()))
                        const Text('时间已过，尚未据此确认工作完成'),
                      if (DateTime.parse(b['end_at']).isAfter(DateTime.now()))
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
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
                              label: Text(b['locked'] == true ? '解锁' : '锁定'),
                            ),
                            TextButton(
                              onPressed: busy ? null : () => cancel(b),
                              child: const Text('取消此段'),
                            ),
                          ],
                        ),
                      TextButton(
                        onPressed: () => context.push('/items/${b['item_id']}'),
                        child: const Text('查看关联任务'),
                      ),
                    ],
                  ),
                ),
              ),
            if (current && blocks.isEmpty)
              const CampusPanel(child: Text('还没有个人计划，试试让系统帮你安排时间。')),
          ],
        );
      },
    ),
  );
}
