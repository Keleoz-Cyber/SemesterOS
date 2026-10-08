import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'media_input.dart';
import '../../ui/motion.dart';
import '../../ui/campus_theme.dart';
import '../../ui/v2/shiri_tokens.dart';

/// Owns one recording at a time. The callback must copy the temporary file
/// before completing; the file is released even when the callback fails.
class HoldVoiceButton extends StatefulWidget {
  const HoldVoiceButton({
    super.key,
    required this.onRecorded,
    required this.onError,
    this.onRecordingChanged,
    this.input,
    this.enabled = true,
    this.compact = false,
    this.onTap,
  });

  final Future<void> Function(String path) onRecorded;
  final ValueChanged<String> onError;
  final ValueChanged<bool>? onRecordingChanged;
  final MediaInput? input;
  final bool enabled;
  final bool compact;
  final VoidCallback? onTap;

  @override
  State<HoldVoiceButton> createState() => _HoldVoiceButtonState();
}

class _HoldVoiceButtonState extends State<HoldVoiceButton>
    with WidgetsBindingObserver {
  MediaInput? _input;
  MediaInput get input => _input ??= widget.input ?? DeviceMediaInput();
  bool starting = false, recording = false, finishing = false;
  bool held = false, cancelling = false, dead = false;
  int? pointer;
  double originY = 0;
  int seconds = 0;
  int interruption = 0;
  Timer? timer;
  DateTime? startedAt;
  Future<void>? pendingStart;
  Future<void>? pendingFinish;

  @override
  void initState() {
    super.initState();
    _input = widget.input;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant HoldVoiceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      unawaited(Future.microtask(() => end(cancel: true)));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(end(cancel: true));
  }

  @override
  void dispose() {
    dead = true;
    held = false;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Permission/start can finish after unmount. Wait for its cleanup before
    // disposing the native recorder, avoiding start/dispose races.
    unawaited(() async {
      await pendingStart;
      if (recording) await end(cancel: true);
      await pendingFinish;
      await _input?.dispose();
    }());
    super.dispose();
  }

  void refresh() {
    if (mounted && !dead) setState(() {});
  }

  void begin() {
    if (!widget.enabled || starting || recording || finishing || dead) return;
    held = true;
    cancelling = false;
    starting = true;
    seconds = 0;
    widget.onRecordingChanged?.call(true);
    refresh();
    pendingStart = start();
  }

  Future<void> start() async {
    try {
      final allowed = await input.start();
      if (!allowed) {
        if (!dead) widget.onError('麦克风权限未开启，可以改用文字输入。');
        return;
      }
      // Releasing while permission is pending always cancels. It must never
      // create an empty source, upload a file, or start a late recording.
      if (dead || !held || !widget.enabled) {
        final path = await input.stop();
        if (path != null) await input.release(path);
        return;
      }
      recording = true;
      startedAt = DateTime.now();
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        seconds = DateTime.now().difference(startedAt!).inSeconds;
        refresh();
        if (seconds >= 119) unawaited(end());
      });
    } catch (_) {
      try {
        final path = await input.stop();
        if (path != null) await input.release(path);
      } catch (_) {
        // The native recorder may have failed before creating any file.
      }
      if (!dead) widget.onError('暂时无法录音，请重试或改用文字。');
    } finally {
      starting = false;
      if (!dead && !recording) widget.onRecordingChanged?.call(false);
      refresh();
    }
  }

  Future<void> end({bool cancel = false}) {
    if (cancel) interruption++;
    held = false;
    pointer = null;
    final discard = cancel || cancelling;
    cancelling = false;
    if (!recording || finishing) {
      refresh();
      return Future<void>.value();
    }
    recording = false;
    finishing = true;
    timer?.cancel();
    if (!dead) widget.onRecordingChanged?.call(false);
    refresh();
    final result = finish(discard, interruption);
    pendingFinish = result;
    return result;
  }

  Future<void> finish(bool discard, int epoch) async {
    String? path;
    try {
      path = await input.stop();
      if (!dead && !discard && widget.enabled && epoch == interruption) {
        if (path == null) {
          widget.onError('没有录到声音，请再试一次。');
        } else {
          await widget.onRecorded(path);
        }
      }
    } catch (_) {
      if (!dead) widget.onError('录音暂时没能保存，请重试。');
    } finally {
      if (path != null) {
        try {
          await input.release(path);
        } catch (_) {
          // Recorder disposal retries cleanup of its owned temporary files.
        }
      }
      finishing = false;
      refresh();
    }
  }

  void accessibleToggle() {
    if (recording || starting) {
      unawaited(end());
    } else {
      begin();
    }
  }

  Widget compactFace(BuildContext context) {
    final active = starting || recording || finishing;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: widget.enabled && !finishing,
      label: active ? (cancelling ? '松开取消' : '松开完成') : '按住说话，轻点打开助手',
      hint: '上滑取消；双击开始，再次双击结束',
      onTap: widget.enabled && !finishing ? accessibleToggle : null,
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.space ||
                  event.logicalKey == LogicalKeyboardKey.enter)) {
            accessibleToggle();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            unawaited(end(cancel: true));
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled && !active ? widget.onTap : null,
          onLongPressStart: widget.enabled && !active
              ? (details) {
                  originY = details.globalPosition.dy;
                  begin();
                }
              : null,
          onLongPressMoveUpdate: (details) {
            final next = originY - details.globalPosition.dy >= 64;
            if (next != cancelling) {
              cancelling = next;
              refresh();
            }
          },
          onLongPressEnd: (_) => unawaited(end()),
          onLongPressCancel: () => unawaited(end(cancel: true)),
          child: ExcludeSemantics(
            child: AnimatedContainer(
              duration: AppMotion.feedback(context),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: cancelling ? null : ShiriGradients.brand,
                color: cancelling ? colors.errorContainer : null,
              ),
              child: active
                  ? Center(
                      child: recording
                          ? const _VoiceWave(width: 26, height: 20)
                          : Text(
                              finishing ? '…' : '…',
                              style: const TextStyle(color: CampusColors.ink),
                            ),
                    )
                  : const Icon(
                      Icons.mic_rounded,
                      size: 24,
                      color: CampusColors.ink,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) return compactFace(context);
    final colors = Theme.of(context).colorScheme;
    final active = recording || starting;
    final label = cancelling
        ? '松开取消'
        : recording
        ? '松开完成 · ${seconds}s'
        : starting
        ? '正在开启麦克风…'
        : finishing
        ? '正在识别…'
        : '按住说话';
    return Semantics(
      button: true,
      enabled: widget.enabled && !finishing,
      label: active ? label : '按住说话，上滑取消',
      hint: '使用屏幕阅读器时，双击开始，再次双击结束',
      onTap: widget.enabled && !finishing ? accessibleToggle : null,
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.space ||
                  event.logicalKey == LogicalKeyboardKey.enter)) {
            accessibleToggle();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            unawaited(end(cancel: true));
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (pointer != null || !widget.enabled || finishing || starting) {
              return;
            }
            pointer = event.pointer;
            originY = event.position.dy;
            begin();
          },
          onPointerMove: (event) {
            if (event.pointer != pointer) return;
            final next = originY - event.position.dy >= 64;
            if (next != cancelling) {
              cancelling = next;
              refresh();
            }
          },
          onPointerUp: (event) {
            if (event.pointer == pointer) unawaited(end());
          },
          onPointerCancel: (event) {
            if (event.pointer == pointer) unawaited(end(cancel: true));
          },
          child: AnimatedContainer(
            duration: AppMotion.feedback(context),
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cancelling
                  ? colors.errorContainer
                  : active
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cancelling
                    ? colors.error
                    : active
                    ? CampusColors.primary
                    : Colors.transparent,
              ),
            ),
            child: ExcludeSemantics(
              child: recording
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _VoiceWave(width: 56, height: 20),
                        const SizedBox(height: 6),
                        Text(
                          '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: cancelling
                                ? colors.onErrorContainer
                                : CampusColors.primary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          cancelling ? '松开取消' : '松开完成',
                          style: TextStyle(
                            fontSize: 14,
                            color: cancelling
                                ? colors.onErrorContainer
                                : colors.onSurface,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: !widget.enabled
                            ? colors.onSurface.withValues(alpha: .4)
                            : cancelling
                            ? colors.onErrorContainer
                            : colors.onSurface,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Decorative hold feedback, not a measurement of microphone amplitude.
class _VoiceWave extends StatefulWidget {
  const _VoiceWave({required this.width, required this.height});
  final double width, height;
  @override
  State<_VoiceWave> createState() => _VoiceWaveState();
}

class _VoiceWaveState extends State<_VoiceWave>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.allowed(context) &&
        ModalRoute.isCurrentOf(context) != false) {
      animation.repeat();
    } else {
      animation.stop();
      animation.value = .5;
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size(widget.width, widget.height),
      painter: _WavePainter(animation),
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.animation) : super(repaint: animation);
  final Animation<double> animation;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = CampusColors.ink;
    for (var i = 0; i < 5; i++) {
      final h =
          size.height *
          (.28 +
              .6 * (math.sin(animation.value * math.pi * 2 + i * .8) + 1) / 2);
      final x = (i + .5) * size.width / 5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, size.height / 2),
            width: 3,
            height: h,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.animation != animation;
}
