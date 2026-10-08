import 'package:flutter/material.dart';

/// The enclosing card supplies the name and action; this mark describes state.
class TaskStateGlyph extends StatelessWidget {
  final String state;
  final Color color;
  const TaskStateGlyph({super.key, required this.state, required this.color});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      child: CustomPaint(
        size: const Size(21, 22),
        painter: _ChecklistMark(state, color),
      ),
    ),
  );
}

class _ChecklistMark extends CustomPainter {
  final String state;
  final Color color;
  _ChecklistMark(this.state, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 21);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final paper = Path()
      ..moveTo(3, 1.5)
      ..lineTo(14, 1.5)
      ..lineTo(18, 5.5)
      ..lineTo(18, 20)
      ..lineTo(3, 20)
      ..close();
    canvas.drawPath(paper, Paint()..color = color.withValues(alpha: .08));
    canvas.drawPath(paper, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(14, 1.5)
        ..lineTo(14, 5.5)
        ..lineTo(18, 5.5),
      stroke,
    );
    if (state == 'completed') {
      canvas.drawPath(
        Path()
          ..moveTo(6, 12)
          ..lineTo(9, 15)
          ..lineTo(15, 8),
        stroke..strokeWidth = 2,
      );
    } else if (state == 'cancelled') {
      canvas.drawLine(const Offset(6, 8), const Offset(15, 16), stroke);
      canvas.drawLine(const Offset(15, 8), const Offset(6, 16), stroke);
    } else {
      for (final y in [9.0, 13.0, 17.0]) {
        canvas.drawCircle(Offset(6, y), .65, Paint()..color = color);
        canvas.drawLine(Offset(9, y), Offset(y == 17 ? 13 : 15, y), stroke);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChecklistMark oldDelegate) =>
      state != oldDelegate.state || color != oldDelegate.color;
}
