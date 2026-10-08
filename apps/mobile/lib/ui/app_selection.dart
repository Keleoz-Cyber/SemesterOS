import 'package:flutter/material.dart';
import 'v2/motion/spring_segmented.dart';

/// Stable API: disabled/selected semantics remain with the spring control.
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
    return SpringSegmented<T>(
      segments: [for (final entry in options.entries) (entry.key, entry.value)],
      selected: value,
      enabled: enabled,
      disabledValues: disabledValues,
      onChanged: onChanged,
    );
  }
}
