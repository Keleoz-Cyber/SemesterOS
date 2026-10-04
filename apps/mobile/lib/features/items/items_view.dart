import '../../ui/app_loading.dart';
import 'dart:async';
import 'dart:convert';
import '../../core/api.dart' show userError;
import '../../ui/app_controls.dart';
import '../../ui/performance_widgets.dart';
import '../../ui/time_urgency.dart';
import '../../ui/empty_states.dart';
import '../../ui/motion.dart';
import '../../ui/app_sheet.dart';
import '../home/home_preferences.dart';
import '../planning/progress_page.dart';
import 'item_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/campus_theme.dart';
import '../../ui/app_selection.dart';
import 'items_controller.dart';
import 'item_widgets.dart';
import '../planning/risk_widgets.dart';
import '../planning/availability_page.dart';
import '../planning/plan_list.dart';
import '../changes/changes_page.dart';

class ItemsView extends StatefulWidget {
  final ItemsController controller;
  final VoidCallback onCreate;
  final void Function(String) onOpen;
  final void Function(Map<String, dynamic>)? onEdit;
  final bool sliver;
  const ItemsView({
    super.key,
    required this.controller,
    required this.onCreate,
    required this.onOpen,
    this.onEdit,
    this.sliver = false,
  });
  @override
  State<ItemsView> createState() => _ItemsViewState();
}

