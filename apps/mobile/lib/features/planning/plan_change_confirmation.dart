import 'package:flutter/material.dart';
import '../items/item_widgets.dart';
import 'risk_widgets.dart';

Future<Map<String, dynamic>?> confirmPlanChange(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required List<Map<String, dynamic>> blocks,
  bool cancelAll = false,
  int? remaining,
  int? maxKeptBlocks,
}) async {
  final selected = <String>{if (cancelAll) ...blocks.map((b) => '${b['id']}')};
  var unlock = false;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final locked = blocks.any(
          (b) => selected.contains(b['id']) && b['locked'] == true,
        );
        final kept = blocks
            .where((b) => !selected.contains(b['id']))
            .fold<int>(
              0,
              (sum, b) => sum + ((b['future_minutes'] ?? b['minutes']) as int),
            );
        final keptCount = blocks
            .where((b) => !selected.contains(b['id']))
            .length;
        final enough =
            (remaining == null || kept <= remaining) &&
            (maxKeptBlocks == null || keptCount <= maxKeptBlocks);
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                if (blocks.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    cancelAll ? '以下未来计划将一并取消' : '选择要取消的未来计划；保留的总时长不能超过剩余所需时间',
                  ),
                  for (final block in blocks)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${displayInstant(block['start_at'])} · ${minutesLabel(block['minutes'])}${block['locked'] == true ? ' · 已锁定' : ''}',
                      ),
                      value: selected.contains(block['id']),
                      onChanged: cancelAll
                          ? null
                          : (v) => setState(() {
                              if (v == true) {
                                selected.add(block['id']);
                              } else {
                                selected.remove(block['id']);
                              }
                            }),
                    ),
                  if (!enough)
                    Text(
                      maxKeptBlocks != null && keptCount > maxKeptBlocks
                          ? '需要一次完成的任务只能保留一段计划，请取消多余安排'
                          : '保留的计划共${minutesLabel(kept)}，超过了任务还需要的时间',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (locked)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('我确认解锁并取消所选锁定计划'),
                      value: unlock,
                      onChanged: (v) => setState(() => unlock = v!),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回修改'),
            ),
            FilledButton(
              onPressed: !enough || (locked && !unlock)
                  ? null
                  : () => Navigator.pop(context, {
                      'cancel_plan_ids': selected.toList(),
                      'confirm_locked_cancellation': locked && unlock,
                    }),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    ),
  );
}
