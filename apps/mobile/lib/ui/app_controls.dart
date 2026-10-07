import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'motion.dart';
import 'accessibility.dart';
import 'performance_widgets.dart';
import 'campus_theme.dart';

/// A list row owns its spacing. Forui still supplies focus and pressed states.
FItemStyleDelta appRowStyle({
  Color? background,
  Color? selectedBackground,
  ShapeBorder? shape,
}) {
  final fill = background ?? Colors.transparent;
  final selected = selectedBackground ?? CampusColors.blueSoft;
  final border =
      shape ??
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      );
  return FItemStyleDelta.delta(
    shape: border,
    padding: const EdgeInsetsGeometryDelta.value(EdgeInsets.zero),
    rawContentStyle: const FRawItemContentStyleDelta.delta(
      padding: EdgeInsetsGeometryDelta.value(EdgeInsets.zero),
    ),
    backgroundColor: FVariantsValueDelta.delta([
      FVariantValueDeltaOperation.all(fill),
    ]),
    contentDecoration: FVariantsDelta.delta([
      FVariantOperation.all(
        DecorationDelta.shapeDelta(shape: border, color: fill),
      ),
      FVariantOperation.exact({
        FTappableVariant.pressed,
        FTappableVariant.hovered,
        FTappableVariant.selected,
      }, DecorationDelta.shapeDelta(color: selected)),
    ]),
  );
}

FButtonStyleDelta _buttonVisualStyle(BuildContext context, ButtonStyle? style) {
  final touch = FTappableStyleDelta.delta(
    motion: AppMotion.allowed(context)
        ? const FTappableMotion(
            bounceDownDuration: Duration(milliseconds: 85),
            bounceUpDuration: Duration(milliseconds: 170),
            bounceUpCurve: Curves.easeOutCubic,
            bounceFloor: 1.5,
          )
        : FTappableMotion.none,
  );
  final background = style?.backgroundColor?.resolve({});
  final padding = style?.padding?.resolve({});
  final shape = style?.shape?.resolve({});
  final side = style?.side?.resolve({});
  final content = padding == null
      ? null
      : FButtonContentStyleDelta.delta(
          padding: EdgeInsetsGeometryDelta.value(padding),
        );
  if (background == null) {
    return FButtonStyleDelta.delta(
      tappableStyle: touch,
      contentStyle: content,
      decoration: shape == null
          ? null
          : FVariantsDelta.delta([
              FVariantOperation.base(
                DecorationDelta.shapeDelta(shape: shape.copyWith(side: side)),
              ),
            ]),
    );
  }
  final pressed = Color.alphaBlend(
    Theme.of(context).colorScheme.onSurface.withValues(alpha: .08),
    background,
  );
  return FButtonStyleDelta.delta(
    tappableStyle: touch,
    contentStyle: content,
    decoration: FVariantsDelta.delta([
      FVariantOperation.base(
        shape == null
            ? DecorationDelta.boxDelta(color: background)
            : DecorationDelta.shapeDelta(
                color: background,
                shape: shape.copyWith(side: side),
              ),
      ),
      FVariantOperation.exact({
        FTappableVariant.pressed,
        FTappableVariant.hovered,
      }, DecorationDelta.boxDelta(color: pressed)),
      FVariantOperation.exact(
        {FTappableVariant.selected},
        DecorationDelta.boxDelta(
          color:
              style?.backgroundColor?.resolve({WidgetState.selected}) ??
              background,
        ),
      ),
      FVariantOperation.exact(
        {FTappableVariant.disabled},
        DecorationDelta.boxDelta(
          color:
              style?.backgroundColor?.resolve({WidgetState.disabled}) ??
              background.withValues(alpha: .5),
        ),
      ),
    ]),
  );
}

