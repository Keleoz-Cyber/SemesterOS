/// The gold "now" dot for time axes, with a once-per-minute halo pulse.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../shiri_tokens.dart';
import 'reduced_motion.dart';

/// A gold dot (sun gradient, white rim) marking the current time.
///
/// Each time the minute changes the halo pulses exactly once: scale 1 -> 1.8,
/// opacity .45 -> 0, 900ms decelerate. It never loops.
///
/// * With [time] null, an internal timer aligned to minute boundaries drives
///   the pulse; the timer only runs while tickers are enabled (not in a hidden
///   tab).
/// * With [time] supplied (e.g. the page's own clock), a pulse plays whenever
///   its minute differs from the previous one.
/// * No pulse under reduced motion. Not shown in semantics unless
///   [semanticLabel] is given; the adjacent time label carries the meaning.
///
/// Per MASTER the now marker lives in the left time axis, never across course
/// columns. The halo paints outside the dot's [size]; leave ~0.4 * [size] of
/// room around it.
class NowDot extends StatefulWidget {
  const NowDot({super.key, this.time, this.size = 12, this.semanticLabel});

  /// External clock; null uses an internal minute timer.
  final DateTime? time;

  /// Diameter of the dot, including its 2dp white rim.
  final double size;
  final String? semanticLabel;

  static const Duration pulseDuration = Duration(milliseconds: 900);

  @override
  State<NowDot> createState() => _NowDotState();
}

class _NowDotState extends State<NowDot> with SingleTickerProviderStateMixin {
  // Value 1 = resting (halo invisible). A pulse runs 0 -> 1.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: NowDot.pulseDuration,
    value: 1,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _pulse,
    curve: ShiriMotion.easeDecelerate,
  );
  Timer? _timer;
  bool _tickersEnabled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickersEnabled =
        motionAllowed(context) && ModalRoute.isCurrentOf(context) != false;
    if (!_tickersEnabled) {
      _pulse.stop();
      _pulse.value = 1;
    }
    _scheduleMinuteTimer();
  }

  @override
  void didUpdateWidget(NowDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.time, after = widget.time;
    if (after != null && before != null && _minute(before) != _minute(after)) {
      _playPulse();
    }
    if ((before == null) != (after == null)) _scheduleMinuteTimer();
  }

  static int _minute(DateTime t) =>
      t.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;

  void _scheduleMinuteTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.time != null || !_tickersEnabled) return;
    final now = DateTime.now();
    final untilNext = Duration(
      milliseconds:
          Duration.millisecondsPerMinute -
          now.millisecondsSinceEpoch % Duration.millisecondsPerMinute,
    );
    _timer = Timer(untilNext + const Duration(milliseconds: 16), () {
      _playPulse();
      _scheduleMinuteTimer();
    });
  }

  void _playPulse() {
    if (!mounted || !_tickersEnabled || !motionAllowed(context)) return;
    _pulse.forward(from: 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _curve.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _NowDotPainter(
          pulse: _curve,
          rim: context.shiri.colors.surface,
          isDark: context.shiri.isDark,
        ),
      ),
    );
    final label = widget.semanticLabel;
    return label == null
        ? ExcludeSemantics(child: dot)
        : Semantics(label: label, child: dot);
  }
}

class _NowDotPainter extends CustomPainter {
  _NowDotPainter({required this.pulse, required this.rim, required this.isDark})
    : super(repaint: pulse);

  final Animation<double> pulse;
  final Color rim;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;

    final t = pulse.value;
    if (t < 1) {
      final haloRadius = radius * (1 + 0.8 * t);
      final alpha = 0.45 * (1 - t);
      canvas.drawCircle(
        center,
        haloRadius,
        Paint()..color = ShiriBrand.sun500.withValues(alpha: alpha),
      );
    }

    // Soft glow so the dot reads on light and dark axes alike.
    canvas.drawCircle(
      center.translate(0, radius * 0.25),
      radius * 1.15,
      Paint()
        ..color = ShiriBrand.sun500.withValues(alpha: isDark ? 0.25 : 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.6),
    );
    canvas.drawCircle(center, radius, Paint()..color = rim);
    final inner = Rect.fromCircle(center: center, radius: radius - 2);
    canvas.drawOval(
      inner,
      Paint()..shader = ShiriGradients.sun.createShader(inner),
    );
    // Thin ink ring keeps the gold dot >= 3:1 against white rims/surfaces.
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ShiriBrand.sunInk.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_NowDotPainter oldDelegate) =>
      oldDelegate.pulse != pulse ||
      oldDelegate.rim != rim ||
      oldDelegate.isDark != isDark;
}
