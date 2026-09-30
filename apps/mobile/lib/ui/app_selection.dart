import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'motion.dart';

/// One actual Forui tab system across list states, ranges and view modes.
class AppSegmentedControl<T> extends StatelessWidget {
  final T value;
  final ValueChanged<T> onChanged;
  final Map<T, String> options;
  final bool enabled;
  final Set<T> disabledValues;
  const AppSegmentedControl({
    super.key,
    required this.value,
    required this.onChanged,
    required this.options,
    this.enabled = true,
    this.disabledValues = const {},
  });
  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final entries = options.entries.toList();
    final index = entries.indexWhere((entry) => entry.key == value);
    var slot = 48.0;
    for (final entry in entries) {
      final painter = TextPainter(
        text: TextSpan(
          text: entry.value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      slot = math.max(slot, painter.width + 32);
      painter.dispose();
    }
    return LayoutBuilder(
      builder: (context, constraints) => IgnorePointer(
        ignoring: !enabled,
        child: FTabs(
          control: FTabControl.lifted(
            index: index < 0 ? 0 : index,
            motion: FTabMotion(duration: AppMotion.change(context)),
            onChange: (next) {
              if (enabled && !disabledValues.contains(entries[next].key)) {
                onChanged(entries[next].key);
              }
            },
          ),
          scrollable:
              !constraints.hasBoundedWidth ||
              slot * entries.length + 8 > constraints.maxWidth,
          style: const FTabsStyleDelta.delta(minHeight: 48, spacing: 0),
          children: [
            for (final entry in entries)
              FTabEntry(
                label: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 16),
                  child: Padding(
                    padding: EdgeInsets.zero,
                    child: Text(
                      entry.value,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: disabledValues.contains(entry.key)
                            ? Theme.of(context).disabledColor
                            : null,
                      ),
                    ),
                  ),
                ),
                child: const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}
