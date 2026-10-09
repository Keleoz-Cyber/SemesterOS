import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import '../../ui/app_controls.dart';
import '../../ui/brand.dart';
import '../../ui/v2/shiri_tokens.dart';
import '../../ui/v2/widgets/sky_header.dart';
import '../../app/controller.dart' show schoolNow;

/// Foreground of the shell's pinned sky header; dates use the supplied school
/// clock, never the device's local timezone.
class TodaySkyHeader extends StatelessWidget {
  const TodaySkyHeader({
    super.key,
    required this.now,
    required this.semester,
    required this.onProfile,
    required this.onSettings,
    this.collapse = 0,
    this.layoutExtent,
    this.active = true,
    this.entryEpoch = 0,
  });
  final DateTime now;
  final Map<String, dynamic> semester;
  final VoidCallback onProfile, onSettings;
  final double collapse;
  final double? layoutExtent;
  final bool active;
  final int entryEpoch;

  static double expandedExtent(BuildContext context, {DateTime? now}) {
    final date = now ?? schoolNow(), shiri = context.shiri;
    final scaler = MediaQuery.textScalerOf(context);
    final side = MediaQuery.sizeOf(context).width <= 360
        ? ShiriSpace.pageCompact
        : ShiriSpace.page;
    final width = MediaQuery.sizeOf(context).width - side * 2;
    Size measure(String value, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final month = measure('${date.month}月', shiri.text.display);
    final day = measure('${date.day}日', shiri.text.display);
    final weekday = measure('周三', shiri.text.title);
    final dateWidth = month.width + day.width <= width
        ? month.width + day.width
        : (month.width > day.width ? month.width : day.width);
    var dateHeight =
        month.height + (month.width + day.width > width ? day.height : 0);
    if (dateWidth + 10 + weekday.width > width) {
      dateHeight += 4 + weekday.height;
    }
    final weekHeight = measure('尚未开学', shiri.text.label).height + 12;
    final needed =
        12 +
        76 +
        dateHeight +
        12 +
        weekHeight +
        20 +
        ShiriLayout.heroOverlapNextCard;
    final base =
        ShiriLayout.heroExpanded + (scaler.scale(34) - 34).clamp(0, 24);
    return needed > base ? needed : base;
  }

  @override
  Widget build(BuildContext context) {
    final t = collapse.clamp(0.0, 1.0), shiri = context.shiri;
    final ink = ShiriGradients.onSky(now);
    final first = DateTime.parse('${semester['first_monday']}T00:00:00Z');
    final day = DateTime.utc(now.year, now.month, now.day);
    final week = day.difference(first).inDays ~/ 7 + 1;
    final total = semester['total_weeks'];
    final weekLabel = day.isBefore(first)
        ? '尚未开学'
        : week > total
        ? '学期已结束'
        : '第$week周';
    final side = MediaQuery.sizeOf(context).width <= 360
        ? ShiriSpace.pageCompact
        : ShiriSpace.page;
    final titleMix = ShiriMotion.easeStandard.transform(
      ((t - .42) / .46).clamp(0.0, 1.0),
    );
    final compactDate = '${now.month}月${now.day}日';
    return SkyHeader(
      now: now,
      collapse: t,
      height: expandedExtent(context, now: now),
      layoutExtent: layoutExtent,
      active: active,
      entryEpoch: entryEpoch,
      child: Padding(
        padding: EdgeInsets.fromLTRB(side, 12, side, 20),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Row(
                children: [
                  SizedBox(
                    width: 30 * (1 - t),
                    height: 30,
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: 30,
                      maxWidth: 30,
                      child: Opacity(
                        opacity: 1 - t,
                        child: Transform.scale(
                          key: const ValueKey('sky-brand-mark'),
                          scale: 1 - t,
                          alignment: Alignment.centerLeft,
                          child: const BrandMark(size: 30),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 10 * (1 - t)),
                  Expanded(
                    child: Semantics(
                      label: titleMix < .5 ? appName : compactDate,
                      child: ExcludeSemantics(
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Opacity(
                              key: const ValueKey('sky-brand-title'),
                              opacity: (1 - titleMix * 2).clamp(0.0, 1.0),
                              child: Text(
                                appName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: shiri.text.title.copyWith(color: ink),
                              ),
                            ),
                            Opacity(
                              key: const ValueKey('sky-date-title'),
                              opacity: (titleMix * 2 - 1).clamp(0.0, 1.0),
                              child: Text(
                                compactDate,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: shiri.text.title.copyWith(color: ink),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AppIconButton(
                    tooltip: '调整首页内容',
                    onPressed: onSettings,
                    color: ink,
                    icon: const Icon(Icons.tune_rounded, size: 21),
                  ),
                  AppIconButton(
                    tooltip: '账户',
                    onPressed: onProfile,
                    color: ink,
                    icon: const Icon(Icons.person_outline_rounded),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: lerpDouble(76, 42, t)!,
              child: IgnorePointer(
                ignoring: t > .7,
                child: Opacity(
                  opacity: (1 - t * 1.6).clamp(0, 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          Wrap(
                            children: [
                              Text(
                                '${now.month}月',
                                style: shiri.text.display.copyWith(color: ink),
                              ),
                              Text(
                                '${now.day}日',
                                style: shiri.text.display.copyWith(color: ink),
                              ),
                            ],
                          ),
                          Text(
                            '周${'一二三四五六日'[now.weekday - 1]}',
                            style: shiri.text.title.copyWith(
                              color: ink.withValues(alpha: .7),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .65),
                              borderRadius: ShiriRadius.smAll,
                            ),
                            child: Text(
                              weekLabel,
                              style: shiri.text.label.copyWith(
                                color: shiri.colors.ink700,
                              ),
                            ),
                          ),
                          Text(
                            '共$total周',
                            style: shiri.text.bodySmall.copyWith(
                              color: ink.withValues(alpha: .7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
