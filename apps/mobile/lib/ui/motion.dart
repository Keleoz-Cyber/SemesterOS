import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'empty_scene.dart';
import 'v2/shiri_tokens.dart';
import 'v2/motion/skeleton.dart';
import 'v2/motion/completion_check.dart';

const Duration motionDuration = ShiriMotion.standard;
const Duration motionQuick = ShiriMotion.quick;
const Curve motionEaseOut = ShiriMotion.easeDecelerate;

class AppMotion {
  static bool reduced(BuildContext context) =>
      (MediaQuery.maybeOf(context)?.disableAnimations ?? false) ||
      (MediaQuery.maybeOf(context)?.accessibleNavigation ?? false);
  static bool allowed(BuildContext context) =>
      !reduced(context) &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.isCurrentOf(context) != false;
  static Duration change(BuildContext context) =>
      reduced(context) ? Duration.zero : motionDuration;
  static Duration feedback(BuildContext context) =>
      reduced(context) ? Duration.zero : motionQuick;
  static Duration sheet(BuildContext context) =>
      reduced(context) ? Duration.zero : ShiriMotion.emphasized;
  static Duration page(BuildContext context) => change(context);
  static Duration expand(BuildContext context) =>
      reduced(context) ? Duration.zero : const Duration(milliseconds: 260);
}

/// Moves new content in place while retaining its scroll and input state.
/// Only the incoming content paints, so dense text never overlaps mid-change.
class AppContentTransition extends StatefulWidget {
  final Object value;
  final Widget child;
  final AxisDirection direction;
  const AppContentTransition({
    super.key,
    required this.value,
    required this.child,
    this.direction = AxisDirection.right,
  });
  @override
  State<AppContentTransition> createState() => _AppContentTransitionState();
}

class _AppContentTransitionState extends State<AppContentTransition>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ShiriMotion.standard,
    value: 1,
  );
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotion.allowed(context)) _finish();
  }

  void _finish() {
    _controller.stop();
    _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant AppContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_foreground || !AppMotion.allowed(context)) {
      _finish();
    } else if (oldWidget.value != widget.value) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _finish();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final t = Curves.easeOutCubic.transform(_controller.value);
      final distance = 14 * (1 - t);
      final offset = switch (widget.direction) {
        AxisDirection.left => Offset(-distance, 0),
        AxisDirection.right => Offset(distance, 0),
        AxisDirection.up => Offset(0, -distance),
        AxisDirection.down => Offset(0, distance),
      };
      return ClipRect(
        child: Transform.translate(
          offset: offset,
          child: Opacity(opacity: .35 + .65 * t, child: child),
        ),
      );
    },
  );
}

/// Reveals content at its natural size, without shrinking its text.
/// Closed fields are mounted only when opened unless state retention is needed.
class AppExpandRegion extends StatefulWidget {
  final bool visible, maintainState;
  final Widget child;
  const AppExpandRegion({
    super.key,
    required this.visible,
    required this.child,
    this.maintainState = false,
  });
  @override
  State<AppExpandRegion> createState() => _AppExpandRegionState();
}

