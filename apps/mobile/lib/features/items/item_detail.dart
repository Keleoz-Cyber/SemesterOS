import '../../ui/app_controls.dart';
import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../media/source_view.dart';
import '../../ui/campus_theme.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/record_actions.dart';
import '../../ui/campus_widgets.dart';
import 'items_controller.dart';
import 'item_form.dart';
import 'item_widgets.dart';
import 'reminder_editor.dart';
import '../planning/risk_widgets.dart';
import '../planning/progress_page.dart';
import '../planning/plan_change_confirmation.dart';

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
  String? error;
  bool busy = false;
  late final generation = widget.controller.api.generation;
  bool get sameSession => generation == widget.controller.api.generation;
  Map<String, dynamic>? get currentItem {
    if (!sameSession) return null;
    final cached = widget.controller.items
        .where((r) => r['id'] == widget.id)
        .firstOrNull;
    return cached != null &&
            (cached['version'] as int) >= (item?['version'] as int? ?? 0)
        ? cached
        : item;
  }

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
      if (mounted && sameSession) {
        setState(() {
          item = value;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
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
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changeState(String state) async {
    final target = currentItem;
    if (target == null || busy) return;
    Map<String, dynamic> preview;
    try {
      preview = await widget.controller.previewLifecycle(target, state);
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
      return;
    }
    if (!mounted || !sameSession) return;
    final blocks = List<Map<String, dynamic>>.from(
      preview['affected_blocks'] ?? [],
    );
    final label = {
      'completed': '确认已完成',
      'cancelled': '确认取消事项',
      'active': '恢复这条事项',
    }[state]!;
    final selection = blocks.isEmpty
        ? null
        : await confirmPlanChange(
            context,
            title: label,
            message: '相关未触发提醒和以下未来个人计划将取消，任务进度只按本次确认更新。',
            confirmLabel: '确认',
            blocks: blocks,
            cancelAll: true,
          );
    if (!mounted) return;
    final yes = blocks.isNotEmpty
        ? selection != null
        : await showDialog<bool>(
            context: context,
            builder: (context) => AppDialog(
              title: Text(label),
              content: Text(
                state == 'active' ? '恢复事项后，已停用的提醒需要重新开启。' : '相关未触发提醒将一并停用。',
              ),
              actions: [
                AppTextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('返回'),
                ),
                AppButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确认'),
                ),
              ],
            ),
          );
    if (yes == true && mounted && sameSession) {
      await run(
        () => widget.controller.lifecycle(
          target,
          state,
          confirmation: {
            'expected_revision': preview['base_revision'],
            ...?selection,
          },
        ),
      );
    }
  }

  Future<void> reminder([Map<String, dynamic>? initial]) async {
    final target = currentItem;
    if (target == null) return;
    final result = await editReminder(
      context,
      kind: target['kind'],
      initial: initial,
    );
    if (result != null && mounted && sameSession) {
      await run(
        () =>
            widget.controller.saveReminder(target, result, id: initial?['id']),
      );
    }
  }

  Future<void> edit(Map<String, dynamic> data) async {
    if (!sameSession) return;
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
  }

  Future<void> progress(Map<String, dynamic> data) async {
    if (!sameSession) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProgressPage(controller: widget.controller, item: data),
      ),
    );
    if (saved == true && mounted) await load();
  }

  Future<void> showHistory() async {
    final generation = widget.controller.api.generation;
    final future = widget.controller.api.request(
      'GET',
      '/items/${widget.id}/history',
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .72,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('修改历史', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<dynamic>(
                  future: future,
                  builder: (context, snapshot) {
                    if (generation != widget.controller.api.generation) {
                      return const Center(child: Text('账号已切换，请重新打开'));
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text(userError(snapshot.error!)));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final rows = List<Map<String, dynamic>>.from(
                      snapshot.data as List,
                    );
                    if (rows.isEmpty) {
                      return const Center(child: Text('还没有修改记录'));
                    }
                    return ListView(
                      children: [
                        for (final h in rows)
                          AppTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(h['reason']),
                            subtitle: Text(
                              '${displayInstant(h['created_at'])}\n${itemTimeLabel(Map<String, dynamic>.from(h['snapshot']))}',
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> showReminders(Map<String, dynamic> data) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final target = currentItem ?? data;
          final reminders = List<Map<String, dynamic>>.from(
            target['reminders'] ?? [],
          );
          return FractionallySizedBox(
            heightFactor: .72,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('提醒', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final r in reminders)
                          RecordActionTile(
                            title:
                                '${reminderLabel(r)} · ${{'item': '事项提醒', 'start_review': '开始复习', 'check_notice': '核实通知'}[r['purpose']] ?? '提醒'}',
                            subtitle: [
                              if (r['trigger_at'] != null)
                                displayInstant(r['trigger_at']),
                              reminderState(r['schedule_state']),
                            ].join(' · '),
                            icon: Icons.notifications_outlined,
                            onTap: target['lifecycle'] != 'active'
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    reminder(r);
                                  },
                          ),
                        if (widget.controller.notificationStatus != null)
                          SoftNotice(widget.controller.notificationStatus!),
                        if (widget.controller.syncedAt != null)
                          Text(
                            '最近更新 ${displayInstant(widget.controller.syncedAt)}',
                            style: const TextStyle(
                              color: CampusColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        RecordActionTile(
                          title: '系统通知设置',
                          icon: Icons.notifications_active_outlined,
                          onTap: () => widget.controller.syncNotifications(
                            requestPermission: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (target['lifecycle'] == 'active')
                    AppButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        reminder();
                      },
                      icon: const Icon(Icons.add_alarm_rounded),
                      label: const Text('添加提醒'),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> more(String action, Map<String, dynamic> data) async {
    switch (action) {
      case 'cancel':
        await changeState('cancelled');
        break;
      case 'history':
        await showHistory();
        break;
      case 'refresh':
        await load();
        break;
      case 'source':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SourceViewPage(
              controller: widget.controller,
              id: data['source_id'],
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final data = currentItem;
      final active = data?['lifecycle'] == 'active';
      final exam = data?['kind'] == 'exam';
      final reminders = List<Map<String, dynamic>>.from(
        data?['reminders'] ?? [],
      );
      final time = Map<String, dynamic>.from(data?['time'] ?? {});
      final overdue =
          active &&
          data?['anchor_at'] != null &&
          DateTime.parse(data!['anchor_at']).isBefore(DateTime.now());
      return Scaffold(
        appBar: AppBar(
          title: Text(exam ? '考试详情' : '事项详情'),
          actions: [
            if (data != null && active)
              AppIconButton(
                tooltip: '编辑事项',
                onPressed: busy ? null : () => edit(data),
                icon: const Icon(Icons.edit_outlined),
              ),
            if (data != null)
              RecordMenuButton<String>(
                enabled: !busy,
                onSelected: (value) => more(value, data),
                actions: [
                  const RecordMenuAction(
                    'history',
                    '修改历史',
                    Icons.history_rounded,
                  ),
                  if (data['source_id'] != null)
                    const RecordMenuAction(
                      'source',
                      '原始通知',
                      Icons.description_outlined,
                    ),
                  const RecordMenuAction(
                    'refresh',
                    '刷新',
                    Icons.refresh_rounded,
                  ),
                  if (active)
                    const RecordMenuAction(
                      'cancel',
                      '取消事项',
                      Icons.delete_outline_rounded,
                      destructive: true,
                    ),
                ],
              ),
          ],
        ),
        bottomNavigationBar: data == null
            ? null
            : active
            ? exam
                  ? ActionFooter(
                      label: '查看复习安排',
                      icon: Icons.school_outlined,
                      onPressed: busy
                          ? null
                          : () => context.push('/exams/${data['id']}'),
                    )
                  : ActionFooter(
                      label: '标记完成',
                      icon: Icons.check_rounded,
                      onPressed: busy ? null : () => changeState('completed'),
                    )
            : ActionFooter(
                label: '恢复事项',
                icon: Icons.undo_rounded,
                onPressed: busy ? null : () => changeState('active'),
              ),
        body: data == null
            ? Center(
                child: !sameSession
                    ? const Text('账号已切换，请重新打开')
                    : error == null
                    ? const CircularProgressIndicator()
                    : Text(error!),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  RecordHeading(
                    title: '${data['title']}',
                    label:
                        '${kindLabel(data['kind'])} · ${data['lifecycle'] == 'completed'
                            ? '已完成'
                            : data['lifecycle'] == 'cancelled'
                            ? '已取消'
                            : data['certainty'] != 'formal'
                            ? '暂定'
                            : '待完成'}',
                    icon: exam ? Icons.school_outlined : Icons.task_alt_rounded,
                    subtitle: data['course_title'],
                  ),
                  if (time['precision'] != null &&
                      time['precision'] != 'unknown')
                    RecordFact(
                      label: exam ? '考试时间' : '截止时间',
                      value: itemTimeLabel(
                        data,
                        includeMissing: false,
                      ).replaceFirst(RegExp(r' (截止|开始)(?= ·|$)'), ''),
                      icon: Icons.schedule_rounded,
                      color: overdue
                          ? CampusColors.error
                          : CampusColors.primary,
                    ),
                  if (overdue)
                    Text(
                      exam ? '开始时间已过' : '已过截止时间',
                      style: const TextStyle(color: CampusColors.error),
                    ),
                  if ('${data['location'] ?? ''}'.trim().isNotEmpty)
                    RecordFact(
                      label: '地点',
                      value: data['location'],
                      icon: Icons.place_outlined,
                    ),
                  if (active && !exam) ...[
                    if (data['remaining_minutes'] != null ||
                        data['review_exam_id'] != null)
                      RecordActionTile(
                        title: data['remaining_minutes'] == null
                            ? '更新任务进度'
                            : '还需 ${minutesLabel(data['remaining_minutes'])}',
                        subtitle: data['remaining_minutes'] == null
                            ? null
                            : '更新进度',
                        icon: Icons.timelapse_rounded,
                        onTap: busy ? null : () => progress(data),
                      ),
                    if (data['remaining_minutes'] != null ||
                        data['review_exam_id'] != null ||
                        const [
                          'high',
                          'medium',
                        ].contains(widget.controller.riskFor(data)?['level']))
                      RiskBadge(
                        risk: widget.controller.riskFor(data),
                        onTap: () =>
                            showRiskDetails(context, widget.controller, data),
                      ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: SoftNotice(error!, warning: true),
                    ),
                  if (busy) const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  if (active || reminders.isNotEmpty)
                    RecordActionTile(
                      title: reminders.isEmpty
                          ? '添加提醒'
                          : '提醒 · ${reminders.length}条',
                      subtitle: reminders.length == 1
                          ? '${reminderLabel(reminders.first)} · ${reminderState(reminders.first['schedule_state'])}'
                          : null,
                      icon: Icons.notifications_outlined,
                      onTap: busy
                          ? null
                          : () => reminders.isEmpty
                                ? reminder()
                                : showReminders(data),
                    ),
                  if (active)
                    RecordActionTile(
                      title: '智能修改',
                      icon: Icons.auto_awesome_outlined,
                      onTap: busy
                          ? null
                          : () =>
                                context.push('/operations?item=${data['id']}'),
                    ),
                  if (data['review_exam_id'] != null)
                    RecordActionTile(
                      title: '关联考试',
                      icon: Icons.school_outlined,
                      onTap: () =>
                          context.push('/exams/${data['review_exam_id']}'),
                    ),
                  if (data['course_id'] != null)
                    RecordActionTile(
                      title: '课程事务',
                      icon: Icons.menu_book_outlined,
                      onTap: () =>
                          context.push('/courses/${data['course_id']}'),
                    ),
                  if ('${data['notes'] ?? ''}'.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    DocumentPanel(title: '备注', text: data['notes']),
                  ],
                  if ('${data['source_text'] ?? ''}'.trim().isNotEmpty)
                    AppDisclosure(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('通知原文'),
                      children: [
                        DocumentPanel(
                          title: data['candidate_id'] == null
                              ? '手工录入'
                              : '已核对的识别内容',
                          text: data['source_text'],
                          footer: Text(
                            '创建于 ${displayInstant(data['created_at'])}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: CampusColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
      );
    },
  );
}
