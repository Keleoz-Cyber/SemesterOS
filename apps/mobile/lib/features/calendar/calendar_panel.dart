import '../../ui/app_loading.dart';
import '../../ui/app_sheet.dart';
import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../../ui/app_selection.dart';
import '../items/items_controller.dart';
import 'schedule_grid.dart';
import 'time_track.dart';
import 'calendar_repository.dart';
import 'day_context_panel.dart';
import 'event_form.dart';
import '../../ui/empty_states.dart';
import '../../ui/assistant_scope.dart';
import '../../ui/motion.dart';

class CalendarPanel extends StatefulWidget {
  final AppController app;
  final ItemsController items;
  final bool todayOnly;
  final DateTime Function()? now;
  const CalendarPanel({
    super.key,
    required this.app,
    required this.items,
    this.todayOnly = false,
    this.now,
  });
  @override
  State<CalendarPanel> createState() => CalendarPanelState();
}

class CalendarPanelState extends State<CalendarPanel>
    with WidgetsBindingObserver {
  late final CalendarRepository repository;
  final ScrollController dayStripController = ScrollController();
  String? dayStripAnchor;
  late int week;
  bool grid = true, weekList = false, active = true, foreground = true;
  bool _viewChosen = false;
  AxisDirection _direction = AxisDirection.right;
  String get _viewKey => 'calendar-view:${widget.app.user['id']}';

  Future<void> restoreView() async {
    final key = _viewKey;
    try {
      final saved = await widget.app.cache.read(key);
      if (!mounted || _viewChosen || key != _viewKey || widget.todayOnly) {
        return;
      }
      if (saved?['mode'] == 'list') setState(() => weekList = true);
    } catch (_) {
      // A view preference must never prevent access to the timetable.
    }
  }

  Future<void> chooseView(String value) async {
    setState(() {
      _viewChosen = true;
      _direction = value == 'list' ? AxisDirection.right : AxisDirection.left;
      grid = true;
      weekList = value == 'list';
    });
    try {
      await widget.app.cache.write(_viewKey, {'mode': value});
    } catch (_) {}
  }

  Future<void> askAssistant() => AssistantScope.open(
    context,
    browsingContext: AssistantBrowsingContext(
      startDate: grid ? first : selectedDay ?? first,
      endDate: grid ? first.add(const Duration(days: 6)) : selectedDay ?? first,
    ),
  );
  MinuteClock? clock;
  DateTime get now => widget.now?.call() ?? schoolNow();
  bool get hasSemester => widget.app.semester != null;
  void updateClock() {
    if (!active || !foreground || !hasSemester) {
      clock?.cancel();
      clock = null;
    } else {
      clock ??= MinuteClock(() {
        if (mounted && active && foreground && hasSemester) setState(() {});
      }, now: () => now);
    }
  }

  String kind = 'all';
  DateTime? selectedDay;
  String? sid;
  int? seenRevision;
  int get expectedRevision {
    final a = widget.app.semester?['revision'] as int? ?? 0,
        b = widget.items.itemsRevision ?? 0;
    return a > b ? a : b;
  }

  static const kinds = {
    'all': '全部',
    'course': '课程',
    'event': '活动',
    'exam': '考试',
    'plan': '学习安排',
    'deadline': '待办',
  };
  Future<void> chooseKind() async {
    const icons = {
      'all': Icons.calendar_month_outlined,
      'course': Icons.menu_book_outlined,
      'event': Icons.event_outlined,
      'exam': Icons.edit_note_rounded,
      'plan': Icons.edit_calendar_outlined,
      'deadline': Icons.flag_outlined,
    };
    final selected = await showAppSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('日程筛选', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 16),
              for (final entry in kinds.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: entry.key == kind
                        ? CampusColors.blueSoft
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: AppTile(
                      key: ValueKey('calendar-filter-${entry.key}'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      selected: entry.key == kind,
                      leading: Icon(icons[entry.key]),
                      title: Text(entry.value),
                      trailing: Icon(
                        entry.key == kind
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 22,
                      ),
                      onTap: () => Navigator.pop(sheetContext, entry.key),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => kind = selected);
  }

  Map<String, dynamic> get semester => widget.app.semester!;
  DateTime get start => DateTime.parse('${semester['first_monday']}T00:00:00Z');
  DateTime get first => start.add(Duration(days: (week - 1) * 7));
  DateTime get end =>
      start.add(Duration(days: (semester['total_weeks'] as int) * 7 - 1));
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    repository = CalendarRepository(widget.app.api, widget.app.cache)
      ..addListener(changed);
    widget.items.addListener(itemsChanged);
    sid = semester['id'];
    seenRevision = expectedRevision;
    week = widget.todayOnly ? widget.app.weekNow(semester) : widget.app.week;
    final today = DateTime.utc(now.year, now.month, now.day);
    selectedDay =
        !today.isBefore(first) &&
            today.isBefore(first.add(const Duration(days: 7)))
        ? today
        : first;
    reload();
    restoreView();
  }

  void itemsChanged() {
    if (!mounted ||
        !hasSemester ||
        widget.items.semesterId != sid ||
        seenRevision == expectedRevision) {
      return;
    }
    seenRevision = expectedRevision;
    if (active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && active) reload();
      });
    }
  }

  void changed() {
    if (mounted && active) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final was = active;
    active = TickerMode.valuesOf(context).enabled;
    updateClock();
    if (active && !was && repository.revision != expectedRevision) reload();
  }

  @override
  void didUpdateWidget(covariant CalendarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!hasSemester) {
      updateClock();
      return;
    }
    if (sid != semester['id'] ||
        seenRevision != expectedRevision ||
        oldWidget.todayOnly != widget.todayOnly ||
        (widget.todayOnly && week != widget.app.weekNow(semester))) {
      sid = semester['id'];
      seenRevision = expectedRevision;
      if (widget.todayOnly || oldWidget.todayOnly != widget.todayOnly) {
        week = widget.app.weekNow(semester);
      }
      week = week.clamp(1, semester['total_weeks'] as int);
      if (active) reload();
    }
  }

  Future<void> reload() async {
    if (!hasSemester || !mounted) return;
    if (widget.todayOnly) week = widget.app.weekNow(semester);
    await repository.load(semester['id'], first);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    updateClock();
    if (foreground && mounted && active) {
      setState(() {});
      reload();
    }
  }

  @override
  void dispose() {
    clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.items.removeListener(itemsChanged);
    dayStripController.dispose();
    repository.dispose();
    super.dispose();
  }

  void changeWeek(int next) {
    if (!hasSemester) return;
    if (next == week || next < 1 || next > semester['total_weeks']) return;
    final weekday = selectedDay?.weekday ?? 1;
    setState(() {
      _direction = next > week ? AxisDirection.right : AxisDirection.left;
      week = next;
      selectedDay = first.add(Duration(days: weekday - 1));
    });
    reload();
  }

  void selectDay(DateTime value) {
    final date = DateTime.utc(value.year, value.month, value.day),
        next =
            DateTime.utc(
                  value.year,
                  value.month,
                  value.day,
                ).difference(start).inDays ~/
                7 +
            1;
    if (date.isBefore(start) || date.isAfter(end)) return;
    final changed = week != next;
    setState(() {
      _viewChosen = true;
      _direction = date.isBefore(selectedDay ?? first)
          ? AxisDirection.left
          : AxisDirection.right;
      week = next;
      selectedDay = date;
      grid = false;
      weekList = false;
    });
    if (changed) reload();
  }

  Future<void> quickAdd() async {
    if (!hasSemester) return;
    final generation = widget.items.api.generation, term = sid;
    final day = selectedDay ?? first;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EventFormPage(
          controller: widget.items,
          semester: semester,
          candidate: {
            'event': {
              'title': '',
              'category_id': 'affairs',
              'certainty': 'formal',
              'time': {'precision': 'date', 'date': calendarDate(day)},
            },
          },
        ),
      ),
    );
    if (saved == true &&
        mounted &&
        generation == widget.items.api.generation &&
        term == sid) {
      await widget.items.refresh();
      if (mounted) await reload();
    }
  }

  Future<void> chooseWeek() async {
    final selected = await showAppSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('选择周次', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 1; i <= semester['total_weeks']; i++)
                    Semantics(
                      selected: i == week,
                      child: AppTextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(72, 48),
                          backgroundColor: i == week
                              ? CampusColors.primary
                              : CampusColors.surface,
                          foregroundColor: i == week
                              ? Colors.white
                              : CampusColors.ink,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context, i),
                        child: Text('第$i周'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) changeWeek(selected);
  }

  bool onDay(Map<String, dynamic> row, DateTime day) {
    row = calendarDisplayEntry(row);
    final a = DateTime.utc(
          day.year,
          day.month,
          day.day,
        ).subtract(const Duration(hours: 8)),
        b = a.add(const Duration(days: 1));
    final time = calendarTime(row);
    if (calendarMeaning(row) == 'window' && time['at'] != null) {
      final begin = DateTime.parse(time['at']),
          end = DateTime.parse(time['end_at'] ?? time['at']);
      return begin.isBefore(b) && !end.isBefore(a);
    }
    if (row['start_at'] != null) {
      final begin = DateTime.parse(
            row['end_at'] == null
                ? row['start_at']
                : row['occupancy_start_at'] ?? row['start_at'],
          ),
          end = row['end_at'] == null
              ? DateTime.parse(
                  row['start_at'],
                ).add(const Duration(microseconds: 1))
              : DateTime.parse(row['end_at']);
      return begin.isBefore(b) && end.isAfter(a);
    }
    if (row['due_at'] != null) {
      final due = DateTime.parse(row['due_at']);
      return !due.isBefore(a) && due.isBefore(b);
    }
    final date = calendarDate(day);
    return row['date'] != null &&
        '${row['date']}'.compareTo(date) <= 0 &&
        '${row['end_date'] ?? row['date']}'.compareTo(date) >= 0;
  }

  Future<void> open(Map<String, dynamic> row) async {
    final id = row['resource_id'];
    if (id == null) return;
    await context.push(switch (row['resource_type']) {
      'event' => '/events/$id',
      'course' =>
        '/courses/$id?occurrence=${Uri.encodeQueryComponent('${row['id']}')}',
      'exam' => '/exams/$id',
      _ => '/items/$id',
    });
    if (mounted) await reload();
  }

  Color color(Map<String, dynamic> row) => switch (row['resource_type']) {
    'course' => CoursePalette.forTitle('${row['title']}').accent,
    'event' => CampusColors.teal,
    'exam' => CampusColors.warning,
    'plan' => CampusColors.primary,
    _ => CampusColors.muted,
  };

  Widget tile(Map<String, dynamic> row, {bool showTime = true, Widget? clock}) {
    final accent = color(row);
    final background = switch (row['resource_type']) {
      'course' => CoursePalette.forTitle('${row['title']}').background,
      'plan' => CampusColors.blueSoft,
      'event' => CampusColors.tealSoft,
      'exam' => CampusColors.warningSoft,
      _ => CampusColors.surface,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => open(row),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: accent, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${row['title']}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: CampusColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded, size: 18, color: accent),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      row['reserve_time'] == false
                          ? calendarParticipationLabel(row)
                          : calendarMeaning(row) == 'window'
                          ? '办理窗口'
                          : kinds[row['resource_type']] ?? '安排',
                      style: TextStyle(
                        fontSize: 12,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if ('${row['location'] ?? ''}'.isNotEmpty)
                      Text(
                        '${row['location']}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: CampusColors.muted,
                        ),
                      ),
                  ],
                ),
                if (showTime && calendarTimeLabel(row).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    calendarTimeLabel(row),
                    style: const TextStyle(
                      fontSize: 14,
                      color: CampusColors.muted,
                    ),
                  ),
                ],
                if (calendarArrivalLabel(row).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    calendarArrivalLabel(row),
                    style: const TextStyle(
                      fontSize: 14,
                      color: CampusColors.muted,
                    ),
                  ),
                ],
                ?clock,
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool hasOverlap(Map<String, dynamic> row, List<Map<String, dynamic>> rows) {
    if (row['end_at'] == null || !calendarReservesTime(row)) return false;
    final start = DateTime.parse(row['start_at']);
    final end = DateTime.parse(row['end_at']);
    return rows.any(
      (other) =>
          !identical(row, other) &&
          calendarReservesTime(other) &&
          other['end_at'] != null &&
          start.isBefore(DateTime.parse(other['end_at'])) &&
          end.isAfter(DateTime.parse(other['start_at'])),
    );
  }

  Widget agenda(List<Map<String, dynamic>> entries, DateTime date) {
    final rows = entries.where((r) => onDay(r, date)).toList();
    final timed =
        rows
            .where(
              (r) => r['start_at'] != null && r['resource_type'] != 'deadline',
            )
            .toList()
          ..sort(
            (a, b) => DateTime.parse(a['occupancy_start_at'] ?? a['start_at'])
                .compareTo(
                  DateTime.parse(b['occupancy_start_at'] ?? b['start_at']),
                ),
          );
    final other = rows
        .where((r) => r['start_at'] == null || r['resource_type'] == 'deadline')
        .toList();
    final now = this.now;
    final today = calendarDate(now) == calendarDate(date);
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0).abs() > 150) {
          selectDay(date.add(Duration(days: d.primaryVelocity! < 0 ? 1 : -1)));
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${date.month}月${date.day}日 · 周${'一二三四五六日'[date.weekday - 1]}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (today)
                  Text(
                    '今天',
                    style: const TextStyle(
                      color: CampusColors.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (rows.isEmpty && !repository.busy && repository.data != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.event_available_outlined,
                    color: CampusColors.teal,
                    size: 28,
                  ),
                  SizedBox(height: 12),
                  Text(
                    '这一天没有已记录的安排',
                    style: TextStyle(color: CampusColors.muted),
                  ),
                ],
              ),
            ),
          TimeTrack(
            rows: timed,
            date: date,
            now: now,
            railX: MediaQuery.textScalerOf(context).scale(1) > 1.3
                ? 72.5
                : 60.5,
            rowBuilder: (row, last, clock) => Column(
              children: [
                weekAgendaRow(
                  row,
                  date,
                  clock: clock,
                  overlap: hasOverlap(row, timed),
                ),
                const Divider(height: 1, color: CampusColors.line),
              ],
            ),
          ),
          if (other.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 12),
              child: Text(
                '按日期记录',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final row in other) ...[
              weekAgendaRow(row, date),
              const Divider(height: 1, color: CampusColors.line),
            ],
          ],
        ],
      ),
    );
  }

  DateTime? agendaInstant(Map<String, dynamic> row) {
    final raw = row['occupancy_start_at'] ?? row['start_at'] ?? row['due_at'];
    return raw == null ? null : DateTime.tryParse('$raw');
  }

  Widget weekAgendaRow(
    Map<String, dynamic> row,
    DateTime day, {
    Widget? clock,
    bool overlap = false,
  }) {
    final type = '${row['resource_type'] ?? ''}';
    final meaning = calendarMeaning(row);
    final start = row['start_at'];
    final due = row['due_at'];
    final time = start != null
        ? hhmm(schoolTime('$start'))
        : due != null
        ? hhmm(schoolTime('$due'))
        : meaning == 'window'
        ? '范围'
        : type == 'deadline' && meaning != 'start'
        ? '截止'
        : '';
    final end = row['end_at'];
    final crossesDay =
        start != null &&
        end != null &&
        calendarDate(schoolTime('$start')) != calendarDate(schoolTime('$end'));
    final detail = <String>[
      if (calendarParticipationLabel(row).isNotEmpty)
        calendarParticipationLabel(row),
      if (calendarArrivalLabel(row).isNotEmpty) calendarArrivalLabel(row),
      if (meaning == 'window' && calendarTimeLabel(row).isNotEmpty)
        calendarTimeLabel(row),
      if (type == 'deadline' && due != null) '截止',
      if (crossesDay)
        '至${schoolTime('$end').month}/${schoolTime('$end').day} ${hhmm(schoolTime('$end'))}',
      if ('${row['location'] ?? ''}'.trim().isNotEmpty) '${row['location']}',
    ];
    final subtitle = [
      if (meaning == 'window')
        '办理时间'
      else if (type != 'event')
        kinds[type] ?? '日程',
      ...detail,
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    final accent = color(row);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('week-agenda-${calendarDate(day)}-${row['id']}'),
        onTap: () => open(row),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: time.isEmpty
                    ? 0
                    : MediaQuery.textScalerOf(context).scale(1) > 1.3
                    ? 70
                    : 58,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      time,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: type == 'deadline'
                            ? CampusColors.muted
                            : CampusColors.ink,
                      ),
                    ),
                    if (end != null && !crossesDay && meaning != 'window')
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          hhmm(schoolTime('$end')),
                          style: const TextStyle(
                            fontSize: 12,
                            color: CampusColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 10),
                child: Container(
                  width: 5,
                  height: 13,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (overlap)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 3),
                        child: Text(
                          '时间重叠',
                          style: TextStyle(
                            fontSize: 12,
                            color: CampusColors.error,
                          ),
                        ),
                      ),
                    Text(
                      '${row['title'] ?? '日程'}',
                      softWrap: true,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: CampusColors.ink,
                        height: 1.35,
                      ),
                    ),
                    if (subtitle.isNotEmpty) const SizedBox(height: 3),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        softWrap: true,
                        style: const TextStyle(
                          fontSize: 13,
                          color: CampusColors.muted,
                          height: 1.3,
                        ),
                      ),
                    ?clock,
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4, left: 4),
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
    );
  }

  Widget currentTimeRule(DateTime now) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(
          hhmm(now),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: CampusColors.teal,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider(height: 1, color: CampusColors.teal)),
        const SizedBox(width: 8),
        const Text(
          '现在',
          style: TextStyle(fontSize: 12, color: CampusColors.teal),
        ),
      ],
    ),
  );

  Widget weekAgenda(List<Map<String, dynamic>> entries, DateTime selected) {
    final now = this.now;
    final days = <DateTime>[
      for (var i = 0; i < 7; i++) first.add(Duration(days: i)),
    ];
    final groups = <DateTime, List<Map<String, dynamic>>>{};
    for (final day in days) {
      final rows =
          entries
              .where((r) => r['time_precision'] != 'week' && onDay(r, day))
              .toList()
            ..sort((a, b) {
              final x = agendaInstant(a), y = agendaInstant(b);
              if (x == null && y == null) return 0;
              if (x == null) return 1;
              if (y == null) return -1;
              return x.compareTo(y);
            });
      if (rows.isNotEmpty || calendarDate(day) == calendarDate(now)) {
        groups[day] = rows;
      }
    }
    return Column(
      key: const ValueKey('calendar-week-agenda'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (groups.isEmpty && !repository.busy && repository.data != null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Text('本周还没有安排', style: TextStyle(color: CampusColors.muted)),
          ),
        for (final group in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 7),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '周${'一二三四五六日'[group.key.weekday - 1]}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: CampusColors.ink,
                  ),
                ),
                Text(
                  '${group.key.month}月${group.key.day}日',
                  style: const TextStyle(
                    fontSize: 14,
                    color: CampusColors.muted,
                  ),
                ),
                if (calendarDate(group.key) == calendarDate(now))
                  const Text(
                    '今天',
                    style: TextStyle(fontSize: 13, color: CampusColors.primary),
                  ),
                Text(
                  '${group.value.length}项',
                  style: const TextStyle(
                    fontSize: 13,
                    color: CampusColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (group.value.isEmpty &&
              !repository.busy &&
              repository.data != null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('暂无安排', style: TextStyle(color: CampusColors.muted)),
            ),
          TimeTrack(
            rows: group.value
                .where(
                  (row) =>
                      row['start_at'] != null &&
                      calendarMeaning(row) != 'window' &&
                      row['resource_type'] != 'deadline',
                )
                .toList(),
            date: group.key,
            now: now,
            railX: MediaQuery.textScalerOf(context).scale(1) > 1.3
                ? 72.5
                : 60.5,
            rowBuilder: (row, last, clock) => Column(
              children: [
                weekAgendaRow(row, group.key, clock: clock),
                const Divider(height: 1, color: CampusColors.line),
              ],
            ),
          ),
          for (final row in group.value.where(
            (row) =>
                row['start_at'] == null ||
                calendarMeaning(row) == 'window' ||
                row['resource_type'] == 'deadline',
          ))
            weekAgendaRow(row, group.key),
        ],
      ],
    );
  }

  Widget dateStrip(
    DateTime date,
    DateTime now,
    Duration duration,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final minimumWidth = MediaQuery.textScalerOf(context).scale(24) + 28;
      final width = (constraints.maxWidth / 7).clamp(
        minimumWidth,
        double.infinity,
      );
      final anchor =
          '${calendarDate(first)}:${calendarDate(date)}:'
          '${width.toStringAsFixed(1)}:${constraints.maxWidth.toStringAsFixed(1)}';
      if (anchor != dayStripAnchor) {
        final initial = dayStripAnchor == null;
        dayStripAnchor = anchor;
        final index = date.difference(first).inDays.clamp(0, 6);
        final viewport = constraints.maxWidth;
        final reducedMotion = MediaQuery.disableAnimationsOf(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              dayStripAnchor != anchor ||
              !dayStripController.hasClients) {
            return;
          }
          final target = (index * width - (viewport - width) / 2)
              .clamp(0.0, dayStripController.position.maxScrollExtent)
              .toDouble();
          if (initial || reducedMotion) {
            dayStripController.jumpTo(target);
          } else {
            dayStripController.animateTo(
              target,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
      return SingleChildScrollView(
        controller: dayStripController,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < 7; i++)
              Builder(
                builder: (context) {
                  final day = first.add(Duration(days: i));
                  final selected =
                      !weekList && calendarDate(day) == calendarDate(date);
                  final today = calendarDate(day) == calendarDate(now);
                  return Semantics(
                    selected: selected,
                    label:
                        '${day.month}月${day.day}日，周${'一二三四五六日'[i]}${today ? '，今天' : ''}',
                    button: true,
                    child: SizedBox(
                      width: width,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: ValueKey('calendar-day-${calendarDate(day)}'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => selectDay(day),
                            child: AnimatedContainer(
                              duration: duration,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: selected
                                    ? CampusColors.primary
                                    : today
                                    ? CampusColors.tealSoft
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '一二三四五六日'[i],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: selected
                                          ? Colors.white
                                          : CampusColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? Colors.white
                                          : CampusColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    today ? '今天' : ' ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: selected
                                          ? Colors.white
                                          : CampusColors.teal,
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
                },
              ),
          ],
        ),
      );
    },
  );

  Widget calendarToolbar(DateTime now) {
    final first = start.add(Duration(days: (week - 1) * 7));
    final last = first.add(const Duration(days: 6));
    final listMode = !grid || weekList;
    final spaciousControls = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    void today() {
      final date = DateTime.utc(now.year, now.month, now.day),
          next = widget.app.weekNow(semester);
      if (next != week) changeWeek(next);
      setState(() {
        selectedDay = date.isBefore(start) || date.isAfter(end) ? first : date;
        if (listMode) {
          grid = false;
          weekList = false;
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppTextButton(
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.zero,
                ),
                onPressed: chooseWeek,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '第$week周',
                            style: TextStyle(
                              fontSize: spaciousControls ? 20 : 23,
                              fontWeight: FontWeight.w700,
                              color: CampusColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${first.month}/${first.day}—${last.month}/${last.day}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: CampusColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 17,
                      color: CampusColors.muted,
                    ),
                  ],
                ),
              ),
            ),
            AppLoadingIndicator(
              compact: true,
              visible: repository.busy,
              label: '正在更新日程',
            ),
            if (!spaciousControls)
              AppTextButton(onPressed: today, child: const Text('今天')),
            AppIconButton(
              tooltip: '上一周',
              onPressed: week > 1 ? () => changeWeek(week - 1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            AppIconButton(
              tooltip: '下一周',
              onPressed: week < semester['total_weeks']
                  ? () => changeWeek(week + 1)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (spaciousControls)
          AppSegmentedControl<String>(
            value: listMode ? 'list' : 'table',
            options: const {'table': '周课表', 'list': '列表'},
            onChanged: chooseView,
          ),
        Row(
          children: [
            if (!spaciousControls)
              Expanded(
                child: AppSegmentedControl<String>(
                  value: listMode ? 'list' : 'table',
                  options: const {'table': '周课表', 'list': '列表'},
                  onChanged: chooseView,
                ),
              ),
            if (spaciousControls) ...[
              AppTextButton(onPressed: today, child: const Text('今天')),
              const Spacer(),
            ] else
              const SizedBox(width: 8),
            AppIconButton(
              tooltip: '添加日程',
              onPressed: quickAdd,
              icon: const Icon(Icons.add_rounded),
            ),
            AppIconButton(
              tooltip: '筛选日程',
              onPressed: chooseKind,
              icon: Icon(
                Icons.tune_rounded,
                color: kind == 'all'
                    ? CampusColors.muted
                    : CampusColors.primary,
              ),
            ),
            AppIconButton(
              key: const Key('calendar-assistant'),
              tooltip: '询问这段日程',
              guardAsync: false,
              onPressed: askAssistant,
              icon: const Icon(Icons.auto_awesome_outlined, size: 21),
            ),
          ],
        ),
        if (listMode && !weekList || kind != 'all')
          Row(
            children: [
              if (listMode && !weekList)
                AppTextButton(
                  key: const ValueKey('calendar-whole-week'),
                  onPressed: () => setState(() {
                    grid = true;
                    weekList = true;
                  }),
                  child: const Text('查看整周'),
                ),
              if (kind != 'all')
                Text(
                  '仅看${kinds[kind]}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: CampusColors.muted,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!hasSemester) return const SizedBox.shrink();
    final entries = repository.entries
        .where((e) => kind == 'all' || e['resource_type'] == kind)
        .toList();
    final untimed = [
      ...entries.where((e) => e['time_precision'] == 'week'),
      ...repository.undated,
    ].where((e) => kind == 'all' || e['resource_type'] == kind).toList();
    final now = this.now, date = selectedDay ?? first;
    final weekMode = grid, phoneWeek = weekList;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    if (widget.todayOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '今日安排',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          for (final r in entries.where((e) => onDay(e, now))) tile(r),
          for (final r in untimed) tile(r),
        ],
      );
    }
    final currentRevision = (repository.revision ?? 0) > expectedRevision
        ? repository.revision!
        : expectedRevision;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        calendarToolbar(now),
        const SizedBox(height: 6),
        if (!weekMode || phoneWeek) dateStrip(date, now, duration),
        if (weekMode && !phoneWeek)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '点日期查看当天',
              style: TextStyle(fontSize: 12, color: CampusColors.muted),
            ),
          )
        else
          const SizedBox(height: 8),
        if (!repository.busy &&
            repository.data != null &&
            widget.items.courses.isEmpty &&
            (kind == 'course' ||
                kind == 'all' &&
                    repository.entries.isEmpty &&
                    repository.undated.isEmpty) &&
            !repository.entries.any((row) => row['resource_type'] == 'course'))
          EmptyTimetable(
            onImport: () => context.push('/import'),
            title: '还没有课程',
            message: '可以导入课表，也可以手工添加。',
          ),
        if (repository.offline && repository.data == null)
          NetworkError(
            onRetry: reload,
            title: '安排暂时无法读取',
            message: repository.error,
          )
        else if (repository.offline)
          Row(
            children: [
              Expanded(
                child: Text(
                  repository.data == null ? '安排暂时无法读取' : '正在显示本机保存的安排',
                  style: const TextStyle(
                    fontSize: 12,
                    color: CampusColors.muted,
                  ),
                ),
              ),
              AppTextButton(
                onPressed: repository.busy ? null : reload,
                child: const Text('重试'),
              ),
            ],
          ),
        AppContentTransition(
          key: ValueKey('calendar-body-$sid'),
          value: '$week:$weekMode:$phoneWeek:${calendarDate(date)}:$kind',
          direction: _direction,
          child: weekMode
              ? Column(
                  children: [
                    Offstage(
                      offstage: phoneWeek,
                      child: ExcludeFocus(
                        excluding: phoneWeek,
                        child: TickerMode(
                          enabled: weekMode && !phoneWeek,
                          child: SizedBox(
                            height: (MediaQuery.sizeOf(context).height * .68)
                                .clamp(320.0, 660.0),
                            child: NotificationListener<OverscrollNotification>(
                              onNotification: (n) {
                                if (n.metrics.axis == Axis.vertical) {
                                  final outer = Scrollable.maybeOf(
                                    context,
                                  )?.position;
                                  if (outer != null) {
                                    outer.jumpTo(
                                      (outer.pixels + n.overscroll).clamp(
                                        outer.minScrollExtent,
                                        outer.maxScrollExtent,
                                      ),
                                    );
                                  }
                                }
                                return false;
                              },
                              child: ScheduleGrid(
                                key: ValueKey('week-grid-$sid'),
                                firstDay: first,
                                minDay: start,
                                maxDay: end,
                                entries: repository.entries,
                                periods: widget.items.rows(semester['periods']),
                                loading: repository.busy,
                                resourceFilter: kind,
                                revision: currentRevision,
                                showHeader: true,
                                selectedDay: date,
                                visible: weekMode && !phoneWeek,
                                now: widget.now,
                                refreshClock: false,
                                onOpen: open,
                                onDay: selectDay,
                                onWeek: (d) => changeWeek(
                                  d.difference(start).inDays ~/ 7 + 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (phoneWeek) weekAgenda(entries, date),
                  ],
                )
              : agenda(entries, date),
        ),
        if (weekMode &&
            !phoneWeek &&
            entries.any(
              (e) =>
                  e['time_precision'] != 'week' &&
                  (e['resource_type'] == 'deadline' ||
                      e['start_at'] == null ||
                      calendarMeaning(e) == 'window'),
            )) ...[
          const Padding(
            padding: EdgeInsets.only(top: 16, bottom: 10),
            child: Text(
              '按日期记录',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          for (final r in entries.where(
            (e) =>
                e['time_precision'] != 'week' &&
                (e['resource_type'] == 'deadline' ||
                    e['start_at'] == null ||
                    calendarMeaning(e) == 'window'),
          ))
            tile(r),
        ],
        if (!weekMode)
          DayContextPanel(
            items: widget.items,
            semesterId: sid!,
            day: date,
            revision: currentRevision,
          ),
        if (untimed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: AppDisclosure(
              title: Text('未定日期 · ${untimed.length}'),
              children: [for (final r in untimed) tile(r)],
            ),
          ),
      ],
    );
  }
}
