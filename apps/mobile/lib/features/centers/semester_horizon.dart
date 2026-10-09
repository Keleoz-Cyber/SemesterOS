import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../ui/v2/shiri_tokens.dart' as v2;
import '../../ui/v2/motion/reduced_motion.dart';

/// A visual projection of the saved semester. Exam dots come from real items;
/// the horizon never invents holidays or an academic calendar.
class SemesterHorizon extends StatefulWidget {
  final int current, total;
  final Set<int> examWeeks;
  final bool active;
  final int entryEpoch;
  const SemesterHorizon({
    super.key,
    required this.current,
    required this.total,
    required this.examWeeks,
    this.active = true,
    this.entryEpoch = 0,
  });

  @override
  State<SemesterHorizon> createState() => _SemesterHorizonState();
}

class _SemesterHorizonState extends State<SemesterHorizon>
    with SingleTickerProviderStateMixin {
  int? _startedEntry;
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: v2.ShiriMotion.slow,
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant SemesterHorizon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if (reduceMotion(context)) {
      _rise.stop();
      _rise.value = 1;
      _startedEntry = widget.entryEpoch;
    } else if (!widget.active || !motionAllowed(context)) {
      _rise.stop();
    } else if (_startedEntry != widget.entryEpoch) {
      _startedEntry = widget.entryEpoch;
      _rise.forward(from: 0);
    } else if (_rise.value < 1 && !_rise.isAnimating) {
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
    final current = widget.current, total = widget.total;
    final examWeeks = widget.examWeeks;
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
            child: AnimatedBuilder(
              animation: _rise,
              builder: (context, _) => CustomPaint(
                painter: _HorizonPainter(
                  current,
                  total,
                  examWeeks,
                  scale,
                  Theme.of(context).textTheme.bodySmall?.fontFamily,
                  v2.ShiriMotion.easeStandard.transform(_rise.value),
                ),
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
  final double rise;
  const _HorizonPainter(
    this.current,
    this.total,
    this.examWeeks,
    this.textScale,
    this.fontFamily,
    this.rise,
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
    // A short continuation below the horizon gives even week 1 an arrival.
    // After this lead-in, both coordinates follow the saved week's rail.
    final approach = Path()
      ..moveTo(left.dx - 26, left.dy + 34)
      ..quadraticBezierTo(left.dx - 12, left.dy + 18, left.dx, left.dy);
    final approachMetric = approach.computeMetrics().first;
    final journey = approachMetric.length + metric.length * fraction;
    final traveled = journey * rise;
    final railTraveled = math.max(0.0, traveled - approachMetric.length);
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
      metric.extractPath(0, railTraveled),
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
      final onApproach = traveled < approachMetric.length;
      final p =
          (onApproach
                  ? approachMetric.getTangentForOffset(traveled)!.position
                  : metric.getTangentForOffset(railTraveled)!.position)
              .translate(0, -16);
      canvas.saveLayer(
        Offset.zero & size,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, (.25 + rise * .75).clamp(0, 1)),
      );
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
      canvas.restore();
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
      old.fontFamily != fontFamily ||
      old.rise != rise;
}
