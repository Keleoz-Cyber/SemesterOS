import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'app_sheet.dart';
import 'campus_theme.dart';

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
  String label(Widget child) => child is Text ? child.data ?? '' : '';
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
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Text(
              widget.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          if (widget.items.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: FTextField(
                label: const Text('搜索'),
                hint: '输入名称筛选',
                control: FTextFieldControl.managed(
                  onChange: (value) =>
                      setState(() => query = value.text.trim()),
                ),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              children: [
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('没有匹配的选项'),
                  ),
                for (final item in filtered)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: FItem.raw(
                      enabled: item.enabled,
                      selected: item.value == widget.value,
                      onPress: () =>
                          Navigator.pop(context, _Picked<T>(item.value)),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 28),
                        child: Row(
                          children: [
                            Expanded(
                              child: DefaultTextStyle.merge(
                                overflow: TextOverflow.visible,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.4,
                                  color: !item.enabled
                                      ? CampusColors.muted.withValues(alpha: .5)
                                      : CampusColors.ink,
                                ),
                                child: item.child,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
