import 'package:flutter/material.dart';
import 'campus_theme.dart';

enum EmptySceneKind { agenda, tasks, search, general }

/// Small decorative line scenes. They contain no dates, counts or sample data.
class AppEmptyScene extends StatefulWidget {
  final EmptySceneKind kind;
  final double size;
  final Color? accent;
  final bool animate;

  const AppEmptyScene({
    super.key,
    this.kind = EmptySceneKind.general,
    this.size = 112,
    this.accent,
    this.animate = true,
  }) : assert(size > 0);

  @override
  State<AppEmptyScene> createState() => _AppEmptySceneState();
}

class _AppEmptySceneState extends State<AppEmptyScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _entrance;
  late final CurvedAnimation _opacity;
  bool _entered = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _opacity = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
    WidgetsBinding.instance.addObserver(this);
  }

  void _finish() {
    _entered = true;
    _entrance.stop();
    _entrance.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.animate ||
        !_foreground ||
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _finish();
    } else if (!_entered) {
      _entered = true;
      _entrance.forward();
    }
  }

  @override
  void didUpdateWidget(covariant AppEmptyScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animate) _finish();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _finish();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _opacity.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: FadeTransition(
      opacity: _opacity,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _EmptyScenePainter(
              kind: widget.kind,
              accent: widget.accent ?? CampusColors.teal,
            ),
          ),
        ),
      ),
    ),
  );
}

class _EmptyScenePainter extends CustomPainter {
  final EmptySceneKind kind;
  final Color accent;
  const _EmptyScenePainter({required this.kind, required this.accent});

  Paint stroke(Color color, [double width = 1.8]) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void line(
    Canvas canvas,
    Paint paint,
    double x1,
    double y1,
    double x2,
    double y2,
  ) => canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 112, size.height / 112);
    final guide = stroke(CampusColors.line, 1.4);
    final ink = stroke(CampusColors.muted.withValues(alpha: .42));
    final color = stroke(accent, 2.3);
    final secondary = stroke(CampusColors.primary.withValues(alpha: .6), 1.7);
    switch (kind) {
      case EmptySceneKind.agenda:
        // An open time grid with a loose ribbon, rather than a calendar tile.
        for (final y in [28.0, 46.0, 64.0, 82.0]) {
          line(canvas, guide, 23, y, 92, y);
        }
        for (final x in [28.0, 50.0, 72.0, 90.0]) {
          line(canvas, guide, x, 22, x, 87);
        }
        line(canvas, ink, 22, 20, 22, 75);
        line(canvas, ink, 18, 28, 22, 28);
        line(canvas, ink, 18, 46, 22, 46);
        line(canvas, ink, 18, 64, 22, 64);
        canvas.drawPath(
          Path()
            ..moveTo(31, 88)
            ..cubicTo(47, 90, 47, 71, 61, 70)
            ..cubicTo(76, 69, 74, 51, 89, 50),
          color,
        );
        canvas.drawPath(
          Path()
            ..moveTo(84, 46)
            ..lineTo(90, 50)
            ..lineTo(86, 55),
          color,
        );
        line(canvas, secondary, 71, 19, 83, 19);
      case EmptySceneKind.tasks:
        // Checklist rules float on their own, with an unfurling edge.
        for (var i = 0; i < 3; i++) {
          final y = 31.0 + i * 20;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(24, y - 4, 8, 8),
              const Radius.circular(1.8),
            ),
            i == 0 ? color : ink,
          );
          line(canvas, i == 0 ? secondary : ink, 42, y, i == 1 ? 75 : 85, y);
          line(canvas, guide, 42, y + 6, i == 2 ? 66 : 73, y + 6);
        }
        canvas.drawPath(
          Path()
            ..moveTo(22, 84)
            ..lineTo(68, 84)
            ..cubicTo(82, 84, 81, 91, 89, 90)
            ..cubicTo(99, 89, 97, 76, 91, 75),
          color,
        );
        line(canvas, guide, 19, 20, 78, 20);
        line(canvas, guide, 19, 20, 19, 62);
      case EmptySceneKind.search:
        // A focus window reveals lines, without the usual magnifier badge.
        for (final y in [35.0, 49.0, 63.0, 77.0]) {
          line(canvas, guide, 18, y, 95, y);
        }
        line(canvas, guide, 39, 19, 39, 92);
        line(canvas, guide, 73, 19, 73, 92);
        canvas.drawPath(
          Path()
            ..moveTo(29, 42)
            ..lineTo(29, 27)
            ..lineTo(44, 27),
          color,
        );
        canvas.drawPath(
          Path()
            ..moveTo(70, 27)
            ..lineTo(85, 27)
            ..lineTo(85, 42),
          ink,
        );
        canvas.drawPath(
          Path()
            ..moveTo(85, 65)
            ..lineTo(85, 80)
            ..lineTo(70, 80),
          color,
        );
        canvas.drawPath(
          Path()
            ..moveTo(44, 80)
            ..lineTo(29, 80)
            ..lineTo(29, 65),
          ink,
        );
        line(canvas, secondary, 45, 51, 67, 51);
        line(canvas, ink, 45, 57, 58, 57);
        line(canvas, color, 91, 86, 98, 93);
      case EmptySceneKind.general:
        // A small route crossing an open aperture is shared by neutral states.
        line(canvas, guide, 21, 33, 86, 33);
        line(canvas, guide, 21, 53, 93, 53);
        line(canvas, guide, 21, 73, 85, 73);
        line(canvas, guide, 35, 20, 35, 91);
        line(canvas, guide, 76, 20, 76, 91);
        canvas.drawPath(
          Path()
            ..moveTo(22, 83)
            ..cubicTo(35, 82, 31, 64, 45, 64)
            ..lineTo(63, 64)
            ..cubicTo(80, 64, 75, 40, 90, 38),
          color,
        );
        canvas.drawPath(
          Path()
            ..moveTo(48, 24)
            ..lineTo(63, 24)
            ..lineTo(63, 34),
          secondary,
        );
        line(canvas, ink, 88, 78, 96, 78);
        line(canvas, ink, 92, 74, 92, 82);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EmptyScenePainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.accent != accent;
}
