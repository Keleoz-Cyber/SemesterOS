import 'package:flutter/material.dart';
import '../../ui/app_controls.dart';
import '../../ui/accessibility.dart';
import '../../core/api.dart' show userError;
import '../planning/plan_change_confirmation.dart';
import '../calendar/event_conflict_review.dart';
import 'items_controller.dart';

/// A short undo opportunity; Flutter otherwise persists snack bars with actions.
void showItemCompletionFeedback(
  BuildContext context, {
  required VoidCallback onUndo,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('已完成'),
      duration: Duration(
        seconds: MediaQuery.accessibleNavigationOf(context) ? 10 : 5,
      ),
      persist: false,
      action: SnackBarAction(label: '撤销', onPressed: onUndo),
    ),
  );
}

/// Shared list/home feedback around the same preview-and-consent lifecycle path.
Future<bool> completeItemWithUndo(
  BuildContext context,
  ItemsController controller,
  Map<String, dynamic> item,
) async {
  final generation = controller.api.generation;
  final owner = controller.owner, semester = controller.semesterId;
  bool same() =>
      context.mounted &&
      generation == controller.api.generation &&
      owner == controller.owner &&
      semester == controller.semesterId;
  final changed = await changeItemLifecycle(
    context,
    controller,
    item,
    'completed',
  );
  if (!changed || !context.mounted || !same()) return changed;
  showItemCompletionFeedback(
    context,
    onUndo: () async {
      try {
        if (!context.mounted || !same()) return;
        final fresh = await controller.get('${item['id']}');
        if (context.mounted && same()) {
          await changeItemLifecycle(context, controller, fresh, 'active');
        }
      } catch (error) {
        if (context.mounted && same()) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(userError(error))));
        }
      }
    },
  );
  return true;
}

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
    'cancelled' => item['kind'] == 'exam' ? '确认取消考试' : '确认取消任务',
    _ => item['kind'] == 'exam' ? '恢复这场考试' : '恢复这条任务',
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
  if (state == 'active' && item['kind'] == 'exam') {
    if (!context.mounted || !same()) return false;
    final impact = Map<String, dynamic>.from(preview['impact'] ?? {});
    if (eventConflicts(impact).isNotEmpty) {
      final choice = await confirmEventConflicts(context, impact);
      if (choice == null || choice.adjustTime) return false;
      selection = {
        ...?selection,
        if (choice.keepConflicts) 'confirm_fixed_conflicts': true,
        if (choice.courseLeaveTargets.isNotEmpty)
          'course_leave_targets': choice.courseLeaveTargets,
      };
    }
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
