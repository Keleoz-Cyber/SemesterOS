// GlassDock + AssistantPill：悬浮玻璃导航坞与助手胶囊。
// - 指示块在页签间用 snappy 弹簧滑动；图标 outline→filled 带一次轻弹
// - 胶囊在内容下滑时收成麦克风圆钮（gentle 弹簧），上滑展开；长按麦克风直接说话
// - lowEnd=true（低端机/减少透明度）时不用 BackdropFilter，改为不透明玻璃色
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter/services.dart';

import '../motion/reduced_motion.dart';
import '../shiri_tokens.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.radius, required this.child, this.lowEnd = false});

  final double radius;
  final Widget child;
  final bool lowEnd;

  @override
  Widget build(BuildContext context) {
    final shiri = context.shiri;
    final shape = BorderRadius.circular(radius);
    final fill = DecoratedBox(
      decoration: BoxDecoration(
        color: lowEnd ? shiri.colors.surfaceGlassFallback : shiri.colors.surfaceGlass,
        borderRadius: shape,
        border: Border.all(color: shiri.colors.glassBorder),
      ),
      // 自带透明 Material，水波纹画在玻璃里而不是被模糊的背景上。
      child: Material(type: MaterialType.transparency, child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: shiri.shadows.floating),
      child: ClipRRect(
        borderRadius: shape,
        child: lowEnd
            ? fill
            : BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: ShiriLayout.glassBlurSigma,
                  sigmaY: ShiriLayout.glassBlurSigma,
                ),
                child: fill,
              ),
      ),
    );
  }
}

class GlassDockItem {
  const GlassDockItem({required this.icon, required this.selectedIcon, required this.label});

  final Widget icon;
  final Widget selectedIcon;
  final String label;
}

class GlassDock extends StatefulWidget {
  const GlassDock({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
    this.lowEnd = false,
  });

  final List<GlassDockItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final bool lowEnd;

  @override
  State<GlassDock> createState() => _GlassDockState();
}

class _GlassDockState extends State<GlassDock> with SingleTickerProviderStateMixin {
  late final AnimationController _x = AnimationController.unbounded(
    vsync: this,
    value: widget.index.toDouble(),
  );

  @override
  void didUpdateWidget(covariant GlassDock old) {
    super.didUpdateWidget(old);
    final target = widget.index.toDouble();
    if (_x.value == target) return;
    if (reduceMotion(context)) {
      _x.value = target;
    } else {
      _x.animateWith(SpringSimulation(ShiriMotion.snappy, _x.value, target, _x.velocity));
    }
  }