// Public app controls deliberately keep simple Flutter-style callbacks. Their
// rendering, interaction, focus and disabled states share the Forui system.
class AppButton extends StatelessWidget {
  static ButtonStyle styleFrom({
    EdgeInsetsGeometry? padding,
    AlignmentGeometry? alignment,
    Size? minimumSize,
    Color? backgroundColor,
    Color? foregroundColor,
    TextStyle? textStyle,
    OutlinedBorder? shape,
    BorderSide? side,
  }) => FilledButton.styleFrom(
    padding: padding,
    alignment: alignment,
    minimumSize: minimumSize,
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    textStyle: textStyle,
    shape: shape,
    side: side,
  );
  final FutureOr<void> Function()? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;
  final FButtonVariant variant;
  final IconAlignment iconAlignment;
  final bool guardAsync;
  const AppButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.guardAsync = true,
  }) : icon = null,
       variant = FButtonVariant.primary,
       iconAlignment = IconAlignment.start;
  const AppButton.icon({
    super.key,
    required this.onPressed,
    required this.icon,
    required Widget label,
    this.style,
    this.iconAlignment = IconAlignment.start,
    this.guardAsync = true,
  }) : child = label,
       variant = FButtonVariant.primary;
  const AppButton.tonal({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.guardAsync = true,
  }) : icon = null,
       variant = FButtonVariant.secondary,
       iconAlignment = IconAlignment.start;
  const AppButton.base({
    super.key,
    required this.onPressed,
    required this.child,
    required this.variant,
    this.icon,
    this.style,
    this.iconAlignment = IconAlignment.start,
    this.guardAsync = true,
  });
  @override
  Widget build(BuildContext context) {
    final states = <WidgetState>{if (onPressed == null) WidgetState.disabled};
    final foreground = style?.foregroundColor?.resolve(states);
    final textStyle = style?.textStyle?.resolve(states);
    final minimum = style?.minimumSize?.resolve(states);
    final styledIcon = icon == null
        ? null
        : IconTheme.merge(
            data: IconThemeData(color: foreground),
            child: icon!,
          );
    final content = DefaultTextStyle.merge(
      style: (textStyle ?? const TextStyle()).copyWith(color: foreground),
      child: child,
    );
    return DebouncedButton(
      onPressed: onPressed,
      guardAsync: guardAsync,
      child: content,
      builder: (context, onPress, processing) => SemanticButton(
        label: '',
        hint: processing ? '正在处理，请稍候' : null,
        enabled: onPress != null,
        onPressed: onPress,
        childHandlesInput: true,
        child: TouchTargetExpander(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth:
                  minimum?.width
                      .clamp(0, MediaQuery.sizeOf(context).width)
                      .toDouble() ??
                  0,
              minHeight: minimum?.height.clamp(48, 120).toDouble() ?? 48,
            ),
            child: FButton(
              style: _buttonVisualStyle(context, style),
              onPress: onPress,
              variant: variant,
              size: FButtonSizeVariant.lg,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: style?.alignment == Alignment.centerLeft
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              prefix: iconAlignment == IconAlignment.start ? styledIcon : null,
              suffix: iconAlignment == IconAlignment.end ? styledIcon : null,
              child: Flexible(
                child: _AsyncButtonFace(processing: processing, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppOutlineButton extends AppButton {
  const AppOutlineButton({
    super.key,
    required super.onPressed,
    required super.child,
    super.style,
    super.guardAsync,
  }) : super.base(variant: FButtonVariant.outline);
  const AppOutlineButton.icon({
    super.key,
    required super.onPressed,
    required Widget icon,
    required Widget label,
    super.style,
    super.iconAlignment,
    super.guardAsync,
  }) : super.base(variant: FButtonVariant.outline, child: label, icon: icon);
}

class AppTextButton extends AppButton {
  static ButtonStyle styleFrom({
    EdgeInsetsGeometry? padding,
    AlignmentGeometry? alignment,
    Size? minimumSize,
    Color? backgroundColor,
    Color? foregroundColor,
    TextStyle? textStyle,
    OutlinedBorder? shape,
  }) => TextButton.styleFrom(
    padding: padding,
    alignment: alignment,
    minimumSize: minimumSize,
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    textStyle: textStyle,
    shape: shape,
  );
  const AppTextButton({
    super.key,
    required super.onPressed,
    required super.child,
    super.style,
    super.guardAsync,
  }) : super.base(variant: FButtonVariant.ghost);
  const AppTextButton.icon({
    super.key,
    required super.onPressed,
    required Widget icon,
    required Widget label,
    super.style,
    super.iconAlignment,
    super.guardAsync,
  }) : super.base(variant: FButtonVariant.ghost, child: label, icon: icon);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quiet = ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? scheme.onSurfaceVariant.withValues(alpha: .5)
            : scheme.onSurface,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => Colors.transparent,
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.25),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide.none,
        ),
      ),
    ).merge(style);
    return AppButton.base(
      onPressed: onPressed,
      icon: icon,
      iconAlignment: iconAlignment,
      guardAsync: guardAsync,
      variant: FButtonVariant.ghost,
      style: quiet,
      child: child,
    );
  }
}

class AppIconButton extends StatelessWidget {
  final FutureOr<void> Function()? onPressed;
  final Widget icon;
  final String? tooltip;
  final ButtonStyle? style;
  final FButtonVariant variant;
  final double? iconSize;
  final Color? color;
  final bool guardAsync;
  const AppIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.style,
    this.iconSize,
    this.color,
    this.guardAsync = true,
  }) : variant = FButtonVariant.ghost;
  const AppIconButton.filled({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.style,
    this.iconSize,
    this.color,
    this.guardAsync = true,
  }) : variant = FButtonVariant.primary;
  const AppIconButton.filledTonal({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.style,
    this.iconSize,
    this.color,
    this.guardAsync = true,
  }) : variant = FButtonVariant.secondary;
  const AppIconButton.outlined({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.style,
    this.iconSize,
    this.color,
    this.guardAsync = true,
  }) : variant = FButtonVariant.outline;
  @override
  Widget build(BuildContext context) {
    final button = DebouncedButton(
      onPressed: onPressed,
      guardAsync: guardAsync,
      child: icon,
      builder: (context, onPress, processing) => SemanticButton(
        label: '',
        hint: processing ? '正在处理，请稍候' : null,
        onPressed: onPress,
        enabled: onPress != null,
        childHandlesInput: true,
        child: TouchTargetExpander(
          child: FButton.icon(
            style: _buttonVisualStyle(context, style),
            onPress: onPress,
            variant: variant,
            size: FButtonSizeVariant.lg,
            semanticsLabel: tooltip,
            child: IconTheme.merge(
              data: IconThemeData(
                size: iconSize ?? 22,
                color:
                    color ??
                    style?.foregroundColor?.resolve({
                      if (onPress == null) WidgetState.disabled,
                    }) ??
                    (variant == FButtonVariant.ghost
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : null),
              ),
              child: _AsyncButtonFace(processing: processing, child: icon),
            ),
          ),
        ),
      ),
    );
    return tooltip == null
        ? button
        : Tooltip(message: tooltip!, excludeFromSemantics: true, child: button);
  }
}

