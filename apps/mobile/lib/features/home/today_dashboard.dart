import '../../ui/app_controls.dart';
import '../../ui/app_sheet.dart';
import '../../ui/app_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import '../items/item_actions.dart';
import '../../core/api.dart' show userError;
import '../calendar/calendar_repository.dart';
import '../calendar/time_track.dart';
import '../../ui/campus_theme.dart';
import '../../ui/assistant_scope.dart';
import 'home_preferences.dart';
import 'day_brief_controller.dart';
import 'today_view_enhanced.dart';
import 'week_heatmap.dart';
import 'semester_progress.dart';
import 'time_stats_card.dart';
import 'study_opportunity_card.dart';
import '../planning/proposal_page.dart';
import '../../ui/breathing_exercise_card.dart';
import '../../ui/time_urgency.dart';
import '../../ui/v2/shiri_tokens.dart';
import 'next_schedule_card.dart';
import 'opportunity_inline_preview.dart';
import 'exam_countdown_card.dart';
import 'today_loading.dart';
import 'today_sky_header.dart';

class TodayDashboard extends StatefulWidget {
  final AppController app;
  final ItemsController items;
  final VoidCallback onCalendar;
  final ValueChanged<DateTime>? onCalendarDay;
  final ValueChanged<Map<String, dynamic>>? onTaskEdit;
  final VoidCallback? onAllTasks;
  final Future<void> Function()? onRetry;
  final DateTime Function()? now;
  final bool showHeader;
  const TodayDashboard({
    super.key,
    required this.app,
    required this.items,
    required this.onCalendar,
    this.onCalendarDay,
    this.onTaskEdit,
    this.onAllTasks,
    this.onRetry,
    this.now,
    this.showHeader = true,
  });
  @override
  State<TodayDashboard> createState() => TodayDashboardState();
}

