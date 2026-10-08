/// Staggered entrance for list children, played once per key per session.
library;

import 'dart:collection';

import 'package:flutter/widgets.dart';

import '../shiri_tokens.dart';
import 'reduced_motion.dart';

/// Fades a list child in while it rises 12dp (260ms, decelerate), delayed by
/// `index * 36ms`.
///
/// * Only the first [ShiriMotion.maxStaggerItems] (8) indices animate; later
///   children (usually below the fold, built while scrolling) appear at once,
///   so scrolling never waits on an entrance.
/// * A child animates only the first time its [revealKey] is seen in this app
///   session. A small static memory (LRU, [memoryCapacity] keys) remembers
///   keys, so returning to a tab or rebuilding a list does not replay it.
///   New items added later still animate once.
/// * No animation under reduced motion.
///
/// ```dart
/// for (final (i, task) in tasks.indexed)
///   StaggeredReveal(revealKey: 'today/task/${task.id}', index: i,
///                   child: TaskRow(task)),
/// ```
class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({
    super.key,
    required this.revealKey,
    required this.index,
    required this.child,
  });

  /// Stable identity of the item across rebuilds and tab switches. Prefix it
  /// with the list name (`'today/agenda/42'`) to keep lists independent.
  final Object revealKey;

  /// Position in the list; drives the stagger delay.
  final int index;

  final Widget child;

  /// Maximum number of remembered keys.
  static const int memoryCapacity = 512;

  static final LinkedHashSet<Object> _seen = LinkedHashSet<Object>();

  /// Records [key] as revealed. Returns true the first time.
  static bool _remember(Object key) {
    if (_seen.remove(key)) {
      _seen.add(key); // refresh LRU position
      return false;
    }
    _seen.add(key);
    while (_seen.length > memoryCapacity) {
      _seen.remove(_seen.first);
    }
    return true;
  }

  /// Forget every key, e.g. after an account switch, or between tests.
  static void resetMemory() => _seen.clear();

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  CurvedAnimation? _progress;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) {
      if (!motionAllowed(context)) {
        _controller?.stop();
        _controller?.value = 1;
      }
      return;
    }
    _decided = true;
    final firstTime = StaggeredReveal._remember(widget.revealKey);
    if (!firstTime ||
        widget.index >= ShiriMotion.maxStaggerItems ||
        !motionAllowed(context)) {
      return;
    }
    // One controller covers delay + entrance, so no timers are needed.
    final delay = ShiriMotion.stagger * widget.index;
    final total = delay + ShiriMotion.standard;
    final start = delay.inMicroseconds / total.inMicroseconds;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _progress = CurvedAnimation(
      parent: controller,
      curve: Interval(start, 1, curve: ShiriMotion.easeDecelerate),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _progress?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    if (progress == null) return widget.child;
    return FadeTransition(
      opacity: progress,
      child: AnimatedBuilder(
        animation: progress,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 12 * (1 - progress.value)),
          child: child,
        ),
      ),
    );
  }
}
