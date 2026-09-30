import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'campus_theme.dart';

/// A record's identity, separate from its dates, actions and editable fields.
class RecordHeading extends StatelessWidget {
  final String title, label;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  const RecordHeading({
    super.key,
    required this.title,
    required this.label,
    this.subtitle,
    required this.icon,
    this.color = CampusColors.primary,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: CampusColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing ??
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
          ],
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: CampusColors.muted,
            ),
          ),
        ],
      ],
    ),
  );
}

/// Use for one coherent form group, never as a wrapper around the whole page.
class EditorSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final String? subtitle;
  final Widget? action;
  final Color accent;
  const EditorSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
    this.action,
    this.accent = CampusColors.primary,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: CampusColors.ink,
                  ),
                ),
              ),
              ?action,
            ],
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              subtitle!,
              style: const TextStyle(fontSize: 13, color: CampusColors.muted),
            ),
          ),
        ...children,
      ],
    ),
  );
}

/// A fact row remains readable at large text sizes, without truncating its value.
class RecordFact extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color? color;
  const RecordFact({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color ?? CampusColors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: CampusColors.muted),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: color ?? CampusColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class WorkflowHeader extends StatelessWidget {
  final List<String> steps;
  final int current;
  const WorkflowHeader({super.key, required this.steps, required this.current});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Wrap(
      spacing: 8,
      runSpacing: 10,
      children: [
        for (var i = 0; i < steps.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: CampusColors.muted,
                  ),
                ),
              Flexible(
                child: Semantics(
                  label:
                      '${steps[i]}，${i < current
                          ? '已完成'
                          : i == current
                          ? '当前步骤'
                          : '待完成'}',
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: i == current
                          ? CampusColors.blueSoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      steps[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: i == current
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: i <= current
                            ? CampusColors.primary
                            : CampusColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class ActionFooter extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? secondary;
  const ActionFooter({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: CampusColors.surface,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?secondary,
            FButton(
              onPress: onPressed,
              size: FButtonSizeVariant.lg,
              prefix: icon == null ? null : Icon(icon),
              child: Flexible(child: Text(label, textAlign: TextAlign.center)),
            ),
          ],
        ),
      ),
    ),
  );
}

class DocumentPanel extends StatelessWidget {
  final String title, text;
  final Widget? footer;
  const DocumentPanel({
    super.key,
    required this.title,
    required this.text,
    this.footer,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: CampusColors.tealSoft,
      borderRadius: BorderRadius.circular(14),
      border: const Border(
        left: BorderSide(color: CampusColors.teal, width: 4),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: CampusColors.teal,
          ),
        ),
        const SizedBox(height: 12),
        SelectableText(
          text,
          style: const TextStyle(
            fontSize: 16,
            height: 1.7,
            color: CampusColors.ink,
          ),
        ),
        if (footer != null) ...[const SizedBox(height: 12), footer!],
      ],
    ),
  );
}