class TodayDashboardState extends State<TodayDashboard>
    with WidgetsBindingObserver {
  late final DayBriefController brief;
  late final CalendarRepository weekly;
  late final HomePreferences preferences;
  MinuteClock? clock;
  bool arrangingOpportunity = false;
  Map<String, dynamic>? _opportunityPreview,
      _opportunityReceipt,
      _displayOpportunity,
      _opportunitySource;
  String? _opportunityError;
  late final String semesterId;
  late final String owner;
  late final int generation;
  int? revision;
  String? _weekRequestKey;
  bool _weekRefreshQueued = false;
  bool active = true, foreground = true;
  int get expectedRevision {
    final calendar = widget.app.semester?['revision'] as int? ?? 0;
    final items = widget.items.itemsRevision ?? 0;
    return calendar > items ? calendar : items;
  }

  DateTime get now => widget.now?.call() ?? schoolNow();
  DateTime get day => DateTime.utc(now.year, now.month, now.day);
  DateTime get weekStart => day.subtract(Duration(days: day.weekday - 1));
  bool get needsWeek =>
      preferences.enabled.contains('week_heatmap') ||
      preferences.enabled.contains('time_stats');
  String get weekRequestKey => '${calendarDate(weekStart)}:$expectedRevision';
  bool get completeWeek =>
      weekly.data != null &&
      weekly.data?['from_date'] == calendarDate(weekStart) &&
      weekly.data?['to_date'] ==
          calendarDate(weekStart.add(const Duration(days: 6))) &&
      weekly.revision != null &&
      weekly.revision! >= (revision ?? 0);
  bool get displayWeek =>
      sameSemester &&
      widget.app.api.session?['user']?['id'] == owner &&
      widget.app.api.generation == generation &&
      weekly.data?['semester_id'] == sid &&
      weekly.data?['from_date'] == calendarDate(weekStart) &&
      weekly.data?['to_date'] ==
          calendarDate(weekStart.add(const Duration(days: 6))) &&
      weekly.revision != null;
  String get sid => semesterId;
  bool get sameSemester =>
      widget.app.semester?['id'] == semesterId &&
      widget.items.semesterId == semesterId &&
      widget.items.owner == owner &&
      widget.items.api.session?['user']?['id'] == owner &&
      widget.items.api.generation == generation;
  @override
  void initState() {
    super.initState();
    semesterId = widget.app.semester!['id'];
    owner = widget.items.owner!;
    generation = widget.items.api.generation;
    WidgetsBinding.instance.addObserver(this);
    final semester = sid;
    preferences = HomePreferences(
      widget.items.cache,
      owner,
      semester,
      () =>
          generation == widget.items.api.generation &&
          owner == widget.items.owner &&
          owner == widget.items.api.session?['user']?['id'] &&
          semester == widget.items.semesterId,
    );
    preferences.addListener(changed);
    preferences.restore().catchError((Object _) {});
    brief = DayBriefController(widget.app.api, widget.app.cache)
      ..addListener(changed);
    weekly = CalendarRepository(widget.app.api, widget.app.cache)
      ..addListener(changed);
    widget.items.addListener(changed);
    revision = expectedRevision;
    reload();
    updateClock();
  }

  void updateClock() {
    if (!active || !foreground || !sameSemester) {
      clock?.cancel();
      clock = null;
      return;
    }
    if (clock != null) return;
    clock = MinuteClock(() {
      if (!active || !foreground || !mounted || !sameSemester) return;
      if (!brief.busy &&
          (brief.data?['date'] != calendarDate(day) ||
              !brief.fresh(revision ?? 0))) {
        reload();
      } else {
        setState(() {});
      }
    }, now: () => now);
  }

  void changed() {
    if (!mounted) return;
    if (!sameSemester) {
      updateClock();
      if (active) setState(() {});
      return;
    }
    if (revision != expectedRevision) {
      revision = expectedRevision;
      if (active && foreground) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && active && foreground) reload();
        });
      }
    }
    queueWeekIfNeeded();
    if (active) setState(() {});
  }

  void queueWeekIfNeeded() {
    if (!needsWeek ||
        !active ||
        !foreground ||
        !sameSemester ||
        _weekRequestKey == weekRequestKey ||
        _weekRefreshQueued) {
      return;
    }
    _weekRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _weekRefreshQueued = false;
      if (mounted) loadWeekIfNeeded();
    });
  }

  Future<void> loadWeekIfNeeded({bool force = false}) async {
    if (!mounted ||
        !needsWeek ||
        !active ||
        !foreground ||
        !sameSemester ||
        (!force && _weekRequestKey == weekRequestKey)) {
      return;
    }
    _weekRequestKey = weekRequestKey;
    await weekly.load(sid, weekStart);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final was = active;
    active = TickerMode.valuesOf(context).enabled;
    updateClock();
    queueWeekIfNeeded();
    if (active &&
        !was &&
        (brief.data?['date'] != calendarDate(day) ||
            !brief.fresh(revision ?? 0))) {
      reload();
    }
  }

  @override
  void didUpdateWidget(covariant TodayDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!sameSemester) {
      updateClock();
      return;
    }
    if (revision != expectedRevision) {
      revision = expectedRevision;
      if (active) reload();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    updateClock();
    if (foreground && active) reload(forceWeek: weekly.offline);
  }

  Future<void> reload({bool forceWeek = false}) async {
    if (mounted && sameSemester) {
      await Future.wait([
        brief.load(sid, day),
        loadWeekIfNeeded(force: forceWeek),
      ]);
    }
  }

  Future<void> retry() => widget.onRetry?.call() ?? reload(forceWeek: true);

  @override
  void dispose() {
    clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.items.removeListener(changed);
    preferences.dispose();
    brief.dispose();
    weekly.dispose();
    super.dispose();
  }

  DateTime? at(dynamic value) => value is String
      ? DateTime.tryParse(value)?.toUtc().add(const Duration(hours: 8))
      : null;
  Future<void> open(Map<String, dynamic> row) async {
    // Calendar plan entries expose resource_id as the associated StudyItem id.
    // A raw plan block may instead provide item_id; its own id is never a task.
    final id = row['resource_type'] == 'plan'
        ? row['item_id'] ?? row['resource_id']
        : row['resource_id'] ?? row['id'];
    if (id == null) return;
    await context.push(switch (row['resource_type']) {
      'course' =>
        '/courses/$id?occurrence=${Uri.encodeQueryComponent('${row['id']}')}',
      'event' => '/events/$id',
      'exam' => '/exams/$id',
      _ => '/items/$id',
    });
    if (mounted) await reload();
  }

  DateTime? deadline(Map<String, dynamic> item) {
    final t = Map<String, dynamic>.from(item['time'] ?? {});
    if (item['kind'] != 'exam' &&
        {
          'window',
          'start',
          'candidate',
          'course_anchor',
        }.contains(t['meaning'])) {
      return null;
    }
    if (t['precision'] == 'date' && t['date'] is String) {
      // Group an all-day deadline by its stated date, even when its confirmed
      // reminder anchor is the following midnight.
      return DateTime.tryParse('${t['date']}T00:00:00Z');
    }
    return (item['kind'] == 'exam'
            ? at(item['anchor_at'] ?? t['at'])
            : itemDeadline(item, schoolClock: true)) ??
        (t['precision'] == 'date' && t['date'] is String
            ? DateTime.tryParse('${t['date']}T00:00:00Z')
            : null);
  }

  Future<void> completeTask(Map<String, dynamic> item) async {
    if (!mounted || !sameSemester) return;
    try {
      await completeItemWithUndo(context, widget.items, item);
    } catch (error) {
      if (mounted && sameSemester) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    }
  }

  Future<void> arrangeOpportunity(Map<String, dynamic> opportunity) async {
    if (arrangingOpportunity || !sameSemester) return;
    setState(() {
      arrangingOpportunity = true;
      _opportunityError = null;
      _opportunityReceipt = null;
      if (_opportunityPreview == null) _displayOpportunity = opportunity;
      _opportunitySource = Map<String, dynamic>.from(opportunity);
    });
    try {
      final p = await widget.items.generateSchedule(
        {
          'days': 1,
          'lead_minutes': 0,
          'tasks': [
            {'item_id': opportunity['item_id']},
          ],
          'window_start_at': opportunity['start_at'],
          'window_end_at': opportunity['end_at'],
        },
        idempotencyKey: 'opportunity-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted || !sameSemester) return;
      final blocks = widget.items.rows(p['blocks']);
      final taskRows = widget.items.rows(p['tasks']);
      final simple =
          p['mode'] != 'replan' &&
          p['status'] == 'FEASIBLE_COMPLETE' &&
          blocks.length == 1 &&
          taskRows.length == 1 &&
          (taskRows.single['existing_minutes'] ?? 0) == 0 &&
          (taskRows.single['later_minutes'] ?? 0) == 0;
      final display = simple ? proposalOpportunity(p) : null;
      if (display != null) {
        setState(() {
          _opportunityPreview = p;
          _displayOpportunity = display;
        });
        return;
      }
      setState(() {
        _opportunityPreview = null;
        _displayOpportunity = null;
      });
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProposalPage(controller: widget.items, proposal: p),
        ),
      );
      if (mounted && sameSemester) await reload();
    } catch (error) {
      if (mounted && sameSemester) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted && sameSemester) setState(() => arrangingOpportunity = false);
    }
  }

  Map<String, dynamic>? proposalOpportunity(Map<String, dynamic> p) {
    final blocks = widget.items.rows(p['blocks']),
        tasks = widget.items.rows(p['tasks']);
    if (blocks.length != 1 || tasks.length != 1) return null;
    return opportunityDisplay(
      blocks.single,
      tasks.single,
      needsCheck: widget.items.rows(p['uncertainty_warnings']).isNotEmpty,
    );
  }

  Map<String, dynamic>? opportunityDisplay(
    Map<String, dynamic> block,
    Map<String, dynamic> task, {
    bool needsCheck = false,
    bool saved = false,
  }) {
    final start = DateTime.tryParse('${block['start_at']}'),
        end = DateTime.tryParse('${block['end_at']}');
    if (start == null || end == null || !end.isAfter(start)) return null;
    final minutes = block['minutes'] is num
        ? (block['minutes'] as num).toInt()
        : end.difference(start).inMinutes;
    final id = block['item_id'] ?? task['item_id'];
    if (minutes <= 0 || id == null) return null;
    return {
      'item_id': id,
      'title': block['title'] ?? task['title'] ?? '',
      'target_minutes': minutes,
      'already_planned_minutes': task['existing_minutes'],
      'start_at': block['start_at'],
      'end_at': block['end_at'],
      'latest_start_at': block['start_at'],
      'needs_check': needsCheck,
      'display_phase': saved ? 'saved' : 'proposal',
    };
  }

  Widget opportunityHistory(String status) => Container(
    key: const Key('opportunity-saved-history'),
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: context.shiri.cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.history_rounded,
              size: 20,
              color: CampusColors.muted,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '保存记录',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            AppTextButton(
              onPressed: arrangingOpportunity ? null : undoOpportunity,
              child: const Text('撤销'),
            ),
          ],
        ),
        if ('${_displayOpportunity?['title'] ?? ''}'.isNotEmpty)
          Text('${_displayOpportunity!['title']}'),
        const SizedBox(height: 4),
        Text(
          displayInterval(
            _displayOpportunity?['start_at'],
            _displayOpportunity?['end_at'],
          ),
          style: const TextStyle(color: CampusColors.muted, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Text(
          status,
          style: const TextStyle(color: CampusColors.muted, fontSize: 14),
        ),
        if (_opportunityError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _opportunityError!,
              style: const TextStyle(color: CampusColors.error),
            ),
          ),
      ],
    ),
  );

  Future<void> saveOpportunity() async {
    final p = _opportunityPreview;
    if (p == null || arrangingOpportunity || !sameSemester) return;
    setState(() {
      arrangingOpportunity = true;
      _opportunityError = null;
    });
    try {
      final receipt = await widget.items.acceptSchedule(p, false);
      if (!mounted || !sameSemester) return;
      setState(() {
        _opportunityReceipt = receipt;
        _displayOpportunity = {
          ...?_displayOpportunity,
          'display_phase': 'saved',
        };
        _opportunityPreview = null;
      });
      await reload();
    } catch (error) {
      if (mounted && sameSemester) {
        setState(() => _opportunityError = userError(error));
      }
    } finally {
      if (mounted && sameSemester) setState(() => arrangingOpportunity = false);
    }
  }

  Future<void> undoOpportunity() async {
    final r = _opportunityReceipt;
    if (r == null || arrangingOpportunity || !sameSemester) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AppDialog(
        title: const Text('撤销最近一次安排？'),
        content: const Text('撤销本次新增或调整的学习安排。已开始或后来修改过的安排会保留。'),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('返回'),
          ),
          AppButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('确认撤销'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || !sameSemester) return;
    setState(() {
      arrangingOpportunity = true;
      _opportunityError = null;
    });
    try {
      await widget.items.undoSchedule({
        'id': r['proposal_id'],
        'version': r['proposal_version'],
      }, r['revision']);
      if (!mounted || !sameSemester) return;
      setState(() {
        _opportunityReceipt = null;
        _displayOpportunity = null;
      });
      await reload();
    } catch (error) {
      if (mounted && sameSemester) {
        setState(() => _opportunityError = userError(error));
      }
    } finally {
      if (mounted && sameSemester) setState(() => arrangingOpportunity = false);
    }
  }

  bool upcoming(Map<String, dynamic> item) {
    final exact = deadline(item), until = day.add(const Duration(days: 8));
    if (exact != null) return !exact.isBefore(day) && exact.isBefore(until);
    final t = Map<String, dynamic>.from(item['time'] ?? {});
    DateTime? begin, end;
    if (t['precision'] == 'week' && t['week'] is int) {
      begin = DateTime.parse(
        '${widget.app.semester!['first_monday']}T00:00:00Z',
      ).add(Duration(days: ((t['week'] as int) - 1) * 7));
      end = begin.add(const Duration(days: 7));
    } else if (t['precision'] == 'range' &&
        t['date'] is String &&
        t['end_date'] is String) {
      begin = DateTime.tryParse('${t['date']}T00:00:00Z');
      end = DateTime.tryParse(
        '${t['end_date']}T00:00:00Z',
      )?.add(const Duration(days: 1));
    }
    return begin != null &&
        end != null &&
        begin.isBefore(until) &&
        end.isAfter(day);
  }

  Future<void> savePreferences({
    List<String>? order,
    Set<String>? enabled,
    TodayViewMode? todayView,
  }) async {
    try {
      await preferences.change(
        order: order,
        enabled: enabled,
        todayView: todayView,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('本机设置未保存，请重试')));
      }
    }
  }

  Future<void> editModules() async {
    await showAppSheet<void>(
      context: context,
      heightFactor: .82,
      builder: (context) => AnimatedBuilder(
        animation: preferences,
        builder: (context, _) {
          final visibleOrder = preferences.order
              .where(
                (id) =>
                    preferences.todayView == TodayViewMode.schedule ||
                    id != 'deadlines',
              )
              .toList();
          return Column(
            children: [
              AppSheetHeading(
                title: '首页内容',
                subtitle: '拖动排序，选择要显示的内容',
                showClose: false,
                trailing: AppTextButton(
                  guardAsync: false,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('完成'),
                ),
              ),
              Padding(
                key: const Key('home-view-setting'),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: AppPickerField<TodayViewMode>(
                  initialValue: preferences.todayView ?? TodayViewMode.overview,
                  decoration: const InputDecoration(labelText: '首页视图'),
                  items: const [
                    DropdownMenuItem(
                      value: TodayViewMode.overview,
                      child: Text('日程与待办'),
                    ),
                    DropdownMenuItem(
                      value: TodayViewMode.schedule,
                      child: Text('仅日程'),
                    ),
                    DropdownMenuItem(
                      value: TodayViewMode.tasks,
                      child: Text('仅待办'),
                    ),
                  ],
                  onChanged: (value) => savePreferences(todayView: value),
                ),
              ),
              Expanded(
                child: ReorderableListView(
                  buildDefaultDragHandles: false,
                  onReorderItem: (oldIndex, newIndex) {
                    final reordered = [...visibleOrder];
                    final id = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, id);
                    final next = preferences.order
                        .map(
                          (id) => visibleOrder.contains(id)
                              ? reordered.removeAt(0)
                              : id,
                        )
                        .toList();
                    savePreferences(order: next);
                  },
                  children: [
                    for (var i = 0; i < visibleOrder.length; i++)
                      Row(
                        key: ValueKey(visibleOrder[i]),
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: const SizedBox(
                              width: 48,
                              height: 48,
                              child: Tooltip(
                                message: '拖动排序',
                                child: Icon(
                                  Icons.drag_indicator_rounded,
                                  size: 20,
                                  color: CampusColors.muted,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: AppSwitchRow(
                              contentPadding: const EdgeInsets.fromLTRB(
                                0,
                                10,
                                20,
                                10,
                              ),
                              title: Text(homeModules[visibleOrder[i]]!),
                              value: preferences.enabled.contains(
                                visibleOrder[i],
                              ),
                              onChanged: (value) {
                                final enabled = {...preferences.enabled};
                                value
                                    ? enabled.add(visibleOrder[i])
                                    : enabled.remove(visibleOrder[i]);
                                savePreferences(enabled: enabled);
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppTextButton(
                    onPressed: () => savePreferences(
                      todayView: TodayViewMode.overview,
                      order: homeModules.keys.toList(),
                      enabled: {...defaultHomeModules},
                    ),
                    child: const Text('恢复默认'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Duration get motionDuration =>
      MediaQuery.disableAnimationsOf(context) ||
          MediaQuery.accessibleNavigationOf(context) ||
          !active ||
          !foreground
      ? Duration.zero
      : const Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    if (!sameSemester) return const SizedBox.shrink();
    if (brief.data == null && brief.busy) {
      return frame(const TodayLoadingBody());
    }
    final entries = brief.entries;
    final timeline =
        entries
            .where(
              (r) =>
                  const [
                    'course',
                    'event',
                    'exam',
                    'plan',
                  ].contains(r['resource_type']) &&
                  r['start_at'] != null &&
                  calendarMeaning(r) != 'window',
            )
            .toList()
          ..sort(
            (a, b) =>
                (at(a['occupancy_start_at'] ?? a['start_at']) ??
                        DateTime.utc(9999))
                    .compareTo(
                      at(b['occupancy_start_at'] ?? b['start_at']) ??
                          DateTime.utc(9999),
                    ),
          );
    final tasks =
        widget.items.items
            .where((r) => r['lifecycle'] == 'active' && r['kind'] != 'exam')
            .toList()
          ..sort(
            (a, b) => (deadline(a) ?? DateTime.utc(9999)).compareTo(
              deadline(b) ?? DateTime.utc(9999),
            ),
          );
    final urgent = tasks
        .where(
          (t) =>
              t['priority'] == 'high' ||
              (itemDeadline(t, schoolClock: true) != null &&
                  itemDeadline(
                    t,
                    schoolClock: true,
                  )!.isBefore(now.add(const Duration(hours: 12)))),
        )
        .firstOrNull;
    final nextRows =
        entries
            .where(
              (r) =>
                  r['start_at'] != null &&
                  calendarReservesTime(r) &&
                  calendarMeaning(r) != 'window' &&
                  ((at(r['end_at'])?.isAfter(now) ?? false) ||
                      !at(r['start_at'])!.isBefore(now)),
            )
            .toList()
          ..sort(
            (a, b) => at(
              a['occupancy_start_at'] ?? a['start_at'],
            )!.compareTo(at(b['occupancy_start_at'] ?? b['start_at'])!),
          );
    final next = nextRows.firstOrNull;
    final dayFinished =
        timeline.isNotEmpty &&
        timeline.every(
          (r) => at(r['end_at']) != null && !at(r['end_at'])!.isAfter(now),
        );
    final tomorrow = briefRows(brief.data?['next_day']?['entries'])
        .where(
          (r) => const [
            'course',
            'event',
            'exam',
            'plan',
          ].contains(r['resource_type']),
        )
        .map(calendarDisplayEntry)
        .toList();
    final nextDate = day.add(const Duration(days: 1));
    final tomorrowTasks = tasks.where((t) {
      final due = deadline(t);
      return due != null && calendarDate(due) == calendarDate(nextDate);
    }).toList();
    final showTomorrow =
        (now.hour >= 17 || next == null) &&
        (tomorrow.isNotEmpty || tomorrowTasks.isNotEmpty);
    final otherDay = entries
        .where(
          (r) =>
              const ['course', 'event', 'exam'].contains(r['resource_type']) &&
                  (r['start_at'] == null || calendarMeaning(r) == 'window') ||
              const [
                    'deadline',
                    'task',
                    'item',
                    'assignment',
                  ].contains(r['resource_type']) &&
                  const ['window', 'start'].contains(calendarMeaning(r)),
        )
        .toList();
    final viewMode =
        preferences.todayView ??
        defaultTodayViewMode(
          events: timeline.length + otherDay.length,
          tasks: tasks.length,
        );
    final overviewTasks = [...tasks];
    final urgentIndex = overviewTasks.indexWhere(
      (t) => t['id'] == urgent?['id'],
    );
    if (urgentIndex > 0) {
      overviewTasks.insert(0, overviewTasks.removeAt(urgentIndex));
    }
    final visibleTaskIds = {
      if (viewMode == TodayViewMode.overview)
        ...overviewTasks.take(3).map((t) => t['id']),
      if (viewMode == TodayViewMode.schedule && urgent != null) urgent['id'],
    };
    final tomorrowPreviewTasks = tomorrowTasks
        .where((t) => !visibleTaskIds.contains(t['id']))
        .toList();
    final tomorrowVisible =
        showTomorrow &&
        viewMode != TodayViewMode.tasks &&
        (tomorrow.isNotEmpty || tomorrowPreviewTasks.isNotEmpty);
    final stockOrder =
        preferences.order.join('|') == homeModules.keys.join('|');
    final earlyGap = stockOrder && preferences.enabled.contains('windows');
    return frame(
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.sizeOf(context).width <= 360
              ? ShiriSpace.pageCompact
              : ShiriSpace.page,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (next != null && viewMode != TodayViewMode.tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NextScheduleCard(
                  row: next,
                  now: now,
                  onOpen: () => open(next),
                ),
              ),
            if (next == null || viewMode == TodayViewMode.tasks)
              const SizedBox(height: 12),
            if (brief.offline)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 20,
                      color: CampusColors.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        brief.data == null ? '暂时无法读取今日安排' : '离线查看已保存安排',
                        style: const TextStyle(
                          color: CampusColors.muted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    AppTextButton(
                      onPressed: brief.busy ? null : retry,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            if (earlyGap) module('windows', tasks, urgent),
            if (viewMode != TodayViewMode.overview)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final title = switch (viewMode) {
                      TodayViewMode.overview => '今日总览',
                      TodayViewMode.tasks => '待办任务',
                      TodayViewMode.schedule => '全天安排',
                    };
                    const titleStyle = TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    );
                    const actionStyle = TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    );
                    double width(String value, TextStyle style) {
                      final text = TextPainter(
                        text: TextSpan(text: value, style: style),
                        textScaler: MediaQuery.textScalerOf(context),
                        textDirection: Directionality.of(context),
                      )..layout();
                      final result = text.width;
                      text.dispose();
                      return result;
                    }

                    final compact =
                        width(title, titleStyle) +
                            width('查看全部', actionStyle) +
                            64 >
                        box.maxWidth;
                    final onOpen = viewMode == TodayViewMode.tasks
                        ? widget.onAllTasks
                        : widget.onCalendar;
                    return Row(
                      children: [
                        Expanded(child: Text(title, style: titleStyle)),
                        const SizedBox(width: 12),
                        if (compact)
                          AppIconButton(
                            key: const Key('today-secondary-action'),
                            tooltip: '查看全部',
                            onPressed: onOpen,
                            color: CampusColors.muted,
                            icon: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 20,
                            ),
                          )
                        else
                          AppTextButton.icon(
                            key: const Key('today-secondary-action'),
                            onPressed: onOpen,
                            iconAlignment: IconAlignment.end,
                            icon: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                            style: AppTextButton.styleFrom(
                              foregroundColor: CampusColors.muted,
                              textStyle: actionStyle,
                            ),
                            label: const Text('查看全部'),
                          ),
                      ],
                    );
                  },
                ),
              ),
            if (viewMode != TodayViewMode.overview) const SizedBox(height: 8),
            TodayViewSwitch(
              timeline: timeline,
              tasks: tasks,
              otherEntries: otherDay,
              now: now,
              day: day,
              preferences: preferences,
              dayFinished: dayFinished,
              scheduleAvailable: brief.data != null,
              scheduleLoading: brief.busy,
              scheduleLeading: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (urgent != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: urgentRow(urgent),
                    ),
                ],
              ),
              onEventTap: open,
              onTaskTap: open,
              onTaskComplete: completeTask,
              onTaskEdit: widget.onTaskEdit,
              onAllTasks: widget.onAllTasks,
              onAllEvents: widget.onCalendar,
              priorityTaskId: urgent?['id'],
              removedTaskStates: {
                for (final r in widget.items.items)
                  if (r['lifecycle'] != 'active')
                    '${r['id']}': '${r['lifecycle']}',
              },
            ),
            for (final id
                in preferences.order
                    .where(preferences.enabled.contains)
                    .where(
                      (id) =>
                          (!earlyGap || id != 'windows') &&
                          (viewMode == TodayViewMode.schedule ||
                              id != 'deadlines'),
                    ))
              module(
                id,
                tomorrowVisible
                    ? tasks
                          .where(
                            (t) =>
                                !tomorrowTasks.any((v) => v['id'] == t['id']),
                          )
                          .toList()
                    : tasks,
                urgent,
              ),
            if (tomorrowVisible)
              tomorrowPreview(tomorrow, tomorrowPreviewTasks),
          ],
        ),
      ),
    );
  }

  Widget frame(Widget body) => LayoutBuilder(
    builder: (context, constraints) {
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeader)
            TodaySkyHeader(
              now: now,
              semester: widget.app.semester!,
              onSettings: editModules,
              onProfile: () => context.push('/profile'),
            ),
          body,
        ],
      );
      return constraints.hasBoundedHeight
          ? SingleChildScrollView(child: content)
          : content;
    },
  );

  Widget tomorrowPreview(
    List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> tasks,
  ) => Container(
    margin: const EdgeInsets.only(top: 18, bottom: 12),
    padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
    decoration: const BoxDecoration(
      color: CampusColors.surface,
      border: Border(left: BorderSide(color: CampusColors.teal, width: 3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '明天',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            if (tasks.isNotEmpty)
              Text(
                '${tasks.length}项截止',
                style: const TextStyle(
                  color: CampusColors.warning,
                  fontSize: 13,
                ),
              ),
          ],
        ),
        for (final row in rows.where((r) => r['start_at'] != null).take(2))
          InkWell(
            onTap: () => open(row),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 54,
                    child: Text(
                      hhmm(schoolTime(row['start_at'])),
                      style: const TextStyle(
                        color: CampusColors.teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['title']}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if ('${row['location'] ?? ''}'.trim().isNotEmpty)
                          Text(
                            '${row['location']}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: CampusColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: CampusColors.muted,
                  ),
                ],
              ),
            ),
          ),
        if (tasks.isNotEmpty)
          InkWell(
            onTap: () => context.push('/items/${tasks.first['id']}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                tasks.map((t) => '${t['title']}').take(2).join(' · '),
                style: const TextStyle(fontSize: 14, color: CampusColors.muted),
              ),
            ),
          ),
      ],
    ),
  );

  Widget urgentRow(Map<String, dynamic> item) =>
      UrgentItemCard(item: item, now: now, onTap: () => open(item));
  Widget section(String title, {IconData? icon}) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: CampusColors.muted),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget recordRow(Map<String, dynamic> row) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: CampusColors.tealSoft,
      borderRadius: BorderRadius.circular(12),
      child: AppTile(
        onTap: () => open(row),
        minVerticalPadding: 12,
        title: Text(
          '${row['title']}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: calendarTimeLabel(row).isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  calendarTimeLabel(row),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      ),
    ),
  );

  Widget module(
    String id,
    List<Map<String, dynamic>> tasks,
    Map<String, dynamic>? urgent,
  ) {
    if (id == 'week_heatmap') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: WeekHeatmap(
          items: displayWeek ? weekly.entries : [],
          now: now,
          available: displayWeek,
          updating:
              displayWeek &&
              !completeWeek &&
              (weekly.busy || _weekRefreshQueued),
          loading: weekly.busy || _weekRefreshQueued,
          offline: weekly.offline,
          onRetry: retry,
          onDayTap: (date) {
            if (widget.onCalendarDay != null) {
              widget.onCalendarDay!(date);
            } else {
              widget.onCalendar();
            }
          },
        ),
      );
    }

    // 学期进度
    if (id == 'semester_progress') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: SemesterProgressCard(semester: widget.app.semester, now: now),
      );
    }

    // 时间统计
    if (id == 'time_stats') {
      if (!displayWeek) {
        if (weekly.busy || _weekRefreshQueued) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: TimeStatsLoading(),
          );
        }
        return AppTile(
          title: const Text('时间统计'),
          subtitle: Text(
            weekly.busy || _weekRefreshQueued ? '正在读取完整周日程…' : '暂时无法统计本周时长',
          ),
          trailing: weekly.busy || _weekRefreshQueued
              ? null
              : AppTextButton(
                  onPressed: () => reload(forceWeek: true),
                  child: const Text('重试'),
                ),
        );
      }
      final todayEntries = weekly.entries;
      final weekEntries = weekly.entries;

      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TimeStatsCard(
          todayItems: todayEntries,
          weekItems: weekEntries,
          now: now,
          updating: !completeWeek && (weekly.busy || _weekRefreshQueued),
        ),
      );
    }

    // 呼吸练习
    if (id == 'breathing_exercise') {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: BreathingExerciseCard(),
      );
    }

    if (id == 'plans') {
      final rows = brief.entries
          .where((r) => r['resource_type'] == 'plan' && r['start_at'] == null)
          .toList();
      if (rows.isEmpty) return const SizedBox();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section('学习安排', icon: Icons.event_note_outlined),
          for (final r in rows) recordRow(r),
        ],
      );
    }
    if (id == 'windows') {
      final hasReceipt =
          _opportunityReceipt?['semester_id'] == sid &&
          _displayOpportunity != null;
      final blockIds = (_opportunityReceipt?['block_ids'] as List? ?? [])
          .map((v) => '$v')
          .toSet();
      final plans = widget.items.planFeed;
      final planRevision = plans?['revision'];
      final checkedPlans =
          hasReceipt &&
          blockIds.isNotEmpty &&
          sameSemester &&
          widget.app.api.session?['user']?['id'] == owner &&
          widget.app.api.generation == generation &&
          widget.items.hasCurrentPlans &&
          planRevision is int &&
          planRevision >= expectedRevision &&
          !widget.items.revisionIsStale(sid, planRevision);
      final matches = checkedPlans
          ? widget.items
                .rows(plans?['blocks'])
                .where((row) => blockIds.contains('${row['id']}'))
                .toList()
          : <Map<String, dynamic>>[];
      final active = matches
          .where((row) => row['status'] == 'active')
          .firstOrNull;
      final current = active == null
          ? null
          : opportunityDisplay(active, const {}, saved: true);
      final heldStart = at(current?['start_at']),
          heldEnd = at(current?['end_at']);
      final savedCurrent =
          current != null &&
          heldStart != null &&
          heldEnd != null &&
          DateUtils.isSameDay(heldStart, now) &&
          heldEnd.isAfter(now);
      final briefFresh = brief.fresh(revision ?? 0);
      if (!briefFresh && _opportunityPreview == null && !hasReceipt) {
        return const SizedBox();
      }
      final dynamic opportunity;
      if (_opportunityPreview != null) {
        opportunity = _displayOpportunity;
      } else if (savedCurrent) {
        opportunity = current;
      } else if (briefFresh) {
        opportunity = brief.data?['study_opportunity'];
      } else {
        opportunity = null;
      }
      final warnings = briefFresh
          ? brief.suggestions
                .where((row) => row['kind'] != 'free_window')
                .toList()
          : <Map<String, dynamic>>[];
      var savedStatus = widget.items.busy || arrangingOpportunity || brief.busy
          ? '当前状态正在更新'
          : '当前状态暂未核对';
      if (checkedPlans) {
        if (matches.isEmpty ||
            matches.every((row) => row['status'] == 'cancelled')) {
          savedStatus = '这段安排已变更，不再作为当前安排';
        } else if (heldEnd != null && !heldEnd.isAfter(now)) {
          savedStatus = '这段时间已结束';
        } else if (heldStart != null && !DateUtils.isSameDay(heldStart, now)) {
          savedStatus = '这段安排不在今天';
        } else {
          savedStatus = '当前安排时间待核对';
        }
      }
      if (warnings.isEmpty && opportunity is! Map && !hasReceipt) {
        return const SizedBox();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasReceipt && !savedCurrent) opportunityHistory(savedStatus),
          if (opportunity is Map)
            StudyOpportunityCard(
              value: Map<String, dynamic>.from(opportunity),
              now: now,
              ready: brief.fresh(revision ?? 0),
              busy: arrangingOpportunity,
              onArrange: () =>
                  arrangeOpportunity(Map<String, dynamic>.from(opportunity)),
              onOpen: () => context.push('/items/${opportunity['item_id']}'),
              saved: savedCurrent,
              preview: _opportunityPreview != null
                  ? OpportunityInlinePreview(
                      proposal: _opportunityPreview!,
                      controller: widget.items,
                      busy: arrangingOpportunity,
                      error: _opportunityError,
                      onSave: saveOpportunity,
                      onRegenerate: () => arrangeOpportunity(
                        Map<String, dynamic>.from(
                          _opportunitySource ?? opportunity,
                        ),
                      ),
                      onCancel: () => setState(() {
                        _opportunityPreview = null;
                        _displayOpportunity = null;
                        _opportunityError = null;
                      }),
                    )
                  : savedCurrent
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 20,
                              color: CampusColors.success,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '已安排',
                                style: TextStyle(
                                  color: CampusColors.success,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            AppTextButton(
                              onPressed: arrangingOpportunity
                                  ? null
                                  : undoOpportunity,
                              child: const Text('撤销'),
                            ),
                          ],
                        ),
                        if (_opportunityError != null)
                          Text(
                            _opportunityError!,
                            style: const TextStyle(color: CampusColors.error),
                          ),
                      ],
                    )
                  : null,
            ),
          if (warnings.isNotEmpty)
            section('需要留意', icon: Icons.info_outline_rounded),
          for (final suggestion in warnings.take(2))
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.only(left: 14),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: CampusColors.teal, width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion['title'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if ('${suggestion['detail'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        suggestion['detail'],
                        style: const TextStyle(
                          fontSize: 14,
                          color: CampusColors.muted,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  AppButton.tonal(
                    onPressed: () => AssistantScope.open(
                      context,
                      initialText: suggestion['request'],
                      autoSubmit: true,
                    ),
                    child: Text(
                      suggestion['action_label'] == '安排一下'
                          ? '安排任务'
                          : suggestion['action_label'],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    final values = id == 'exams'
        ? widget.items.items
              .where((r) => r['kind'] == 'exam' && r['lifecycle'] == 'active')
              .toList()
        : tasks;
    final list = values
        .where(
          (r) =>
              r['id'] != urgent?['id'] &&
              upcoming(r) &&
              !brief.entries.any(
                (entry) =>
                    entry['resource_id'] == r['id'] &&
                    const ['window', 'start'].contains(calendarMeaning(entry)),
              ),
        )
        .take(3)
        .toList();
    if (list.isEmpty) return const SizedBox();
    if (id == 'exams') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section(homeModules[id]!, icon: Icons.school_outlined),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const SizedBox(width: ShiriSpace.itemGap),
                    ExamCountdownCard(
                      item: list[i],
                      now: now,
                      date: deadline(list[i]),
                      onOpen: () => open(list[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section(
          homeModules[id]!,
          icon: id == 'exams' ? Icons.assignment_outlined : Icons.flag_outlined,
        ),
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          AppTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 4,
            ),
            onTap: () => open(list[i]),
            title: Text(
              '${list[i]['title']}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                itemTimeLabel(list[i], includeMissing: false),
                style: const TextStyle(fontSize: 14, color: CampusColors.muted),
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded, size: 20),
          ),
        ],
      ],
    );
  }
}
