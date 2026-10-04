import 'dart:async';
import 'package:flutter/material.dart';
import 'app_controls.dart';
import 'campus_theme.dart';

/// Optional, explicitly started breathing guide. Time advances only while the
/// card is visible and the app is in the foreground; reduced motion is static.
class BreathingExerciseCard extends StatefulWidget {
  const BreathingExerciseCard({super.key});
  @override
  State<BreathingExerciseCard> createState() => _BreathingExerciseCardState();
}

class _BreathingExerciseCardState extends State<BreathingExerciseCard>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _running = false, _visible = true, _foreground = true;
  int _elapsed = 0;
  int get _cycleSecond => _elapsed % 19;
  int get _phase => _cycleSecond < 4
      ? 0
      : _cycleSecond < 11
      ? 1
      : 2;
  int get _remaining => _phase == 0
      ? 4 - _cycleSecond
      : _phase == 1
      ? 11 - _cycleSecond
      : 19 - _cycleSecond;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  void _sync() {
    if (!_running || !_visible || !_foreground) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _elapsed++;
          if (_elapsed >= 19 * 4) {
            _running = false;
            _timer?.cancel();
            _timer = null;
          }
        });
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _running = !_running;
      if (_running) _elapsed = 0;
    });
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final motion =
        !media.disableAnimations &&
        !media.accessibleNavigation &&
        _visible &&
        _foreground &&
        _running;
    final phaseLabel = ['吸气', '屏息', '呼气'][_phase];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CampusColors.tealSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '呼吸练习',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (_running || _elapsed >= 76)
            Row(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 1, end: motion && _phase != 2 ? 1.12 : 1),
                  duration: motion
                      ? const Duration(milliseconds: 600)
                      : Duration.zero,
                  builder: (_, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: const SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(
                      Icons.air_rounded,
                      color: CampusColors.teal,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _running
                        ? '${!_visible || !_foreground ? '已暂停 · ' : ''}$phaseLabel $_remaining秒 · 第${_elapsed ~/ 19 + 1}/4轮'
                        : _elapsed >= 76
                        ? '本次练习结束'
                        : '点击开始一段简短练习',
                    style: const TextStyle(color: CampusColors.teal),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          AppTextButton(
            onPressed: _toggle,
            child: Text(_running ? '结束练习' : '开始练习'),
          ),
        ],
      ),
    );
  }
}
