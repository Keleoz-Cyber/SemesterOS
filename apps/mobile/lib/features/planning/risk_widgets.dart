import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/detail_widgets.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';

String minutesLabel(dynamic value) {
  if (value == null) return '待补齐信息';
  final n = (value as num).toInt(), m = n.abs();
  final text = m >= 60
      ? '${m ~/ 60}小时${m % 60 == 0 ? '' : '${m % 60}分钟'}'
      : '$m分钟';
  return n < 0 ? '−$text' : text;
}

String riskLabel(String? value) => switch (value) {
  'high' => '需优先处理',
  'medium' => '需要留意',
  'low' => '按当前安排，时间较充裕',
  _ => '还需补充信息',
};
Color riskColor(String? value) => switch (value) {
  'high' => CampusColors.error,
  'medium' => CampusColors.warning,
  'low' => CampusColors.teal,
  _ => CampusColors.muted,
};
String reasonLabel(String code) =>
    const {
      'needs_availability': '先确认每周可学习时间',
      'other_tasks_incomplete': '其他任务还需补充信息，整体负荷尚不能确定',
      'plan_conflict': '已有计划与课程、考试或学习时间冲突，请查看并调整',
      'plan_overcoverage': '安排的时长超过了剩余所需时间，请更新进度并调整计划',
      'needs_estimate': '补充预计剩余耗时',
      'needs_deadline': '请补充截止时间，或确认在当天结束前完成',
      'needs_start': '确认任务最早什么时候可以开始',
      'needs_deadline_confirmation': '截止时间尚未确定，请先核实',
      'uncertain_fixed': '附近有尚未确定的固定日程',
      'needs_fixed_time': '固定日程缺少完整时间，请先核对',
      'needs_exam_time': '相关考试缺少明确开始或结束时间',
      'outside_semester': '截止超过当前学期分析范围',
      'analysis_limit': '事项超过本次分析上限，暂未完成分析',
      'uncertain_exam': '附近有尚未正式确定的考试安排',
      'fixed_conflict': '相关固定安排或暂定预留存在时间冲突',
      'overdue': '已过确认的截止时间，仍有剩余工作',
      'window_overload': '这些任务需要的总时间超过了同期可用时间',
      'no_contiguous_slot': '这项任务需要一次完成，但目前没有足够长的连续空闲时间',
      'start_after_deadline': '最早开始时间不早于截止，请核对',
    }[code] ??
    '请核对相关时间信息';

String riskSummary(Map<String, dynamic>? risk) {
  if (risk == null) return '安排评估待更新';
  final gap = (risk['window_gap_minutes'] as num?)?.toInt() ?? 0;
  final slack = (risk['task_slack_minutes'] as num?)?.toInt();
  if (gap > 0) return '同期任务至少还缺 ${minutesLabel(gap)}';
  if (risk['level'] == 'unknown' ||
      !const ['high', 'medium', 'low'].contains(risk['level'])) {
    final reasons = List<String>.from(risk['reason_codes'] ?? []);
    return reasons.isEmpty ? '暂时无法判断是否来得及' : reasonLabel(reasons.first);
  }
  if (slack != null && slack < 0) return '截止前还缺 ${minutesLabel(slack.abs())}';
  if (risk['level'] == 'high') {
    final reasons = List<String>.from(risk['reason_codes'] ?? []);
    if (reasons.contains('overdue')) return '已过截止，任务尚未完成';
    if (reasons.contains('no_contiguous_slot')) return '缺少足够长的连续空闲时间';
    if (reasons.contains('start_after_deadline')) return '开始时间晚于截止，请核对';
    if (reasons.contains('plan_overcoverage')) return '已安排时长需要调整';
    return '当前安排需要调整';
  }
  if (risk['level'] == 'medium') return '时间安排需要留意';
  return '按当前安排，时间够用';
}

