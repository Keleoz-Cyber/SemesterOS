import 'package:flutter/material.dart';
import 'time_urgency.dart';
export 'time_urgency.dart';

/// A brief border cue for the one urgent item at the top of Today. It settles
/// after two breaths and pauses with visibility or reduced motion.
class BreathingCard extends StatefulWidget {
  final Widget child;
  final int? remainingMinutes;
  final Color? urgencyColor;
  final bool enabled;
  const BreathingCard({
    super.key,
    required this.child,
    this.remainingMinutes,
    this.urgencyColor,
    this.enabled = false,
  });
  @override
  State<BreathingCard> createState() => _BreathingCardState();
}

class _BreathingCardState extends State<BreathingCard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  bool _foreground = true;
  bool _started = false;
  bool _canAnimate = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
  }

  void _sync() {
    if (!mounted) return;
    final media = MediaQuery.maybeOf(context);
    _canAnimate =
        widget.enabled &&
        widget.remainingMinutes != null &&
        widget.remainingMinutes! > 0 &&
        widget.remainingMinutes! < 120 &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !(media?.disableAnimations ?? false) &&
        !(media?.accessibleNavigation ?? false);
    if (!_canAnimate) {
      _controller.stop();
    } else if (!_started) {
      _started = true;
      _controller.forward(from: 0);
    } else if (_controller.value < 1 && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant BreathingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.remainingMinutes == null) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final phase = _canAnimate ? _controller.value * 4 : 0.0;
        final breath = phase < 1
            ? phase
            : phase < 2
            ? 2 - phase
            : phase < 3
            ? phase - 2
            : 4 - phase;
        return Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  (widget.urgencyColor ??
                          TimeUrgency.getColor(widget.remainingMinutes))
                      .withValues(alpha: .22 + .24 * breath.clamp(0, 1)),
              width: 1.5,
            ),
          ),
          child: child,
        );
      },
    );
  }
}
