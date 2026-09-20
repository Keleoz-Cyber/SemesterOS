import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';
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
  'high' => const Color(0xFFAA3A35),
  'medium' => const Color(0xFF85631C),
  'low' => const Color(0xFF247454),
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

class RiskBadge extends StatelessWidget {
  final Map<String, dynamic>? risk;
  final VoidCallback? onTap;
  const RiskBadge({super.key, this.risk, this.onTap});
  @override
  Widget build(BuildContext context) {
    final r = risk;
    final gap = (r?['window_gap_minutes'] as num?)?.toInt() ?? 0;
    final slack = r?['task_slack_minutes'];
    final color = riskColor(r?['level']);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r == null
                  ? '计划余量待更新'
                  : gap > 0
                  ? '这些任务合计至少缺 ${minutesLabel(gap)}'
                  : slack == null
                  ? '计划余量待补齐信息'
                  : '计划余量 ${minutesLabel(slack)}',
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (r != null)
              Text(
                '${riskLabel(r['level'])}${gap > 0 && slack != null ? ' · 单项余量 ${minutesLabel(slack)}' : ''}',
                style: TextStyle(color: color, fontSize: 12),
              ),
            if (onTap != null)
              const Text(
                '查看计算依据 ›',
                style: TextStyle(fontSize: 12, color: CampusColors.muted),
              ),
            if (r?['planned_minutes'] != null &&
                r?['unplanned_minutes'] != null)
              Text(
                '后续已安排 ${minutesLabel(r!['planned_minutes'])} · 尚待安排 ${minutesLabel(r['unplanned_minutes'])}',
                style: const TextStyle(fontSize: 12, color: CampusColors.muted),
              ),
          ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading('时间与余量', action: '学习时间', onAction: onSettings),
        CampusPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (c.riskBusy) const LinearProgressIndicator(),
              Text(
                data == null
                    ? '余量等待计算'
                    : summary['configured'] != true
                    ? '先设置可学习时间'
                    : gap > 0
                    ? '至少缺少 ${minutesLabel(gap)}'
                    : (summary['fixed_conflict_count'] ?? 0) > 0
                    ? '固定安排存在冲突'
                    : (summary['active_task_count'] ?? 0) == 0
                    ? '暂无待分析任务'
                    : riskLabel(summary['level']),
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: riskColor(summary?['level']),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                c.riskNotice ??
                    (data == null
                        ? '安排变化或分析过期后，需要重新计算。'
                        : '${summary['active_task_count']}项待处理任务 · ${summary['incomplete_count']}项还需补充信息'),
              ),
              if (data != null) ...[
                const SizedBox(height: 8),
                Text(
                  '计算于 ${displayInstant(data['computed_at'])}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: CampusColors.muted,
                  ),
                ),
                if ((summary['uncertain_exam_count'] ?? 0) > 0)
                  Text(
                    '${summary['uncertain_exam_count']}项考试时间仍需核对',
                    style: const TextStyle(fontSize: 13),
                  ),
              ],
              if ((summary?['plan_conflict_count'] ?? 0) > 0)
                Text(
                  '${summary['plan_conflict_count']}段已有计划需要核对',
                  style: const TextStyle(fontSize: 13),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onSettings,
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: const Text('设置学习时段'),
                  ),
                  TextButton(
                    onPressed: c.busy || c.riskBusy ? null : () => c.refresh(),
                    child: const Text('重新计算'),
                  ),
                ],
              ),
              if (summary?['critical_window'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '这些任务共同需要的时间段：${displayInstant(summary['critical_window']['start_at'])} 至 ${displayInstant(summary['critical_window']['end_at'])}\n'
                    '任务需 ${minutesLabel(summary['critical_window']['demand_minutes'])}，${summary['critical_window']['capacity_is_upper_bound'] == true ? '最多可用' : '可用'} ${minutesLabel(summary['critical_window']['capacity_minutes'])}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const SoftNotice('总时间够用，也可能缺少一整段空闲时间。可以点击“生成计划”，看看具体能怎么安排。'),
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
      Widget fact(String label, dynamic n) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, color: CampusColors.muted),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              flex: 2,
              child: Text(
                minutesLabel(n),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '时间够不够，怎么算的',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text('${current['title']}'),
            RiskBadge(risk: risk),
            const SizedBox(height: 16),
            if (risk == null)
              const SoftNotice('分析已过期、安排已变化或尚未计算。请刷新后查看本次结果。', warning: true)
            else ...[
              for (final code in risk['reason_codes'] as List)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SoftNotice(
                    reasonLabel('$code'),
                    warning: risk['level'] != 'low',
                  ),
                ),
              if (risk['capacity_after_fixed_minutes'] != null)
                CampusPanel(
                  child: Column(
                    children: [
                      fact(
                        '截止前可用于学习的时间',
                        risk['capacity_before_fixed_minutes'],
                      ),
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
                ),
              if (risk['critical_window'] != null) ...[
                const SectionHeading('这些任务一起做，时间够吗'),
                CampusPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${displayInstant(risk['critical_window']['start_at'])}\n至 ${displayInstant(risk['critical_window']['end_at'])}',
                      ),
                      fact(
                        '这些任务总共需要',
                        risk['critical_window']['demand_minutes'],
                      ),
                      fact(
                        risk['critical_window']['capacity_is_upper_bound'] ==
                                true
                            ? '已知安排下最多可用'
                            : '这段时间内可用',
                        risk['critical_window']['capacity_minutes'],
                      ),
                      fact('至少缺少', risk['critical_window']['gap_minutes']),
                      const Text(
                        '单看每项任务，时间可能够用；放在一起时，它们会争用同一段空闲时间。',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
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
            FilledButton(
              onPressed: controller.busy || controller.riskBusy
                  ? null
                  : () => controller.refresh(),
              child: Text(controller.riskBusy ? '正在计算…' : '刷新分析'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      );
    },
  ),
);
