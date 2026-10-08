/// Task completion control and the strike-through that follows a confirmed
/// save.
///
/// MASTER: a task is struck through only after the server confirms the save.
/// These widgets never decide that themselves - the parent moves
/// [CompletionCheck.status] to [CompletionStatus.pending] when it starts the
/// request and to [CompletionStatus.done] when the receipt arrives (or back to
/// idle on failure), and flips [StrikeThroughText.struck] at the same time.
library;

import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../shiri_tokens.dart';
import 'pressable.dart';
import 'reduced_motion.dart';

/// Save state of a task's completion.
enum CompletionStatus {
  /// Not completed; tappable.
  idle,

  /// A save is in flight; shows an arc spinner, not tappable.
  pending,

  /// The server confirmed completion.
  done,
}

/// A round check with a 24dp ring inside a 48x48 touch target.
///
/// idle -> pending: a primary arc spins around the ring while saving (static
/// under reduced motion). pending -> done: the circle fills with a clockwise
/// sweep (220ms), the check draws (180ms), then the whole check pops with
/// [ShiriMotion.pop]. done -> idle reverses quickly without the pop. A widget
/// first built as done shows the final state without animating.
class CompletionCheck extends StatefulWidget {
  const CompletionCheck({
    super.key,
    required this.status,
    this.onPressed,
    this.semanticLabel,
    this.color,
  });

  final CompletionStatus status;

  /// Called on tap while idle or done. Ignored while pending.
  final VoidCallback? onPressed;

  /// e.g. `'完成：高数作业'`. Read together with the checked state.
  final String? semanticLabel;

  /// Fill when done. Defaults to [ShiriColors.success].
  final Color? color;

  static const double ringSize = 24;
  static const Duration fillDuration = Duration(milliseconds: 220);
  static const Duration checkDuration = Duration(milliseconds: 180);

  @override
  State<CompletionCheck> createState() => _CompletionCheckState();
}

