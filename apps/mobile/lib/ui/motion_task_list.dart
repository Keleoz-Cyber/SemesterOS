import 'package:flutter/material.dart';
import 'dart:async';
import 'motion.dart';

/// Keeps rows readable during refresh, and removes them only after real data
/// changes. The retiring row cannot receive touch, focus or semantic actions.
class MotionTaskList extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final Widget Function(BuildContext, Map<String, dynamic>, int) builder;
  final bool sliver;
  final Map<String, String> removedStates;
  final Widget? empty;
  const MotionTaskList({
    super.key,
    required this.items,
    required this.builder,
    this.sliver = false,
    this.removedStates = const {},
    this.empty,
  });
  @override
  State<MotionTaskList> createState() => _MotionTaskListState();
}

class _MotionTaskListState extends State<MotionTaskList>
    with WidgetsBindingObserver {
  late List<Map<String, dynamic>> data;
  GlobalKey<AnimatedListState> list = GlobalKey();
  GlobalKey<SliverAnimatedListState> sliver = GlobalKey();
  bool foreground = true;
  int retiring = 0, epoch = 0;
  final cleanups = <Timer>{};
  @override
  void initState() {
    super.initState();
    data = [...widget.items];
    WidgetsBinding.instance.addObserver(this);
  }

  bool get animated => foreground && AppMotion.allowed(context);
  void reset() {
    epoch++;
    retiring = 0;
    for (final timer in cleanups) {
      timer.cancel();
    }
    cleanups.clear();
    data = [...widget.items];
    list = GlobalKey();
    sliver = GlobalKey();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!animated) reset();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (mounted && !foreground) setState(reset);
  }

  void remove(int index) {
    retiring++;
    final stamp = epoch;
    late final Timer timer;
    timer = Timer(const Duration(milliseconds: 900), () {
      cleanups.remove(timer);
      if (mounted && stamp == epoch) setState(() => retiring--);
    });
    cleanups.add(timer);
    final old = data.removeAt(index);
    final retired = {
      ...old,
      '_completion_reveal': widget.removedStates['${old['id']}'] == 'completed',
      if (widget.removedStates['${old['id']}'] != null)
        'lifecycle': widget.removedStates['${old['id']}'],
    };
    Widget leaving(BuildContext c, Animation<double> a) => IgnorePointer(
      child: ExcludeFocus(
        child: ExcludeSemantics(
          child: SizeTransition(
            sizeFactor: a.drive(
              CurveTween(
                curve: const Interval(0, 260 / 880, curve: Curves.easeInOut),
              ),
            ),
            alignment: Alignment.topCenter,
            child: FadeTransition(
              opacity: a.drive(CurveTween(curve: const Interval(0, 260 / 880))),
              child: widget.builder(c, retired, index),
            ),
          ),
        ),
      ),
    );
    if (widget.sliver) {
      sliver.currentState!.removeItem(
        index,
        leaving,
        duration: const Duration(milliseconds: 880),
      );
    } else {
      list.currentState!.removeItem(
        index,
        leaving,
        duration: const Duration(milliseconds: 880),
      );
    }
  }

  void insert(int index, Map<String, dynamic> row) {
    data.insert(index, row);
    if (widget.sliver) {
      sliver.currentState!.insertItem(
        index,
        duration: const Duration(milliseconds: 260),
      );
    } else {
      list.currentState!.insertItem(
        index,
        duration: const Duration(milliseconds: 260),
      );
    }
  }

  @override
  void didUpdateWidget(covariant MotionTaskList old) {
    super.didUpdateWidget(old);
    if (!animated ||
        (widget.sliver
            ? sliver.currentState == null
            : list.currentState == null)) {
      reset();
      return;
    }
    final ids = widget.items.map((r) => r['id']).toSet();
    final survivors = data
        .where((r) => ids.contains(r['id']))
        .map((r) => r['id'])
        .toList();
    final previousIds = data.map((r) => r['id']).toSet();
    final incoming = widget.items
        .where((r) => previousIds.contains(r['id']))
        .map((r) => r['id'])
        .toList();
    if (survivors.join('|') != incoming.join('|')) {
      reset();
      return;
    }
    for (var i = data.length - 1; i >= 0; i--) {
      if (!ids.contains(data[i]['id'])) remove(i);
    }
    for (var i = 0; i < widget.items.length; i++) {
      final row = widget.items[i];
      final previous = data.indexWhere((r) => r['id'] == row['id']);
      if (previous == i) {
        data[i] = row;
      } else {
        if (previous >= 0) remove(previous);
        insert(i, row);
      }
    }
  }

  Widget row(BuildContext c, int index, Animation<double> animation) =>
      SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: animation,
          child: widget.builder(c, data[index], index),
        ),
      );
  @override
  Widget build(BuildContext context) => widget.sliver
      ? SliverMainAxisGroup(
          slivers: [
            SliverAnimatedList(
              key: sliver,
              initialItemCount: data.length,
              itemBuilder: row,
            ),
            if (data.isEmpty && retiring == 0 && widget.empty != null)
              SliverToBoxAdapter(child: widget.empty!),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedList(
              key: list,
              initialItemCount: data.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: row,
            ),
            if (data.isEmpty && retiring == 0 && widget.empty != null)
              AppExpandRegion(visible: true, child: widget.empty!),
          ],
        );
  @override
  void dispose() {
    for (final timer in cleanups) {
      timer.cancel();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
