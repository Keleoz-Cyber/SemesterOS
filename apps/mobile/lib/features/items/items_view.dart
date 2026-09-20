import 'package:flutter/material.dart';
import '../../ui/campus_widgets.dart';
import 'items_controller.dart';
import 'item_widgets.dart';

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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CampusHero(
            eyebrow: 'PLAN / 从记录开始',
            title: '我的事项',
            subtitle: '作业、考试和个人任务\n记下来，也记得提醒',
          ),
          SectionHeading('学期事项', action: '添加事项', onAction: widget.onCreate),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in {
                'active': '待处理',
                'completed': '已完成',
                'cancelled': '已取消',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: filter == entry.key,
                  onSelected: (_) => setState(() => filter = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (c.notice != null) ...[
            SoftNotice(c.notice!, warning: true),
            const SizedBox(height: 12),
          ],
          if (c.busy) const LinearProgressIndicator(),
          if (rows.isEmpty && !c.busy)
            EmptyPanel(
              title: '这里还没有事项',
              message: '把作业、考试或想做的事记下来。',
              action: '添加事项',
              onAction: widget.onCreate,
            ),
          for (final row in rows)
            ItemCard(item: row, onTap: () => widget.onOpen(row['id'])),
          const SectionHeading('提醒状态'),
          SoftNotice(c.notificationStatus ?? '同步事项后更新本机提醒'),
          if (c.syncedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '清单最近同步：${displayInstant(c.syncedAt)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          TextButton.icon(
            onPressed: () => c.syncNotifications(requestPermission: true),
            icon: const Icon(Icons.notifications_outlined),
            label: const Text('开启或检查系统通知'),
          ),
          const SizedBox(height: 12),
          const SoftNotice('自动排程和计划余量还在开发中。当前可以先记录耗时、截止和提醒。'),
        ],
      );
    },
  );
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
          SectionHeading('待处理事项', action: '全部事项', onAction: onAll),
          if (controller.notice != null) ...[
            SoftNotice(controller.notice!, warning: true),
            const SizedBox(height: 10),
          ],
          if (rows.isEmpty)
            const CampusPanel(child: Text('暂无待处理事项，可以通过“＋记录”添加。')),
          for (final row in rows.take(3))
            ItemCard(item: row, onTap: () => onOpen(row['id'])),
        ],
      );
    },
  );
}