class _CompletionCheckState extends State<CompletionCheck>
    with TickerProviderStateMixin {
  static final double _fillSplit =
      CompletionCheck.fillDuration.inMicroseconds /
      (CompletionCheck.fillDuration + CompletionCheck.checkDuration)
          .inMicroseconds;

  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: CompletionCheck.fillDuration + CompletionCheck.checkDuration,
    value: widget.status == CompletionStatus.done ? 1 : 0,
  );
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _pop = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpinner();
  }

  @override
  void didUpdateWidget(CompletionCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status == widget.status) return;
    final animate = motionAllowed(context);
    switch (widget.status) {
      case CompletionStatus.done:
        _pop.value = 1;
        if (!animate) {
          _draw.value = 1;
        } else {
          _draw.forward(from: 0).then((_) {
            if (!mounted || widget.status != CompletionStatus.done) return;
            // An impulse on a resting spring: ~+12% bump, ~2% rebound.
            _pop.animateWith(
              SpringSimulation(ShiriMotion.pop, 1, 1, 4.5, snapToEnd: true),
            );
          });
        }
      case CompletionStatus.idle || CompletionStatus.pending:
        _pop
          ..stop()
          ..value = 1;
        if (!animate || oldWidget.status != CompletionStatus.done) {
          _draw.value = 0;
        } else {
          _draw.animateBack(0, duration: ShiriMotion.quick);
        }
    }
    _syncSpinner();
  }

  void _syncSpinner() {
    if (widget.status == CompletionStatus.pending && !reduceMotion(context)) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    _spin.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shiri.colors;
    final status = widget.status;
    final pending = status == CompletionStatus.pending;
    return Pressable(
      onPressed: pending ? null : widget.onPressed,
      pressedScale: 0.88,
      haptic: true,
      button: false,
      checked: status == CompletionStatus.done,
      semanticLabel: widget.semanticLabel ?? '完成',
      semanticHint: pending ? '正在保存' : null,
      focusBorderRadius: const BorderRadius.all(Radius.circular(24)),
      child: SizedBox.square(
        dimension: ShiriLayout.touchTarget,
        child: Center(
          child: ScaleTransition(
            scale: _pop,
            child: RepaintBoundary(
              child: CustomPaint(
                size: const Size.square(CompletionCheck.ringSize),
                painter: _CheckPainter(
                  draw: _draw,
                  spin: _spin,
                  fillSplit: _fillSplit,
                  pending: pending,
                  ring: pending ? colors.ink400 : colors.ink500,
                  arc: colors.primary,
                  fill: widget.color ?? colors.success,
                  check: colors.isDark ? colors.inkInverse : colors.surface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({
    required this.draw,
    required this.spin,
    required this.fillSplit,
    required this.pending,
    required this.ring,
    required this.arc,
    required this.fill,
    required this.check,
  }) : super(repaint: Listenable.merge([draw, spin]));

  final Animation<double> draw;
  final Animation<double> spin;
  final double fillSplit;
  final bool pending;
  final Color ring;
  final Color arc;
  final Color fill;
  final Color check;

  static const double _stroke = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - _stroke / 2;
    final d = draw.value;
    final fillT = ShiriMotion.easeStandard.transform(
      (d / fillSplit).clamp(0.0, 1.0),
    );
    final checkT = ShiriMotion.easeDecelerate.transform(
      ((d - fillSplit) / (1 - fillSplit)).clamp(0.0, 1.0),
    );

    if (fillT < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..color = ring,
      );
    }
    if (fillT > 0) {
      // Clockwise wipe from 12 o'clock, covering the ring stroke too.
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius + _stroke / 2),
        -math.pi / 2,
        2 * math.pi * fillT,
        true,
        Paint()..color = fill,
      );
    }
    if (checkT > 0) {
      final s = size.shortestSide / 24;
      final path = Path()
        ..moveTo(center.dx - 5.2 * s, center.dy + 0.4 * s)
        ..lineTo(center.dx - 1.6 * s, center.dy + 3.9 * s)
        ..lineTo(center.dx + 5.4 * s, center.dy - 3.6 * s);
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * checkT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 * s
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = check,
      );
    }
    if (pending) {
      // A quarter arc rotating once per 900ms; static when spin is idle.
      final start = -math.pi / 2 + 2 * math.pi * spin.value;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        math.pi / 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke + 0.6
          ..strokeCap = StrokeCap.round
          ..color = arc,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) =>
      oldDelegate.draw != draw ||
      oldDelegate.spin != spin ||
      oldDelegate.pending != pending ||
      oldDelegate.ring != ring ||
      oldDelegate.arc != arc ||
      oldDelegate.fill != fill ||
      oldDelegate.check != check;
}

/// Text that gets struck through once its task is confirmed done.
///
/// When [struck] turns true a line draws across each line of the text, left to
/// right, over 220ms, while the text fades to [ShiriColors.ink400]. Turning it
/// false retracts the line. Instant under reduced motion. Multi-line text is
/// struck line by line, following the actual line breaks.
class StrikeThroughText extends StatefulWidget {
  const StrikeThroughText(
    this.text, {
    super.key,
    required this.struck,
    this.style,
    this.struckColor,
    this.maxLines,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final bool struck;

  /// Merged over the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// Text and line color when struck; defaults to [ShiriColors.ink400].
  final Color? struckColor;
  final int? maxLines;
  final TextAlign textAlign;

  static const Duration duration = Duration(milliseconds: 220);

  @override
  State<StrikeThroughText> createState() => _StrikeThroughTextState();
}

class _StrikeThroughTextState extends State<StrikeThroughText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: StrikeThroughText.duration,
    value: widget.struck ? 1 : 0,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: ShiriMotion.easeStandard,
  );
  final _StrikeLayout _layout = _StrikeLayout();

  @override
  void didUpdateWidget(StrikeThroughText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.struck == widget.struck) return;
    final target = widget.struck ? 1.0 : 0.0;
    if (motionAllowed(context)) {
      _controller.animateTo(target);
    } else {
      _controller.value = target;
    }
  }

  @override
  void dispose() {
    _layout.dispose();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(widget.style);
    final struckColor = widget.struckColor ?? context.shiri.colors.ink400;
    final from = base.color ?? context.shiri.colors.ink900;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, _) {
          final t = _curve.value;
          final style = base.copyWith(color: Color.lerp(from, struckColor, t));
          return CustomPaint(
            foregroundPainter: t == 0
                ? null
                : _StrikePainter(
                    layout: _layout,
                    text: widget.text,
                    style: style,
                    scaler: scaler,
                    direction: direction,
                    align: widget.textAlign,
                    maxLines: widget.maxLines,
                    progress: t,
                    color: struckColor,
                  ),
            child: Text(
              widget.text,
              style: style,
              maxLines: widget.maxLines,
              overflow: widget.maxLines == null
                  ? TextOverflow.clip
                  : TextOverflow.ellipsis,
              textAlign: widget.textAlign,
            ),
          );
        },
      ),
    );
  }
}

