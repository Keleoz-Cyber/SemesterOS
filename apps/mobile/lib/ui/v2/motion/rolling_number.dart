/// Odometer-style number that rolls only the digits that changed.
library;

import 'package:flutter/widgets.dart';

import '../shiri_tokens.dart';
import 'reduced_motion.dart';

/// Shows [value] (or a preformatted [text], e.g. `'13:20'`, `'2/5'`) with
/// tabular figures. When it changes, each changed character slides: the old
/// one up and out, the new one in from below (260ms, standard curve).
/// Unchanged characters stay still; strings are right-aligned so units line
/// up when the length changes.
///
/// Screen readers get the final value only ([semanticsLabel] overrides it).
/// Under reduced motion the new value appears at once.
class RollingNumber extends StatefulWidget {
  const RollingNumber({
    super.key,
    required num this.value,
    this.fractionDigits = 0,
    this.style,
    this.semanticsLabel,
  }) : text = null;

  /// Rolls an already formatted string; any character may change.
  const RollingNumber.text(
    String this.text, {
    super.key,
    this.style,
    this.semanticsLabel,
  }) : value = null,
       fractionDigits = 0;

  final num? value;
  final String? text;
  final int fractionDigits;

  /// Merged over the ambient [DefaultTextStyle]; tabular figures are added.
  final TextStyle? style;
  final String? semanticsLabel;

  String get display => text ?? value!.toStringAsFixed(fractionDigits);

  @override
  State<RollingNumber> createState() => _RollingNumberState();
}

class _RollingNumberState extends State<RollingNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ShiriMotion.standard,
  )..addStatusListener(_onStatus);
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: ShiriMotion.easeStandard,
  );
  late String _current = widget.display;
  String? _previous;

  @override
  void initState() {
    super.initState();
    // Allocate while the element is active, even if the value never changes.
    _controller;
    _curve;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!motionAllowed(context)) {
      _controller.stop();
      _previous = null;
    }
  }

  static final Animatable<Offset> _outTween = Tween(
    begin: Offset.zero,
    end: const Offset(0, -1),
  );
  static final Animatable<Offset> _inTween = Tween(
    begin: const Offset(0, 1),
    end: Offset.zero,
  );
  static final Animatable<double> _fadeOut = Tween(begin: 1.0, end: 0.0);

  void _onStatus(AnimationStatus status) {
    if (status.isCompleted && _previous != null) {
      setState(() => _previous = null);
    }
  }

  @override
  void didUpdateWidget(RollingNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.display;
    if (next == _current) return;
    if (!motionAllowed(context)) {
      _controller.value = 1;
      _previous = null;
      _current = next;
      return;
    }
    // An interrupted roll restarts from the value that was rolling in.
    _previous = _current;
    _current = next;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style
        .merge(widget.style)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    if (_previous == null) {
      return Text(
        _current,
        style: style,
        semanticsLabel: widget.semanticsLabel,
      );
    }
    final now = _current.characters.toList();
    final before = (_previous ?? _current).characters.toList();
    final length = now.length > before.length ? now.length : before.length;
    List<String> pad(List<String> chars) => [
      for (var i = chars.length; i < length; i++) '',
      ...chars,
    ];
    final to = pad(now), from = pad(before);

    return Semantics(
      label: widget.semanticsLabel ?? _current,
      container: true,
      child: ExcludeSemantics(
        child: Wrap(
          textDirection: TextDirection.ltr,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < length; i++)
              if (_previous == null || from[i] == to[i])
                Text(to[i], style: style)
              else
                ClipRect(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SlideTransition(
                        position: _curve.drive(_outTween),
                        child: FadeTransition(
                          opacity: _curve.drive(_fadeOut),
                          child: Text(from[i], style: style),
                        ),
                      ),
                      SlideTransition(
                        position: _curve.drive(_inTween),
                        child: FadeTransition(
                          opacity: _curve,
                          child: Text(to[i], style: style),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
