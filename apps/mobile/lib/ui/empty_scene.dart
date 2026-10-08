import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum EmptySceneKind {
  agenda,
  tasks,
  search,
  general,
  allDone,
  offline,
  assistant,
  semester,
  timetable,
  collect,
  plan,
  adapt,
  reminder,
}

/// Small decorative line scenes. They contain no dates, counts or sample data.
class AppEmptyScene extends StatefulWidget {
  final EmptySceneKind kind;
  final double size;
  final Color? accent;
  final bool animate;

  const AppEmptyScene({
    super.key,
    this.kind = EmptySceneKind.general,
    this.size = 112,
    this.accent,
    this.animate = true,
  }) : assert(size > 0);

  @override
  State<AppEmptyScene> createState() => _AppEmptySceneState();
}

class _AppEmptySceneState extends State<AppEmptyScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _entrance;
  late final CurvedAnimation _opacity;
  bool _entered = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _opacity = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
    WidgetsBinding.instance.addObserver(this);
  }

  void _finish() {
    _entered = true;
    _entrance.stop();
    _entrance.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.animate ||
        !_foreground ||
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _finish();
    } else if (!_entered) {
      _entered = true;
      _entrance.forward();
    }
  }

  @override
  void didUpdateWidget(covariant AppEmptyScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animate) _finish();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _finish();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _opacity.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: FadeTransition(
      opacity: _opacity,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: SvgPicture.asset(
            'assets/illustrations/${switch (widget.kind) {
              EmptySceneKind.agenda => 'empty-today',
              EmptySceneKind.tasks => 'empty-tasks',
              EmptySceneKind.search => 'no-results',
              EmptySceneKind.general => 'empty-week',
              EmptySceneKind.allDone => 'all-done',
              EmptySceneKind.offline => 'offline',
              EmptySceneKind.assistant => 'assistant-hello',
              EmptySceneKind.semester => 'semester-start',
              EmptySceneKind.timetable => 'import-timetable',
              EmptySceneKind.collect => 'onboard-collect',
              EmptySceneKind.plan => 'onboard-plan',
              EmptySceneKind.adapt => 'onboard-adapt',
              EmptySceneKind.reminder => 'reminder-permission',
            }}.svg',
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ),
      ),
    ),
  );
}
