import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../ui/v2/shiri_tokens.dart' as v2;

/// A visual projection of the saved semester. Exam dots come from real items;
/// the horizon never invents holidays or an academic calendar.
class SemesterHorizon extends StatelessWidget {
  final int current, total;
  final Set<int> examWeeks;
  const SemesterHorizon({
    super.key,
    required this.current,
    required this.total,
    required this.examWeeks,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final textScale = scale.scale(1).clamp(1.0, 1.6);
    return Semantics(
      label: [
        '共$total周，${current < 1
            ? '学期尚未开始'
            : current > total
            ? '学期已结束'
            : '现在第$current周'}',
        for (final week in examWeeks.toList()..sort()) '第$week周有考试',
      ].join('；'),
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: SizedBox(
            height: 136 * textScale,
            width: double.infinity,
            child: CustomPaint(
              painter: _HorizonPainter(
                current,
                total,
                examWeeks,
                scale,
                Theme.of(context).textTheme.bodySmall?.fontFamily,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HorizonPainter extends CustomPainter {
  final int current, total;
  final Set<int> examWeeks;
  final TextScaler textScale;
  final String? fontFamily;
  const _HorizonPainter(
    this.current,
    this.total,
    this.examWeeks,
    this.textScale,
    this.fontFamily,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final left = Offset(12, size.height - 34);
    final right = Offset(size.width - 12, size.height - 34);
    final top = Offset(size.width / 2, 16);
    final path = Path()
      ..moveTo(left.dx, left.dy)
      ..quadraticBezierTo(top.dx, -size.height * .14, right.dx, right.dy);
    final metric = path.computeMetrics().first;
    Offset at(double t) =>
        metric.getTangentForOffset(metric.length * t.clamp(0.0, 1.0))!.position;
    final fraction = total <= 1
        ? (current > total ? 1.0 : 0.0)
        : ((current - 1) / (total - 1)).clamp(0.0, 1.0).toDouble();
    final rail = Paint()
      ..color = v2.ShiriColors.light.lineStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (double start = 0; start < metric.length; start += 9) {
      canvas.drawPath(
        metric.extractPath(start, math.min(start + 4, metric.length)),
        rail,
      );
    }
    canvas.drawPath(
      metric.extractPath(0, metric.length * fraction),
      Paint()
        ..shader = v2.ShiriGradients.brand.createShader(Offset.zero & size)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    for (var week = 1; week <= total; week++) {
      final t = total <= 1 ? 0.0 : (week - 1) / (total - 1);
      final p = at(t);
      canvas.drawCircle(
        p,
        2.6,
        Paint()
          ..color = week <= current
              ? v2.ShiriBrand.cyan
              : v2.ShiriColors.light.lineStrong,
      );
      if (examWeeks.contains(week)) {
        canvas.drawCircle(
          p,
          5.5,
          Paint()..color = v2.ShiriColors.light.surface,
        );
        canvas.drawCircle(
          p,
          3.5,
          Paint()..color = v2.ShiriColors.light.dangerAccent,
        );
      }
    }
    if (current >= 1 && current <= total) {
      final p = at(fraction).translate(0, -16);
      final disc = Rect.fromCircle(center: p, radius: 11);
      canvas.drawCircle(
        p,
        18,
        Paint()..color = v2.ShiriBrand.sun500.withValues(alpha: .12),
      );
      canvas.drawOval(
        disc,
        Paint()..shader = v2.ShiriGradients.sun.createShader(disc),
      );
      final rays = Paint()
        ..color = v2.ShiriBrand.sun500
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (final angle in [-math.pi / 2, -math.pi * .75, -math.pi * .25]) {
        canvas.drawLine(
          p + Offset(math.cos(angle), math.sin(angle)) * 16,
          p + Offset(math.cos(angle), math.sin(angle)) * 21,
          rays,
        );
      }
      canvas.drawPath(
        Path()
          ..moveTo(p.dx - 5, p.dy + 1)
          ..quadraticBezierTo(p.dx, p.dy - 4, p.dx + 6, p.dy + 3),
        Paint()
          ..color = Colors.white.withValues(alpha: .9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
    void label(String text, double x, bool alignRight) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: 12,
            color: v2.ShiriColors.light.ink500,
            fontWeight: FontWeight.w600,
            fontFamily: fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScale,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          alignRight ? x - painter.width : x,
          size.height - painter.height,
        ),
      );
      painter.dispose();
    }

    label('第1周', 8, false);
    label('第$total周', size.width - 8, true);
  }

  @override
  bool shouldRepaint(covariant _HorizonPainter old) =>
      old.current != current ||
      old.total != total ||
      old.examWeeks.length != examWeeks.length ||
      !old.examWeeks.containsAll(examWeeks) ||
      old.textScale != textScale ||
      old.fontFamily != fontFamily;
}
