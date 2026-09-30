import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
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
  const ItemsView({
    super.key,
    required this.controller,
    required this.onCreate,
    required this.onOpen,
  });
  @override
  State<ItemsView> createState() => _ItemsViewState();
}

class _ItemsViewState extends State<ItemsView> {
  String filter = 'active';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final rows = orderedItems(
        c.items.where((r) => r['lifecycle'] == filter).toList(),
      );
      if (filter == 'active') {
        int urgency(Map<String, dynamic> row) {
          final at = row['anchor_at'] ?? row['time']?['at'];
          if (at != null &&
              DateTime.tryParse('$at')?.isBefore(DateTime.now()) == true) {
            return 0;
          }
          if (c.riskFor(row)?['level'] == 'high') return 1;
          if (row['priority'] == 'high') return 2;
          return row['priority'] == 'low' ? 4 : 3;
        }

        final original = {
          for (var i = 0; i < rows.length; i++) rows[i]['id']: i,
        };
        rows.sort((a, b) {
          final rank = urgency(a).compareTo(urgency(b));
          return rank != 0
              ? rank
              : original[a['id']]!.compareTo(original[b['id']]!);
        });
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '任务',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              AppIconButton.outlined(
                tooltip: '添加事项',
                onPressed: widget.onCreate,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
          SectionHeading('任务清单 · ${rows.length}'),
          AppSegmentedControl<String>(
            value: filter,
            options: const {
              'active': '待处理',
              'completed': '已完成',
              'cancelled': '已取消',
            },
            onChanged: (value) => setState(() => filter = value),
          ),
          const SizedBox(height: 12),
          if (c.notice != null) ...[
            SoftNotice(c.notice!, warning: true),
            const SizedBox(height: 12),
          ],
          if (c.busy) const LinearProgressIndicator(),
          if (rows.isEmpty && !c.busy)
            EmptyPanel(
              title: filter == 'active'
                  ? '暂时没有待办'
                  : filter == 'completed'
                  ? '还没有完成的任务'
                  : '没有已取消的任务',
              message: filter == 'active'
                  ? '把作业、考试或想做的事记下来。'
                  : '切换到待处理，继续安排接下来的事。',
              action: '添加事项',
              onAction: widget.onCreate,
            ),
          for (final row in rows)
            _TaskRow(
              key: ValueKey('plan-task-${row['id']}'),
              item: row,
              controller: c,
              onOpen: () => widget.onOpen(row['id']),
            ),
          const SizedBox(height: 16),
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
                  MaterialPageRoute(builder: (_) => ChangesPage(controller: c)),
                ),
                icon: const Icon(Icons.published_with_changes),
                label: const Text('记录调课或停课'),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class _TaskRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final ItemsController controller;
  final VoidCallback onOpen;
  const _TaskRow({
    super.key,
    required this.item,
    required this.controller,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) {
    final risk = controller.riskFor(item);
    return ItemCard(
      item: item,
      onTap: onOpen,
      riskFooter: item['lifecycle'] == 'active' &&
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
        ? '计划余量 ${minutesLabel(slack)}'
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
    );
  }
}

class TodayItems extends StatelessWidget {
  final ItemsController controller;
  final VoidCallback onAll;
  final void Function(String) onOpen;
  const TodayItems({
    super.key,
    required this.controller,
    required this.onAll,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final rows = orderedItems(
        controller.items.where((r) => r['lifecycle'] == 'active').toList(),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlanningEntry(controller: controller, today: true),
          SectionHeading('待处理事项', action: '全部事项', onAction: onAll),
          if (controller.notice != null) ...[
            SoftNotice(controller.notice!, warning: true),
            const SizedBox(height: 10),
          ],
          if (rows.isEmpty)
            const CampusPanel(child: Text('暂无待处理事项，可从下方输入条添加。')),
          for (final row in rows.take(3))
            ItemCard(
              item: row,
              onTap: () => onOpen(row['id']),
              riskFooter: row['kind'] == 'exam' ||
                      !_hasListRisk(controller.riskFor(row))
                  ? null
                  : _CompactRiskLine(
                      risk: controller.riskFor(row),
                      onTap: () => showRiskDetails(context, controller, row),
                    ),
            ),
        ],
      );
    },
  );
}
