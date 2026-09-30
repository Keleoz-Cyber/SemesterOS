import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'campus_theme.dart';
import 'motion.dart';

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
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;
  final FButtonVariant variant;
  final IconAlignment iconAlignment;
  const AppButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
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
  }) : child = label,
       variant = FButtonVariant.primary;
  const AppButton.tonal({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
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
  });
  @override
  Widget build(BuildContext context) {
    final states = <WidgetState>{if (onPressed == null) WidgetState.disabled};
    final foreground = style?.foregroundColor?.resolve(states);
    final textStyle = style?.textStyle?.resolve(states);
    final minimum = style?.minimumSize?.resolve(states);
    final content = DefaultTextStyle.merge(
      style: (textStyle ?? const TextStyle()).copyWith(color: foreground),
      child: child,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: minimum?.height.clamp(48, 120) ?? 48,
      ),
      child: FButton(
        onPress: onPressed,
        variant: variant,
        size: FButtonSizeVariant.lg,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: style?.alignment == Alignment.centerLeft
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        prefix: iconAlignment == IconAlignment.start ? icon : null,
        suffix: iconAlignment == IconAlignment.end ? icon : null,
        child: Flexible(child: content),
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
  }) : super.base(variant: FButtonVariant.outline);
  const AppOutlineButton.icon({
    super.key,
    required super.onPressed,
    required Widget icon,
    required Widget label,
    super.style,
    super.iconAlignment,
  }) : super.base(variant: FButtonVariant.outline, child: label, icon: icon);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: super.build(context),
  );
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
  }) : super.base(variant: FButtonVariant.ghost);
  const AppTextButton.icon({
    super.key,
    required super.onPressed,
    required Widget icon,
    required Widget label,
    super.style,
    super.iconAlignment,
  }) : super.base(variant: FButtonVariant.ghost, child: label, icon: icon);
}

class AppIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;
  final ButtonStyle? style;
  final FButtonVariant variant;
  final double? iconSize;
  final Color? color;
  const AppIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.style,
    this.iconSize,
    this.color,
  }) : variant = FButtonVariant.ghost;
  const AppIconButton.filled({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.style,
    this.iconSize,
    this.color,
  }) : variant = FButtonVariant.primary;
  const AppIconButton.filledTonal({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.style,
    this.iconSize,
    this.color,
  }) : variant = FButtonVariant.secondary;
  const AppIconButton.outlined({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.style,
    this.iconSize,
    this.color,
  }) : variant = FButtonVariant.outline;
  @override
  Widget build(BuildContext context) {
    final button = FButton.icon(
      onPress: onPressed,
      variant: variant,
      size: FButtonSizeVariant.lg,
      semanticsLabel: tooltip,
      child: IconTheme.merge(
        data: IconThemeData(size: iconSize ?? 22, color: color),
        child: icon,
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class AppField extends StatelessWidget {
  final TextEditingController? controller;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final TextInputType? keyboardType;
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
      inputFormatters: inputFormatters,
      onTap: onTap,
      onSubmit: onSubmitted,
      counterBuilder: (_, _, _, _) => null,
      prefixBuilder: decoration.prefixIcon == null
          ? null
          : (_, _, _) => decoration.prefixIcon!,
      suffixBuilder: decoration.suffixIcon != null
          ? (_, _, _) =>
                readOnly &&
                    onTap != null &&
                    decoration.suffixIcon is AppIconButton
                ? ExcludeSemantics(
                    child: IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: (decoration.suffixIcon as AppIconButton).icon,
                      ),
                    ),
                  )
                : decoration.suffixIcon!
          : decoration.suffixText != null
          ? (_, _, _) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(decoration.suffixText!),
            )
          : null,
    ),
  );
}

class AppFormField extends FormField<String> {
  final TextEditingController? controller;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final TextInputType? keyboardType;
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

Widget? _rowLabel(Widget? title, Widget? subtitle) {
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
            style: const TextStyle(fontSize: 14, color: CampusColors.muted),
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
                Expanded(child: _rowLabel(title, subtitle) ?? const SizedBox()),
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

class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const AppSwitch({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) =>
      FSwitch(value: value, onChange: onChanged, enabled: onChanged != null);
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
    child: MergeSemantics(
      child: Semantics(
        toggled: value,
        enabled: onChanged != null,
        child: FTappable.static(
          onPress: onChanged == null ? null : () => onChanged!(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(child: _rowLabel(title, subtitle) ?? const SizedBox()),
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
  Widget build(BuildContext context) => FItem.raw(
    selected: selected,
    enabled: enabled,
    onPress: enabled ? onTap : null,
    style: const FItemStyleDelta.delta(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    child: Padding(
      padding:
          contentPadding ??
          EdgeInsets.symmetric(
            vertical: minVerticalPadding ?? (dense ? 4 : 8),
            horizontal: 2,
          ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: [
            if (leading != null) ...[
              IconTheme.merge(
                data: const IconThemeData(
                  size: 22,
                  color: CampusColors.primary,
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: CampusColors.ink,
                      ),
                      overflow: TextOverflow.visible,
                      softWrap: true,
                      child: title!,
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    DefaultTextStyle.merge(
                      style: const TextStyle(
                        fontSize: 14,
                        color: CampusColors.muted,
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
      AppTile(
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
      Builder(
        builder: (context) => open
            ? Padding(
                padding:
                    widget.childrenPadding ??
                    const EdgeInsets.only(top: 8, bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.children,
                ),
              )
            : widget.maintainState
            ? Offstage(child: Column(children: widget.children))
            : const SizedBox.shrink(),
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
          if (icon != null)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: icon!),
          if (title != null)
            DefaultTextStyle.merge(
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: CampusColors.ink,
              ),
              child: title!,
            ),
          if (content != null)
            Flexible(
              child: Padding(
                padding:
                    contentPadding ?? const EdgeInsets.symmetric(vertical: 20),
                child: content!,
              ),
            ),
          if (actions != null)
            OverflowBar(
              spacing: 8,
              overflowSpacing: 8,
              alignment: MainAxisAlignment.end,
              children: actions!,
            ),
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