/// Caches the line metrics of the struck text for one width, so the 220ms
/// animation lays the paragraph out once instead of on every frame.
class _StrikeLayout {
  TextPainter? _painter;
  Object? _key;
  List<LineMetrics> _lines = const [];

  List<LineMetrics> linesFor({
    required String text,
    required TextStyle style,
    required TextScaler scaler,
    required TextDirection direction,
    required TextAlign align,
    required int? maxLines,
    required double width,
  }) {
    // Color does not affect layout; leave it out of the cache key.
    final key = Object.hash(
      text,
      style.copyWith(color: const Color(0xFF000000)),
      scaler,
      direction,
      align,
      maxLines,
      width,
    );
    if (key == _key) return _lines;
    _painter?.dispose();
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textAlign: align,
      textScaler: scaler,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: width + 0.5);
    _painter = painter;
    _key = key;
    _lines = painter.computeLineMetrics();
    return _lines;
  }

  void dispose() => _painter?.dispose();
}

class _StrikePainter extends CustomPainter {
  _StrikePainter({
    required this.layout,
    required this.text,
    required this.style,
    required this.scaler,
    required this.direction,
    required this.align,
    required this.maxLines,
    required this.progress,
    required this.color,
  });

  final _StrikeLayout layout;
  final String text;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection direction;
  final TextAlign align;
  final int? maxLines;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lines = layout.linesFor(
      text: text,
      style: style,
      scaler: scaler,
      direction: direction,
      align: align,
      maxLines: maxLines,
      width: size.width,
    );
    final total = lines.fold<double>(0, (sum, l) => sum + l.width);
    if (total <= 0) return;
    final fontSize = scaler.scale(style.fontSize ?? 14);
    final paint = Paint()
      ..color = color
      ..strokeWidth = math.max(1.5, fontSize / 11)
      ..strokeCap = StrokeCap.round;
    var remaining = total * progress;
    for (final line in lines) {
      if (remaining <= 0) break;
      final length = math.min(line.width, remaining);
      remaining -= length;
      // Through the visual middle of CJK and lowercase Latin glyphs.
      final y = line.baseline - fontSize * 0.33;
      final ltr = direction == TextDirection.ltr;
      final startX = ltr ? line.left : line.left + line.width;
      final endX = ltr ? startX + length : startX - length;
      canvas.drawLine(Offset(startX, y), Offset(endX, y), paint);
    }
  }

  @override
  bool shouldRepaint(_StrikePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.text != text ||
      oldDelegate.style != style ||
      oldDelegate.color != color ||
      oldDelegate.scaler != scaler ||
      oldDelegate.align != align ||
      oldDelegate.maxLines != maxLines;
}