class _AsyncButtonFace extends StatelessWidget {
  final bool processing;
  final Widget child;
  const _AsyncButtonFace({required this.processing, required this.child});
  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    clipBehavior: Clip.none,
    children: [
      AnimatedOpacity(
        opacity: processing && ModalRoute.isCurrentOf(context) != false ? 0 : 1,
        duration: AppMotion.feedback(context),
        alwaysIncludeSemantics: true,
        child: child,
      ),
      if (processing && ModalRoute.isCurrentOf(context) != false)
        Positioned.fill(
          child: Center(
            child: ExcludeSemantics(
              child:
                  !AppMotion.allowed(context) ||
                      ModalRoute.isCurrentOf(context) == false
                  ? Icon(
                      Icons.hourglass_top_rounded,
                      size: 18,
                      color: DefaultTextStyle.of(context).style.color,
                    )
                  : SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DefaultTextStyle.of(context).style.color,
                      ),
                    ),
            ),
          ),
        ),
    ],
  );
}

class AppField extends StatelessWidget {
  final TextEditingController? controller;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? minLines, maxLines, maxLength;
  final bool enabled, readOnly, obscureText, autocorrect, autofocus;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  const AppField({
    super.key,
    this.controller,
    this.decoration = const InputDecoration(),
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.keyboardType,
    this.textInputAction,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.autocorrect = true,
    this.autofocus = false,
    this.autofillHints,
    this.focusNode,
    this.inputFormatters,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: FTextField(
      control: FTextFieldControl.managed(
        controller: controller,
        onChange: (value) => onChanged?.call(value.text),
      ),
      label:
          decoration.label ??
          (decoration.labelText == null ? null : Text(decoration.labelText!)),
      hint: decoration.hintText,
      description: decoration.helperText == null
          ? null
          : Text(decoration.helperText!),
      error: decoration.errorText == null ? null : Text(decoration.errorText!),
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
      autocorrect: autocorrect,
      autofocus: autofocus,
      autofillHints: autofillHints,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onTap: onTap,
      onSubmit: onSubmitted,
      counterBuilder: (_, _, _, _) => null,
      prefixBuilder: decoration.prefixIcon == null
          ? null
          : (context, style, variants) => _fieldAdornment(
              context,
              decoration.prefixIcon!,
              contentPadding: style.contentPadding,
              iconTheme: style.iconStyle.resolve(variants).copyWith(size: 20),
              leading: true,
            ),
      suffixBuilder: decoration.suffixIcon != null
          ? (context, style, variants) {
              final passive =
                  readOnly &&
                  onTap != null &&
                  decoration.suffixIcon is AppIconButton;
              return _fieldAdornment(
                context,
                passive
                    ? (decoration.suffixIcon as AppIconButton).icon
                    : decoration.suffixIcon!,
                contentPadding: style.contentPadding,
                iconTheme: style.iconStyle.resolve(variants).copyWith(size: 20),
                leading: false,
                passive: passive,
              );
            }
          : decoration.suffixText != null
          ? (context, style, variants) => Padding(
              padding: EdgeInsetsDirectional.only(
                start: 4,
                end: Directionality.of(context) == TextDirection.ltr
                    ? style.contentPadding.resolve(TextDirection.ltr).right
                    : style.contentPadding.resolve(TextDirection.rtl).left,
              ),
              child: Text(
                decoration.suffixText!,
                style: style.contentTextStyle.resolve(variants),
              ),
            )
          : null,
    ),
  );
}

/// InputDecorator supplies the final 4dp gap to the editable text. Static
/// adornments restore the field's outer inset; action icons keep their hit area.
Widget _fieldAdornment(
  BuildContext context,
  Widget child, {
  required EdgeInsetsGeometry contentPadding,
  required IconThemeData iconTheme,
  required bool leading,
  bool passive = false,
}) {
  if (child is AppIconButton && !passive) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
      child: child,
    );
  }
  final padding = contentPadding.resolve(Directionality.of(context));
  final direction = Directionality.of(context);
  final start = direction == TextDirection.ltr ? padding.left : padding.right;
  final end = direction == TextDirection.ltr ? padding.right : padding.left;
  final adornment = IconTheme.merge(data: iconTheme, child: child);
  return Padding(
    padding: EdgeInsetsDirectional.only(
      start: leading ? start : 4,
      end: leading ? 4 : end,
    ),
    child: child is Icon || passive
        ? ExcludeSemantics(child: IgnorePointer(child: adornment))
        : adornment,
  );
}

