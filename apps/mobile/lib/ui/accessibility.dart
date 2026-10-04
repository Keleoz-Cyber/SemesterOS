import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'campus_theme.dart';

/// Custom action semantics preserve child actions. Existing native controls can
/// set childHandlesInput so their pointer and keyboard behavior stays intact.
class SemanticButton extends StatelessWidget {
  final String label;
  final String? hint;
  final VoidCallback? onPressed;
  final Widget child;
  final bool enabled, childHandlesInput;
  const SemanticButton({
    super.key,
    required this.label,
    this.hint,
    required this.onPressed,
    required this.child,
    this.enabled = true,
    this.childHandlesInput = false,
  });
  @override
  Widget build(BuildContext context) {
    final action = enabled ? onPressed : null;
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled && onPressed != null,
        label: label.isEmpty ? null : label,
        hint: hint,
        onTap: action,
        child: _AccessibleAction(
          onTap: action,
          childHandlesInput: childHandlesInput,
          child: child,
        ),
      ),
    );
  }
}

class SemanticCard extends StatelessWidget {
  final String label;
  final String? hint, value;
  final VoidCallback? onTap;
  final Widget child;
  final bool childHandlesInput;
  const SemanticCard({
    super.key,
    required this.label,
    this.hint,
    this.value,
    this.onTap,
    required this.child,
    this.childHandlesInput = false,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: label.isEmpty ? null : label,
    hint: hint,
    value: value,
    button: !childHandlesInput && onTap != null,
    onTap: childHandlesInput ? null : onTap,
    child: _AccessibleAction(
      onTap: onTap,
      childHandlesInput: childHandlesInput,
      child: child,
    ),
  );
}

class SemanticProgressBar extends StatelessWidget {
  final double value;
  final String label;
  final Widget child;
  const SemanticProgressBar({
    super.key,
    required this.value,
    required this.label,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    value: '${(value.clamp(0, 1) * 100).round()}%',
    child: child,
  );
}

class HighContrastDetector extends StatelessWidget {
  final Widget child;
  final Widget Function(BuildContext, bool)? builder;
  const HighContrastDetector({super.key, required this.child, this.builder});
  @override
  Widget build(BuildContext context) =>
      builder?.call(
        context,
        MediaQuery.maybeOf(context)?.highContrast ?? false,
      ) ??
      child;
}

/// Keeps the campus light appearance with stronger text, borders and states.
/// This is an accessibility adaptation, not a WCAG certification.
class HighContrastTheme {
  static const background = CampusColors.background;
  static const surface = CampusColors.surface;
  static const primary = Color(0xFF244B9F);
  static const text = Color(0xFF142238);
  static const textSecondary = Color(0xFF384B63);
  static const border = Color(0xFF68788B);
  static const success = Color(0xFF205D4E);
  static const error = Color(0xFF8D2927);
  static const warning = Color(0xFF6B4A19);
  static ThemeData theme([ThemeData? base]) =>
      campusHighContrastTheme(base: base);
}

class TouchTargetExpander extends StatelessWidget {
  final Widget child;
  final double minSize;
  const TouchTargetExpander({
    super.key,
    required this.child,
    this.minSize = 48,
  });
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
    child: child,
  );
}

/// Paints a focus ring without changing layout. With onTap=null this observes
/// native descendant focus without adding a second tab stop.
class FocusHighlight extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? focusColor;
  final bool? canRequestFocus;
  const FocusHighlight({
    super.key,
    required this.child,
    this.onTap,
    this.focusColor,
    this.canRequestFocus,
  });
  @override
  State<FocusHighlight> createState() => _FocusHighlightState();
}

class _FocusHighlightState extends State<FocusHighlight> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: widget.canRequestFocus ?? widget.onTap != null,
    onFocusChange: (value) {
      if (_focused != value) setState(() => _focused = value);
    },
    onKeyEvent: (_, event) {
      if (widget.onTap != null &&
          event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space)) {
        widget.onTap!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: _focused
            ? Border.all(
                color:
                    widget.focusColor ?? Theme.of(context).colorScheme.primary,
                width: 2,
              )
            : null,
      ),
      position: DecorationPosition.foreground,
      child: widget.onTap == null
          ? widget.child
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: widget.child,
            ),
    ),
  );
}

