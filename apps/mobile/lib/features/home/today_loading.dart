import 'package:flutter/material.dart';
import '../../ui/v2/shiri_tokens.dart';
import '../../ui/v2/motion/skeleton.dart';

/// Layout-shaped placeholders; the sky remains in the shell and refreshes keep
/// their already loaded content instead of replacing it with this body.
class TodayLoadingBody extends StatelessWidget {
  const TodayLoadingBody({super.key});
  @override
  Widget build(BuildContext context) {
    final shiri = context.shiri;
    final side = MediaQuery.sizeOf(context).width <= 360
        ? ShiriSpace.pageCompact
        : ShiriSpace.page;
    Widget card(List<Widget> lines) => Container(
      padding: const EdgeInsets.all(20),
      decoration: shiri.cardDecoration(borderRadius: ShiriRadius.lgAll),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: lines,
      ),
    );
    return SkeletonScope(
      semanticLabel: '正在读取今日安排',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: side),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: card([
                SkeletonLine(widthFactor: .4, style: shiri.text.bodyStrong),
                const SizedBox(height: 12),
                SkeletonLine(widthFactor: .8, style: shiri.text.numL),
                const SizedBox(height: 8),
                SkeletonLine(widthFactor: .75, style: shiri.text.bodySmall),
              ]),
            ),
            card([
              SkeletonLine(widthFactor: .5, style: shiri.text.bodyStrong),
              const SizedBox(height: 12),
              const SkeletonBox(height: 44),
              const SizedBox(height: 12),
              SkeletonLine(widthFactor: .75, style: shiri.text.titleSmall),
              const SizedBox(height: 8),
              SkeletonLine(widthFactor: .45, style: shiri.text.bodySmall),
            ]),
            const SizedBox(height: ShiriSpace.sectionGap),
            SkeletonLine(widthFactor: .25, style: shiri.text.title),
            const AgendaLoadingRail(scoped: false),
          ],
        ),
      ),
    );
  }
}

class AgendaLoadingRail extends StatelessWidget {
  const AgendaLoadingRail({super.key, this.scoped = true});
  final bool scoped;
  @override
  Widget build(BuildContext context) {
    final shiri = context.shiri;
    final content = Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(width: 52, height: 16),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SkeletonLine(
                        widthFactor: .8,
                        style: shiri.text.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      SkeletonLine(
                        widthFactor: .6,
                        style: shiri.text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    return scoped
        ? SkeletonScope(semanticLabel: '正在读取今日安排', child: content)
        : content;
  }
}
