// SkyHeader：今日页头部。天空随北京时间变化（黎明/白天/傍晚/夜晚，边界 20 分钟交叉淡化），
// 太阳沿弧线按 06:00→18:00 的进度移动，夜间换成月亮；底部是图标同款波浪。
// 每次真正进入今日播放一次沿弧入场；减少动画时直接到位。
// collapse 0..1 用于 SliverPersistentHeader，entryEpoch 由外壳的页签进入事件更新。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../motion/reduced_motion.dart';
import '../shiri_tokens.dart';
import 'wave_edge.dart';

class SkyHeader extends StatefulWidget {
  const SkyHeader({
    super.key,
    required this.now,
    this.collapse = 0,
    this.height = ShiriLayout.heroExpanded,
    this.child,
    this.playIntro = true,
    this.layoutExtent,
    this.active = true,
    this.entryEpoch = 0,
  });

  /// 已换算为北京时间（见 ShiriGradients.beijingTime）。
  final DateTime now;
  final double collapse;
  final double height;
  final double? layoutExtent;

  /// 前景：品牌行、日期、周次芯片。文字颜色用 ShiriGradients.onSky(now)。
  final Widget? child;
  final bool playIntro;
  final bool active;
  final int entryEpoch;

  @override
  State<SkyHeader> createState() => _SkyHeaderState();
}

class _SkyHeaderState extends State<SkyHeader>
    with SingleTickerProviderStateMixin {
  int? _startedEntry;
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: ShiriMotion.slow,
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant SkyHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if (!widget.playIntro || reduceMotion(context)) {
      _rise.stop();
      _rise.value = 1;
      _startedEntry = widget.entryEpoch;
      return;
    }
    if (!widget.active || !motionAllowed(context)) {
      _rise.stop();
      return;
    }
    if (_startedEntry != widget.entryEpoch) {
      _startedEntry = widget.entryEpoch;
      _rise.forward(from: 0);
    } else if (_rise.value < 1 && !_rise.isAnimating) {
      // A sheet or background transition pauses the current entry, rather
      // than turning its dismissal into a second sunrise.
      _rise.forward();
    }
  }

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final night = ShiriGradients.nightAmount(widget.now);
    final collapse = widget.collapse.clamp(0.0, 1.0);
    final height =
        widget.layoutExtent ??
        ui.lerpDouble(widget.height, ShiriLayout.heroCollapsed, collapse)!;
    final hour = widget.now.hour + widget.now.minute / 60;
    final progress = night > .5
        ? ((hour >= 18 ? hour - 18 : hour + 6) / 12).clamp(0.0, 1.0)
        : ((hour - 6) / 12).clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Only the scenery feathers into the content underneath. The
            // pinned title and its 48dp actions remain opaque and readable.
            ShaderMask(
              key: const ValueKey('sky-scenery-edge'),
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                final feather = ui.lerpDouble(12, 18, collapse)!;
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: const [
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [
                    0,
                    ((bounds.height - feather) / bounds.height).clamp(0, 1),
                    1,
                  ],
                ).createShader(bounds);
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: ShiriGradients.skyGradient(widget.now),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: FractionallySizedBox(
                      heightFactor: .4,
                      widthFactor: 1,
                      child: Opacity(
                        opacity: 1 - night * .85,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: ShiriGradients.sheen,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 18,
                    top: 58 - collapse * 36,
                    width: 176,
                    height: 104,
                    child: ExcludeSemantics(
                      child: Opacity(
                        opacity: (1 - collapse * 1.6).clamp(0.0, 1.0),
                        child: RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: _rise,
                            builder: (context, _) => CustomPaint(
                              painter: SunArcPainter(
                                progress: progress,
                                rise: ShiriMotion.easeStandard.transform(
                                  _rise.value,
                                ),
                                night: night > .5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 72,
                    child: Opacity(
                      opacity: 1 - night * .65,
                      child: WaveEdge(dark: night > .5),
                    ),
                  ),
                ],
              ),
            ),
            ?widget.child,
          ],
        ),
      ),
    );
  }
}

/// 弧线：二次贝塞尔 (0,h·0.92) → 控制点 (w/2, −h·0.77) → (w, h·0.92)，顶点约在 8%。
class SunArcPainter extends CustomPainter {
  const SunArcPainter({
    required this.progress,
    this.rise = 1,
    this.night = false,
  });

