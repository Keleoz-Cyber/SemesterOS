import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../ui/app_controls.dart';
import '../../ui/v2/shiri_tokens.dart' as v2;
import '../../ui/v2/motion/rolling_number.dart';

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
                              if (!compact) ...[
                                Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: i == current
                                        ? CampusColors.blueSoft
                                        : CampusColors.background,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: i <= current
                                          ? CampusColors.primary
                                          : CampusColors.line,
                                    ),
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: i <= current
                                          ? CampusColors.primary
                                          : CampusColors.muted,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  steps[i],
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: i == current
                                        ? CampusColors.primary
                                        : CampusColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 9),
                              ],
                              AnimatedContainer(
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : v2.ShiriMotion.quick,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: i <= current
                                      ? null
                                      : CampusColors.line,
                                  gradient: i <= current
                                      ? v2.ShiriGradients.brand
                                      : null,
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
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: .12), CampusColors.background],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
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
                child: Icon(icon, size: 25, color: color),
              ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: color,
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
    ),
  );
}

/// A form group owns one surface; individual fields stay in the same group.
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
    padding: const EdgeInsets.only(top: 8, bottom: 20),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CampusColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: v2.ShiriShadows.light.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
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
              ?trailing,
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
    ),
  );
}

class AcademicStatStrip extends StatelessWidget {
  final List<({String label, int value, Color color})> stats;
  const AcademicStatStrip({super.key, required this.stats});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      if (stats.isEmpty) return const SizedBox.shrink();
      final columns = MediaQuery.textScalerOf(context).scale(1) > 1.3
          ? 2
          : stats.length;
      return Wrap(
        children: [
          for (final stat in stats)
            SizedBox(
              width: bounds.maxWidth / columns,
              child: Container(
                margin: const EdgeInsets.only(right: 8, bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CampusColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RollingNumber(
                      value: stat.value,
                      style: TextStyle(
                        fontSize: 28,
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
      color: v2.ShiriColors.light.surfaceSunken,
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
