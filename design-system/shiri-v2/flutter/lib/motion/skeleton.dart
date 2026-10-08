// ignore_for_file: prefer_initializing_formals
/// Loading placeholders that share one shimmer.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../shiri_tokens.dart';
import 'reduced_motion.dart';

/// Owns the single shimmer controller (1200ms linear loop) for every
/// [SkeletonBox] / [SkeletonLine] below it.
///
/// The highlight band is computed in the scope's coordinate space, so all
/// placeholders shimmer as one sweep. Boxes repaint without rebuilding, and
/// the scope is a repaint boundary, so the loop never repaints the rest of the
/// page. This is the only perpetual animation in the kit: it runs while
/// [loading] is true and tickers are enabled, and is static under reduced
/// motion. The scope announces itself once as loading ([semanticLabel]) and
/// hides the placeholder shapes from screen readers.
class SkeletonScope extends StatefulWidget {
  const SkeletonScope({
    super.key,
    required this.child,
    this.loading = true,
    this.semanticLabel = '正在加载',
  });

  final Widget child;

  /// When false the shimmer stops and the child is shown as-is.
  final bool loading;
  final String semanticLabel;

  static _SkeletonScopeData? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonScopeData>();

  @override
  State<SkeletonScope> createState() => _SkeletonScopeState();
}

class _SkeletonScopeState extends State<SkeletonScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: ShiriMotion.shimmerLoop,
  );
  final GlobalKey _boundaryKey = GlobalKey();

  bool get _animate => widget.loading && !reduceMotion(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SkeletonScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_animate) {
      if (!_shimmer.isAnimating) _shimmer.repeat();
    } else {
      _shimmer.stop();
    }
  }

  RenderBox? _scopeBox() =>
      _boundaryKey.currentContext?.findRenderObject() as RenderBox?;

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _SkeletonScopeData(
      shimmer: _animate ? _shimmer : null,
      scopeBox: _scopeBox,
      child: RepaintBoundary(key: _boundaryKey, child: widget.child),
    );
    if (!widget.loading) return content;
    return Semantics(
      label: widget.semanticLabel,
      liveRegion: true,
      container: true,
      child: ExcludeSemantics(child: content),
    );
  }
}

class _SkeletonScopeData extends InheritedWidget {
  const _SkeletonScopeData({
    required this.shimmer,
    required this.scopeBox,
    required super.child,
  });

  final Animation<double>? shimmer;
  final RenderBox? Function() scopeBox;

  @override
  bool updateShouldNotify(_SkeletonScopeData oldWidget) =>
      oldWidget.shimmer != shimmer;
}

/// A rounded placeholder block. [width] null fills the available width.
/// Works outside a [SkeletonScope] too (static, no shimmer).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = ShiriRadius.xsAll,
  });

  final double? width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.shiri.colors;
    final scope = SkeletonScope._of(context);
    return SizedBox(
      width: width,
      height: height,
      child: _SkeletonShape(
        borderRadius: borderRadius,
        base: colors.isDark ? colors.line : colors.line,
        highlight: colors.isDark
            ? colors.lineStrong
            : Color.lerp(colors.line, colors.surface, 0.75)!,
        shimmer: scope?.shimmer,
        scopeBox: scope?.scopeBox,
      ),
    );
  }
}

/// A placeholder for one line of text in [style] (default: ambient style).
///
/// Its height is the style's line height under the current text scale, so the
/// layout does not jump when the real text arrives.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.widthFactor = 1, this.style});

  /// Fraction of the available width.
  final double widthFactor;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(this.style);
    final fontSize = MediaQuery.textScalerOf(
      context,
    ).scale(style.fontSize ?? 14);
    final lineHeight = fontSize * (style.height ?? 1.4);
    final barHeight = (fontSize * 0.72).roundToDouble();
    return SizedBox(
      height: lineHeight,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: widthFactor.clamp(0.0, 1.0),
          child: SkeletonBox(
            height: barHeight,
            borderRadius: BorderRadius.all(Radius.circular(barHeight / 2)),
          ),
        ),
      ),
    );
  }
}

class _SkeletonShape extends LeafRenderObjectWidget {
  const _SkeletonShape({
    required this.borderRadius,
    required this.base,
    required this.highlight,
    required this.shimmer,
    required this.scopeBox,
  });

  final BorderRadius borderRadius;
  final Color base;
  final Color highlight;
  final Animation<double>? shimmer;
  final RenderBox? Function()? scopeBox;

  @override
  _RenderSkeletonShape createRenderObject(BuildContext context) =>
      _RenderSkeletonShape(
        borderRadius: borderRadius,
        base: base,
        highlight: highlight,
        shimmer: shimmer,
        scopeBox: scopeBox,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSkeletonShape renderObject,
  ) {
    renderObject
      ..borderRadius = borderRadius
      ..base = base
      ..highlight = highlight
      ..shimmer = shimmer
      ..scopeBox = scopeBox;
  }
}

class _RenderSkeletonShape extends RenderBox {
  _RenderSkeletonShape({
    required BorderRadius borderRadius,
    required Color base,
    required Color highlight,
    required Animation<double>? shimmer,
    required RenderBox? Function()? scopeBox,
  }) : _borderRadius = borderRadius,
       _base = base,
       _highlight = highlight,
       _shimmer = shimmer,
       _scopeBox = scopeBox;

  BorderRadius _borderRadius;
  set borderRadius(BorderRadius value) {
    if (value == _borderRadius) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  Color _base;
  set base(Color value) {
    if (value == _base) return;
    _base = value;
    markNeedsPaint();
  }

  Color _highlight;
  set highlight(Color value) {
    if (value == _highlight) return;
    _highlight = value;
    markNeedsPaint();
  }

  Animation<double>? _shimmer;
  set shimmer(Animation<double>? value) {
    if (value == _shimmer) return;
    if (attached) _shimmer?.removeListener(markNeedsPaint);
    _shimmer = value;
    if (attached) _shimmer?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  RenderBox? Function()? _scopeBox;
  set scopeBox(RenderBox? Function()? value) => _scopeBox = value;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _shimmer?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _shimmer?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => Size(
    constraints.hasBoundedWidth ? constraints.maxWidth : constraints.minWidth,
    constraints.hasBoundedHeight
        ? constraints.maxHeight
        : constraints.minHeight,
  );

  @override
  void paint(PaintingContext context, Offset offset) {
    final rect = offset & size;
    final rrect = _borderRadius.toRRect(rect);
    final canvas = context.canvas;
    canvas.drawRRect(rrect, Paint()..color = _base);

    final shimmer = _shimmer;
    if (shimmer == null) return;
    var originX = 0.0;
    var scopeWidth = size.width;
    final scope = _scopeBox?.call();
    if (scope != null && scope.attached && scope.hasSize) {
      originX = localToGlobal(Offset.zero, ancestor: scope).dx;
      scopeWidth = scope.size.width;
    }
    // The band travels from beyond the scope's left edge to beyond its right.
    final band = math.max(160.0, scopeWidth * 0.45);
    final centerInScope = -band + (scopeWidth + 2 * band) * shimmer.value;
    final left = offset.dx + centerInScope - originX - band / 2;
    if (left > rect.right || left + band < rect.left) return;
    final bandRect = Rect.fromLTWH(left, rect.top, band, rect.height);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [_base, _highlight, _base],
        stops: const [0, 0.5, 1],
      ).createShader(bandRect);
    canvas.drawRRect(rrect, paint);
  }
}
