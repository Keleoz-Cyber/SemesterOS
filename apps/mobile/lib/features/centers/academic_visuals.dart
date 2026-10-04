import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../ui/app_controls.dart';

/// The academic flow has a short route, not a second page navigation bar.
class AcademicStepRail extends StatelessWidget {
  final List<String> steps;
  final int current;
  const AcademicStepRail({
    super.key,
    required this.steps,
    required this.current,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: LayoutBuilder(
      builder: (context, bounds) {
        final compact =
            bounds.maxWidth < 420 &&
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        return Semantics(
          label: '第${current + 1}步，共${steps.length}步，${steps[current]}',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (compact)
                  Row(
                    children: [
                      Text(
                        '${current + 1}'.padLeft(2, '0'),
                        style: const TextStyle(
                          color: CampusColors.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          steps[current],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${current + 1}/${steps.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: CampusColors.muted,
                        ),
                      ),
                    ],
                  ),
                if (compact) const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: i == steps.length - 1 ? 0 : 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!compact)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    '${i + 1}  ${steps[i]}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: i == current
                                          ? CampusColors.primary
                                          : CampusColors.muted,
                                    ),
                                  ),
                                ),
                              Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: i == current
                                      ? CampusColors.primary
                                      : i < current
                                      ? CampusColors.teal
                                      : CampusColors.line,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Small academic headings keep the title next to its subject icon.
class AcademicRecordHeading extends StatelessWidget {
  final String title, label;
  final String? subtitle;
  final IconData icon;
  final Color color;
  const AcademicRecordHeading({
    super.key,
    required this.title,
    this.label = '',
    this.subtitle,
    required this.icon,
    this.color = CampusColors.primary,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 10),
              child: Icon(icon, size: 23, color: color),
            ),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
        if (subtitle?.trim().isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 14,
                color: CampusColors.muted,
                height: 1.4,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Forms read as an editing ledger rather than nested cards.
class AcademicEditorSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final String? subtitle;
  final List<Widget> children;
  final Widget? trailing;
  const AcademicEditorSection({
    super.key,
    required this.title,
    required this.icon,
    this.accent = CampusColors.primary,
    this.subtitle,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 19, color: accent),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (trailing != null)
              trailing!
            else
              const SizedBox(width: 30, child: Divider(height: 1)),
          ],
        ),
        if (subtitle?.trim().isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              subtitle!,
              style: const TextStyle(fontSize: 13, color: CampusColors.muted),
            ),
          ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}

class AcademicStatStrip extends StatelessWidget {
  final List<({String label, int value, Color color})> stats;
  const AcademicStatStrip({super.key, required this.stats});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final columns = MediaQuery.textScalerOf(context).scale(1) > 1.3
          ? 2
          : stats.length;
      return Wrap(
        children: [
          for (final stat in stats)
            SizedBox(
              width: bounds.maxWidth / columns,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${stat.value}',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        color: stat.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stat.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: CampusColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// A time endpoint owns the full-width hit area, not just a text link.
class AcademicMomentControl extends StatelessWidget {
  final String label, value;
  final VoidCallback? onTap;
  final bool ending;
  const AcademicMomentControl({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.ending = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Material(
      color: CampusColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: AppTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        leading: Icon(
          ending ? Icons.schedule_rounded : Icons.calendar_today_outlined,
          color: ending ? CampusColors.muted : CampusColors.teal,
        ),
        title: Text(
          label,
          style: const TextStyle(fontSize: 12, color: CampusColors.muted),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: CampusColors.ink,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    ),
  );
}
