import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'app_controls.dart';
import 'app_sheet.dart';
import 'motion.dart';

/// A readable summary for week/period selections, without input syntax.
String formatNumberSelection(Iterable<int> values, {required String unit}) {
  final numbers = values.toSet().toList()..sort();
  if (numbers.isEmpty) return '选择${unit == '周' ? '周次' : '节次'}';
  if (unit == '周' &&
      numbers.length > 2 &&
      List.generate(
        numbers.length - 1,
        (i) => i,
      ).every((i) => numbers[i + 1] - numbers[i] == 2)) {
    return '第${numbers.first}–${numbers.last}周（${numbers.first.isOdd ? '单' : '双'}周）';
  }
  final ranges = <String>[];
  var first = numbers.first, last = first;
  for (final number in numbers.skip(1)) {
    if (number == last + 1) {
      last = number;
    } else {
      ranges.add(first == last ? '$first' : '$first–$last');
      first = last = number;
    }
  }
  ranges.add(first == last ? '$first' : '$first–$last');
  return '第${ranges.join('、')}$unit';
}

/// Weeks/periods open one touch-friendly grid. Only confirmation commits edits.
class AppNumberPickerField extends StatelessWidget {
  const AppNumberPickerField({
    super.key,
    required this.label,
    required this.unit,
    required this.values,
    required this.options,
    required this.onChanged,
    this.weekShortcuts = false,
    this.enabled = true,
    this.description,
    this.errorText,
  });

  final String label, unit;
  final List<int> values, options;
  final ValueChanged<List<int>> onChanged;
  final bool weekShortcuts, enabled;
  final String? description, errorText;

  Future<void> _choose(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final result = await showAppSheet<List<int>>(
      context: context,
      heightFactor: .78,
      builder: (_) => _NumberSelectionSheet(
        label: label,
        unit: unit,
        values: values,
        options: options,
        weekShortcuts: weekShortcuts,
      ),
    );
    if (result != null && context.mounted) onChanged(result);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(label, style: FTheme.of(context).typography.body.sm),
        ),
        Semantics(
          label: '选择$label',
          value: formatNumberSelection(values, unit: unit),
          button: true,
          enabled: enabled && options.isNotEmpty,
          onTap: enabled && options.isNotEmpty ? () => _choose(context) : null,
          child: ExcludeSemantics(
            child: FButton(
              onPress: enabled && options.isNotEmpty
                  ? () => _choose(context)
                  : null,
              variant: FButtonVariant.outline,
              size: FButtonSizeVariant.lg,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              suffix: const Icon(Icons.chevron_right_rounded, size: 20),
              child: Flexible(
                child: Text(
                  formatNumberSelection(values, unit: unit),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (description?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              description!,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}

class _NumberSelectionSheet extends StatefulWidget {
  const _NumberSelectionSheet({
    required this.label,
    required this.unit,
    required this.values,
    required this.options,
    required this.weekShortcuts,
  });
  final String label, unit;
  final List<int> values, options;
  final bool weekShortcuts;

  @override
  State<_NumberSelectionSheet> createState() => _NumberSelectionSheetState();
}

class _NumberSelectionSheetState extends State<_NumberSelectionSheet> {
  late final selected = widget.values.toSet();
  late final options = widget.options.toSet().toList()..sort();
  bool bulkFeedback = false;

  void selectWhere(bool Function(int) predicate) => setState(() {
    bulkFeedback = true;
    selected
      ..clear()
      ..addAll(options.where(predicate));
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppSheetHeading(title: '选择${widget.label}'),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppTextButton(
                    onPressed: () => selectWhere((_) => true),
                    child: const Text('全选'),
                  ),
                  if (widget.weekShortcuts) ...[
                    AppTextButton(
                      onPressed: () => selectWhere((n) => n.isOdd),
                      child: const Text('单周'),
                    ),
                    AppTextButton(
                      onPressed: () => selectWhere((n) => n.isEven),
                      child: const Text('双周'),
                    ),
                  ],
                  AppTextButton(
                    onPressed: () => selectWhere((_) => false),
                    child: const Text('清空'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                  final slot = math.max(56.0, 32 + 24 * scale);
                  final columns = ((constraints.maxWidth + 8) / (slot + 8))
                      .floor()
                      .clamp(1, 7);
                  final width =
                      (constraints.maxWidth - (columns - 1) * 8) / columns;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final value in options)
                        SizedBox(
                          width: width,
                          child: Semantics(
                            label: '第$value${widget.unit}',
                            button: true,
                            selected: selected.contains(value),
                            onTap: () => toggle(value),
                            child: ExcludeSemantics(
                              child: _NumberChoice(
                                value: value,
                                selected: selected.contains(value),
                                wave: bulkFeedback
                                    ? options.indexOf(value) % columns
                                    : 0,
                                onTap: () => toggle(value),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                selected.isEmpty
                    ? '选择${widget.label}'
                    : formatNumberSelection(selected, unit: widget.unit),
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            AppButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected.toList()..sort()),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    ],
  );

  void toggle(int value) => setState(() {
    bulkFeedback = false;
    if (!selected.remove(value)) selected.add(value);
  });
}

/// All values change immediately; a brief column rhythm communicates a bulk
/// selection without serializing taps or blocking the confirm action.
class _NumberChoice extends StatelessWidget {
  final int value, wave;
  final bool selected;
  final VoidCallback onTap;
  const _NumberChoice({
    required this.value,
    required this.selected,
    required this.wave,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduced = !AppMotion.allowed(context);
    return FButton.raw(
      onPress: onTap,
      selected: selected,
      style: FButtonStyleDelta.delta(
        decoration: FVariantsDelta.delta([
          FVariantOperation.all(
            DecorationDelta.boxDelta(
              color: Colors.transparent,
              border: const Border.fromBorderSide(BorderSide.none),
            ),
          ),
        ]),
      ),
      child: Builder(
        builder: (context) {
          final pressed = FButtonData.of(
            context,
          ).variants.contains(FTappableVariant.pressed);
          return TweenAnimationBuilder<double>(
            key: ValueKey(reduced),
            tween: Tween(end: selected ? 1 : 0),
            duration: reduced
                ? Duration.zero
                : Duration(milliseconds: 160 + wave * 12),
            curve: Curves.easeOutCubic,
            builder: (context, amount, _) => Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              decoration: BoxDecoration(
                color: Color.lerp(
                  scheme.surface,
                  scheme.primaryContainer,
                  pressed ? .75 : amount,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Color.lerp(
                    scheme.outlineVariant,
                    scheme.primary.withValues(alpha: .45),
                    amount,
                  )!,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '$value',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color.lerp(
                          scheme.onSurface,
                          scheme.primary,
                          amount,
                        ),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Opacity(
                      opacity: amount,
                      child: Icon(
                        Icons.check_rounded,
                        size: 11,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
