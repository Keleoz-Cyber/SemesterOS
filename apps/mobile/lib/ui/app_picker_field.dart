import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'app_sheet.dart';
import 'campus_theme.dart';
import 'app_controls.dart';
import 'empty_scene.dart';

/// A single form value opens a touch-friendly sheet, rather than a desktop menu.
class AppPickerField<T> extends FormField<T> {
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final bool isExpanded;
  AppPickerField({
    super.key,
    super.initialValue,
    required this.items,
    this.onChanged,
    this.decoration = const InputDecoration(),
    this.isExpanded = true,
    super.validator,
  }) : super(
         builder: (field) {
           final widget = field.widget as AppPickerField<T>;
           final selected = widget.items
               .where((item) => item.value == field.value)
               .firstOrNull;
           Future<void> choose() async {
             FocusScope.of(field.context).unfocus();
             final result = await showAppSheet<_Picked<T>>(
               context: field.context,
               heightFactor: widget.items.length > 8 ? .7 : null,
               builder: (_) => _PickerSheet<T>(
                 title: widget.decoration.labelText ?? '请选择',
                 items: widget.items,
                 value: field.value,
               ),
             );
             if (result == null || !field.mounted) return;
             field.didChange(result.value);
             widget.onChanged?.call(result.value);
           }

           return Padding(
             padding: const EdgeInsets.only(top: 4, bottom: 12),
             child: Column(
               mainAxisSize: MainAxisSize.min,
               crossAxisAlignment: CrossAxisAlignment.stretch,
               children: [
                 if (widget.decoration.labelText != null)
                   Padding(
                     padding: const EdgeInsets.only(bottom: 8),
                     child: Text(
                       widget.decoration.labelText!,
                       style: FTheme.of(field.context).typography.body.sm,
                     ),
                   ),
                 FButton(
                   onPress: widget.onChanged == null ? null : choose,
                   variant: FButtonVariant.outline,
                   size: FButtonSizeVariant.lg,
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   suffix: const Icon(Icons.unfold_more_rounded, size: 20),
                   child: Flexible(
                     child: DefaultTextStyle.merge(
                       style: const TextStyle(
                         fontSize: 16,
                         fontWeight: FontWeight.w400,
                         color: CampusColors.ink,
                       ),
                       child:
                           selected?.child ??
                           Text(widget.decoration.hintText ?? '请选择'),
                     ),
                   ),
                 ),
                 if (field.errorText != null)
                   Padding(
                     padding: const EdgeInsets.only(top: 8),
                     child: Text(
                       field.errorText!,
                       style: TextStyle(
                         fontSize: 13,
                         color: Theme.of(field.context).colorScheme.error,
                       ),
                     ),
                   ),
               ],
             ),
           );
         },
       );

  @override
  FormFieldState<T> createState() => _AppPickerFieldState<T>();
}

class _AppPickerFieldState<T> extends FormFieldState<T> {
  @override
  void didUpdateWidget(covariant AppPickerField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
  }
}

class _Picked<T> {
  final T? value;
  const _Picked(this.value);
}

class _PickerSheet<T> extends StatefulWidget {
  final String title;
  final List<DropdownMenuItem<T>> items;
  final T? value;
  const _PickerSheet({required this.title, required this.items, this.value});
  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  String query = '';
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String label(Widget child) =>
      child is Text ? child.data ?? child.textSpan?.toPlainText() ?? '' : '';

  // A compact field may truncate its selected value; the chooser must show
  // enough information to distinguish long course names and arrangements.
  Widget fullLabel(Widget child) => child is Text
      ? Text.rich(
          child.textSpan ?? TextSpan(text: child.data),
          style: child.style,
          strutStyle: child.strutStyle,
          textAlign: child.textAlign,
          textDirection: child.textDirection,
          locale: child.locale,
          textScaler: child.textScaler,
          semanticsLabel: child.semanticsLabel,
          softWrap: true,
          overflow: TextOverflow.visible,
          textWidthBasis: child.textWidthBasis,
          textHeightBehavior: child.textHeightBehavior,
        )
      : child;
  @override
  Widget build(BuildContext context) {
    final filtered = widget.items
        .where(
          (item) =>
              query.isEmpty ||
              label(item.child).toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.sizeOf(context).height *
            (widget.items.length > 8 ? 1 : .7),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSheetHeading(title: widget.title),
          if (widget.items.length > 8)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppField(
                controller: search,
                decoration: const InputDecoration(
                  hintText: '搜索选项',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => query = value.trim()),
              ),
            ),
          if (query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '${filtered.length}项匹配',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              children: [
                if (filtered.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppEmptyScene(
                          kind: EmptySceneKind.search,
                          size: 88,
                        ),
                        const Text('没有匹配的选项'),
                        AppTextButton(
                          onPressed: () {
                            search.clear();
                            setState(() => query = '');
                          },
                          child: const Text('清除搜索'),
                        ),
                      ],
                    ),
                  ),
                for (final item in filtered)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: FItem.raw(
                      style: appRowStyle(),
                      enabled: item.enabled,
                      selected: item.value == widget.value,
                      onPress: () =>
                          Navigator.pop(context, _Picked<T>(item.value)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 28),
                          child: Row(
                            children: [
                              Expanded(
                                child: DefaultTextStyle.merge(
                                  overflow: TextOverflow.visible,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: item.value == widget.value
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    height: 1.4,
                                    color: !item.enabled
                                        ? CampusColors.muted.withValues(
                                            alpha: .5,
                                          )
                                        : CampusColors.ink,
                                  ),
                                  child: fullLabel(item.child),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                item.value == widget.value
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 20,
                                color: item.value == widget.value
                                    ? CampusColors.teal
                                    : CampusColors.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