class RiskBadge extends StatelessWidget {
  final Map<String, dynamic>? risk;
  final VoidCallback? onTap;
  const RiskBadge({super.key, this.risk, this.onTap});
  @override
  Widget build(BuildContext context) {
    if (risk == null) return const SizedBox.shrink();
    final color = riskColor(risk?['level']);
    final reasons = List<String>.from(risk?['reason_codes'] ?? []);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: .065),
          borderRadius: BorderRadius.circular(12),
        ),
        child: AppTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.all(12),
          leading: Icon(
            risk?['level'] == 'low'
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded,
            color: color,
            size: 20,
          ),
          title: Text(
            riskSummary(risk),
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle:
              reasons.isNotEmpty &&
                  risk?['level'] != 'low' &&
                  riskSummary(risk) != reasonLabel(reasons.first)
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    reasonLabel(reasons.first),
                    style: const TextStyle(
                      color: CampusColors.muted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                )
              : null,
          trailing: onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded, color: color, size: 18),
        ),
      ),
    );
  }
}

class RiskOverview extends StatelessWidget {
  final ItemsController controller;
  final VoidCallback onSettings;
  const RiskOverview({
    super.key,
    required this.controller,
    required this.onSettings,
  });
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final data = c.hasCurrentRisk ? c.analysis : null;
    final summary = data?['summary'];
    final gap = summary?['window_gap_minutes'] ?? 0;
    final configured = summary?['configured'];
    final conflicts = c.rows(data?['fixed_conflicts']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.riskBusy) const LinearProgressIndicator(),
        if (configured == false)
          AppOutlineButton.icon(
            onPressed: onSettings,
            icon: const Icon(Icons.edit_calendar_outlined),
            label: const Text('设置可学习时间'),
          )
        else
          Align(
            alignment: Alignment.centerRight,
            child: AppTextButton.icon(
              onPressed: onSettings,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('学习时间设置'),
            ),
          ),
        if (c.riskNotice != null) SoftNotice(c.riskNotice!, warning: true),
        if (gap > 0)
          SoftNotice('截止前还缺 ${minutesLabel(gap)}，优先处理下面标记的任务。', warning: true),
        for (final conflict in conflicts.take(3))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SoftNotice(
              '${(conflict['titles'] as List).join(' / ')} 时间重叠\n${displayInstant(conflict['start_at'])} 至 ${displayInstant(conflict['end_at'])}',
              warning: true,
            ),
          ),
        if ((summary?['plan_conflict_count'] ?? 0) > 0)
          SoftNotice(
            '${summary['plan_conflict_count']}段学习安排与当前日程冲突，请在“安排记录”中核对。',
            warning: true,
          ),
        if (configured == false) const Text('填好空闲时段后，就能为任务安排具体时间。'),
      ],
    );
  }
}

