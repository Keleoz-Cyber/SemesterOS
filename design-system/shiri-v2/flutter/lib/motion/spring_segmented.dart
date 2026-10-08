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
  });

  /// (值, 文案)。文案在大字号下可换行，不强制省略。
  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final double minHeight;

  @override
  State<SpringSegmented<T>> createState() => _SpringSegmentedState<T>();
}

class _SpringSegmentedState<T> extends State<SpringSegmented<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: _index.toDouble(),
  );

  int get _index =>
      math.max(0, widget.segments.indexWhere((s) => s.$1 == widget.selected));

  @override
  void didUpdateWidget(covariant SpringSegmented<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
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
  void dispose() {
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
            final segmentWidth = box.maxWidth / count;
            return Stack(
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
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: selected
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onChanged(value);
              },
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: widget.minHeight - 8),
          child: Center(
            child: AnimatedBuilder(
              animation: _position,
              builder: (context, _) {
                final t = (1 - (_position.value - i).abs()).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
