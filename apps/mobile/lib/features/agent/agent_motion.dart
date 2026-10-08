import 'package:flutter/material.dart';
import '../../ui/motion.dart' show AppMotion;
import '../../ui/v2/shiri_tokens.dart';

/// A real snapshot arriving may reveal once. The child is never truncated,
/// delayed or size-animated, and remains readable/interactive immediately.
class AssistantArrival extends StatefulWidget {
  final Widget child;
  final Object? revision;
  final bool animateInitial;
  final VoidCallback? onInitialConsumed;
  final Duration duration;
  final double shift;
  const AssistantArrival({
    super.key,
    required this.child,
    this.revision,
    this.animateInitial = false,
    this.onInitialConsumed,
    this.duration = ShiriMotion.standard,
    this.shift = 12,
  });
  @override
  State<AssistantArrival> createState() => _AssistantArrivalState();
}

class _AssistantArrivalState extends State<AssistantArrival>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  late final Animation<double> _opacity;
  bool _pending = false, _foreground = true;
  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1,
    );
    _opacity = _motion.drive(CurveTween(curve: ShiriMotion.easeReveal));
    _pending = widget.animateInitial;
    if (_pending) widget.onInitialConsumed?.call();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  void _sync() {
    if (!_foreground ||
        ModalRoute.isCurrentOf(context) == false ||
        !AppMotion.allowed(context)) {
      _pending = false;
      _motion.stop();
      _motion.value = 1;
      return;
    }
    if (_pending) {
      _pending = false;
      _motion.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AssistantArrival oldWidget) {
    super.didUpdateWidget(oldWidget);
    _motion.duration = widget.duration;
    if (widget.revision != null && widget.revision != oldWidget.revision) {
      _pending = true;
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
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: FadeTransition(
      opacity: _opacity,
      alwaysIncludeSemantics: true,
      child: AnimatedBuilder(
        animation: _opacity,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, widget.shift * (1 - _opacity.value)),
          child: child,
        ),
      ),
    ),
  );
}