Future<void> showRiskDetails(
  BuildContext context,
  ItemsController controller,
  Map<String, dynamic> original,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final current =
          controller.items
              .where((r) => r['id'] == original['id'])
              .firstOrNull ??
          original;
      final risk = controller.riskFor(current);
      Widget fact(String label, dynamic n) {
        final total =
            label == '单项计划余量' || label == '扣除这些安排后可用' || label == '至少缺少';
        final shortage =
            n is num &&
            ((label == '至少缺少' && n > 0) || (label == '单项计划余量' && n < 0));
        final accent = shortage ? riskColor('high') : CampusColors.teal;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: total
                ? (shortage
                      ? accent.withValues(alpha: .08)
                      : CampusColors.tealSoft)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: LayoutBuilder(
            builder: (context, size) {
              final name = Text(
                label,
                style: const TextStyle(fontSize: 14, color: CampusColors.muted),
              );
              final value = Text(
                minutesLabel(n),
                style: TextStyle(
                  fontSize: total ? 20 : 17,
                  fontWeight: FontWeight.w600,
                  color: total ? accent : CampusColors.ink,
                ),
              );
              if (size.maxWidth < 280 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [name, const SizedBox(height: 6), value],
                );
              }
              return Row(
                children: [
                  Expanded(child: name),
                  const SizedBox(width: 16),
                  Flexible(child: value),
                ],
              );
            },
          ),
        );
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RecordHeading(
              title: '${current['title']}',
              label: '安排评估',
              icon: Icons.calculate_outlined,
            ),
            RiskBadge(risk: risk),
            if (risk?['planned_minutes'] != null)
              fact('后续已安排', risk!['planned_minutes']),
            if (risk?['unplanned_minutes'] != null)
              fact('还需安排', risk!['unplanned_minutes']),
            const SizedBox(height: 16),
            if (risk == null)
              const SoftNotice('分析已过期、安排已变化或尚未计算。请刷新后查看本次结果。', warning: true)
            else ...[
              for (final code in (risk['reason_codes'] as List? ?? []).skip(1))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SoftNotice(
                    reasonLabel('$code'),
                    warning: risk['level'] != 'low',
                  ),
                ),
              if (risk['capacity_after_fixed_minutes'] != null)
                EditorSection(
                  title: '可用时间如何扣除',
                  icon: Icons.timelapse_rounded,
                  children: [
                    fact('截止前可用于学习的时间', risk['capacity_before_fixed_minutes']),
                    fact('课程、考试和不可用时段占用', risk['fixed_occupied_minutes']),
                    const Divider(),
                    fact('扣除这些安排后可用', risk['capacity_after_fixed_minutes']),
                    fact('已安排给其他任务的时间', risk['other_plan_minutes']),
                    fact('这项任务还需要', risk['remaining_minutes']),
                    const Divider(),
                    fact('单项计划余量', risk['task_slack_minutes']),
                    fact('最长连续空档', risk['max_contiguous_minutes']),
                  ],
                ),
              if (risk['critical_window'] != null) ...[
                EditorSection(
                  title: '同期任务共同占用',
                  icon: Icons.groups_outlined,
                  accent: CampusColors.teal,
                  children: [
                    Text(
                      '${displayInstant(risk['critical_window']['start_at'])}\n至 ${displayInstant(risk['critical_window']['end_at'])}',
                    ),
                    fact('这些任务总共需要', risk['critical_window']['demand_minutes']),
                    fact(
                      risk['critical_window']['capacity_is_upper_bound'] == true
                          ? '已知安排下最多可用'
                          : '这段时间内可用',
                      risk['critical_window']['capacity_minutes'],
                    ),
                    fact('至少缺少', risk['critical_window']['gap_minutes']),
                    const Text(
                      '单看每项任务，时间可能够用；放在一起时，它们会争用同一段空闲时间。',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ],
              if (controller.analysis?['fixed_conflicts'] is List &&
                  (controller.analysis!['fixed_conflicts'] as List)
                      .isNotEmpty) ...[
                const SectionHeading('学期内固定安排冲突'),
                for (final conflict in controller.analysis!['fixed_conflicts'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SoftNotice(
                      '${(conflict['titles'] as List).join(' / ')}\n${displayInstant(conflict['start_at'])} 至 ${displayInstant(conflict['end_at'])}',
                      warning: true,
                    ),
                  ),
                if ((controller.analysis?['summary']?['fixed_conflict_count'] ??
                        0) >
                    30)
                  const Text('这里显示最近30处，完整数量见分析概况。'),
              ],
            ],
            const SizedBox(height: 16),
            const Text(
              '根据当前记录估算，重叠的占用时间只计算一次。本任务已经安排的时间仍算可用，实际进度以你填写的剩余时间为准。',
              style: TextStyle(fontSize: 12, color: CampusColors.muted),
            ),
            const SizedBox(height: 14),
            AppButton(
              onPressed: controller.busy || controller.riskBusy
                  ? null
                  : () => controller.refresh(),
              child: Text(controller.riskBusy ? '正在计算…' : '刷新分析'),
            ),
            AppTextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      );
    },
  ),
);
