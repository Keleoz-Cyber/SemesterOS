import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

import 'motion.dart';

/// A single draggable modal surface, with keyboard avoidance owned here.
///
/// Supply [heightFactor] for a bounded, flex-based page. Its builder receives
/// the actual available body size through MediaQuery, with consumed keyboard
/// insets removed. Without it, content wraps naturally and scrolls if needed.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double? heightFactor,
  bool showHandle = true,
  bool barrierDismissible = true,
  bool swipeDismissible = true,
}) {
  assert(heightFactor == null || (heightFactor > 0 && heightFactor <= 1));
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context).context,
  );
  return Navigator.of(context).push<T>(
    ModalSheetRoute<T>(
      barrierDismissible: barrierDismissible,
      swipeDismissible: swipeDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: AppMotion.sheet(context),
      transitionCurve: Curves.easeOutCubic,
      viewportBuilder: (context, child) {
        final media = MediaQuery.of(context);
        final side = math.max(0.0, (media.size.width - 720) / 2);
        return SheetViewport(
          padding: EdgeInsets.fromLTRB(
            math.max(side, media.padding.left),
            media.padding.top + 8,
            math.max(side, media.padding.right),
            media.viewInsets.bottom,
          ),
          child: child,
        );
      },
      builder: (context) => themes.wrap(
        _AppSheet(
          builder: builder,
          heightFactor: heightFactor,
          showHandle: showHandle,
        ),
      ),
    ),
  );
}

class _AppSheet extends StatelessWidget {
  const _AppSheet({
    required this.builder,
    required this.heightFactor,
    required this.showHandle,
  });

  final WidgetBuilder builder;
  final double? heightFactor;
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    final height = heightFactor == null
        ? null
        : MediaQuery.sizeOf(context).height * heightFactor!;
    return Sheet(
      decoration: MaterialSheetDecoration(
        size: SheetSize.fit,
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showHandle)
                ExcludeSemantics(
                  child: SizedBox(
                    key: const ValueKey('app-sheet-handle'),
                    height: 24,
                    width: double.infinity,
                    child: Center(
                      child: Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              if (heightFactor == null)
                Flexible(
                  child: SingleChildScrollView(
                    child: Builder(builder: builder),
                  ),
                )
              else
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(size: constraints.biggest),
                      child: Builder(builder: builder),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
