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
import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../ui/v2/shiri_tokens.dart' as v2;
import '../../ui/v2/motion/rolling_number.dart';
import '../../ui/v2/motion/pressable.dart';
import 'semester_horizon.dart';

String semesterActivityTimeLabel(Map<String, dynamic> row) {
  if (row['start_at'] == null || calendarMeaning(row) == 'window') {
    return calendarTimeLabel(row);
  }
  final start = schoolTime(row['start_at']);
  if (row['end_at'] == null) return hhmm(start);
  final end = schoolTime(row['end_at']);
  if (start.year == end.year &&
      start.month == end.month &&
      start.day == end.day) {
    return '${hhmm(start)}—${hhmm(end)}';
  }
  return calendarTimeLabel(row);
}

class SemesterHome extends StatefulWidget {
  final ItemsController controller;
  final VoidCallback onManage;
  final bool active;
  final int entryEpoch;
  const SemesterHome({
    super.key,
    required this.controller,
    required this.onManage,
    this.active = true,
    this.entryEpoch = 0,
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
  double get _weekWidth {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: base.merge(style)),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    var width = 64.0;
    for (final week in widget.controller.rows(_adopted?['weeks'])) {
      width = math.max(
        width,
        measure(
              '${week['week']}',
              const TextStyle(
                fontSize: 28,
                height: 1.15,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ) +
            24,
      );
      width = math.max(
        width,
        measure(
              _nodeDate(week['start_date']),
              const TextStyle(
                fontSize: 12,
                height: 1.25,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ) +
            24,
      );
    }
    return width;
  }

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
  }) {
    final accent = warning ? CampusColors.warning : CampusColors.teal;
    final details = [
      if (at != null) _nodeDate(at),
      if (time.isNotEmpty && !(at == null && RegExp(r'^第\d+周$').hasMatch(time)))
        time,
      label,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: '${at == null ? '' : '${_nodeDate(at)}，'}$label，$title，$time',
        onTap: onTap,
        child: ExcludeSemantics(
          child: Material(
            color: CampusColors.surface,
            borderRadius: BorderRadius.circular(16),
            child: Pressable(
              onPressed: onTap,
              haptic: true,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, color: accent, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            details,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: warning
                                  ? CampusColors.warning
                                  : CampusColors.muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
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
      ),
    );
  }

  Widget _semesterCaption(String name) {
    const style = TextStyle(
      fontSize: 16,
      color: CampusColors.primary,
      fontWeight: FontWeight.w700,
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

  Widget _semesterHeader(Map<String, dynamic> data) {
    final semester = Map<String, dynamic>.from(data['semester']);
    final weeks = widget.controller.rows(data['weeks']);
    final current = _currentWeek(semester);
    final total = semester['total_weeks'] as int;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _semesterCaption('${semester['name']}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (current >= 1 && current <= total)
                RollingNumber.text(
                  '第$current周',
                  style: const TextStyle(
                    fontSize: 44,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: CampusColors.ink,
                  ),
                )
              else
                Text(
                  current < 1 ? '学期尚未开始' : '本学期已结束',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(
                '共$total周 · 还剩${(total - current.clamp(0, total)).clamp(0, total)}周',
                style: const TextStyle(
                  fontSize: 14,
                  color: CampusColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SemesterHorizon(
            current: current,
            total: total,
            active: widget.active && _foreground,
            entryEpoch: widget.entryEpoch,
            examWeeks: {
              for (final w in weeks)
                if (widget.controller
                    .rows(w['items'])
                    .any((i) => i['kind'] == 'exam'))
                  w['week'] as int,
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => HubData(
    key: _hub,
    controller: widget.controller,
    path: '/semesters/${widget.controller.semesterId}/hub',
    headerBuilder: (context, data, fresh, load) => _semesterHeader(data),
    builder: (context, data, fresh, load) {
      if (!identical(_adopted, data)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _adopt(data));
      }
      final semester = Map<String, dynamic>.from(data['semester']);
      final weeks = widget.controller.rows(data['weeks']);
      final current = _currentWeek(semester);
      final selected = weeks.where((w) => w['week'] == _selected).firstOrNull;
      final weekItems = widget.controller.rows(selected?['items']);
      final weekChanges = widget.controller.rows(selected?['changes']);
      final exams = weekItems.where((item) => item['kind'] == 'exam').length;
      final otherItems = weekItems.length - exams;
      final animate = _foreground && AppMotion.allowed(context);
      final undatedEvents = _calendar.undated
          .where((e) => e['resource_type'] == 'event')
          .toList();
      final events =
          <Map<String, dynamic>>[
            for (final item in weekItems)
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
                      '${studentDate(DateTime.parse(selected['start_date']))}—${studentDate(DateTime.parse(selected['end_date']))}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (weekItems.isNotEmpty || weekChanges.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        [
                          if (exams > 0) '考试 $exams 场',
                          if (otherItems > 0) '待办 $otherItems 项',
                          if (weekChanges.isNotEmpty)
                            '课程变更 ${weekChanges.length} 项',
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
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
                          ItemCard(
                            item: Map<String, dynamic>.from(e['row']),
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
                            time: semesterActivityTimeLabel(e['row']),
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
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Column(
                            children: [
                              SvgPicture.asset(
                                'assets/illustrations/empty-week.svg',
                                width: 180,
                                height: 135,
                                excludeFromSemantics: true,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                '这一周还没有记录截止事项、考试或活动',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: CampusColors.muted),
                              ),
                            ],
                          ),
                        ),
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
          const SizedBox(height: 28),
          const SectionHeading('学期资料'),
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
                  detail: data['courses'] is List
                      ? '${widget.controller.rows(data['courses']).length} 门'
                      : null,
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
                  detail: data['exams'] is List
                      ? '${widget.controller.rows(data['exams']).length} 场'
                      : null,
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
                  onPressed: () => context.push('/import'),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('导入课表'),
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

class _SemesterWeekStrip extends StatefulWidget {
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
  State<_SemesterWeekStrip> createState() => _SemesterWeekStripState();
}

class _SemesterWeekStripState extends State<_SemesterWeekStrip>
    with SingleTickerProviderStateMixin {
  int get index => math.max(
    0,
    widget.weeks.indexWhere((week) => week['week'] == widget.selected),
  );
  late final AnimationController position;

  @override
  void initState() {
    super.initState();
    position = AnimationController.unbounded(
      vsync: this,
      value: index.toDouble(),
    );
  }

  @override
  void didUpdateWidget(covariant _SemesterWeekStrip old) {
    super.didUpdateWidget(old);
    if (old.selected == null || !widget.animate) {
      position
        ..stop()
        ..value = index.toDouble();
    } else if (position.value != index.toDouble()) {
      position.animateWith(
        SpringSimulation(
          v2.ShiriMotion.snappy,
          position.value,
          index.toDouble(),
          position.velocity,
          snapToEnd: true,
        ),
      );
    }
  }

  @override
  void dispose() {
    position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final base = DefaultTextStyle.of(context).style;
    final numberStyle = base.merge(
      const TextStyle(
        fontSize: 28,
        height: 1.15,
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
    final dateStyle = base.merge(
      const TextStyle(
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w500,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
    final labelStyle = base.merge(
      const TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w600),
    );
    double textHeight(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scale,
      )..layout(maxWidth: widget.slotWidth - 8);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final numberHeight = widget.weeks.fold<double>(
      0,
      (height, week) =>
          math.max(height, textHeight('${week['week']}', numberStyle)),
    );
    final dateHeight = widget.weeks.fold<double>(
      0,
      (height, week) => math.max(
        height,
        textHeight(widget.dateLabel(week['start_date']), dateStyle),
      ),
    );
    final height =
        textHeight('本周', labelStyle) + numberHeight + dateHeight + 44;
    Widget face(Map<String, dynamic> week, {required bool selected}) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          week['week'] == widget.current ? '本周' : ' ',
          style: labelStyle.copyWith(
            color: selected ? Colors.white : v2.ShiriBrand.sunInk,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${week['week']}',
          maxLines: 1,
          softWrap: false,
          style: numberStyle.copyWith(
            color: selected ? Colors.white : CampusColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.dateLabel(week['start_date']),
          maxLines: 1,
          softWrap: false,
          style: dateStyle.copyWith(
            color: selected ? Colors.white : CampusColors.muted,
          ),
        ),
      ],
    );
    return RepaintBoundary(
      child: SizedBox(
        width: widget.weeks.length * widget.slotWidth,
        height: height,
        child: Stack(
          children: [
            Row(
              children: [
                for (final week in widget.weeks)
                  SizedBox(
                    width: widget.slotWidth,
                    height: height,
                    child: Semantics(
                      key: ValueKey('semester-week-${week['week']}'),
                      button: true,
                      selected: widget.selected == week['week'],
                      label:
                          '第${week['week']}周，${widget.dateLabel(week['start_date'])}开始${week['week'] == widget.current ? '，本周' : ''}',
                      onTap: () => widget.onSelected(week['week'] as int),
                      child: ExcludeSemantics(
                        child: Pressable(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            widget.onSelected(week['week'] as int);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: CampusColors.surface,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: face(week, selected: false),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (widget.weeks.any((w) => w['week'] == widget.selected))
              AnimatedBuilder(
                animation: position,
                builder: (context, _) {
                  final x = position.value * widget.slotWidth + 4;
                  return PositionedDirectional(
                    start: x,
                    top: 3,
                    width: widget.slotWidth - 8,
                    height: height - 6,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: DecoratedBox(
                            key: const Key('semester-week-indicator'),
                            decoration: const BoxDecoration(
                              color: CampusColors.primary,
                            ),
                            child: Stack(
                              children: [
                                PositionedDirectional(
                                  start: -x,
                                  top: 0,
                                  width: widget.weeks.length * widget.slotWidth,
                                  height: height - 6,
                                  child: Row(
                                    children: [
                                      for (final week in widget.weeks)
                                        SizedBox(
                                          width: widget.slotWidth,
                                          child: face(week, selected: true),
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
                  );
                },
              ),
            Row(
              children: [
                for (final week in widget.weeks)
                  SizedBox(
                    width: widget.slotWidth,
                    height: height,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Stack(
                          children: [
                            if (week['week'] == widget.current)
                              Positioned(
                                top: 9,
                                right: 12,
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: v2.ShiriBrand.sun500,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            if ((week['items'] as List? ?? [])
                                .whereType<Map>()
                                .any((i) => i['kind'] == 'exam'))
                              Positioned(
                                bottom: 8,
                                left: (widget.slotWidth - 5) / 2,
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: v2.ShiriColors.light.dangerAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
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
    const duration = v2.ShiriMotion.standard;
    return AnimatedSize(
      key: ValueKey('semester-week-size-$animate'),
      duration: duration,
      curve: v2.ShiriMotion.easeStandard,
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: AnimatedSwitcher(
          key: ValueKey('semester-week-switch-$animate'),
          duration: duration,
          reverseDuration: v2.ShiriMotion.quick,
          switchInCurve: v2.ShiriMotion.easeDecelerate,
          switchOutCurve: v2.ShiriMotion.easeAccelerate,
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
  final String? detail;
  const _SemesterAction({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.primary = false,
    this.detail,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width:
        (MediaQuery.sizeOf(context).width - 40) /
        (MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 2 : 3),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primary
                      ? CampusColors.blueSoft
                      : CampusColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconTheme(
                  data: const IconThemeData(
                    color: CampusColors.primary,
                    size: 22,
                  ),
                  child: icon,
                ),
              ),
              const SizedBox(height: 8),
              DefaultTextStyle.merge(
                style: const TextStyle(
                  fontSize: 14,
                  color: CampusColors.ink,
                  fontWeight: FontWeight.w600,
                ),
                child: label,
              ),
              if (detail != null) ...[
                const SizedBox(height: 4),
                Text(
                  detail!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: CampusColors.muted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
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
