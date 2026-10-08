import 'dart:ui';
import 'package:flutter/widgets.dart';

/// Session-local rendering fallback after sustained slow raster frames.
class ShiriPerformance extends StatefulWidget {
  const ShiriPerformance({super.key, required this.child});
  final Widget child;
  static bool lowEndOf(BuildContext context) =>
      (context.dependOnInheritedWidgetOfExactType<_PerformanceData>()?.lowEnd ??
          false) ||
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
      (MediaQuery.maybeHighContrastOf(context) ?? false);
  @override
  State<ShiriPerformance> createState() => _ShiriPerformanceState();
}

class _ShiriPerformanceState extends State<ShiriPerformance>
    with WidgetsBindingObserver {
  bool lowEnd = false, foreground = true;
  int slowFrames = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(timings);
  }

  void timings(List<FrameTiming> frames) {
    if (!foreground || lowEnd || !mounted) return;
    for (final frame in frames) {
      slowFrames = frame.rasterDuration.inMilliseconds > 32
          ? slowFrames + 1
          : 0;
      if (slowFrames >= 8) {
        setState(() => lowEnd = true);
        break;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final next = state == AppLifecycleState.resumed;
    if (next != foreground && mounted) setState(() => foreground = next);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(timings);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: foreground,
    child: _PerformanceData(lowEnd: lowEnd, child: widget.child),
  );
}

class _PerformanceData extends InheritedWidget {
  const _PerformanceData({required this.lowEnd, required super.child});
  final bool lowEnd;
  @override
  bool updateShouldNotify(_PerformanceData oldWidget) =>
      lowEnd != oldWidget.lowEnd;
}
