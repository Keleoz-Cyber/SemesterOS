import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'motion.dart';

/// A nullable choice: the same option can be pressed again to clear it.
/// The moving surface shares fixed slots, so changing selection never reflows
/// the field or delays the caller's value update.
class AppOptionalChoiceStrip<T> extends StatefulWidget {
  final T? value;
  final Map<T, String> options;
  final Map<T, IconData> icons;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  const AppOptionalChoiceStrip({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icons = const {},
    this.enabled = true,
  });

  @override
  State<AppOptionalChoiceStrip<T>> createState() =>
      _AppOptionalChoiceStripState<T>();
}

class _AppOptionalChoiceStripState<T> extends State<AppOptionalChoiceStrip<T>> {
  int _lastSelected = 0;

  @override
  void initState() {
    super.initState();
    _rememberSelection();
  }

  @override
  void didUpdateWidget(covariant AppOptionalChoiceStrip<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rememberSelection();
  }

  void _rememberSelection() {
    final index = widget.options.keys.toList().indexWhere(
      (option) => option == widget.value,
    );
    if (index >= 0) _lastSelected = index;
    _lastSelected = _lastSelected.clamp(
      0,
      math.max(0, widget.options.length - 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) return const SizedBox.shrink();
    final entries = widget.options.entries.toList();
    final selected = entries.any((entry) => entry.key == widget.value);
    final scheme = Theme.of(context).colorScheme;
    final textStyle =
        (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.25,
        );
    final reduced = AppMotion.reduced(context);
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final feedback = AppMotion.feedback(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Both slots use the tallest label at the current system font scale.
        // This lets long labels wrap at large text without moving on selection.
        var naturalWidth = 0.0;
        for (final entry in entries) {
          final painter = TextPainter(
            text: TextSpan(text: entry.value, style: textStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          naturalWidth = math.max(
            naturalWidth,
            painter.width + (widget.icons.containsKey(entry.key) ? 28 : 0) + 24,
          );
          painter.dispose();
        }
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : naturalWidth * entries.length + 8;
        final slotWidth = math.max(1.0, (width - 8) / entries.length);
        final vertical = slotWidth < naturalWidth;
        var height = 48.0;
        for (final entry in entries) {
          final painter =
              TextPainter(
                text: TextSpan(text: entry.value, style: textStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(
                maxWidth: math.max(
                  1.0,
                  slotWidth -
                      24 -
                      (!vertical && widget.icons.containsKey(entry.key)
                          ? 28
                          : 0),
                ),
              );
          height = math.max(
            height,
            painter.height +
                24 +
                (vertical && widget.icons.containsKey(entry.key) ? 28 : 0),
          );
          painter.dispose();
        }

        return SizedBox(
          width: width,
          height: height + 8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        // Reset only on a system motion preference change,
                        // so an interrupted transition lands immediately.
                        key: ValueKey('choice-strip-opacity-$reduced'),
                        opacity: selected ? (widget.enabled ? 1 : .5) : 0,
                        duration: feedback,
                        child: AnimatedAlign(
                          key: ValueKey('choice-strip-position-$reduced'),
                          alignment: AlignmentDirectional(
                            entries.length == 1
                                ? 0
                                : -1 + 2 * _lastSelected / (entries.length - 1),
                            0,
                          ),
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          child: FractionallySizedBox(
                            widthFactor: 1 / entries.length,
                            heightFactor: 1,
                            child: DecoratedBox(
                              key: const Key('choice-strip-surface'),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: scheme.primary.withValues(alpha: .18),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: scheme.onSurface.withValues(
                                      alpha: .05,
                                    ),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final entry in entries)
                        Expanded(
                          child: FButton.raw(
                            selected: widget.value == entry.key,
                            semanticsLabel: entry.value,
                            variant: FButtonVariant.ghost,
                            style: FButtonStyleDelta.delta(
                              decoration: FVariantsDelta.delta([
                                FVariantOperation.all(
                                  DecorationDelta.boxDelta(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(14),
                                    border: const Border.fromBorderSide(
                                      BorderSide.none,
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                            onPress: widget.enabled
                                ? () {
                                    HapticFeedback.selectionClick();
                                    widget.onChanged(
                                      widget.value == entry.key
                                          ? null
                                          : entry.key,
                                    );
                                  }
                                : null,
                            child: Builder(
                              builder: (context) {
                                final variants = FButtonData.of(
                                  context,
                                ).variants;
                                final pressed = variants.contains(
                                  FTappableVariant.pressed,
                                );
                                final chosen = widget.value == entry.key;
                                final color = !widget.enabled
                                    ? Theme.of(context).disabledColor
                                    : chosen
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurfaceVariant;
                                return AnimatedContainer(
                                  key: ValueKey('choice-strip-press-$reduced'),
                                  duration: feedback,
                                  height: height,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: pressed
                                        ? scheme.primary.withValues(alpha: .08)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: AnimatedScale(
                                    key: ValueKey(
                                      'choice-strip-scale-$reduced',
                                    ),
                                    scale: pressed ? .97 : 1,
                                    duration: feedback,
                                    curve: Curves.easeOutCubic,
                                    child: TweenAnimationBuilder<Color?>(
                                      key: ValueKey(
                                        'choice-strip-color-$reduced',
                                      ),
                                      tween: ColorTween(end: color),
                                      duration: feedback,
                                      builder: (context, color, _) {
                                        final children = <Widget>[
                                          if (widget.icons[entry.key]
                                              case final icon?) ...[
                                            ExcludeSemantics(
                                              child: Icon(
                                                icon,
                                                size: 20,
                                                color: color,
                                              ),
                                            ),
                                            SizedBox(
                                              width: vertical ? 0 : 8,
                                              height: vertical ? 8 : 0,
                                            ),
                                          ],
                                          Flexible(
                                            child: Text(
                                              entry.value,
                                              textAlign: TextAlign.center,
                                              style: textStyle.copyWith(
                                                color: color,
                                              ),
                                            ),
                                          ),
                                        ];
                                        return vertical
                                            ? Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: children,
                                              )
                                            : Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: children,
                                              );
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
