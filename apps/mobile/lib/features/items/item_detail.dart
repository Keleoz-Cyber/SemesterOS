import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';
import 'items_controller.dart';
import 'item_form.dart';
import 'item_widgets.dart';
import 'reminder_editor.dart';

class ItemDetailPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> semester;
  final String id;
  const ItemDetailPage({
    super.key,
    required this.controller,
    required this.semester,
    required this.id,
  });
  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  Map<String, dynamic>? item;
  List<Map<String, dynamic>>? history;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    item = widget.controller.items
        .where((r) => r['id'] == widget.id)
        .firstOrNull;
    load();
  }

  Future<void> load() async {
    try {
      final value = await widget.controller.get(widget.id);
      if (mounted) {
        setState(() {
          item = value;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (!mounted) return;
      item =
          widget.controller.items
              .where((r) => r['id'] == widget.id)
              .firstOrNull ??
          item;
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changeState(String state) async {
    final label = {
      'completed': '确认已完成',
      'cancelled': '确认取消事项',
      'active': '恢复这条事项',
    }[state]!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Text(
          state == 'active' ? '恢复事项后，已停用的提醒需要重新开启。' : '相关未触发提醒将一并停用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await run(() => widget.controller.lifecycle(item!, state));
    }
  }

  Future<void> reminder([Map<String, dynamic>? initial]) async {
    final result = await editReminder(
      context,
      kind: item!['kind'],
      initial: initial,
    );
    if (result != null && mounted) {
      await run(
        () => widget.controller.saveReminder(item!, result, id: initial?['id']),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = item;
    return Scaffold(
      appBar: AppBar(
        title: const Text('事项详情'),
        actions: [
          IconButton(
            tooltip: '刷新事项',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: data == null
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(error!),
                    ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ItemCard(item: data, onTap: () {}),
                if (error != null) ...[
                  SoftNotice(error!, warning: true),
                  const SizedBox(height: 12),
                ],
                if (busy) const LinearProgressIndicator(),
                if (data['lifecycle'] == 'active')
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                final saved = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ItemFormPage(
                                      controller: widget.controller,
                                      semester: widget.semester,
                                      initial: data,
                                    ),
                                  ),
                                );
                                if (saved == true && mounted) await load();
                              },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('编辑事项'),
                      ),
                      if (data['kind'] != 'exam')
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => changeState('completed'),
                          icon: const Icon(Icons.check),
                          label: const Text('标记完成'),
                        ),
                      TextButton(
                        onPressed: busy ? null : () => changeState('cancelled'),
                        child: const Text('取消事项'),
                      ),
                    ],
                  )
                else
                  OutlinedButton(
                    onPressed: busy ? null : () => changeState('active'),
                    child: const Text('恢复事项'),
                  ),
                if ('${data['location'] ?? ''}'.isNotEmpty) ...[
                  const SectionHeading('地点'),
                  CampusPanel(child: Text(data['location'])),
                ],
                SectionHeading(
                  '提醒',
                  action: data['lifecycle'] == 'active' ? '添加提醒' : null,
                  onAction: busy ? null : () => reminder(),
                ),
                if ((data['reminders'] as List).isEmpty)
                  const CampusPanel(child: Text('尚未设置提醒，可选择提前提醒或指定时刻。')),
                for (final r in List<Map<String, dynamic>>.from(
                  data['reminders'],
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: CampusPanel(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: const Icon(
                          Icons.notifications_outlined,
                          color: CampusColors.primary,
                        ),
                        title: Text(
                          '${reminderLabel(r)} · ${{'item': '事项提醒', 'start_review': '开始复习', 'check_notice': '核实通知'}[r['purpose']]}',
                        ),
                        subtitle: Text(
                          '${displayInstant(r['trigger_at'])}\n${reminderState(r['schedule_state'])}',
                        ),
                        trailing: data['lifecycle'] == 'active'
                            ? const Icon(Icons.edit_outlined)
                            : null,
                        onTap: busy || data['lifecycle'] != 'active'
                            ? null
                            : () => reminder(r),
                      ),
                    ),
                  ),
                ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SoftNotice(
                        widget.controller.notificationStatus ?? '尚未同步系统提醒',
                      ),
                      if (widget.controller.syncedAt != null)
                        Text(
                          '清单最近同步：${displayInstant(widget.controller.syncedAt)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      TextButton.icon(
                        onPressed: () => widget.controller.syncNotifications(
                          requestPermission: true,
                        ),
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('开启或检查系统通知'),
                      ),
                    ],
                  ),
                ),
                if ('${data['notes'] ?? ''}'.isNotEmpty) ...[
                  const SectionHeading('补充说明'),
                  CampusPanel(child: Text(data['notes'])),
                ],
                const SectionHeading('来源与修改记录'),
                CampusPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['candidate_id'] == null
                            ? '手工录入并确认'
                            : '文字解析后由本人核对确认',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${data['source_text'] ?? ''}'.isEmpty
                            ? '没有附加原文'
                            : data['source_text'],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '创建于 ${displayInstant(data['created_at'])}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: CampusColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                ExpansionTile(
                  title: const Text('查看修改历史'),
                  onExpansionChanged: (open) async {
                    if (!open) return;
                    try {
                      final rows = await widget.controller.api.request(
                        'GET',
                        '/items/${widget.id}/history',
                      );
                      if (mounted) {
                        setState(
                          () => history = List<Map<String, dynamic>>.from(rows),
                        );
                      }
                    } catch (e) {
                      if (mounted) setState(() => error = '$e');
                    }
                  },
                  children: [
                    if (history == null)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('正在读取修改记录…'),
                      ),
                    for (final h in history ?? <Map<String, dynamic>>[])
                      ListTile(
                        title: Text(h['reason']),
                        subtitle: Text(
                          '${displayInstant(h['created_at'])}\n${itemTimeLabel(Map<String, dynamic>.from(h['snapshot']))}',
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}
