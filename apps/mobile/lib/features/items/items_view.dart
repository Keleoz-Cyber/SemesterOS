import '../../ui/app_loading.dart';
import 'dart:async';
import 'dart:convert';
import '../../core/api.dart' show userError;
import '../../ui/app_controls.dart';
import '../../ui/performance_widgets.dart';
import '../../ui/time_urgency.dart';
import '../../ui/motion.dart';
import '../../ui/app_sheet.dart';
import '../../ui/assistant_scope.dart';
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
  final VoidCallback? onCapture;
  final void Function(String) onOpen;
  final void Function(Map<String, dynamic>)? onEdit;
  final bool sliver;
  const ItemsView({
    super.key,
    required this.controller,
    required this.onCreate,
    this.onCapture,
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
      } else if (choice == 'complete') {
        await completeItemWithUndo(context, c, row);
      } else {
        await changeItemLifecycle(context, c, row, 'active');
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

  Future<void> completeRow(Map<String, dynamic> row) async {
    final id = '${row['id']}';
    if (processing.contains(id)) return;
    final selectedController = c, generation = c.api.generation;
    processing.add(id);
    try {
      await completeItemWithUndo(context, selectedController, row);
    } catch (error) {
      if (mounted &&
          c == selectedController &&
          generation == c.api.generation) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
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
      onComplete: row['lifecycle'] == 'active' && row['kind'] != 'exam'
          ? () => completeRow(row)
          : null,
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
                    tooltip: '新建任务',
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
                        '任务',
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
          if (filter == 'active' && rows.isNotEmpty)
            Wrap(
              spacing: 4,
              children: [
                AppTextButton.icon(
                  key: const ValueKey('learning-plan-action'),
                  onPressed: () => AssistantScope.open(
                    context,
                    initialText: '请结合现有日程和任务，帮我安排接下来的学习时间；有冲突的安排请一起调整，先给我方案。',
                    autoSubmit: true,
                  ),
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('安排任务'),
                ),
                if (widget.onCapture != null)
                  AppTextButton.icon(
                    onPressed: widget.onCapture,
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text('整理通知'),
                  ),
              ],
            ),
          const SizedBox(height: 6),
          if (filter == 'active')
            RiskOverview(
              controller: c,
              showSettings: false,
              onSettings: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AvailabilityPage(controller: c),
                ),
              ),
            ),
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    filter == 'active'
                        ? '暂无任务'
                        : filter == 'completed'
                        ? '暂无完成记录'
                        : '没有已取消的任务',
                    style: const TextStyle(
                      color: CampusColors.muted,
                      fontSize: 16,
                    ),
                  ),
                  if (filter == 'active') ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        AppButton.icon(
                          onPressed: widget.onCreate,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('新建任务'),
                        ),
                        if (widget.onCapture != null)
                          AppTextButton.icon(
                            onPressed: widget.onCapture,
                            icon: const Icon(Icons.edit_note_rounded, size: 18),
                            label: const Text('整理通知'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
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
          c.riskBusy,
          c.riskNotice,
          preferences.taskOrder,
        ]),
        builder: makeHeader,
      );
      final footer = Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (filter == 'active') ...[
              PlanningEntry(
                controller: c,
                showAction: false,
                onSettings: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AvailabilityPage(controller: c),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            AppDisclosure(
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
                    MaterialPageRoute(
                      builder: (_) => ChangesPage(controller: c),
                    ),
                  ),
                  icon: const Icon(Icons.published_with_changes),
                  label: const Text('记录调课或停课'),
                ),
              ],
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
  final Future<void> Function()? onComplete;
  const _TaskRow({
    super.key,
    required this.item,
    required this.controller,
    required this.onOpen,
    required this.onActions,
    this.onEdit,
    this.onComplete,
  });
  @override
  Widget build(BuildContext context) {
    final risk = controller.riskFor(item);
    return ItemCard(
      item: item,
      onTap: onOpen,
      onDoubleTap: onEdit,
      onLongPress: onActions,
      onComplete: onComplete,
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