class _AccessibleAction extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool childHandlesInput;
  const _AccessibleAction({
    required this.child,
    required this.onTap,
    required this.childHandlesInput,
  });
  @override
  Widget build(BuildContext context) => onTap == null && !childHandlesInput
      ? child
      : FocusHighlight(
          onTap: childHandlesInput ? null : onTap,
          canRequestFocus: !childHandlesInput && onTap != null,
          child: child,
        );
}

/// Uses the current FlutterView and respects platform announcement support.
/// Status widgets also expose live regions for platforms preferring semantics.
class ScreenReaderAnnouncement {
  static Future<void> announce(
    String message, {
    BuildContext? context,
    Assertiveness assertiveness = Assertiveness.polite,
  }) async {
    if (context != null && !context.mounted) return;
    final view = context == null
        ? WidgetsBinding.instance.platformDispatcher.implicitView
        : View.maybeOf(context);
    final supported = context == null
        ? view?.platformDispatcher.accessibilityFeatures.supportsAnnounce ??
              false
        : MediaQuery.supportsAnnounceOf(context);
    if (view == null || !supported) return;
    await SemanticsService.sendAnnouncement(
      view,
      message,
      context == null ? TextDirection.ltr : Directionality.of(context),
      assertiveness: assertiveness,
    );
  }

  static void announceSuccess(String message, {BuildContext? context}) {
    unawaited(announce('成功：$message', context: context));
  }

  static void announceError(String message, {BuildContext? context}) {
    unawaited(
      announce(
        '错误：$message',
        context: context,
        assertiveness: Assertiveness.assertive,
      ),
    );
  }

  static void announceWarning(String message, {BuildContext? context}) {
    unawaited(
      announce(
        '提示：$message',
        context: context,
        assertiveness: Assertiveness.assertive,
      ),
    );
  }
}

class SemanticListItem extends StatelessWidget {
  final int index, total;
  final String label;
  final Widget child;
  final VoidCallback? onTap;
  final bool childHandlesInput;
  const SemanticListItem({
    super.key,
    required this.index,
    required this.total,
    required this.label,
    required this.child,
    this.onTap,
    this.childHandlesInput = false,
  });
  @override
  Widget build(BuildContext context) => SemanticCard(
    label: '${label.isEmpty ? '' : '$label，'}第${index + 1}项，共$total项',
    onTap: onTap,
    childHandlesInput: childHandlesInput,
    child: child,
  );
}

class SemanticSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? child;
  final bool childHandlesInput;
  const SemanticSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.child,
    this.childHandlesInput = false,
  });
  @override
  Widget build(BuildContext context) {
    final action = onChanged == null ? null : () => onChanged!(!value);
    final native = child == null;
    return MergeSemantics(
      child: Semantics(
        label: label.isEmpty ? null : label,
        value: value ? '已开启' : '已关闭',
        toggled: value,
        enabled: onChanged != null,
        onTap: action,
        child: _AccessibleAction(
          onTap: action,
          childHandlesInput: native || childHandlesInput,
          child: TouchTargetExpander(
            child: child ?? Switch(value: value, onChanged: onChanged),
          ),
        ),
      ),
    );
  }
}

class SemanticTab extends StatelessWidget {
  final String label;
  final int index, total;
  final bool selected, childHandlesInput, replaceNativeSemantics;
  final Widget child;
  final VoidCallback onTap;
  const SemanticTab({
    super.key,
    required this.label,
    required this.index,
    required this.total,
    required this.selected,
    required this.child,
    required this.onTap,
    this.childHandlesInput = false,
    this.replaceNativeSemantics = false,
  });
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      label: label,
      excludeSemantics: replaceNativeSemantics,
      hint: '第${index + 1}个标签，共$total个',
      selected: selected,
      button: true,
      onTap: onTap,
      child: TouchTargetExpander(
        child: _AccessibleAction(
          onTap: onTap,
          childHandlesInput: childHandlesInput,
          child: child,
        ),
      ),
    ),
  );
}
