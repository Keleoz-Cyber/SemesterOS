import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../core/api.dart';
import '../items/item_widgets.dart';
import '../changes/course_change_display.dart';
import 'agent_controller.dart';

/// Confirmation authority stays with the visible selection, never model prose.
class ChangeConfirmation extends StatefulWidget {
  final Map<String, dynamic> run;
  final AgentController controller;
  final Widget Function(Map<String, dynamic>) details;
  const ChangeConfirmation({
    super.key,
    required this.run,
    required this.controller,
    required this.details,
  });
  @override
  State<ChangeConfirmation> createState() => _ChangeConfirmationState();
}

class _ChangeConfirmationState extends State<ChangeConfirmation> {
  final Set<String> selected = {};
  bool conflictAcknowledged = false;
  bool checking = false;
  String? selectionError;
  Map<String, dynamic>? selectedImpact;
  int selectionEpoch = 0;
  Map<String, dynamic> get preview =>
      Map<String, dynamic>.from(widget.run['preview']);
  @override
  void initState() {
    super.initState();
    selected.addAll(rows(preview['groups']).map((g) => g['id'] as String));
  }

  Future<void> checkSelection() async {
    final stamp = ++selectionEpoch;
    setState(() {
      checking = selected.isNotEmpty;
      selectionError = null;
      selectedImpact = {};
      conflictAcknowledged = false;
    });
    if (selected.isEmpty) return;
    try {
      final value = await widget.controller.selectionPreview(
        widget.run,
        selected.toList(),
      );
      if (mounted && stamp == selectionEpoch) {
        setState(() => selectedImpact = value);
      }
    } catch (e) {
      if (mounted && stamp == selectionEpoch) {
        setState(() => selectionError = userError(e));
      }
    } finally {
      if (mounted && stamp == selectionEpoch) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = preview, c = widget.controller;
    final pending = widget.run['status'] == 'needs_confirmation';
    final applied = widget.run['status'] == 'applied';
    final batch = p['kind'] == 'batch', undo = p['kind'] == 'undo';
    final impact = Map<String, dynamic>.from(
      applied && batch
          ? (widget.run['receipt']?['impact'] ?? {})
          : (selectedImpact ?? p['impact'] ?? {}),
    );
    final conflicts = rows(
      impact['new_fixed_conflicts'] ?? impact['fixed_conflicts'],
    );
    final saved = rows(
      widget.run['receipt']?['groups'],
    ).map((g) => g['id']).toSet();
    final selectedCount = rows(p['groups'])
        .where((g) => selected.contains(g['id']))
        .fold<int>(0, (n, g) => n + rows(g['operations']).length);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: CampusColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          top: BorderSide(
            color: applied ? CampusColors.teal : CampusColors.primary,
            width: 3,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  applied
                      ? Icons.check_circle_outline_rounded
                      : undo
                      ? Icons.undo_rounded
                      : Icons.fact_check_outlined,
                  size: 20,
                  color: applied ? CampusColors.teal : CampusColors.primary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    applied
                        ? (undo ? '已撤销' : '已保存')
                        : undo
                        ? '核对撤销范围'
                        : batch
                        ? '选择要保存的安排'
                        : p['action'] == 'restore'
                        ? '恢复日程'
                        : '修改预览',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (batch) ...[
              for (final group in rows(p['groups'])) ...[
                AppCheckRow(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    rows(group['operations']).length == 1 &&
                            rows(group['operations']).first['after'] is Map
                        ? '${rows(group['operations']).first['after']['title'] ?? group['title']}'
                        : '${group['title']}',
                  ),
                  subtitle: applied && !saved.contains(group['id'])
                      ? const Text('本次未保存')
                      : null,
                  value: applied
                      ? saved.contains(group['id'])
                      : selected.contains(group['id']),
                  onChanged: pending && !c.busy
                      ? (v) {
                          setState(() {
                            if (v == true) {
                              selected.add(group['id']);
                            } else {
                              selected.remove(group['id']);
                            }
                            conflictAcknowledged = false;
                          });
                          checkSelection();
                        }
                      : null,
                ),
                for (final child in rows(group['operations']))
                  widget.details({
                    ...child,
                    '_compact': true,
                    if (rows(group['operations']).length == 1)
                      '_hide_title': true,
                  }),
              ],
            ] else if (p['kind'] == 'course_change') ...[
              CourseChangeSummary(change: p, showSource: false),
            ] else if (undo) ...[
              for (final entry in rows(p['summary']))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry['title'] ?? '这次操作',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (entry['detail'] != null) Text(entry['detail']),
                    ],
                  ),
                ),
            ] else ...[
              widget.details(p),
              for (final review in rows(p['reviews']))
                Text(
                  '${review['title']}：${review['will_align'] == true ? '复习截止跟随考试调整' : '保留原复习截止'}',
                ),
            ],
            if (conflicts.isNotEmpty) ...[
              const Divider(height: 28),
              const Text(
                '有时间冲突',
                style: TextStyle(
                  color: CampusColors.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (final conflict in conflicts.take(6))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${(conflict['titles'] as List? ?? []).join(' / ')}\n${displayInstant(conflict['start_at'])} — ${displayInstant(conflict['end_at'])}',
                  ),
                ),
              if (pending)
                AppCheckRow(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('保留这些重叠安排'),
                  value: conflictAcknowledged,
                  onChanged: c.busy
                      ? null
                      : (v) => setState(() => conflictAcknowledged = v == true),
                ),
            ],
            if (checking)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('正在核对所选安排…'),
              ),
            if (selectionError != null) ...[
              Text(
                selectionError!,
                style: const TextStyle(color: CampusColors.warning),
              ),
              AppTextButton(
                onPressed: c.busy || checking ? null : checkSelection,
                child: const Text('重新核对'),
              ),
            ],
            if ((impact['affected_plan_count'] as num? ??
                    rows(impact['affected_blocks']).length) >
                0)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('部分个人计划可能受影响。保存后可再调整个人计划。'),
              ),
            if (pending) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  AppOutlineButton(
                    onPressed: c.busy
                        ? null
                        : () => c.decide(widget.run, false),
                    child: const Text('暂不处理'),
                  ),
                  AppButton(
                    onPressed:
                        c.busy ||
                            checking ||
                            selectionError != null ||
                            (batch && selected.isEmpty) ||
                            (conflicts.isNotEmpty && !conflictAcknowledged)
                        ? null
                        : () => c.decide(
                            widget.run,
                            true,
                            selectedGroupIds: batch ? selected.toList() : null,
                            confirmFixedConflicts: conflictAcknowledged,
                          ),
                    child: Text(
                      undo
                          ? '确认撤销'
                          : batch
                          ? '保存 $selectedCount 项'
                          : p['kind'] == 'item_state'
                          ? {
                                  'completed': '标记完成',
                                  'cancelled': '确认取消',
                                  'active': '恢复事项',
                                }[p['action']] ??
                                '确认修改'
                          : p['kind'] == 'course_change' &&
                                {'suspend', 'cancel'}.contains(p['action'])
                          ? '确认停课'
                          : p['action'] == 'restore'
                          ? '确认恢复'
                          : '确认修改',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
