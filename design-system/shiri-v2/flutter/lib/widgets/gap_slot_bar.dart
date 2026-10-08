// GapSlotBar：空档可视化。虚线框=空档时长，任务块按"任务时长/空档时长"占比；
// 未安排时显示虚线预览块，安排保存后宽度 0→占比（380ms reveal）并弹出小勾。
import 'package:flutter/material.dart';

import '../motion/reduced_motion.dart';
import '../shiri_tokens.dart';
import 'dashed_border.dart';

class GapSlotBar extends StatelessWidget {
  const GapSlotBar({
    super.key,
    required this.start,
    required this.end,
    required this.gapMinutes,
    required this.taskTitle,
    required this.taskMinutes,
    required this.filled,
    this.nextLabel,
  });

  final String start;
  final String end;
  final int gapMinutes;
  final String taskTitle;
  final int taskMinutes;
  final bool filled;

  /// 空档之后的安排，如"数据结构"。
  final String? nextLabel;

  @override
  Widget build(BuildContext context) {
    final shiri = context.shiri;
    final c = shiri.colors;
    final fraction = (taskMinutes / gapMinutes).clamp(0.12, 1.0);
    final chipLabel = '$taskMinutes 分钟';
    return Semantics(
      label: '空档 $start 到 $end，$gapMinutes 分钟。${filled ? '已安排' : '可安排'}$taskTitle，$taskMinutes 分钟',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: CustomPaint(
              painter: const DashedRRectPainter(color: Color(0xFF9BC9EE), radius: 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Stack(
                    children: [
                      // 预览块（虚线）
                      FractionallySizedBox(
                        widthFactor: fraction,
                        heightFactor: 1,
                        child: CustomPaint(
                          painter: DashedRRectPainter(color: c.primary.withValues(alpha: .35), radius: 10),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.primary.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: _label(context, chipLabel, c.primary, false),
                          ),
                        ),
                      ),
                      // 实际安排（渐变填充）
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: filled ? 1 : 0),
                        duration: motionDuration(context, ShiriMotion.emphasized),
                        curve: ShiriMotion.easeReveal,
                        builder: (context, v, child) => v == 0
                            ? const SizedBox.shrink()
                            : FractionallySizedBox(widthFactor: fraction * v, heightFactor: 1, child: child),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: ShiriGradients.brand,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: _label(context, chipLabel, Colors.white, true),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(start, style: shiri.text.numS.copyWith(color: c.ink500)),
              const Spacer(),
              Text(nextLabel == null ? end : '$end $nextLabel', style: shiri.text.numS.copyWith(color: c.ink500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text, Color color, bool check) => ClipRect(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          if (check)
            AnimatedScale(
              scale: filled ? 1 : 0,
              duration: motionDuration(context, ShiriMotion.slow),
              curve: Curves.easeOutBack,
              child: const Padding(
                padding: EdgeInsets.only(right: 6),
                child: CircleAvatar(
                  radius: 9,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.check_rounded, size: 13, color: Color(0xFF2E6FE0)),
                ),
              ),
            ),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: context.shiri.text.label.copyWith(color: color),
            ),
          ),
        ],
      ),
    ),
  );
}
