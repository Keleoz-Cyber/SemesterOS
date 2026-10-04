import '../../ui/app_loading.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_sheet.dart';
import '../../ui/motion.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import '../calendar/calendar_repository.dart';
import '../changes/changes_page.dart';
import 'hub_data.dart';
import 'exam_pages.dart';
import '../tags/tag_management_page.dart';
import '../../ui/date_labels.dart';
import 'semester_centers.dart' show CourseHubPage, openHubItem, changeCard;

class SemesterHome extends StatefulWidget {
  final ItemsController controller;
  final VoidCallback onManage;
  const SemesterHome({
    super.key,
    required this.controller,
    required this.onManage,
  });
  @override
  SemesterHomeState createState() => SemesterHomeState();
}

class SemesterHomeState extends State<SemesterHome>
    with WidgetsBindingObserver {
  final _hub = GlobalKey<HubDataState>();
  final _weekStrip = ScrollController();
  late final CalendarRepository _calendar;
  Map<String, dynamic>? _adopted;
  int? _selected;
  String? _calendarWeek;
  Future<void>? _calendarPending;
  int? _calendarRevision;
  DateTime? _calendarLoadedAt;
  int _calendarRequest = 0;
  int _weekDirection = 1;
  bool _foreground = true;
  double get _weekWidth => MediaQuery.textScalerOf(context).scale(44) + 28;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _calendar = CalendarRepository(
      widget.controller.api,
      widget.controller.cache,
    )..addListener(_calendarChanged);
  }

  void _calendarChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  void _selectWeek(int week, Map<String, dynamic> data) {
    if (_selected != week) {
      setState(() {
        _weekDirection = week >= (_selected ?? week) ? 1 : -1;
        _selected = week;
      });
    }
    _loadActivities(data);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _calendar.removeListener(_calendarChanged);
    _calendar.dispose();
    _weekStrip.dispose();
    super.dispose();
  }

  /// Pull-to-refresh waits for both the hub and the selected week's activities.
  Future<void> reload() async {
    await _hub.currentState?.load();
    final data = _hub.currentState?.data;
    if (mounted && data != null) {
      _adopt(data);
      await _loadActivities(data, force: true);
    }
  }

  int _currentWeek(Map<String, dynamic> semester) {
    final first = DateTime.parse(semester['first_monday']);
    final now = schoolNow();
    return (DateTime(now.year, now.month, now.day).difference(first).inDays / 7)
            .floor() +
        1;
  }

  void _adopt(Map<String, dynamic> data) {
    if (!mounted || identical(_adopted, data)) return;
    _adopted = data;
    final weeks = widget.controller.rows(data['weeks']);
    if (weeks.isEmpty) return;
    final current = _currentWeek(Map<String, dynamic>.from(data['semester']));
    if (!weeks.any((w) => w['week'] == _selected)) {
      final nearest = [...weeks]
        ..sort(
          (a, b) => ((a['week'] as int) - current).abs().compareTo(
            ((b['week'] as int) - current).abs(),
          ),
        );
      setState(() => _selected = nearest.first['week']);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_weekStrip.hasClients) return;
        final index = weeks.indexWhere((w) => w['week'] == _selected);
        _weekStrip.jumpTo(
          (index * _weekWidth).clamp(0.0, _weekStrip.position.maxScrollExtent),
        );
      });
    }
    _loadActivities(data);
  }

  Future<void> _loadActivities(
    Map<String, dynamic> data, {
    bool force = false,
  }) async {
    if (!mounted || !TickerMode.valuesOf(context).enabled) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final week = widget.controller
        .rows(data['weeks'])
        .where((w) => w['week'] == _selected)
        .firstOrNull;
    final sid = widget.controller.semesterId;
    if (week == null || sid == null) return;
    final date = '${week['start_date']}';
    if (_calendarWeek == date && _calendarPending != null) {
      await _calendarPending;
      if (!mounted || (!force && _calendar.revision == data['revision'])) {
        return;
      }
      return _loadActivities(data, force: true);
    }
    if (!force &&
        _calendarWeek == date &&
        _calendarRevision == data['revision'] &&
        _calendarLoadedAt != null &&
        DateTime.now().difference(_calendarLoadedAt!) <
            const Duration(seconds: 45)) {
      return;
    }
    _calendarWeek = date;
    final request = ++_calendarRequest;
    final future = _calendar.load(sid, DateTime.parse(date));
    _calendarPending = future;
    await future;
    if (!mounted || request != _calendarRequest) return;
    _calendarPending = null;
    if (_calendar.data != null &&
        !_calendar.offline &&
        !widget.controller.revisionIsStale(sid, _calendar.revision!)) {
      widget.controller.observeRevision(sid, _calendar.revision!);
      _calendarRevision = _calendar.revision;
      _calendarLoadedAt = DateTime.now();
    }
  }

  Future<void> _courses(Map<String, dynamic> data) async {
    await showAppSheet<void>(
      context: context,
      heightFactor: .7,
      builder: (sheetContext) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('课程事务', style: Theme.of(context).textTheme.titleLarge),
          for (final course in widget.controller.rows(data['courses']))
            AppTile(
              title: Text('${course['title']}'),
              subtitle: _courseSummary(course).isEmpty
                  ? null
                  : Text(_courseSummary(course)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CourseHubPage(
                      controller: widget.controller,
                      courseId: course['id'],
                    ),
                  ),
                ).then((_) {
                  if (mounted) reload();
                });
              },
            ),
          if (widget.controller.rows(data['courses']).isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('还没有导入课程')),
        ],
      ),
    );
  }

  Widget _node({
    required String title,
    required String time,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool warning = false,
    dynamic at,
  }) => Semantics(
    button: true,
    label: '${at == null ? '' : '${_nodeDate(at)}，'}$label，$title，$time',
    onTap: onTap,
    child: ExcludeSemantics(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: MediaQuery.textScalerOf(context).scale(42) + 14,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 13),
                    child: Text(
                      at == null
                          ? (RegExp(r'第\d+周').firstMatch(time)?.group(0) ?? '')
                          : _nodeDate(at),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: CampusColors.ink,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 20,
                  child: Stack(
                    children: [
                      const Positioned(
                        top: 0,
                        bottom: 0,
                        left: 9,
                        child: SizedBox(
                          width: 2,
                          child: ColoredBox(color: CampusColors.line),
                        ),
                      ),
                      Positioned(
                        top: 15,
                        left: 2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: CampusColors.background,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: warning
                                  ? CampusColors.warning
                                  : CampusColors.teal,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            icon,
                            size: 10,
                            color: warning
                                ? CampusColors.warning
                                : CampusColors.teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 10, 4, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          time.isEmpty ||
                                  at == null &&
                                      RegExp(r'^第\d+周$').hasMatch(time)
                              ? label
                              : '$label · $time',
                          style: TextStyle(
                            fontSize: 13,
                            color: warning
                                ? CampusColors.warning
                                : CampusColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 12, right: 2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: CampusColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _semesterCaption(String name) {
    const style = TextStyle(
      fontSize: 14,
      color: CampusColors.primary,
      fontWeight: FontWeight.w600,
    );
    final standard = RegExp(
      r'^(.*?)(第[一二三四五六七八九十\d]+学期|[春秋夏冬]季?学期)$',
    ).firstMatch(name.trim());
    final prefix = standard?.group(1)?.trim() ?? '';
    if (standard == null || prefix.isEmpty) return Text(name, style: style);
    return Semantics(
      label: name,
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 6,
          runSpacing: 2,
          children: [
            Text(prefix, style: style),
            Text(standard.group(2)!, softWrap: false, style: style),
          ],
        ),
      ),
    );
  }

  String _nodeDate(dynamic value) {
    final raw = '$value';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '待确认';
    final date = raw.length == 10 ? parsed : schoolTime(raw);
    return '${date.month}/${date.day}';
  }

  @override
  Widget build(BuildContext context) => HubData(
    key: _hub,
    controller: widget.controller,
    path: '/semesters/${widget.controller.semesterId}/hub',
    builder: (context, data, fresh, load) {
      if (!identical(_adopted, data)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _adopt(data));
      }
      final semester = Map<String, dynamic>.from(data['semester']);
      final weeks = widget.controller.rows(data['weeks']);
      final current = _currentWeek(semester);
      final total = semester['total_weeks'] as int;
      final selected = weeks.where((w) => w['week'] == _selected).firstOrNull;
      final animate = _foreground && AppMotion.allowed(context);
      final undatedEvents = _calendar.undated
          .where((e) => e['resource_type'] == 'event')
          .toList();
      final events =
          <Map<String, dynamic>>[
            for (final item in widget.controller.rows(selected?['items']))
              {
                'type': 'item',
                'row': item,
                'at':
                    item['anchor_at'] ??
                    item['time']?['at'] ??
                    item['time']?['date'],
              },
            if (_calendarWeek == selected?['start_date'])
              for (final event in _calendar.entries.where(
                (e) => e['resource_type'] == 'event',
              ))
                {
                  'type': 'event',
                  'row': event,
                  'at': event['start_at'] ?? event['date'],
                },
          ]..sort(
            (a, b) =>
                timelineInstant(a['at']).compareTo(timelineInstant(b['at'])),
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _semesterCaption('${semester['name']}'),
                const SizedBox(height: 4),
                Text(
                  current < 1
                      ? '学期尚未开始'
                      : current > total
                      ? '本学期已结束'
                      : '第$current周',
                  style: TextStyle(
                    fontSize: current < 1 || current > total ? 24 : 32,
                    fontWeight: FontWeight.w700,
                    color: CampusColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '共 $total 周 · ${studentDate(DateTime.parse(semester['first_monday']))} 开始',
                  style: const TextStyle(
                    color: CampusColors.muted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total <= 0
                        ? 0
                        : ((current - 1) / total).clamp(0.0, 1.0),
                    minHeight: 6,
                    color: CampusColors.primary,
                    backgroundColor: CampusColors.line,
                  ),
                ),
              ],
            ),
          ),
          const SectionHeading('学期周次'),
          SingleChildScrollView(
            controller: _weekStrip,
            scrollDirection: Axis.horizontal,
            child: _SemesterWeekStrip(
              weeks: weeks,
              selected: _selected,
              current: current,
              slotWidth: _weekWidth,
              animate: animate,
              dateLabel: _nodeDate,
              onSelected: (week) => _selectWeek(week, data),
            ),
          ),
          const SizedBox(height: 12),
          if (selected != null)
            _SemesterWeekContent(
              week: '${semester['id']}/${selected['week']}',
              direction: _weekDirection,
              animate: animate,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppLoadingOverlay(
                    loading: _calendar.busy,
                    label: '正在更新',
                    padding: const EdgeInsets.only(right: 2),
                    child: Text(
                      '第${selected['week']}周安排',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${studentDate(DateTime.parse(selected['start_date']))}—${studentDate(DateTime.parse(selected['end_date']))}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: CampusColors.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_calendar.error != null ||
                      (_calendar.revision != null &&
                          widget.controller.revisionIsStale(
                            widget.controller.semesterId,
                            _calendar.revision!,
                          ))) ...[
                    const SoftNotice('本周活动尚未更新，以下保留上次记录。', warning: true),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppTextButton(
                        onPressed: () => _loadActivities(data, force: true),
                        child: const Text('重试活动'),
                      ),
                    ),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final e in events)
                        if (e['type'] == 'item')
                          _node(
                            at: e['at'],
                            title: e['row']['title'],
                            time: itemTimeLabel(e['row']),
                            label:
                                '${kindLabel(e['row']['kind'])}${e['row']['certainty'] == 'tentative' ? ' · 暂定' : ''}',
                            icon: e['row']['kind'] == 'exam'
                                ? Icons.school_outlined
                                : Icons.flag_outlined,
                            warning: e['row']['certainty'] == 'tentative',
                            onTap: () async {
                              await openHubItem(
                                context,
                                widget.controller,
                                e['row'],
                                semester,
                              );
                              if (mounted) await reload();
                            },
                          )
                        else
                          _node(
                            at: e['at'],
                            title: e['row']['title'],
                            time: calendarTimeLabel(e['row']),
                            label:
                                '${e['row']['reserve_time'] == false ? '仅作参考' : '固定活动'}${e['row']['certainty'] == 'tentative' ? ' · 暂定' : ''}',
                            warning: e['row']['certainty'] == 'tentative',
                            icon: Icons.event_outlined,
                            onTap: () async {
                              await context.push(
                                '/events/${e['row']['resource_id']}',
                              );
                              if (mounted) await reload();
                            },
                          ),
                      for (final change in widget.controller.rows(
                        selected['changes'],
                      ))
                        changeCard(
                          change,
                          onOpen: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ChangesPage(controller: widget.controller),
                              ),
                            );
                            if (mounted) await reload();
                          },
                        ),
                      if (events.isEmpty &&
                          widget.controller.rows(selected['changes']).isEmpty)
                        const CampusPanel(child: Text('这一周还没有记录截止事项、考试或活动')),
                    ],
                  ),
                ],
              ),
            )
          else if (weeks.isEmpty)
            const CampusPanel(child: Text('还没有学期周次，请检查学期起止时间。')),
          if (widget.controller.rows(data['undated']).isNotEmpty ||
              undatedEvents.isNotEmpty) ...[
            const SectionHeading('其他待办'),
            for (final event in undatedEvents)
              _node(
                title: event['title'],
                time: calendarTimeLabel(event),
                label:
                    '${event['reserve_time'] == false ? '仅作参考' : '固定活动'}${event['certainty'] == 'tentative' ? ' · 暂定' : ''}',
                warning: event['certainty'] == 'tentative',
                icon: Icons.help_outline,
                onTap: () async {
                  await context.push('/events/${event['resource_id']}');
                  if (mounted) await reload();
                },
              ),
            for (final item in widget.controller.rows(data['undated']))
              _node(
                title: item['title'],
                time: itemTimeLabel(item),
                label:
                    '${kindLabel(item['kind'])}${item['certainty'] == 'tentative' ? ' · 暂定' : ''}',
                icon: Icons.help_outline,
                onTap: () async {
                  await openHubItem(context, widget.controller, item, semester);
                  if (mounted) await reload();
                },
              ),
          ],
          if (widget.controller.rows(data['outside']).isNotEmpty) ...[
            const SectionHeading('学期范围外'),
            for (final item in widget.controller.rows(data['outside']))
              _node(
                title: item['title'],
                time: itemTimeLabel(item),
                label: '需核对日期',
                icon: Icons.event_busy_outlined,
                onTap: () async {
                  await openHubItem(context, widget.controller, item, semester);
                  if (mounted) await reload();
                },
              ),
          ],
          const SizedBox(height: 8),
          const SizedBox(height: 20),
          Material(
            color: CampusColors.surface,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Wrap(
              alignment: WrapAlignment.spaceAround,
              children: [
                _SemesterAction(
                  onPressed: () => _courses(data),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text('课程'),
                ),
                _SemesterAction(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExamCenterPage(
                          controller: widget.controller,
                          semester: semester,
                        ),
                      ),
                    );
                    if (mounted) await reload();
                  },
                  icon: const Icon(Icons.school_outlined),
                  label: const Text('考试'),
                ),
                _SemesterAction(
                  primary: true,
                  onPressed: () => context.push('/insights'),
                  icon: const Icon(Icons.bar_chart_rounded),
                  label: const Text('统计'),
                ),
                _SemesterAction(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TagManagementPage(controller: widget.controller),
                      ),
                    );
                    if (mounted) await reload();
                  },
                  icon: const Icon(Icons.label_outline),
                  label: const Text('标签'),
                ),
                _SemesterAction(
                  onPressed: widget.onManage,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('管理'),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _SemesterWeekStrip extends StatelessWidget {
  final List<Map<String, dynamic>> weeks;
  final int? selected;
  final int current;
  final double slotWidth;
  final bool animate;
  final String Function(dynamic) dateLabel;
  final ValueChanged<int> onSelected;

  const _SemesterWeekStrip({
    required this.weeks,
    required this.selected,
    required this.current,
    required this.slotWidth,
    required this.animate,
    required this.dateLabel,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final labelStyle = base.merge(
      const TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w500),
    );
    final numberStyle = base.merge(
      const TextStyle(
        fontSize: 20,
        height: 1,
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
    final dateStyle = base.merge(
      const TextStyle(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w500,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
    Size measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final labelHeight = measure('本周', labelStyle).height;
    final dateHeight = measure('11/30', dateStyle).height;
    var diskSize = 44.0;
    for (final week in weeks) {
      final size = measure('${week['week']}', numberStyle);
      diskSize = math.max(diskSize, math.max(size.width, size.height) + 18);
    }
    final selectedIndex = weeks.indexWhere((week) => week['week'] == selected);
    final height = 4 + labelHeight + 4 + diskSize + 6 + dateHeight + 8;
    final duration = animate
        ? const Duration(milliseconds: 240)
        : Duration.zero;
    final feedback = animate ? motionQuick : Duration.zero;
    return RepaintBoundary(
      child: SizedBox(
        width: weeks.length * slotWidth,
        height: height,
        child: Stack(
          children: [
            Row(
              children: [
                for (final week in weeks)
                  SizedBox(
                    width: slotWidth,
                    height: height,
                    child: Semantics(
                      key: ValueKey('semester-week-${week['week']}'),
                      button: true,
                      selected: selected == week['week'],
                      label:
                          '第${week['week']}周，${dateLabel(week['start_date'])}开始${week['week'] == current ? '，本周' : ''}',
                      onTap: () => onSelected(week['week'] as int),
                      child: ExcludeSemantics(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => onSelected(week['week'] as int),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: labelHeight,
                                    child: Text(
                                      week['week'] == current ? '本周' : '周',
                                      style: labelStyle.copyWith(
                                        color: week['week'] == current
                                            ? CampusColors.teal
                                            : CampusColors.muted,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    height: diskSize,
                                    child: Center(
                                      child: Text(
                                        '${week['week']}',
                                        style: numberStyle.copyWith(
                                          color: CampusColors.ink,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    height: dateHeight,
                                    child: AnimatedDefaultTextStyle(
                                      key: ValueKey(
                                        'semester-week-date-$animate',
                                      ),
                                      duration: feedback,
                                      style: dateStyle.copyWith(
                                        color: selected == week['week']
                                            ? CampusColors.primary
                                            : CampusColors.muted,
                                      ),
                                      child: Text(
                                        dateLabel(week['start_date']),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (selectedIndex >= 0)
              TweenAnimationBuilder<double>(
                key: ValueKey('semester-week-position-$animate'),
                tween: Tween<double>(
                  end: selectedIndex * slotWidth + (slotWidth - diskSize) / 2,
                ),
                duration: duration,
                curve: Curves.easeOutCubic,
                builder: (context, position, _) => PositionedDirectional(
                  start: position,
                  top: 8 + labelHeight,
                  width: diskSize,
                  height: diskSize,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: ClipOval(
                        child: DecoratedBox(
                          key: const Key('semester-week-indicator'),
                          decoration: const BoxDecoration(
                            color: CampusColors.primary,
                            shape: BoxShape.circle,
                          ),
                          // Numerals stay in their slots. The white projection
                          // is clipped by the moving disk, so contrast follows
                          // its actual position even when a tap interrupts it.
                          child: Stack(
                            children: [
                              PositionedDirectional(
                                start: -position,
                                top: 0,
                                width: weeks.length * slotWidth,
                                height: diskSize,
                                child: Row(
                                  children: [
                                    for (final week in weeks)
                                      SizedBox(
                                        width: slotWidth,
                                        height: diskSize,
                                        child: Center(
                                          child: Text(
                                            '${week['week']}',
                                            style: numberStyle.copyWith(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The latest week is always readable. Incoming content settles into place while
/// the surrounding layout follows its height without overlapping old text.
class _SemesterWeekContent extends StatelessWidget {
  final String week;
  final int direction;
  final bool animate;
  final Widget child;
  const _SemesterWeekContent({
    required this.week,
    required this.direction,
    required this.animate,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final currentKey = ValueKey('semester-week-content-$week');
    if (!animate) {
      return ClipRect(
        child: KeyedSubtree(key: currentKey, child: child),
      );
    }
    const duration = Duration(milliseconds: 230);
    return AnimatedSize(
      key: ValueKey('semester-week-size-$animate'),
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: AnimatedSwitcher(
          key: ValueKey('semester-week-switch-$animate'),
          duration: duration,
          reverseDuration: const Duration(milliseconds: 150),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: Tween<double>(begin: .65, end: 1).animate(animation),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(direction * .035, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          layoutBuilder: (currentChild, previousChildren) =>
              currentChild ?? const SizedBox.shrink(),
          child: KeyedSubtree(key: currentKey, child: child),
        ),
      ),
    );
  }
}

class _SemesterAction extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget icon, label;
  final bool primary;
  const _SemesterAction({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.primary = false,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: (MediaQuery.sizeOf(context).width - 40) / 5,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme(
                data: const IconThemeData(
                  color: CampusColors.primary,
                  size: 22,
                ),
                child: icon,
              ),
              const SizedBox(height: 8),
              DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 12, color: CampusColors.ink),
                child: label,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// Date-only records sort at the start of their Shanghai day, without assigning
// an appointment time. Exact instants may carry different serialized offsets.
DateTime timelineInstant(dynamic value) {
  final text = '$value';
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    return DateTime.parse('${text}T00:00:00+08:00').toUtc();
  }
  return DateTime.tryParse(text)?.toUtc() ?? DateTime.utc(9999);
}

String _courseSummary(Map<String, dynamic> course) => [
  if ('${course['teacher'] ?? ''}'.trim().isNotEmpty) '${course['teacher']}',
  if ((course['task_count'] as num? ?? 0) > 0) '待办 ${course['task_count']}',
  if ((course['exam_count'] as num? ?? 0) > 0) '考试 ${course['exam_count']}',
].join(' · ');