  final double progress;
  final double rise;
  final bool night;

  Path _arc(Size size) => Path()
    ..moveTo(0, size.height * .92)
    ..quadraticBezierTo(
      size.width / 2,
      -size.height * .77,
      size.width,
      size.height * .92,
    );

  Path _approach(Size size) => Path()
    ..moveTo(-18, size.height * 1.14)
    ..quadraticBezierTo(-8, size.height * 1.02, 0, size.height * .92);

  double _revealedLength(Size size) {
    final arc = _arc(size).computeMetrics().first;
    final approach = _approach(size).computeMetrics().first;
    final distance = approach.length + arc.length * progress.clamp(0.0, 1.0);
    return math.max(0.0, distance * rise.clamp(0.0, 1.0) - approach.length);
  }

  /// Both axes come from the same path: the orb never slides vertically
  /// beside a fully drawn rail. The endpoint remains the actual clock value.
  Offset centerFor(Size size) {
    final metric = _arc(size).computeMetrics().first;
    final approach = _approach(size).computeMetrics().first;
    final distance = approach.length + metric.length * progress.clamp(0.0, 1.0);
    final traveled = distance * rise.clamp(0.0, 1.0);
    return (traveled < approach.length
            ? approach.getTangentForOffset(traveled)
            : metric.getTangentForOffset(traveled - approach.length))!
        .position;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final arc = _arc(size);
    final metric = arc.computeMetrics().first;

    // 虚线全程
    final dots = Paint()
      ..color = (night ? const Color(0x47FFFFFF) : const Color(0xE6FFFFFF))
          .withValues(alpha: (night ? .28 : .9) * (.35 + .65 * rise))
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (double d = 0; d < metric.length; d += 8) {
      canvas.drawPath(metric.extractPath(d, d + 1.5), dots);
    }
    // The revealed rail and the sun/moon share one path position.
    if (progress > 0) {
      canvas.drawPath(
        metric.extractPath(0, _revealedLength(size)),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0x33FFE7A6), ShiriBrand.sun500],
          ).createShader(Offset.zero & size)
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }

    final center = centerFor(size);
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Color.fromRGBO(0, 0, 0, (.25 + rise * .75).clamp(0, 1)),
    );
    night ? _moon(canvas, center) : _sun(canvas, center);
    canvas.restore();
  }

  void _sun(Canvas canvas, Offset c) {
    canvas.drawCircle(
      c,
      22,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xB3FFE9A8), Color(0x00FFE9A8)],
        ).createShader(Rect.fromCircle(center: c, radius: 22)),
    );
    final body = Paint()
      ..shader = ShiriGradients.sun.createShader(
        Rect.fromCircle(center: c, radius: 11),
      );
    canvas.drawCircle(c, 10.5, body);
    final ray = Paint()
      ..shader = ShiriGradients.sun.createShader(
        Rect.fromCircle(center: c, radius: 20),
      )
      ..strokeWidth = 3.1
      ..strokeCap = StrokeCap.round;
    for (final deg in const [-125.0, -90.0, -55.0]) {
      final a = deg * math.pi / 180;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * 14.5, c + dir * 19.5, ray);
    }
    // 图标里太阳与屋顶之间的白色分隔弧，这里作为高光
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - 7, c.dy - 1)
        ..quadraticBezierTo(c.dx - 1, c.dy - 4, c.dx + 6, c.dy + 2.5),
      Paint()
        ..color = const Color(0xBFFFFFFF)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  void _moon(Canvas canvas, Offset c) {
    canvas.drawCircle(
      c,
      20,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x59FFE9A8), Color(0x00FFE9A8)],
        ).createShader(Rect.fromCircle(center: c, radius: 20)),
    );
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: c, radius: 11)),
      Path()..addOval(
        Rect.fromCircle(center: c + const Offset(5.5, -4), radius: 9.5),
      ),
    );
    canvas.drawPath(
      moon,
      Paint()
        ..shader = ShiriGradients.sun.createShader(
          Rect.fromCircle(center: c, radius: 11),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant SunArcPainter old) =>
      old.progress != progress || old.rise != rise || old.night != night;
}
