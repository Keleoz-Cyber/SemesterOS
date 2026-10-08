// 虚线圆角边框：学习安排块（计划）与空档条共用。
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

class DashedRRectPainter extends CustomPainter {
  const DashedRRectPainter({
    required this.color,
    this.strokeWidth = 1.5,
    this.dash = 4,
    this.gap = 3,
    this.radius = 11,
  });

  final Color color;
  final double strokeWidth;
  final double dash;
  final double gap;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final dashed = ui.Path();
    for (final metric in (ui.Path()..addRRect(rrect)).computeMetrics()) {
      for (double d = 0; d < metric.length; d += dash + gap) {
        dashed.addPath(metric.extractPath(d, d + dash), Offset.zero);
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant DashedRRectPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.dash != dash ||
      old.gap != gap ||
      old.radius != radius;
}