class _ItemsViewState extends State<ItemsView> {
  String filter = 'active';
  bool sorting = false;
  late HomePreferences preferences;
  final projections = MemoryCache<String, List<Map<String, dynamic>>>(
    maxSize: 4,
    expiration: const Duration(seconds: 30),
  );
  final processing = <String>{};
  ItemsController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    bindPreferences();
  }

  void bindPreferences() {
    final owner = c.owner ?? '',
        sid = c.semesterId ?? '',
        generation = c.api.generation;
    preferences = HomePreferences(
      c.cache,
      owner,
      sid,
      () =>
          mounted &&
          c.owner == owner &&
          c.semesterId == sid &&
          c.api.generation == generation,
    );
    projections.setOwner('$owner:$sid:$generation');
    unawaited(preferences.restore());
  }

  @override
  void didUpdateWidget(covariant ItemsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      preferences.dispose();
      bindPreferences();
      sorting = false;
    }
  }

  @override
  void dispose() {
    preferences.dispose();
    projections.clear();
    super.dispose();
  }

  List<Map<String, dynamic>> orderedRows() {
    final stamp = jsonEncode([
      c.owner,
      c.semesterId,
      c.api.generation,
      c.itemsRevision,
      filter,
      DateTime.now().millisecondsSinceEpoch ~/ 60000,
      identityHashCode(c.analysis),
      preferences.taskOrder,
      for (final row in c.items)
        [
          row['id'],
          row['version'],
          row['lifecycle'],
          row['priority'],
          row['anchor_at'],
          row['time'],
        ],
    ]);
    final cached = projections.get(stamp);
    if (cached != null) return cached;
    final rows = orderedItems(
      c.items.where((r) => r['lifecycle'] == filter).toList(),
    );
    final manual = {
      for (var i = 0; i < preferences.taskOrder.length; i++)
        preferences.taskOrder[i]: i,
    };
    int urgency(Map<String, dynamic> row) {
      final deadline = itemDeadline(row);
      if (deadline?.isBefore(DateTime.now()) == true) return 0;
      final t = row['time'] as Map?;
      if (t?['precision'] == 'date' &&
          t?['meaning'] != 'start' &&
          t?['meaning'] != 'window') {
        final d = DateTime.tryParse('${t?['date']}');
        final now = DateTime.now().toUtc().add(const Duration(hours: 8));
        if (d != null &&
            !d.isAfter(DateTime.utc(now.year, now.month, now.day))) {
          return 0;
        }
      }
      if (c.riskFor(row)?['level'] == 'high') return 1;
      if (row['priority'] == 'high') return 2;
      return row['priority'] == 'low' ? 4 : 3;
    }

    final original = {for (var i = 0; i < rows.length; i++) rows[i]['id']: i};
    rows.sort((a, b) {
      if (manual.isNotEmpty) {
        final rank = (manual[a['id']] ?? 1000000).compareTo(
          manual[b['id']] ?? 1000000,
        );
        if (rank != 0) return rank;
      } else if (filter == 'active') {
        final rank = urgency(a).compareTo(urgency(b));
        if (rank != 0) return rank;
      }
      return original[a['id']]!.compareTo(original[b['id']]!);
    });
    projections.set(stamp, rows);
    return rows;
  }

  Future<void> reorder(
    List<Map<String, dynamic>> rows,
    int old,
    int next, {
    bool adjusted = false,
  }) async {
    final ids = rows.map((r) => '${r['id']}').toList();
    if (!adjusted && next > old) next--;
    final id = ids.removeAt(old);
    ids.insert(next, id);
    await preferences.change(
      taskOrder: [
        ...ids,
        ...preferences.taskOrder.where((v) => !ids.contains(v)),
      ],
    );
  }

  Future<void> chooseSort() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppSheetHeading(title: '任务排序'),
            AppTile(
              title: const Text('自动排序'),
              leading: const Icon(Icons.auto_awesome_outlined),
              onTap: () => Navigator.pop(sheet, 'auto'),
            ),
            AppTile(
              title: const Text('拖动排序'),
              leading: const Icon(Icons.drag_handle_rounded),
              onTap: () => Navigator.pop(sheet, 'manual'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'auto') await preferences.change(taskOrder: []);
    if (mounted) setState(() => sorting = choice == 'manual');
  }

  Future<void> moveTask(Map<String, dynamic> row) async {
    final owner = c.owner, sid = c.semesterId, generation = c.api.generation;
    final id = '${row['id']}';
    final current = orderedRows();
    final at = current.indexWhere((item) => '${item['id']}' == id);
    if (at < 0 || current.length < 2) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSheetHeading(title: '${row['title']}'),
            if (at > 0)
              AppTile(
                title: const Text('上移'),
                leading: const Icon(Icons.arrow_upward_rounded),
                onTap: () => Navigator.pop(sheet, 'up'),
              ),
            if (at < current.length - 1)
              AppTile(
                title: const Text('下移'),
                leading: const Icon(Icons.arrow_downward_rounded),
                onTap: () => Navigator.pop(sheet, 'down'),
              ),
          ],
        ),
      ),
    );
    if (!mounted ||
        !sorting ||
        choice == null ||
        owner != c.owner ||
        sid != c.semesterId ||
        generation != c.api.generation) {
      return;
    }
    final fresh = orderedRows();
    final index = fresh.indexWhere((item) => '${item['id']}' == id);
    if (index < 0) return;
    if (choice == 'up' && index > 0) {
      await reorder(fresh, index, index - 1);
    }
    if (choice == 'down' && index < fresh.length - 1) {
      await reorder(fresh, index, index + 2);
    }
  }

  Future<void> actions(Map<String, dynamic> row) async {
    final id = '${row['id']}', generation = c.api.generation;
    if (processing.contains(id)) return;
    final choices = <String, (String, IconData)>{
      'open': ('查看详情', Icons.open_in_new_rounded),
      if (widget.onEdit != null) 'edit': ('编辑', Icons.edit_outlined),
      if (row['lifecycle'] == 'active' && row['kind'] != 'exam')
        'progress': ('更新进度', Icons.timelapse_rounded),
      if (row['lifecycle'] == 'active')
        'complete': ('标记完成', Icons.task_alt_rounded)
      else
        'restore': ('恢复事项', Icons.restore_rounded),
    };
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSheetHeading(title: '${row['title']}'),
            for (final entry in choices.entries)
              AppTile(
                title: Text(entry.value.$1),
                leading: Icon(entry.value.$2),
                onTap: () => Navigator.pop(sheet, entry.key),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null || generation != c.api.generation) return;
    if (choice == 'open') {
      widget.onOpen(id);
      return;
    }
    if (choice == 'edit') {
      widget.onEdit?.call(row);
      return;
    }
    processing.add(id);
    try {
      if (choice == 'progress') {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProgressPage(controller: c, item: row),
          ),
        );
      } else {
        final changed = await changeItemLifecycle(
          context,
          c,
          row,
          choice == 'complete' ? 'completed' : 'active',
        );
        if (changed && mounted && choice == 'complete') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('已完成'),
              action: SnackBarAction(
                label: '撤销',
                onPressed: () async {
                  try {
                    final fresh = await c.get(id);
                    if (mounted && generation == c.api.generation) {
                      await changeItemLifecycle(context, c, fresh, 'active');
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(userError(e))));
                    }
                  }
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(e))));
      }
    } finally {
      processing.remove(id);
    }
  }

  Widget taskRow(
    Map<String, dynamic> row,
    int index,
    List<Map<String, dynamic>> rows,
  ) {
    final card = _TaskRow(
      key: ValueKey('plan-task-${row['id']}'),
      item: row,
      controller: c,
      onOpen: () => widget.onOpen(row['id']),
      onEdit: widget.onEdit == null ? null : () => widget.onEdit!(row),
      onActions: () => actions(row),
    );
    if (!sorting) return card;
    return Row(
      key: ValueKey('ordered-task-${row['id']}'),
      children: [
        Expanded(child: card),
        Semantics(
          label: '拖动${row['title']}调整顺序',
          customSemanticsActions: {
            if (index > 0)
              const CustomSemanticsAction(label: '上移'): () =>
                  reorder(rows, index, index - 1),
            if (index < rows.length - 1)
              const CustomSemanticsAction(label: '下移'): () =>
                  reorder(rows, index, index + 2),
          },
          child: ReorderableDelayedDragStartListener(
            index: index,
            child: AppIconButton(
              tooltip: '移动任务',
              onPressed: rows.length < 2 ? null : () => moveTask(row),
              icon: const Icon(
                Icons.drag_handle_rounded,
                color: CampusColors.muted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget liftedTask(Widget child, int index, Animation<double> lift) =>
      AnimatedBuilder(
        animation: lift,
        child: child,
        builder: (context, child) {
          final amount = AppMotion.reduced(context)
              ? 1.0
              : Curves.easeOutCubic.transform(lift.value);
          return Transform.translate(
            offset: Offset(0, -3 * amount),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CampusColors.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: CampusColors.ink.withValues(alpha: .14 * amount),
                    blurRadius: 16 * amount,
                    offset: Offset(0, 6 * amount),
                  ),
                ],
              ),
              child: Material(color: Colors.transparent, child: child),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, preferences]),
    builder: (context, _) {
      final rows = orderedRows();
      Widget makeHeader(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlanningEntry(controller: c),
          const SizedBox(height: 8),
          RiskOverview(
            controller: c,
            onSettings: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AvailabilityPage(controller: c),
              ),
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, box) {
              final actions = <Widget>[
                if (sorting)
                  AppTextButton(
                    onPressed: () => setState(() => sorting = false),
                    child: const Text('完成'),
                  )
                else if (rows.length > 1)
                  AppIconButton(
                    tooltip: '调整任务顺序',
                    onPressed: chooseSort,
                    icon: const Icon(Icons.sort_rounded),
                  ),
                if (rows.isNotEmpty ||
                    (c.itemsRevision == null && c.busy) ||
                    filter != 'active')
                  AppIconButton(
                    tooltip: '添加事项',
                    onPressed: widget.onCreate,
                    icon: const Icon(Icons.add_rounded),
                  ),
              ];
              final scaler = MediaQuery.textScalerOf(context);
              final needed =
                  scaler.scale(19) * 4 +
                  scaler.scale(14) * '${rows.length}'.length +
                  46 +
                  (sorting ? 80 : 48) * actions.length;
              final stacked = box.maxWidth < needed;
              final heading = Semantics(
                label: '任务清单，${rows.length}项',
                child: ExcludeSemantics(
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        '任务清单',
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${rows.length}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: CampusColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
              final status = AppLoadingIndicator(
                compact: true,
                visible: c.busy,
                label: '正在更新任务',
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        Expanded(child: heading),
                        status,
                        if (!stacked) ...actions,
                      ],
                    ),
                  ),
                  if (stacked && actions.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: actions,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          AppSegmentedControl<String>(
            value: filter,
            options: const {
              'active': '待处理',
              'completed': '已完成',
              'cancelled': '已取消',
            },
            onChanged: (value) => setState(() {
              filter = value;
              sorting = false;
            }),
          ),
          const SizedBox(height: 12),
          if (c.notice != null) ...[
            SoftNotice(c.notice!, warning: true),
            const SizedBox(height: 12),
          ],
          if (rows.isEmpty && (c.itemsRevision != null || !c.busy))
            EmptyItems(
              title: filter == 'active'
                  ? '暂时没有待办'
                  : filter == 'completed'
                  ? '还没有完成的任务'
                  : '没有已取消的任务',
              customMessage: filter == 'active'
                  ? '把作业、考试或想做的事记下来。'
                  : '切换到待处理，继续安排接下来的事。',
              onAddItem: filter == 'active' ? widget.onCreate : null,
            ),
        ],
      );
      final header = BuildCache(
        cacheKey: 'task-header',
        ownerGeneration: '${c.owner}:${c.semesterId}:${c.api.generation}',
        invalidationKey: jsonEncode([
          filter,
          sorting,
          rows.length,
          c.itemsRevision,
          identityHashCode(c.analysis),
          c.notice,
          c.busy,
          preferences.taskOrder,
        ]),
        builder: makeHeader,
      );
      final footer = Padding(
        padding: const EdgeInsets.only(top: 16),
        child: AppDisclosure(
          title: const Text('提醒与变更'),
          childrenPadding: const EdgeInsets.all(12),
          children: [
            SoftNotice(c.notificationStatus ?? '同步事项后更新本机提醒'),
            AppTextButton.icon(
              onPressed: () => c.syncNotifications(requestPermission: true),
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('开启或检查系统通知'),
            ),
            AppTextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChangesPage(controller: c)),
              ),
              icon: const Icon(Icons.published_with_changes),
              label: const Text('记录调课或停课'),
            ),
          ],
        ),
      );
      if (widget.sliver) {
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(child: header),
            if (sorting)
              SliverReorderableList(
                itemCount: rows.length,
                itemBuilder: (context, i) => taskRow(rows[i], i, rows),
                proxyDecorator: liftedTask,
                onReorderItem: (a, b) => reorder(rows, a, b, adjusted: true),
              )
            else
              VirtualizedSliverList<Map<String, dynamic>>(
                items: rows,
                itemKey: (r) => ValueKey('virtual-task-${r['id']}'),
                itemBuilder: (context, r, i) => taskRow(r, i, rows),
              ),
            SliverToBoxAdapter(child: footer),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (sorting)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              itemBuilder: (context, i) => taskRow(rows[i], i, rows),
              proxyDecorator: liftedTask,
              onReorderItem: (a, b) => reorder(rows, a, b, adjusted: true),
            )
          else
            for (var i = 0; i < rows.length; i++) taskRow(rows[i], i, rows),
          footer,
        ],
      );
    },
  );
}

