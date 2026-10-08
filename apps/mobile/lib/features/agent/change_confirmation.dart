import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../core/api.dart';
import '../changes/course_change_display.dart';
import '../calendar/event_conflict_review.dart';
import 'agent_controller.dart';
import 'agent_surfaces.dart';

/// Confirmation authority stays with the visible selection, never model prose.
class ChangeConfirmation extends StatefulWidget {
  final Map<String, dynamic> run;
  final AgentController controller;
  final Widget Function(Map<String, dynamic>) details;
  final VoidCallback? onAdjustTime;
  const ChangeConfirmation({
    super.key,
    required this.run,
    required this.controller,
    required this.details,
    this.onAdjustTime,
  });
  @override
  State<ChangeConfirmation> createState() => _ChangeConfirmationState();
}

class _ChangeConfirmationState extends State<ChangeConfirmation> {
  final Set<String> selected = {};
  final Set<String> leaveTargets = {};
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
      leaveTargets.clear();
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

  Future<void> saveDecision({required bool batch}) async {
    await widget.controller.decide(
      widget.run,
      true,
      selectedGroupIds: batch ? selected.toList() : null,
      confirmFixedConflicts: conflictAcknowledged,
      courseLeaveTargets: leaveTargets.toList(),
    );
    if (mounted && widget.controller.error != null) {
      setState(() {
        conflictAcknowledged = false;
        leaveTargets.clear();
      });
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
    final conflicts = eventConflicts(impact);
    final unresolved = unresolvedEventConflicts(impact, leaveTargets);
    final saved = rows(
      widget.run['receipt']?['groups'],
    ).map((g) => g['id']).toSet();
    final selectedCount = rows(p['groups'])
        .where((g) => selected.contains(g['id']))
        .fold<int>(0, (n, g) => n + rows(g['operations']).length);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AgentSurface(
        raised: !applied,
        padding: const EdgeInsets.all(20),
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
                        : p['kind'] == 'event' && p['action'] == 'create'
                        ? '新增日程'
                        : p['kind'] == 'item' &&
                              p['after']?['kind'] == 'exam' &&
                              p['action'] == 'create'
                        ? '新增考试'
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
                  onChanged: pending && !c.busy && !c.processing
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
              widget.details({...p, '_compact': true}),
              for (final review in rows(p['reviews']))
                Text(
                  '${review['title']}：${review['will_align'] == true ? '复习截止跟随考试调整' : '保留原复习截止'}',
                ),
            ],
            if (conflicts.isNotEmpty) ...[
              const Divider(height: 28),
              EventConflictReview(
                impact: impact,
                leaveTargets: leaveTargets,
                acknowledged: conflictAcknowledged,
                enabled: !c.busy && !c.processing && !checking,
                onAdjustTime: pending ? widget.onAdjustTime : null,
                onLeaveChanged: pending
                    ? (id, value) => setState(() {
                        if (value) {
                          leaveTargets.add(id);
                        } else {
                          leaveTargets.remove(id);
                        }
                        conflictAcknowledged = false;
                      })
                    : null,
                onAcknowledged: pending
                    ? (value) => setState(() => conflictAcknowledged = value)
                    : null,
              ),
            ],
            if (applied &&
                rows(
                  widget.run['receipt']?['course_attendance'],
                ).isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '已记录 ${rows(widget.run['receipt']?['course_attendance']).length} 次课程请假',
                style: const TextStyle(color: CampusColors.teal),
              ),
              const Text('原课程保留，本次不再占用时间。', style: TextStyle(fontSize: 13)),
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
                child: Text('部分学习安排可能受影响。保存后可再调整学习安排。'),
              ),
            if (pending) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  AppTextButton(
                    onPressed: c.busy || c.processing
                        ? null
                        : () => c.decide(widget.run, false),
                    child: const Text('暂不处理'),
                  ),
                  AppButton(
                    onPressed:
                        c.busy ||
                            c.processing ||
                            checking ||
                            selectionError != null ||
                            (batch && selected.isEmpty) ||
                            (unresolved.isNotEmpty && !conflictAcknowledged)
                        ? null
                        : () => saveDecision(batch: batch),
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
                          : p['kind'] == 'course_change' &&
                                {
                                  'leave',
                                  'plan_leave',
                                  'attend',
                                }.contains(p['action'])
                          ? '保存听课状态'
                          : p['action'] == 'restore'
                          ? '确认恢复'
                          : p['kind'] == 'event' && p['action'] == 'create'
                          ? '保存日程'
                          : p['kind'] == 'item' &&
                                p['after']?['kind'] == 'exam' &&
                                p['action'] == 'create'
                          ? '保存考试'
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
