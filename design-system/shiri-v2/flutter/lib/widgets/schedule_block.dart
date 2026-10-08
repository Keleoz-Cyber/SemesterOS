// ScheduleBlock：周课表里的日程块。按 KindStyle 区分课程/活动/计划/考试——
// 不只靠颜色：活动=白底描边，计划=虚线框+“计划”，考试=珊瑚底+“考试”。
// 放在有明确高度的父级里（如 Positioned(top, height)）。
import 'package:flutter/material.dart';

import '../motion/pressable.dart';
import '../shiri_tokens.dart';
import 'dashed_border.dart';

class ScheduleBlock extends StatelessWidget {
  const ScheduleBlock({
    super.key,
    required this.title,
    required this.kind,
    this.location,
    this.palette,
    this.onTap,
    this.heroTag,
  });

  final String title;
  final ScheduleKind kind;
  final String? location;

  /// 课程默认 CoursePalette.forTitle(title)。
  final CoursePalette? palette;
  final VoidCallback? onTap;

  /// 与课程详情页共享，做"块 → 详情"的容器变换。
  final Object? heroTag;

  static const double radius = 11;

  @override
  Widget build(BuildContext context) {
    final style = KindStyle.of(
      kind,
      palette: palette ?? CoursePalette.forTitle(title),
      brightness: Theme.of(context).brightness,
    );
    final fg = style.foreground;
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: BorderRadius.circular(radius),
        border: !style.dashed && style.border != null
            ? Border.all(color: style.border!, width: style.borderWidth)
            : null,
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: KindStyle.accentBarWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: style.accentGradient == null ? style.accent : null,
                gradient: style.accentGradient,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 5, 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (style.badge != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      style.badge!,
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: fg),
                    ),
                  ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, height: 1.25, fontWeight: FontWeight.w700, color: fg),
                  ),
                ),
                if (location != null)
                  Text(
                    location!,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: fg.withValues(alpha: .78),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    body = ClipRRect(borderRadius: BorderRadius.circular(radius), child: body);
    if (style.dashed && style.border != null) {
      body = CustomPaint(
        foregroundPainter: DashedRRectPainter(
          color: style.border!,
          strokeWidth: style.borderWidth,
          dash: style.dash,
          gap: style.gap,
          radius: radius,
        ),
        child: body,
      );
    }
    if (heroTag != null) body = Hero(tag: heroTag!, child: body);
    return Pressable(
      onPressed: onTap,
      pressedScale: .96,
      semanticLabel: [title, location, style.badge].whereType<String>().join('，'),
      child: body,
    );
  }
}
