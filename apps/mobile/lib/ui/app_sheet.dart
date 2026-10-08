import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

import 'motion.dart';
import 'app_controls.dart';
import 'v2/shiri_tokens.dart';

/// A compact, consistent title and an explicit way to leave a chooser.
class AppSheetHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading, trailing;
  final String closeLabel;
  final bool showClose;
  final EdgeInsetsGeometry padding;
  const AppSheetHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.closeLabel = '取消选择',
    this.showClose = true,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 12, 12),
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[
          Padding(padding: const EdgeInsets.only(top: 12), child: leading!),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        ?trailing,
        if (showClose)
          AppIconButton(
            tooltip: closeLabel,
            guardAsync: false,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 21),
          ),
      ],
    ),
  );
}

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
  Rect? originRect,
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
      transitionCurve: ShiriMotion.easeStandard,
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
          child: MediaQuery(
            data: media.copyWith(
              viewInsets: media.viewInsets.copyWith(bottom: 0),
            ),
            child: child,
          ),
        );
      },
      builder: (context) => themes.wrap(
        _AppSheet(
          builder: builder,
          heightFactor: heightFactor,
          showHandle: showHandle,
          originRect: originRect,
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
    this.originRect,
  });

  final WidgetBuilder builder;
  final double? heightFactor;
  final bool showHandle;
  final Rect? originRect;

  @override
  Widget build(BuildContext context) {
    final height = heightFactor == null
        ? null
        : MediaQuery.sizeOf(context).height * heightFactor!;
    final sheet = Sheet(
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
    return originRect == null
        ? sheet
        : _SheetMorph(origin: originRect!, child: sheet);
  }
}

/// Keeps the existing draggable route and keyboard viewport. Only its painted
/// surface moves from the triggering pill's bounds to the final sheet bounds.
class _SheetMorph extends StatefulWidget {
  const _SheetMorph({required this.origin, required this.child});
  final Rect origin;
  final Widget child;
  @override
  State<_SheetMorph> createState() => _SheetMorphState();
}

class _SheetMorphState extends State<_SheetMorph> {
  final boundsKey = GlobalKey();
  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final animation =
        ModalRoute.of(context)?.animation ??
        const AlwaysStoppedAnimation<double>(1);
    return RepaintBoundary(
      key: boundsKey,
      child: AnimatedBuilder(
        animation: animation,
        child: widget.child,
        builder: (context, child) {
          final box = boundsKey.currentContext?.findRenderObject();
          final current = box is RenderBox && box.hasSize && !box.size.isEmpty
              ? box.localToGlobal(Offset.zero) & box.size
              : null;
          final t = reduced ? 1.0 : animation.value;
          final rect = current == null
              ? null
              : Rect.lerp(widget.origin, current, t)!;
          // Keep one subtree while bounds arrive or accessibility changes.
          // Replacing the first-frame Sheet with a Transform would dispose its
          // model and the live assistant, including input and hit geometry.
          return Transform.translate(
            offset: current == null
                ? Offset.zero
                : rect!.topLeft - current.topLeft,
            child: Transform.scale(
              alignment: Alignment.topLeft,
              scaleX: current == null ? 1 : rect!.width / current.width,
              scaleY: current == null ? 1 : rect!.height / current.height,
              child: Opacity(opacity: t.clamp(.05, 1.0), child: child),
            ),
          );
        },
      ),
    );
  }
}