class _AppExpandRegionState extends State<AppExpandRegion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late final Animation<double> _reveal;
  late bool _mountedChild;
  late double _target;
  bool _foreground = true, _releaseScheduled = false;

  @override
  void initState() {
    super.initState();
    _mountedChild = widget.visible || widget.maintainState;
    _target = widget.visible ? 1 : 0;
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 260),
          value: widget.visible ? 1 : 0,
        )..addStatusListener((status) {
          if (status == AnimationStatus.dismissed) _releaseClosedChild();
        });
    _reveal = _controller.drive(CurveTween(curve: Curves.easeOutCubic));
    WidgetsBinding.instance.addObserver(this);
  }

  void _releaseClosedChild() {
    if (_releaseScheduled || !_mountedChild || widget.maintainState) return;
    _releaseScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _releaseScheduled = false;
      if (mounted &&
          !widget.visible &&
          !widget.maintainState &&
          _controller.value == 0 &&
          _mountedChild) {
        setState(() => _mountedChild = false);
      }
    });
  }

  void _sync() {
    final target = widget.visible ? 1.0 : 0.0;
    if (!_foreground || !AppMotion.allowed(context)) {
      _target = target;
      _controller.stop();
      _controller.value = target;
      if (target == 0) _releaseClosedChild();
    } else if (_target != target || !_controller.isAnimating) {
      _target = target;
      if (_controller.value == target) {
        _controller.stop();
        if (target == 0) _releaseClosedChild();
      } else {
        target == 1 ? _controller.forward() : _controller.reverse();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AppExpandRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible || widget.maintainState) _mountedChild = true;
    _sync();
    if (!widget.visible && _controller.value == 0) _releaseClosedChild();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_mountedChild) return const SizedBox.shrink();
    return ClipRect(
      child: SizeTransition(
        sizeFactor: _reveal,
        alignment: Alignment.topCenter,
        child: IgnorePointer(
          ignoring: !widget.visible,
          child: ExcludeSemantics(
            excluding: !widget.visible,
            child: ExcludeFocus(
              excluding: !widget.visible,
              child: TickerMode(
                enabled: widget.visible,
                child: FadeTransition(opacity: _reveal, child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stops repeating motion when the subtree is offstage or the app is backgrounded.
abstract class _MotionState<T extends StatefulWidget> extends State<T>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController controller;
  Duration get duration;
  bool get repeats => false;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: duration);
    WidgetsBinding.instance.addObserver(this);
  }

  void syncMotion() {
    if (!mounted) return;
    if (!_foreground || !AppMotion.allowed(context)) {
      controller.stop();
      controller.value = repeats ? .5 : 1;
    } else if (!controller.isAnimating) {
      if (repeats) {
        controller.repeat();
      } else if (!controller.isCompleted) {
        controller.forward();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    syncMotion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }
}

class TabEntrance extends StatefulWidget {
  final Widget child;
  final bool active, animateOnMount;
  final AxisDirection direction;
  const TabEntrance({
    super.key,
    required this.child,
    required this.active,
    this.animateOnMount = true,
    this.direction = AxisDirection.right,
  });
  @override
  State<TabEntrance> createState() => _TabEntranceState();
}

class _TabEntranceState extends _MotionState<TabEntrance> {
  bool _firstAppearance = true;
  bool _pendingEntrance = false;
  @override
  Duration get duration => motionDuration;
  @override
  void syncMotion() {
    if (_firstAppearance) {
      _firstAppearance = false;
      _pendingEntrance = widget.active && widget.animateOnMount;
      controller.value = 1;
    }
    if (!widget.active || AppMotion.reduced(context)) {
      _pendingEntrance = false;
      controller.stop();
      controller.value = 1;
      return;
    }
    if (!_foreground || !AppMotion.allowed(context)) {
      controller.stop();
      controller.value = 1;
      _pendingEntrance = false;
      return;
    }
    if (_pendingEntrance) {
      _pendingEntrance = false;
      controller.forward(from: 0);
      return;
    }
    super.syncMotion();
  }

  @override
  void didUpdateWidget(covariant TabEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _pendingEntrance = true;
    syncMotion();
  }

  Offset get offset => switch (widget.direction) {
    AxisDirection.left => const Offset(-.04, 0),
    AxisDirection.right => const Offset(.04, 0),
    AxisDirection.up => const Offset(0, -.04),
    AxisDirection.down => const Offset(0, .04),
  };
  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: widget.active && ModalRoute.isCurrentOf(context) != false,
    child: ExcludeFocus(
      excluding: !widget.active,
      child: FadeTransition(
        opacity: controller.drive(CurveTween(curve: motionEaseOut)),
        child: ScaleTransition(
          scale: controller.drive(
            Tween(begin: .98, end: 1.0).chain(CurveTween(curve: motionEaseOut)),
          ),
          child: HeroMode(
            enabled: widget.active && !AppMotion.reduced(context),
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

class LoadingDots extends StatefulWidget {
  final Color? color;
  final double size;
  const LoadingDots({super.key, this.color, this.size = 8});
  @override
  State<LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends _MotionState<LoadingDots> {
  @override
  Duration get duration => const Duration(milliseconds: 1200);
  @override
  bool get repeats => true;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载',
    liveRegion: true,
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          final value = (controller.value - index * .2).clamp(0.0, 1.0);
          final scale = math.sin(value * math.pi);
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.size / 4),
            child: Transform.scale(
              scale: .5 + scale * .5,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: (widget.color ?? Theme.of(context).colorScheme.primary)
                      .withValues(alpha: .3 + scale * .7),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final EmptySceneKind? scene;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.scene,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (scene != null)
            AppEmptyScene(
              kind: scene!,
              size: 180,
              accent: Theme.of(context).colorScheme.secondary,
            )
          else
            ExcludeSemantics(
              child: Icon(
                icon,
                size: 40,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (message?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorState({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: EmptyState(
      icon: Icons.error_outline_rounded,
      scene: EmptySceneKind.offline,
      title: '加载失败',
      message: message,
      action: onRetry == null
          ? null
          : FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
    ),
  );
}

/// Legacy API backed by the shared v2 shimmer scope.
class SkeletonLoader extends StatelessWidget {
  final double width, height;
  final BorderRadius? borderRadius;
  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载',
    child: SkeletonBox(
      width: width,
      height: height,
      borderRadius: borderRadius ?? ShiriRadius.xsAll,
    ),
  );
}

class SuccessCheckmark extends StatelessWidget {
  final double size;
  final Color? color;
  const SuccessCheckmark({super.key, this.size = 64, this.color});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CompletionCheck(status: CompletionStatus.done, color: color),
    ),
  );
}
