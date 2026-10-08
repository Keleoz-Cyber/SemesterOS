import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'campus_theme.dart';
import 'app_controls.dart';
import 'v2/shiri_tokens.dart';

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
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: CampusColors.ink,
                    ),
                  ),
                  if (label.trim().isNotEmpty) ...[
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
    padding: const EdgeInsets.only(bottom: ShiriSpace.sectionGap),
    child: Container(
      padding: const EdgeInsets.all(ShiriSpace.cardLoose),
      decoration: BoxDecoration(
        color: context.shiri.colors.surface,
        borderRadius: ShiriRadius.lgAll,
      ),
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
                if (action != null) ...[const SizedBox(width: 12), action!],
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

class ActionFooter extends StatelessWidget {
  final Key? actionKey;
  final String label;
  final FutureOr<void> Function()? onPressed;
  final IconData? icon;
  final Widget? secondary;
  const ActionFooter({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary,
    this.actionKey,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: CampusColors.surface,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?secondary,
            AppButton.base(
              key: actionKey,
              onPressed: onPressed,
              variant: FButtonVariant.primary,
              icon: icon == null ? null : Icon(icon),
              child: Text(label, textAlign: TextAlign.center),
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
      color: CampusColors.surface,
      borderRadius: ShiriRadius.lgAll,
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