  @override
  void dispose() {
    _x.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.shiri.colors;
    return GlassSurface(
      radius: ShiriLayout.dockRadius,
      lowEnd: widget.lowEnd,
      child: SizedBox(
        height: ShiriLayout.dockHeight,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth / widget.items.length;
            return Stack(
              children: [
                AnimatedBuilder(
                  animation: _x,
                  builder: (context, child) => Positioned(
                    left: _x.value * w + (w - ShiriLayout.dockIndicatorWidth) / 2,
                    top: 8,
                    width: ShiriLayout.dockIndicatorWidth,
                    height: ShiriLayout.dockIndicatorHeight,
                    child: child!,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.primarySoftStrong,
                      borderRadius: BorderRadius.circular(ShiriLayout.dockIndicatorRadius),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < widget.items.length; i++) Expanded(child: _item(context, i)),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int i) {
    final shiri = context.shiri;
    final item = widget.items[i];
    final selected = i == widget.index;
    final color = selected ? shiri.colors.primary : shiri.colors.ink500;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: InkResponse(
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        onTap: () {
          if (!selected) HapticFeedback.selectionClick();
          widget.onSelect(i);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: ShiriLayout.dockIndicatorWidth,
              height: ShiriLayout.dockIndicatorHeight,
              child: IconTheme.merge(
                data: IconThemeData(color: color, size: 24),
                child: AnimatedSwitcher(
                  duration: motionDuration(context, ShiriMotion.quick),
                  transitionBuilder: (child, a) => ScaleTransition(
                    scale: Tween(begin: .86, end: 1.0)
                        .animate(CurvedAnimation(parent: a, curve: ShiriMotion.easeReveal)),
                    child: FadeTransition(opacity: a, child: child),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(selected),
                    child: selected ? item.selectedIcon : item.icon,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              style: shiri.text.caption.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class AssistantPill extends StatefulWidget {
  const AssistantPill({
    super.key,
    required this.collapsed,
    required this.onOpen,
    this.onImage,
    this.onHoldStart,
    this.onHoldEnd,
    this.placeholder = '记一条通知，或问问日程',
    this.heroTag,
    this.lowEnd = false,
  });

  /// 由页面滚动方向驱动：下滑 true，上滑 false。
  final bool collapsed;
  final VoidCallback onOpen;
  final VoidCallback? onImage;
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;
  final String placeholder;

  /// 与助手面板共享，可做胶囊 → 面板的容器变换。
  final Object? heroTag;
  final bool lowEnd;

  @override
  State<AssistantPill> createState() => _AssistantPillState();
}

class _AssistantPillState extends State<AssistantPill> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController.unbounded(
    vsync: this,
    value: widget.collapsed ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant AssistantPill old) {
    super.didUpdateWidget(old);
    final target = widget.collapsed ? 1.0 : 0.0;
    if (_t.value == target) return;
    if (reduceMotion(context)) {
      _t.value = target;
    } else {
      _t.animateWith(SpringSimulation(ShiriMotion.gentle, _t.value, target, _t.velocity));
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shiri = context.shiri;
    final pill = LayoutBuilder(
      builder: (context, box) => AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final t = _t.value.clamp(0.0, 1.0);
          final width = ui.lerpDouble(box.maxWidth, ShiriLayout.pillCollapsed, _t.value)!;
          final extras = (1 - t * 2).clamp(0.0, 1.0);
          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: width,
              height: ShiriLayout.pillHeight,
              child: GlassSurface(
                radius: ShiriLayout.pillRadius,
                lowEnd: widget.lowEnd,
                child: Row(
                  children: [
                    if (extras > 0)
                      Expanded(
                        child: Opacity(
                          opacity: extras,
                          child: InkWell(
                            onTap: widget.onOpen,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Row(
                                children: [
                                  const Icon(Icons.auto_awesome_rounded, size: 20, color: ShiriBrand.sky),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      widget.placeholder,
                                      maxLines: 1,
                                      overflow: TextOverflow.fade,
                                      softWrap: false,
                                      style: shiri.text.body.copyWith(fontSize: 15, color: shiri.colors.ink400),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (extras > 0 && widget.onImage != null)
                      Opacity(
                        opacity: extras,
                        child: IconButton(
                          tooltip: '图片',
                          onPressed: widget.onImage,
                          icon: Icon(Icons.image_outlined, color: shiri.colors.ink500),
                        ),
                      ),
                    Padding(padding: const EdgeInsets.all(5), child: _mic(context)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    return widget.heroTag == null ? pill : Hero(tag: widget.heroTag!, child: pill);
  }

  Widget _mic(BuildContext context) => Semantics(
    button: true,
    label: '按住说话，轻点打开助手',
    excludeSemantics: true,
    child: GestureDetector(
      onTap: widget.onOpen,
      onLongPressStart: (_) {
        HapticFeedback.mediumImpact();
        widget.onHoldStart?.call();
      },
      onLongPressEnd: (_) => widget.onHoldEnd?.call(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: ShiriGradients.brand,
          boxShadow: context.shiri.shadows.glowBrand,
        ),
        child: const SizedBox.square(
          dimension: 42,
          child: Icon(Icons.mic_rounded, color: Colors.white, size: 22),
        ),
      ),
    ),
  );
}