/// Keep validation beside its field and bring the first problem into view.
/// This does not focus a different field or open the keyboard unexpectedly.
bool validateAppForm(GlobalKey<FormState> key) {
  final form = key.currentState;
  if (form == null || form.validate()) return form != null;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final root = key.currentContext;
    if (root == null || !root.mounted || key.currentState != form) return;
    Element? first;
    void inspect(Element node) {
      if (first != null) return;
      if (node case StatefulElement(:final state)) {
        if (state is FormFieldState && state.hasError) {
          first = node;
          return;
        }
      }
      node.visitChildElements(inspect);
    }

    root.visitChildElements(inspect);
    final target = first;
    if (target != null && target.mounted) {
      Scrollable.ensureVisible(
        target,
        alignment: .16,
        duration: AppMotion.feedback(target),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
  });
  return false;
}

class AppFormField extends FormField<String> {
  final TextEditingController? controller;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final int? minLines, maxLines, maxLength;
  final bool readOnly, obscureText, autocorrect, autofocus;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  AppFormField({
    super.key,
    this.controller,
    String? initialValue,
    this.decoration = const InputDecoration(),
    this.onChanged,
    this.onTap,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    super.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.autocorrect = true,
    this.autofocus = false,
    this.autofillHints,
    this.focusNode,
    this.inputFormatters,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
  }) : super(
         initialValue: controller?.text ?? initialValue ?? '',
         builder: (state) {
           final field = state as _AppFormFieldState;
           final widget = state.widget as AppFormField;
           return AppField(
             controller: field.text,
             decoration: widget.decoration.copyWith(errorText: state.errorText),
             enabled: widget.enabled,
             readOnly: widget.readOnly,
             obscureText: widget.obscureText,
             autocorrect: widget.autocorrect,
             autofocus: widget.autofocus,
             autofillHints: widget.autofillHints,
             keyboardType: widget.keyboardType,
             textInputAction: widget.textInputAction,
             onSubmitted: widget.onSubmitted,
             focusNode: widget.focusNode,
             inputFormatters: widget.inputFormatters,
             minLines: widget.minLines,
             maxLines: widget.maxLines,
             maxLength: widget.maxLength,
             onTap: widget.onTap,
             onChanged: widget.onChanged,
           );
         },
       );
  @override
  FormFieldState<String> createState() => _AppFormFieldState();
}

