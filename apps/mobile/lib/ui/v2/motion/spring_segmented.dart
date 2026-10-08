// SpringSegmented：选中块用 snappy 弹簧滑动，被打断时保留速度。
//
// 用法：
// SpringSegmented<String>(
//   segments: const [('todo', '待处理'), ('done', '已完成'), ('cancelled', '已取消')],
//   selected: tab,
//   onChanged: (v) => setState(() => tab = v),
// )
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter/services.dart';

import '../shiri_tokens.dart';
import 'reduced_motion.dart';

class SpringSegmented<T> extends StatefulWidget {
  const SpringSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.minHeight = ShiriLayout.touchTarget,
    this.enabled = true,
    this.disabledValues = const {},
  });

  /// (值, 文案)。文案在大字号下可换行，不强制省略。
  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final double minHeight;
  final bool enabled;
  final Set<T> disabledValues;

  @override
  State<SpringSegmented<T>> createState() => _SpringSegmentedState<T>();
}

class _SpringSegmentedState<T> extends State<SpringSegmented<T>>
    with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    _position;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(
        (_index * _slot - (_scroll.position.viewportDimension - _slot) / 2)
            .clamp(0.0, _scroll.position.maxScrollExtent),
      );
    });
  }

  final _scroll = ScrollController();
  double _slot = 48;
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: _index.toDouble(),
  );

  int get _index =>
      math.max(0, widget.segments.indexWhere((s) => s.$1 == widget.selected));

  @override
  void didUpdateWidget(covariant SpringSegmented<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final offset =
          (_index * _slot - (_scroll.position.viewportDimension - _slot) / 2)
              .clamp(0.0, _scroll.position.maxScrollExtent);
      if (reduceMotion(context)) {
        _scroll.jumpTo(offset);
      } else {
        _scroll.animateTo(
          offset,
          duration: ShiriMotion.standard,
          curve: ShiriMotion.easeStandard,
        );
      }
    });
    final target = _index.toDouble();
    if (_position.value == target) return;
    if (reduceMotion(context)) {
      _position.value = target;
    } else {
      _position.animateWith(
        SpringSimulation(
          ShiriMotion.snappy,
          _position.value,
          target,
          _position.velocity,
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!motionAllowed(context)) {
      _position.stop();
      _position.value = _index.toDouble();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shiri = context.shiri;
    final c = shiri.colors;
    final count = widget.segments.length;
    return Semantics(
      container: true,
      child: Container(
        constraints: BoxConstraints(minHeight: widget.minHeight),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.surfaceSunken,
          borderRadius: BorderRadius.circular(14),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            var minimum = ShiriLayout.touchTarget;
            for (final segment in widget.segments) {
              final p = TextPainter(
                text: TextSpan(
                  text: segment.$2,
                  style: shiri.text.label.copyWith(fontSize: 14.5),
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              minimum = math.max(minimum, p.width + 16);
              p.dispose();
            }
            final width = box.hasBoundedWidth
                ? math.max(box.maxWidth, minimum * count)
                : minimum * count;
            final segmentWidth = width / count;
            _slot = segmentWidth;
            final track = SizedBox(
              width: width,
              child: Stack(
                children: [
                  AnimatedBuilder(
                    animation: _position,
                    builder: (context, child) => Positioned(
                      left: _position.value * segmentWidth,
                      top: 0,
                      bottom: 0,
                      width: segmentWidth,
                      child: child!,
                    ),
                    child: DecoratedBox(
                      key: const Key('spring-selection-surface'),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: shiri.shadows.card,
                      ),
                    ),
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: Row(
                      children: [
                        for (var i = 0; i < count; i++)
                          Expanded(child: _segment(context, i)),
                      ],
                    ),
                  ),
                ],
              ),
            );
            return box.hasBoundedWidth && width <= box.maxWidth
                ? track
                : SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    child: track,
                  );
          },
        ),
      ),
    );
  }

  Widget _segment(BuildContext context, int i) {
    final c = context.shiri.colors;
    final (value, label) = widget.segments[i];
    final selected = i == _index;
    return Semantics(
      button: true,
      enabled: widget.enabled && !widget.disabledValues.contains(value),
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: c.primarySoft,
        splashFactory: NoSplash.splashFactory,
        onTap: !widget.enabled || widget.disabledValues.contains(value)
            ? null
            : () {
                if (selected) return;
                HapticFeedback.selectionClick();
                widget.onChanged(value);
              },
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: widget.minHeight),
          child: Center(
            child: AnimatedBuilder(
              animation: _position,
              builder: (context, _) {
                final t = (1 - (_position.value - i).abs()).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: context.shiri.text.label.copyWith(
                      fontSize: 14.5,
                      color: Color.lerp(c.ink500, c.ink900, t),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
