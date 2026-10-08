import 'package:flutter/material.dart';
import '../../ui/app_controls.dart';
import '../../ui/campus_theme.dart';
import '../../ui/motion.dart';
import '../../ui/v2/shiri_tokens.dart';
import '../planning/risk_widgets.dart' show minutesLabel;

/// A fact reads like a small document, rather than another nested card.
class TaskFactStrip extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color accent;
  final String? detail;
  const TaskFactStrip({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent = CampusColors.primary,
    this.detail,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: CampusColors.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 44,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          alignment: Alignment.topCenter,
          child: Icon(icon, color: accent, size: 23),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 14, color: CampusColors.muted),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: context.shiri.text.title.copyWith(color: accent),
              ),
              if (detail?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 5),
                Text(
                  detail!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: CampusColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class TaskQuickAction {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const TaskQuickAction(this.label, this.icon, this.onTap);
}

/// The frequent actions form one compact tool rail. At large text size they
/// become a readable column; hidden or unavailable actions are never invented.
class TaskActionRail extends StatelessWidget {
  final List<TaskQuickAction> actions;
  const TaskActionRail({super.key, required this.actions});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: LayoutBuilder(
      builder: (context, size) {
        Widget action(TaskQuickAction item) => AppTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          leading: Icon(item.icon, size: 21, color: CampusColors.primary),
          title: Text(
            item.label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          onTap: item.onTap,
        );
        final stack =
            size.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.4;
        return Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CampusColors.line)),
          ),
          child: stack
              ? Column(children: [for (final item in actions) action(item)])
              : Row(
                  children: [
                    for (final item in actions) Expanded(child: action(item)),
                  ],
                ),
        );
      },
    ),
  );
}

/// The number stays fully editable; presets are shortcuts, not a restricted set.
class WorkMinuteField extends StatelessWidget {
  final Key? fieldKey;
  final TextEditingController controller;
  final String label;
  final String? helper;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  const WorkMinuteField({
    super.key,
    this.fieldKey,
    required this.controller,
    required this.label,
    this.helper,
    this.validator,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppFormField(
        key: fieldKey,
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          suffixText: '分钟',
        ),
        validator: validator,
      ),
      const SizedBox(height: 8),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final minutes in [30, 60, 90])
              AppTextButton(
                onPressed: enabled
                    ? () {
                        controller.text = '$minutes';
                        controller.selection = TextSelection.collapsed(
                          offset: controller.text.length,
                        );
                      }
                    : null,
                style: AppTextButton.styleFrom(
                  backgroundColor: value.text.trim() == '$minutes'
                      ? CampusColors.blueSoft
                      : null,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(minutesLabel(minutes)),
              ),
            if (value.text.isNotEmpty)
              AppTextButton(
                onPressed: enabled ? controller.clear : null,
                child: const Text('清空'),
              ),
          ],
        ),
      ),
    ],
  );
}

/// All segments are real minutes from the proposal. Missing values do not turn
/// into a fabricated percentage or a zero-duration record.
class TaskDurationBalance extends StatelessWidget {
  final num? target;
  final num existing, added, unarranged;
  const TaskDurationBalance({
    super.key,
    required this.target,
    required this.existing,
    required this.added,
    required this.unarranged,
  });
  @override
  Widget build(BuildContext context) {
    final parts = <(String, num, Color)>[
      if (existing > 0) ('原有安排', existing, CampusColors.muted),
      if (added > 0) ('本次新增', added, CampusColors.teal),
      if (unarranged > 0) ('未安排', unarranged, CampusColors.warning),
    ];
    final total = parts.fold<num>(0, (sum, part) => sum + part.$2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (target != null)
          Text(
            '目标 ${minutesLabel(target)}',
            style: const TextStyle(fontSize: 14, color: CampusColors.muted),
          ),
        if (total > 0) ...[
          const SizedBox(height: 10),
          Semantics(
            label: parts
                .map((part) => '${part.$1}${minutesLabel(part.$2)}')
                .join('，'),
            child: ClipRRect(
              borderRadius: ShiriRadius.xsAll,
              child: Row(
                children: [
                  for (final part in parts)
                    Expanded(
                      flex: (part.$2 * 100).round().clamp(1, 100000000),
                      child: AnimatedContainer(
                        duration: AppMotion.change(context),
                        height: 7,
                        decoration: BoxDecoration(
                          color: part.$3,
                          gradient: part.$1 == '本次新增'
                              ? ShiriGradients.brand
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final part in parts)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, color: part.$3),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${part.$1} ${minutesLabel(part.$2)}',
                        style: TextStyle(fontSize: 14, color: part.$3),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Side-by-side facts collapse vertically when the labels need more room.
class TaskChangeFacts extends StatelessWidget {
  final String before, after;
  final String beforeLabel, afterLabel;
  final String? beforeDetail, afterDetail;
  const TaskChangeFacts({
    super.key,
    required this.before,
    required this.after,
    this.beforeLabel = '原来',
    this.afterLabel = '现在',
    this.beforeDetail,
    this.afterDetail,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      Widget fact(String label, String value, Color color, String? detail) =>
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 13, color: CampusColors.muted),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (detail?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  detail!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: CampusColors.muted,
                  ),
                ),
              ],
            ],
          );
      if (size.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.4) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            fact(beforeLabel, before, CampusColors.muted, beforeDetail),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Icon(
                  Icons.south_rounded,
                  size: 18,
                  color: CampusColors.teal,
                ),
              ),
            ),
            fact(afterLabel, after, CampusColors.teal, afterDetail),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: fact(beforeLabel, before, CampusColors.muted, beforeDetail),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 18, 10, 0),
            child: Icon(Icons.east_rounded, size: 18, color: CampusColors.teal),
          ),
          Expanded(
            child: fact(afterLabel, after, CampusColors.teal, afterDetail),
          ),
        ],
      );
    },
  );
}

/// Two time budgets share a scale, so the shortage can be read at a glance.
/// They are not a completion percentage and never combine unrelated periods.
class TaskTimeBudget extends StatelessWidget {
  final num available, needed;
  final String availableLabel, neededLabel;
  const TaskTimeBudget({
    super.key,
    required this.available,
    required this.needed,
    this.availableLabel = '可用于这项任务',
    this.neededLabel = '任务还需',
  });
  @override
  Widget build(BuildContext context) {
    final scale = [available, needed, 1].reduce((a, b) => a > b ? a : b);
    Widget track(String label, num amount, Color color) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 14, color: CampusColors.muted),
              ),
              Text(
                minutesLabel(amount),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          LayoutBuilder(
            builder: (context, size) => TweenAnimationBuilder<double>(
              tween: Tween(end: (amount / scale).clamp(0, 1).toDouble()),
              duration: AppMotion.change(context),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => SizedBox(
                height: 7,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: CampusColors.line,
                        borderRadius: ShiriRadius.xsAll,
                      ),
                    ),
                    Container(
                      width: size.maxWidth * value,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: ShiriRadius.xsAll,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          track(availableLabel, available, CampusColors.teal),
          track(
            neededLabel,
            needed,
            needed > available ? CampusColors.warning : CampusColors.primary,
          ),
        ],
      ),
    );
  }
}