class _AppFormFieldState extends FormFieldState<String> {
  TextEditingController? own;
  AppFormField get config => widget as AppFormField;
  TextEditingController get text => config.controller ?? own!;
  @override
  void initState() {
    super.initState();
    if (config.controller == null) {
      own = TextEditingController(text: widget.initialValue);
    }
    text.addListener(changed);
  }

  void changed() {
    if (value != text.text) didChange(text.text);
  }

  @override
  void didUpdateWidget(covariant AppFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != config.controller) {
      (oldWidget.controller ?? own)?.removeListener(changed);
      if (config.controller == null) own ??= TextEditingController(text: value);
      text.addListener(changed);
      setValue(text.text);
    }
  }

  @override
  void reset() {
    super.reset();
    text.text = widget.initialValue ?? '';
  }

  @override
  void dispose() {
    text.removeListener(changed);
    own?.dispose();
    super.dispose();
  }
}

Widget? _rowLabel(BuildContext context, Widget? title, Widget? subtitle) {
  if (title == null && subtitle == null) return null;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ?title,
      if (subtitle != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            child: subtitle,
          ),
        ),
    ],
  );
}

class AppCheckRow extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final Widget? title, subtitle;
  final EdgeInsetsGeometry? contentPadding;
  final ListTileControlAffinity controlAffinity;
  final Color? activeColor;
  const AppCheckRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.contentPadding,
    this.controlAffinity = ListTileControlAffinity.platform,
    this.activeColor,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: contentPadding ?? const EdgeInsets.symmetric(vertical: 8),
    child: MergeSemantics(
      child: Semantics(
        checked: value ?? false,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged!(!(value ?? false)),
        child: FTappable.static(
          onPress: onChanged == null
              ? null
              : () => onChanged!(!(value ?? false)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                if (controlAffinity != ListTileControlAffinity.trailing) ...[
                  ExcludeSemantics(
                    child: IgnorePointer(
                      child: FCheckbox(
                        value: value ?? false,
                        enabled: onChanged != null,
                        onChange: onChanged,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child:
                      _rowLabel(context, title, subtitle) ?? const SizedBox(),
                ),
                if (controlAffinity == ListTileControlAffinity.trailing) ...[
                  const SizedBox(width: 12),
                  ExcludeSemantics(
                    child: IgnorePointer(
                      child: FCheckbox(
                        value: value ?? false,
                        enabled: onChanged != null,
                        onChange: onChanged,
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
  );
}

class AppSwitchRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title, subtitle;
  final EdgeInsetsGeometry? contentPadding;
  const AppSwitchRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.contentPadding,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: contentPadding ?? const EdgeInsets.symmetric(vertical: 8),
    child: SemanticSwitch(
      label: '',
      value: value,
      onChanged: onChanged,
      childHandlesInput: true,
      child: FTappable.static(
        onPress: onChanged == null ? null : () => onChanged!(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(
                child: _rowLabel(context, title, subtitle) ?? const SizedBox(),
              ),
              const SizedBox(width: 12),
              ExcludeSemantics(
                child: IgnorePointer(
                  child: FSwitch(
                    value: value,
                    enabled: onChanged != null,
                    onChange: onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AppTile extends StatelessWidget {
  final Widget? title, subtitle, leading, trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final bool dense, selected, enabled;
  final double? minVerticalPadding;
  final Color? tileColor, selectedTileColor;
  final ShapeBorder? shape;
  const AppTile({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.contentPadding,
    this.dense = false,
    this.selected = false,
    this.enabled = true,
    this.minVerticalPadding,
    this.tileColor,
    this.selectedTileColor,
    this.shape,
  });
  @override
  Widget build(BuildContext context) => SemanticCard(
    label: '',
    onTap: enabled ? onTap : null,
    childHandlesInput: true,
    child: FItem.raw(
      selected: selected,
      enabled: enabled,
      onPress: enabled ? onTap : null,
      style: appRowStyle(
        background: tileColor,
        selectedBackground:
            selectedTileColor ?? Theme.of(context).colorScheme.primaryContainer,
        shape: shape,
      ),
      child: Padding(
        padding:
            contentPadding ??
            EdgeInsets.symmetric(
              vertical: minVerticalPadding ?? (dense ? 4 : 8),
              horizontal: 2,
            ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              if (leading != null) ...[
                IconTheme.merge(
                  data: IconThemeData(
                    size: 22,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: leading!,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      DefaultTextStyle.merge(
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.visible,
                        softWrap: true,
                        child: title!,
                      ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      DefaultTextStyle.merge(
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.visible,
                        softWrap: true,
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    ),
  );
}

class AppDisclosure extends StatefulWidget {
  final Widget title;
  final Widget? subtitle, leading;
  final List<Widget> children;
  final bool initiallyExpanded, maintainState, enabled;
  final EdgeInsetsGeometry? tilePadding, childrenPadding;
  final ValueChanged<bool>? onExpansionChanged;
  const AppDisclosure({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.children = const [],
    this.initiallyExpanded = false,
    this.maintainState = false,
    this.enabled = true,
    this.tilePadding,
    this.childrenPadding,
    this.onExpansionChanged,
  });
  @override
  State<AppDisclosure> createState() => _AppDisclosureState();
}

class _AppDisclosureState extends State<AppDisclosure> {
  late bool open = widget.initiallyExpanded;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        expanded: open,
        child: AppTile(
          title: widget.title,
          subtitle: widget.subtitle,
          leading: widget.leading,
          contentPadding: widget.tilePadding,
          trailing: AnimatedRotation(
            turns: open ? .5 : 0,
            duration: AppMotion.change(context),
            child: const Icon(Icons.expand_more_rounded, size: 20),
          ),
          onTap: widget.enabled
              ? () {
                  setState(() => open = !open);
                  widget.onExpansionChanged?.call(open);
                }
              : null,
        ),
      ),
      AppExpandRegion(
        visible: open,
        maintainState: widget.maintainState,
        child: Padding(
          padding:
              widget.childrenPadding ??
              const EdgeInsets.only(top: 8, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
        ),
      ),
    ],
  );
}

class AppDialog extends StatelessWidget {
  final Widget? title, content, icon;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? contentPadding;
  const AppDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.contentPadding,
    this.icon,
  });
  @override
  Widget build(BuildContext context) => FDialog(
    builder: (context, style) => Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null || icon != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (icon != null) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: IconTheme.merge(
                              data: IconThemeData(
                                size: 25,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              child: icon!,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (title != null)
                          Expanded(
                            child: DefaultTextStyle.merge(
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              child: title!,
                            ),
                          ),
                        if (actions == null)
                          AppIconButton(
                            tooltip: '关闭',
                            guardAsync: false,
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                      ],
                    ),
                  if (content != null)
                    Padding(
                      padding:
                          contentPadding ??
                          const EdgeInsets.symmetric(vertical: 20),
                      child: content!,
                    ),
                ],
              ),
            ),
          ),
          if (actions != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            LayoutBuilder(
              builder: (context, box) =>
                  box.maxWidth < 280 ||
                      MediaQuery.textScalerOf(context).scale(14) > 21
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < actions!.length; i++)
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                            child: actions![i],
                          ),
                      ],
                    )
                  : OverflowBar(
                      spacing: 12,
                      overflowSpacing: 8,
                      alignment: MainAxisAlignment.end,
                      children: actions!,
                    ),
            ),
          ],
        ],
      ),
    ),
  );
}

class AppFilterChip extends StatelessWidget {
  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
  });
  @override
  Widget build(BuildContext context) => FButton(
    variant: selected ? FButtonVariant.secondary : FButtonVariant.outline,
    selected: selected,
    onPress: onSelected == null ? null : () => onSelected!(!selected),
    prefix: selected ? const Icon(Icons.check_rounded, size: 16) : null,
    mainAxisSize: MainAxisSize.min,
    child: Flexible(child: label),
  );
}

class AppInputChip extends StatelessWidget {
  final Widget label;
  final VoidCallback? onDeleted;
  const AppInputChip({super.key, required this.label, this.onDeleted});
  @override
  Widget build(BuildContext context) => FButton(
    variant: FButtonVariant.secondary,
    onPress: onDeleted,
    mainAxisSize: MainAxisSize.min,
    suffix: const Icon(Icons.close_rounded, size: 16),
    child: Flexible(child: label),
  );
}
