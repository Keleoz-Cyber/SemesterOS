import 'package:flutter/material.dart';
import 'campus_theme.dart';

class CampusPanel extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  const CampusPanel({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(18),
  });
  @override
  Widget build(BuildContext context) => Material(
    color: color ?? Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: CampusColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color foreground, background;
  final IconData? icon;
  const StatusPill(
    this.text, {
    super.key,
    this.foreground = CampusColors.primary,
    this.background = const Color(0xFFEEEBFF),
    this.icon,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ),
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeading(this.title, {super.key, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(action!, style: const TextStyle(fontSize: 13)),
          ),
      ],
    ),
  );
}

class SoftNotice extends StatelessWidget {
  final String text;
  final bool warning;
  const SoftNotice(this.text, {super.key, this.warning = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFFF2D9) : const Color(0xFFEDF3FF),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          warning ? Icons.info_outline_rounded : Icons.cloud_done_outlined,
          size: 19,
          color: warning ? const Color(0xFF825C1D) : const Color(0xFF48659A),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: warning
                  ? const Color(0xFF825C1D)
                  : const Color(0xFF48659A),
            ),
          ),
        ),
      ],
    ),
  );
}

class CampusHero extends StatelessWidget {
  final String eyebrow, title, subtitle;
  const CampusHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) {
    final art = MediaQuery.textScalerOf(context).scale(1) <= 1.3;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFECEBFF), Color(0xFFEDF6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Stack(
        children: [
          if (art)
            const Positioned(
              right: -4,
              bottom: 0,
              child: SizedBox(
                width: 135,
                height: 142,
                child: CustomPaint(painter: CampusScenePainter()),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 20, art ? 124 : 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF626A93),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Color(0xFF606D8C),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CampusScenePainter extends CustomPainter {
  const CampusScenePainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 150, size.height / 155);
    final p = Paint();
    void rect(
      double x,
      double y,
      double w,
      double h,
      int color, [
      double radius = 0,
    ]) {
      p.color = Color(color);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          Radius.circular(radius),
        ),
        p,
      );
    }

    p.color = const Color(0xFFFFFFFF).withValues(alpha: .68);
    canvas.drawCircle(const Offset(112, 30), 24, p);
    canvas.drawCircle(const Offset(39, 41), 11, p);
    canvas.drawCircle(const Offset(53, 38), 15, p);
    canvas.drawCircle(const Offset(69, 43), 10, p);
    rect(18, 86, 117, 60, 0xFFC6D7EA, 3);
    rect(20, 80, 110, 8, 0xFFB5C6DF, 2);
    rect(58, 48, 39, 101, 0xFFE9D4C8, 2);
    rect(54, 43, 47, 8, 0xFFD8BFB1, 2);
    rect(73, 19, 4, 24, 0xFFAEB5D4);
    final flag = Path()
      ..moveTo(77, 20)
      ..lineTo(98, 25)
      ..lineTo(77, 31)
      ..close();
    p.color = const Color(0xFF9B96D8);
    canvas.drawPath(flag, p);
    for (var x = 29; x < 128; x += 17) {
      for (var y = 97; y < 137; y += 19) {
        rect(x.toDouble(), y.toDouble(), 8, 11, 0xFF8EAEC7, 1);
      }
    }
    rect(65, 87, 25, 42, 0xFFE9D4C8);
    rect(70, 110, 13, 38, 0xFFC0AAA9, 6);
    p.color = const Color(0xFFFBF8F4);
    canvas.drawCircle(const Offset(77, 69), 13, p);
    p
      ..color = const Color(0xFFB8AAA8)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(77, 69), const Offset(77, 62), p);
    canvas.drawLine(const Offset(77, 69), const Offset(83, 72), p);
    rect(0, 145, 150, 12, 0xFFCDE9DF, 6);
    for (final point in [
      const Offset(16, 122),
      const Offset(126, 125),
      const Offset(142, 114),
    ]) {
      rect(point.dx - 2, point.dy, 4, 26, 0xFFA6BFB1, 1);
      p.color = const Color(0xFF9DCDB7);
      canvas.drawOval(Rect.fromCenter(center: point, width: 22, height: 33), p);
      p.color = const Color(0xFFBADECC);
      canvas.drawOval(
        Rect.fromCenter(center: point.translate(-4, -6), width: 15, height: 23),
        p,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CampusScenePainter oldDelegate) => false;
}

class EmptyPanel extends StatelessWidget {
  final String title, message;
  final String? action;
  final VoidCallback? onAction;
  final IconData icon;
  const EmptyPanel({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.onAction,
    this.icon = Icons.event_note_rounded,
  });
  @override
  Widget build(BuildContext context) => CampusPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFFEEEBFF),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: CampusColors.primary, size: 27),
        ),
        const SizedBox(height: 17),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: const TextStyle(color: CampusColors.muted, fontSize: 14),
        ),
        if (action != null) ...[
          const SizedBox(height: 18),
          OutlinedButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}
