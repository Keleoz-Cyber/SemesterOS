import 'package:flutter/material.dart';
import '../../ui/app_controls.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/v2/shiri_tokens.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import '../agent/agent_widgets.dart' show PlanWarningNote;

/// The same simple, complete proposal rendered inside its source gap card.
/// Complex/partial proposals continue through the existing ProposalPage.
class OpportunityInlinePreview extends StatelessWidget {
  const OpportunityInlinePreview({
    super.key,
    required this.proposal,
    required this.controller,
    required this.busy,
    required this.onSave,
    required this.onCancel,
    required this.onRegenerate,
    this.error,
  });
  final Map<String, dynamic> proposal;
  final ItemsController controller;
  final bool busy;
  final VoidCallback onSave, onCancel, onRegenerate;
  final String? error;
  @override
  Widget build(BuildContext context) {
    final p = proposal, shiri = context.shiri;
    final blocks = controller.rows(p['blocks']);
    final expired =
        p['phase'] == 'expired' ||
        (p['valid_until'] != null &&
            !DateTime.parse(p['valid_until']).isAfter(DateTime.now()));
    final stale = controller.revisionIsStale(
      p['semester_id'],
      p['base_revision'],
    );
    final canApply =
        p['can_apply'] == true &&
        p['phase'] == 'ready' &&
        !expired &&
        !stale &&
        p['semester_id'] == controller.semesterId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Divider(color: shiri.colors.lineStrong),
        const SizedBox(height: 8),
        Text(
          '待确认',
          style: shiri.text.label.copyWith(color: shiri.colors.primary),
        ),
        for (final b in blocks)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              displayInterval(b['start_at'], b['end_at']),
              style: shiri.text.titleSmall,
            ),
          ),
        const SizedBox(height: 6),
        Text(
          '只追加这一段，已有安排不动',
          style: shiri.text.bodySmall.copyWith(color: shiri.colors.ink500),
        ),
        for (final message in (p['messages'] as List? ?? []).where(
          (m) =>
              m != '保留已有计划，只为尚未安排的工作补充时间' &&
              !controller
                  .rows(p['uncertainty_warnings'])
                  .any((w) => w['message'] == m),
        ))
          SoftNotice(
            '$message',
            warning: !('${p['status']}'.startsWith('FEASIBLE')),
          ),
        if ((p['existing_conflict_count'] ?? 0) > 0)
          const SoftNotice('课程或考试存在时间冲突，请先核实。生成计划不会移动这些安排。', warning: true),
        for (final warning in controller.rows(p['uncertainty_warnings']))
          PlanWarningNote(message: '${warning['message']}'),
        if (p['optimal'] == false)
          Text('这份方案符合当前时间要求，但可能还有更合适的安排。', style: shiri.text.bodySmall),
        if (expired) const SoftNotice('方案中的时间已经过去，请重新生成。', warning: true),
        if (p['phase'] == 'stale' || stale)
          const SoftNotice('你的安排已有变化，请重新生成计划。', warning: true),
        if (error != null) SoftNotice(error!, warning: true),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (canApply)
              AppButton.icon(
                onPressed: busy ? null : onSave,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('保存学习安排'),
              ),
            if (!canApply)
              AppButton.tonal(
                onPressed: busy ? null : onRegenerate,
                child: const Text('重新生成方案'),
              ),
            AppTextButton(
              onPressed: busy ? null : onCancel,
              child: const Text('暂不安排'),
            ),
          ],
        ),
      ],
    );
  }
}
