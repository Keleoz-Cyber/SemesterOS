/// Press feedback for custom tappable surfaces (cards, blocks, chips).
library;

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../shiri_tokens.dart';
import 'reduced_motion.dart';

/// Scales its child to [pressedScale] while pressed (90ms, standard curve) and
/// springs back with [ShiriMotion.snappy], keeping velocity if a new press
/// interrupts the release.
///
/// Even a very quick tap shows the full press-in before springing back, so the
/// feedback is always visible. It also:
///
/// * exposes button semantics ([semanticLabel], [semanticHint]; child labels
///   are merged by default),
/// * is focusable and activates with Enter / Space, drawing a focus ring,
/// * plays [HapticFeedback.lightImpact] on tap and
///   [HapticFeedback.mediumImpact] on long-press when [haptic] is true,
/// * does not scale under reduced motion.
///
/// Pressable does not add a touch target: give the child at least 48dp.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.haptic = false,
    this.pressedScale = 0.97,
    this.semanticLabel,
    this.semanticHint,
    this.button = true,
    this.selected,
    this.checked,
    this.mergeSemantics = true,
    this.excludeChildSemantics = false,
    this.focusNode,
    this.autofocus = false,
    this.focusBorderRadius = ShiriRadius.mdAll,
  });

  final Widget child;

  /// Null (with [onLongPress] null) disables the widget.
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool haptic;

  /// Scale while pressed. Use ~0.9 for small controls so the change reads.
  final double pressedScale;

  final String? semanticLabel;
  final String? semanticHint;

  /// Whether the semantics node has the button role.
  final bool button;

  /// Semantics selected state (tabs, segments); null = not selectable.
  final bool? selected;

  /// Semantics checked state (check boxes); null = not checkable.
  final bool? checked;

  /// Merge descendant semantics (e.g. a card's texts) into this node.
  final bool mergeSemantics;

  /// Replace descendant semantics with [semanticLabel] only.
  final bool excludeChildSemantics;

  final FocusNode? focusNode;
  final bool autofocus;

  /// Shape of the keyboard focus ring; match the child's corners.
  final BorderRadius focusBorderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  TickerFuture? _pressIn;
  bool _down = false;
  bool _focused = false;
  bool _disposed = false;

  bool get _enabled => widget.onPressed != null || widget.onLongPress != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) _settle();
  }

  @override
  void didUpdateWidget(Pressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) _settle();
  }

  void _settle() {
    _down = false;
    _pressIn = null;
    _scale
      ..stop()
      ..value = 1;
  }

  void _handleTapDown(TapDownDetails _) {
    if (!_enabled || reduceMotion(context)) return;
    _down = true;
    _pressIn = _scale.animateTo(
      widget.pressedScale,
      duration: ShiriMotion.tap,
      curve: ShiriMotion.easeStandard,
    );
  }

  void _handleTapEnd() {
    if (!_down) return;
    _down = false;
    final pressIn = _pressIn;
    if (pressIn != null && _scale.isAnimating) {
      // Let a quick tap finish its press-in so the feedback is visible.
      pressIn.whenCompleteOrCancel(() {
        if (!_disposed && !_down && identical(pressIn, _pressIn)) {
          _springBack();
        }
      });
    } else {
      _springBack();
    }
  }

  void _springBack() {
    _pressIn = null;
    _scale.animateWith(
      SpringSimulation(
        ShiriMotion.snappy,
        _scale.value,
        1,
        _scale.velocity,
        snapToEnd: true,
      ),
    );
  }

  void _activate() {
    if (widget.onPressed == null) return;
    if (widget.haptic) HapticFeedback.lightImpact();
    widget.onPressed!();
  }

  void _activateFromKeyboard() {
    if (widget.onPressed == null) return;
    if (!reduceMotion(context)) {
      _scale.value = widget.pressedScale;
      _springBack();
    }
    _activate();
  }

  void _longPress() {
    if (widget.onLongPress == null) return;
    if (widget.haptic) HapticFeedback.mediumImpact();
    widget.onLongPress!();
  }

  @override
  void dispose() {
    _disposed = true;
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    Widget result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTapDown: enabled ? _handleTapDown : null,
      onTapUp: enabled ? (_) => _handleTapEnd() : null,
      onTapCancel: enabled ? _handleTapEnd : null,
      onTap: widget.onPressed == null ? null : _activate,
      onLongPress: widget.onLongPress == null ? null : _longPress,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );

    result = FocusableActionDetector(
      enabled: enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowFocusHighlight: (value) {
        if (_focused != value) setState(() => _focused = value);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activateFromKeyboard();
            return null;
          },
        ),
      },
      // Always a DecoratedBox, so showing the ring never reparents the child.
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: _focused
            ? BoxDecoration(
                borderRadius: widget.focusBorderRadius,
                border: Border.all(
                  color: context.shiri.colors.focusRing,
                  width: 2,
                ),
              )
            : const BoxDecoration(),
        child: result,
      ),
    );

    result = Semantics(
      container: true,
      button: widget.button,
      selected: widget.selected,
      checked: widget.checked,
      enabled: enabled,
      label: widget.semanticLabel,
      hint: widget.semanticHint,
      onTap: widget.onPressed == null ? null : _activate,
      onLongPress: widget.onLongPress == null ? null : _longPress,
      excludeSemantics: widget.excludeChildSemantics,
      child: result,
    );
    return widget.mergeSemantics ? MergeSemantics(child: result) : result;
  }
}
