import 'package:flutter/material.dart';

abstract final class AppMotion {
  static Duration feedback(BuildContext context) => _duration(context, 120);
  static Duration change(BuildContext context) => _duration(context, 220);
  static Duration sheet(BuildContext context) => _duration(context, 300);
  static Duration _duration(BuildContext context, int ms) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(milliseconds: ms);
}

/// Moves only the newly visible tab. The page subtree stays mounted so its
/// scroll position and draft state survive navigation.
class TabEntrance extends StatefulWidget {
  final bool active;
  final bool animateOnMount;
  final double direction;
  final Widget child;

  const TabEntrance({
    super.key,
    required this.active,
    required this.direction,
    required this.child,
    this.animateOnMount = false,
  });

  @override
  State<TabEntrance> createState() => _TabEntranceState();
}

class _TabEntranceState extends State<TabEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    value: 1,
  );
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller.duration = AppMotion.change(context);
    if (!initialized) {
      initialized = true;
      if (widget.active &&
          widget.animateOnMount &&
          !MediaQuery.disableAnimationsOf(context)) {
        controller.forward(from: 0);
      }
    } else if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant TabEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.value = 1;
      } else {
        controller.forward(from: 0);
      }
    } else if (!widget.active && oldWidget.active) {
      controller.stop();
      controller.value = 1;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (context, child) => Transform.translate(
      key: const ValueKey('tab-entrance-transform'),
      offset: Offset(
        widget.direction *
            (1 - Curves.easeOutCubic.transform(controller.value)) *
            14,
        0,
      ),
      child: child,
    ),
  );
}
