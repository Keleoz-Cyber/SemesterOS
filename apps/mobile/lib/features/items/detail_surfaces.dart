import 'package:flutter/material.dart';

import '../../ui/v2/shiri_tokens.dart';
import '../../ui/v2/motion/staggered_reveal.dart';
import '../../ui/v2/motion/reduced_motion.dart';
import '../../ui/v2/widgets/performance_scope.dart';

/// Record identity uses a quiet color wash; factual content stays on white
/// grouped surfaces. All values are provided by the existing record page.
class DetailHero extends StatelessWidget {
  final String title, label;
  final String? subtitle;
  final IconData icon;
  final Color background, foreground;
  final Object? heroTag;
  const DetailHero({
    super.key,
    required this.title,
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    this.subtitle,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [background, context.shiri.colors.bg],
        ),
        borderRadius: ShiriRadius.xlAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: context.shiri.text.headline.copyWith(
                    fontSize: 30,
                    height: 1.3,
                    color: foreground,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .7),
                    borderRadius: ShiriRadius.smAll,
                  ),
                  child: Icon(icon, color: foreground, size: 24),
                ),
              ),
            ],
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .7),
                  borderRadius: ShiriRadius.xsAll,
                ),
                child: Text(
                  label,
                  style: context.shiri.text.label.copyWith(color: foreground),
                ),
              ),
            ),
          ],
          if (subtitle?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(
              subtitle!,
              style: context.shiri.text.bodySmall.copyWith(
                color: context.shiri.colors.ink700,
              ),
            ),
          ],
        ],
      ),
    );
    return heroTag == null ||
            reduceMotion(context) ||
            ShiriPerformance.lowEndOf(context)
        ? content
        : Hero(
            tag: heroTag!,
            child: Material(type: MaterialType.transparency, child: content),
          );
  }
}

class DetailGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final Object? revealKey;
  final int index;
  const DetailGroup({
    super.key,
    this.title,
    required this.children,
    this.revealKey,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: context.shiri.cardDecoration(borderRadius: ShiriRadius.lgAll),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: context.shiri.text.bodySmall.copyWith(
                color: context.shiri.colors.ink500,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
          ],
          ...children,
        ],
      ),
    );
    return revealKey == null
        ? content
        : RepaintBoundary(
            child: StaggeredReveal(
              revealKey: revealKey!,
              index: index,
              child: content,
            ),
          );
  }
}