class _TaskRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final ItemsController controller;
  final VoidCallback onOpen, onActions;
  final VoidCallback? onEdit;
  const _TaskRow({
    super.key,
    required this.item,
    required this.controller,
    required this.onOpen,
    required this.onActions,
    this.onEdit,
  });
  @override
  Widget build(BuildContext context) {
    final risk = controller.riskFor(item);
    return ItemCard(
      item: item,
      onTap: onOpen,
      onDoubleTap: onEdit,
      onLongPress: onActions,
      riskFooter:
          item['lifecycle'] == 'active' &&
              item['kind'] != 'exam' &&
              _hasListRisk(risk)
          ? _CompactRiskLine(
              risk: risk,
              onTap: () => showRiskDetails(context, controller, item),
            )
          : null,
    );
  }
}

bool _hasListRisk(Map<String, dynamic>? risk) {
  if (risk == null) return false;
  final gap = (risk['window_gap_minutes'] as num?)?.toInt() ?? 0;
  return gap > 0 ||
      risk['task_slack_minutes'] is num ||
      risk['level'] == 'high' ||
      risk['level'] == 'medium';
}

// The list shows only the useful conclusion. The full calculation remains one
// tap away, instead of putting a second card and every caveat inside each row.
class _CompactRiskLine extends StatelessWidget {
  final Map<String, dynamic>? risk;
  final VoidCallback onTap;
  const _CompactRiskLine({required this.risk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (risk == null) return const SizedBox.shrink();
    final gap = (risk!['window_gap_minutes'] as num?)?.toInt() ?? 0;
    final slack = (risk!['task_slack_minutes'] as num?)?.toInt();
    final level = '${risk!['level']}';
    final label = gap > 0
        ? riskSummary(risk)
        : slack != null && slack < 0
        ? '计划时间还缺 ${minutesLabel(slack.abs())}'
        : level == 'high' || level == 'medium'
        ? riskSummary(risk)
        : slack != null
        ? '完成后还剩 ${minutesLabel(slack)}'
        : riskSummary(risk);
    final color = riskColor(level);
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CampusColors.line)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    level == 'low'
                        ? Icons.timelapse_rounded
                        : Icons.info_outline_rounded,
                    size: 17,
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, size: 17, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
