import 'campus_theme.dart';
import 'package:flutter/material.dart';

const appName = '拾日';

/// Two collected notes and a day marker, also used for launcher exports.
class BrandMark extends StatelessWidget {
  final double size;
  final bool background;
  const BrandMark({super.key, this.size = 32, this.background = true});
  @override
  Widget build(BuildContext context) => Semantics(
    label: appName,
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: BrandPainter(background: background)),
    ),
  );
}

class BrandPainter extends CustomPainter {
  final bool background;
  const BrandPainter({this.background = true});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final p = Paint()..isAntiAlias = true;
    if (background) {
      p.shader = const LinearGradient(
        colors: [Color(0xFF6888CA), CampusColors.primary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 100, 100),
          const Radius.circular(26),
        ),
        p,
      );
      p.shader = null;
    }
    canvas.save();
    canvas.translate(48, 48);
    canvas.rotate(-.13);
    p.color = const Color(0xFFD5E7E2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-27, -24, 42, 56),
        const Radius.circular(9),
      ),
      p,
    );
    canvas.restore();
    p.color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(37, 22, 42, 56),
        const Radius.circular(9),
      ),
      p,
    );
    p.color = CampusColors.primary;
    p.strokeCap = StrokeCap.round;
    p.strokeWidth = 4;
    canvas.drawLine(const Offset(48, 42), const Offset(67, 42), p);
    canvas.drawLine(const Offset(48, 53), const Offset(63, 53), p);
    canvas.drawLine(const Offset(48, 64), const Offset(57, 64), p);
    p.color = const Color(0xFFDCC48D);
    canvas.drawCircle(const Offset(77, 25), 10, p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BrandPainter old) =>
      old.background != background;
}
