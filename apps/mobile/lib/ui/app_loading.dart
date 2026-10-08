import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'campus_theme.dart';
import 'motion.dart';
import 'v2/motion/skeleton.dart';

/// First-load placeholder; refresh continues to use the non-reflowing overlay.
class AppPageSkeleton extends StatelessWidget {
  const AppPageSkeleton({super.key, this.label = '正在加载'});
  final String label;
  @override
  Widget build(BuildContext context) => SkeletonScope(
    semanticLabel: label,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        SkeletonLine(widthFactor: .48),
        SizedBox(height: 24),
        SkeletonBox(height: 128),
        SizedBox(height: 28),
        SkeletonLine(widthFactor: .28),
        SizedBox(height: 16),
        SkeletonBox(height: 72),
        SizedBox(height: 12),
        SkeletonBox(height: 72),
        SizedBox(height: 12),
        SkeletonBox(height: 72),
      ],
    ),
  );
}

/// Refresh feedback paints above the existing content; it never becomes a row.
class AppLoadingOverlay extends StatelessWidget {
  final bool loading;
  final Widget child;
  final String label;
  final bool compact;
  final Alignment alignment;
  final EdgeInsetsGeometry padding;
  const AppLoadingOverlay({
    super.key,
    required this.loading,
    required this.child,
    this.label = '正在更新',
    this.compact = true,
    this.alignment = Alignment.topRight,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      Positioned.fill(
        child: IgnorePointer(
          child: Padding(
            padding: padding,
            child: Align(
              alignment: alignment,
              child: AppLoadingIndicator(
                visible: loading,
                label: label,
                compact: compact,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// A brief request stays quiet; longer work receives a small, honest status.
/// [compact] shows just the dots while keeping [label] for screen readers.
class AppLoadingIndicator extends StatefulWidget {
  final String label;
  final bool compact, visible;
  final Duration delay;
  const AppLoadingIndicator({
    super.key,
    this.label = '正在加载',
    this.compact = false,
    this.visible = true,
    this.delay = const Duration(milliseconds: 180),
  });

  @override
  State<AppLoadingIndicator> createState() => _AppLoadingIndicatorState();
}

class _AppLoadingIndicatorState extends State<AppLoadingIndicator>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  Timer? _delay;
  bool _revealed = false, _foreground = true;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _prepare();
  }

  void _prepare() {
    _delay?.cancel();
    _revealed = widget.visible && widget.delay == Duration.zero;
    if (widget.visible && !_revealed) {
      _delay = Timer(widget.delay, () {
        if (!mounted || !widget.visible) return;
        setState(() => _revealed = true);
        _sync();
      });
    }
  }

  void _sync() {
    if (_revealed &&
        widget.visible &&
        _foreground &&
        ModalRoute.isCurrentOf(context) != false &&
        AppMotion.allowed(context)) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
      _motion.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AppLoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible ||
        oldWidget.delay != widget.delay) {
      _prepare();
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    _delay?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    excluding: !_revealed,
    child: IgnorePointer(
      child: AnimatedOpacity(
        opacity: _revealed ? 1 : 0,
        duration: AppMotion.feedback(context),
        child: Semantics(
          liveRegion: true,
          label: widget.label,
          child: ExcludeSemantics(
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.compact
                      ? Colors.transparent
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: widget.compact
                      ? null
                      : Border.all(color: CampusColors.line),
                ),
                child: Padding(
                  padding: widget.compact
                      ? const EdgeInsets.all(4)
                      : const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 12,
                        child: CustomPaint(
                          painter: _LoadingDotsPainter(
                            _motion,
                            color: CampusColors.teal,
                          ),
                        ),
                      ),
                      if (!widget.compact) ...[
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            widget.label,
                            maxLines: 2,
                            style: const TextStyle(
                              fontSize: 12,
                              color: CampusColors.muted,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _LoadingDotsPainter extends CustomPainter {
  final Animation<double> progress;
  final Color color;
  _LoadingDotsPainter(this.progress, {required this.color})
    : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var i = 0; i < 3; i++) {
      final wave = (math.sin((progress.value * 2 - i * .3) * math.pi) + 1) / 2;
      paint.color = color.withValues(alpha: .45 + wave * .55);
      canvas.drawCircle(
        Offset(3 + i * 8, size.height / 2 - wave * 1.5),
        2.2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LoadingDotsPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
