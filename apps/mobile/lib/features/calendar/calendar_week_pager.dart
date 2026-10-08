import 'package:flutter/material.dart';

import '../../ui/motion.dart';

/// Adjacent weeks share one horizontal viewport. The drag moves both pages
/// continuously; it does not fade or scale a newly rebuilt timetable.
class CalendarWeekPager extends StatefulWidget {
  final int week, totalWeeks;
  final ValueChanged<int> onChanged;
  final Widget Function(BuildContext context, int week) pageBuilder;

  const CalendarWeekPager({
    super.key,
    required this.week,
    required this.totalWeeks,
    required this.onChanged,
    required this.pageBuilder,
  });

  @override
  State<CalendarWeekPager> createState() => _CalendarWeekPagerState();
}

class _CalendarWeekPagerState extends State<CalendarWeekPager>
    with WidgetsBindingObserver {
  late final PageController _pages;
  late int _reportedWeek;
  int? _programmaticWeek;
  bool _foreground = true, _userScroll = false;
  int _sync = 0;

  @override
  void initState() {
    super.initState();
    _reportedWeek = widget.week;
    _pages = PageController(initialPage: widget.week - 1);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant CalendarWeekPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.week != oldWidget.week &&
        (widget.week != _reportedWeek ||
            (_programmaticWeek != null && widget.week != _programmaticWeek))) {
      _moveToSelected();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotion.allowed(context)) _moveToSelected();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _moveToSelected();
  }

  void _moveToSelected() {
    final sync = ++_sync;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || sync != _sync || !_pages.hasClients) return;
      final target = widget.week;
      _programmaticWeek = target;
      if (!_foreground || !AppMotion.allowed(context)) {
        _pages.jumpToPage(target - 1);
      } else {
        await _pages.animateToPage(
          target - 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
      if (!mounted || sync != _sync) return;
      _reportedWeek = target;
      _programmaticWeek = null;
    });
  }

  void _pageChanged(int index) {
    if (_programmaticWeek != null) return;
    _reportedWeek = index + 1;
  }

  void _userScrollEnded() {
    final userScroll = _userScroll;
    _userScroll = false;
    if (!userScroll || _programmaticWeek != null || !_pages.hasClients) return;
    final page = _pages.page;
    if (page == null || (page - page.round()).abs() > .001) return;
    // A drag may cancel an arrow transition and return to the very page that
    // PageView last reported. No onPageChanged fires in that case, so reconcile
    // the actual settled page. Only settling commits a user-selected week;
    // crossing intermediate pages while dragging never requests their data.
    _reportedWeek = page.round() + 1;
    if (_reportedWeek != widget.week) widget.onChanged(_reportedWeek);
  }

  @override
  void dispose() {
    _sync++;
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis != Axis.horizontal) return false;
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _sync++;
            _programmaticWeek = null;
            _userScroll = true;
          } else if (notification is ScrollEndNotification) {
            _userScrollEnded();
          }
          return false;
        },
        child: PageView.builder(
          key: const ValueKey('calendar-week-pages'),
          controller: _pages,
          itemCount: widget.totalWeeks,
          onPageChanged: _pageChanged,
          itemBuilder: (context, index) =>
              RepaintBoundary(child: widget.pageBuilder(context, index + 1)),
        ),
      );
}
