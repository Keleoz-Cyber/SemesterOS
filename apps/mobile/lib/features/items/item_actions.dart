import 'package:flutter/material.dart';
import '../../ui/app_controls.dart';
import '../../ui/accessibility.dart';
import '../planning/plan_change_confirmation.dart';
import 'items_controller.dart';

/// One business path for detail buttons and list shortcuts. Related plans still
/// require the same explicit choices, revision and lock confirmation.
Future<bool> changeItemLifecycle(
  BuildContext context,
  ItemsController c,
  Map<String, dynamic> item,
  String state, {
  Future<void> Function(Future<void> Function())? commit,
}) async {
  final generation = c.api.generation, owner = c.owner, sid = c.semesterId;
  bool same() =>
      context.mounted &&
      generation == c.api.generation &&
      owner == c.owner &&
      sid == c.semesterId;
  if (!context.mounted || !same()) return false;
  final preview = await c.previewLifecycle(item, state);
  if (!context.mounted || !same()) return false;
  final blocks = List<Map<String, dynamic>>.from(
    preview['affected_blocks'] ?? [],
  );
  final label = switch (state) {
    'completed' => '确认已完成',
    'cancelled' => '确认取消事项',
    _ => '恢复这条事项',
  };
  Map<String, dynamic>? selection;
  if (blocks.isNotEmpty) {
    selection = await confirmPlanChange(
      context,
      title: label,
      message: '相关提醒和以下未来学习安排会取消。',
      confirmLabel: '确认',
      blocks: blocks,
      cancelAll: true,
    );
    if (selection == null) return false;
  } else if (state == 'cancelled') {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AppDialog(
        title: Text(label),
        content: const Text('相关未触发提醒将一并停用。'),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('返回'),
          ),
          AppButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (yes != true) return false;
  }
  if (!context.mounted || !same()) return false;
  var saved = false;
  Future<void> save() async {
    await c.lifecycle(
      item,
      state,
      confirmation: {
        'expected_revision': preview['base_revision'],
        ...?selection,
      },
    );
    saved = true;
  }

  if (commit == null) {
    await save();
  } else {
    await commit(save);
  }

  if (!saved || !context.mounted || !same()) return false;
  ScreenReaderAnnouncement.announceSuccess(switch (state) {
    'completed' => '已完成',
    'cancelled' => '已取消',
    _ => '已恢复',
  }, context: context);
  return true;
}
