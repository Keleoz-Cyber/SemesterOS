import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../../ui/app_selection.dart';
import '../items/items_controller.dart';
import 'schedule_grid.dart';
import 'calendar_repository.dart';
import 'day_context_panel.dart';

class CalendarPanel extends StatefulWidget {
  final AppController app;
  final ItemsController items;
  final bool todayOnly;
  const CalendarPanel({
    super.key,
    required this.app,
    required this.items,
    this.todayOnly = false,
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
  bool grid = true, active = true;
  String kind = 'all';
  DateTime? selectedDay;
  String? sid;
  int? seenRevision;
  int get expectedRevision {
    final a = semester['revision'] as int, b = widget.items.itemsRevision ?? 0;
    return a > b ? a : b;
  }

  static const kinds = {
    'all': '全部',
    'course': '课程',
    'event': '活动',
    'exam': '考试',
    'plan': '个人计划',
    'deadline': '待办截止',
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
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
                      subtitle: entry.key == 'plan'
                          ? const Text('为任务预留的时间')
                          : null,
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
    final today = DateTime.utc(
      schoolNow().year,
      schoolNow().month,
      schoolNow().day,
    );
    selectedDay =
        !today.isBefore(first) &&
            today.isBefore(first.add(const Duration(days: 7)))
        ? today
        : first;
    reload();
  }

  void itemsChanged() {
    if (!mounted ||
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
    if (active && !was && repository.revision != expectedRevision) reload();
  }

  @override
  void didUpdateWidget(covariant CalendarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  Future<void> reload() {
    if (widget.todayOnly) week = widget.app.weekNow(semester);
    return repository.load(semester['id'], first);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && active) reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.items.removeListener(itemsChanged);
    dayStripController.dispose();
    repository.dispose();
    super.dispose();
  }

  void changeWeek(int next) {
    if (next == week || next < 1 || next > semester['total_weeks']) return;
    final weekday = selectedDay?.weekday ?? 1;
    setState(() {
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
      week = next;
      selectedDay = date;
      grid = false;
    });
    if (changed) reload();
  }

  Future<void> chooseWeek() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
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
    final a = DateTime.utc(
          day.year,
          day.month,
          day.day,
        ).subtract(const Duration(hours: 8)),
        b = a.add(const Duration(days: 1));
    if (row['start_at'] != null) {
      final begin = DateTime.parse(row['start_at']),
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
      'course' => '/courses/$id',
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

  Widget tile(Map<String, dynamic> row, {bool showTime = true}) {
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
                      kinds[row['resource_type']] ?? '安排',
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
                if (showTime) ...[
                  const SizedBox(height: 6),
                  Text(
                    calendarTimeLabel(row),
                    style: const TextStyle(
                      fontSize: 14,
                      color: CampusColors.muted,
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

  bool hasOverlap(Map<String, dynamic> row, List<Map<String, dynamic>> rows) {
    if (row['end_at'] == null) return false;
    final start = DateTime.parse(row['start_at']);
    final end = DateTime.parse(row['end_at']);
    return rows.any(
      (other) =>
          !identical(row, other) &&
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
            (a, b) => DateTime.parse(
              a['start_at'],
            ).compareTo(DateTime.parse(b['start_at'])),
          );
    final other = rows
        .where((r) => r['start_at'] == null || r['resource_type'] == 'deadline')
        .toList();
    final now = schoolNow();
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
          for (final row in timed)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: MediaQuery.textScalerOf(context).scale(1) > 1.3
                        ? 84
                        : 68,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          hhmm(schoolTime(row['start_at'])),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: CampusColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (row['end_at'] != null)
                          Text(
                            hhmm(schoolTime(row['end_at'])),
                            style: const TextStyle(
                              fontSize: 12,
                              color: CampusColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 20,
                    child: Column(
                      children: [
                        const SizedBox(height: 18),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color(row),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Container(width: 2, color: CampusColors.line),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (hasOverlap(row, timed))
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text(
                              '时间重叠',
                              style: TextStyle(
                                fontSize: 12,
                                color: CampusColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        tile(
                          row,
                          showTime:
                              row['end_at'] != null &&
                              calendarDate(schoolTime(row['start_at'])) !=
                                  calendarDate(schoolTime(row['end_at'])),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (other.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 12),
              child: Text(
                '截止与待定事项',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final row in other) tile(row),
          ],
        ],
      ),
    );
  }

  DateTime? agendaInstant(Map<String, dynamic> row) {
    final raw = row['start_at'] ?? row['due_at'];
    return raw == null ? null : DateTime.tryParse('$raw');
  }

  Widget weekAgendaRow(Map<String, dynamic> row, DateTime day) {
    final type = '${row['resource_type'] ?? ''}';
    final start = row['start_at'];
    final due = row['due_at'];
    final time = start != null
        ? hhmm(schoolTime('$start'))
        : due != null
        ? hhmm(schoolTime('$due'))
        : type == 'deadline'
        ? '截止'
        : '全天';
    final end = row['end_at'];
    final crossesDay =
        start != null &&
        end != null &&
        calendarDate(schoolTime('$start')) != calendarDate(schoolTime('$end'));
    final detail = <String>[
      if (type == 'deadline' && due != null) '截止',
      if (crossesDay)
        '至${schoolTime('$end').month}/${schoolTime('$end').day} ${hhmm(schoolTime('$end'))}',
      if ('${row['location'] ?? ''}'.trim().isNotEmpty) '${row['location']}',
    ];
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
                width: MediaQuery.textScalerOf(context).scale(1) > 1.3
                    ? 70
                    : 58,
                child: Text(
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
                    const SizedBox(height: 3),
                    Text(
                      [kinds[type] ?? '日程', ...detail].join(' · '),
                      softWrap: true,
                      style: const TextStyle(
                        fontSize: 13,
                        color: CampusColors.muted,
                        height: 1.3,
                      ),
                    ),
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
      if (rows.isNotEmpty || calendarDate(day) == calendarDate(selected)) {
        groups[day] = rows;
      }
    }
    final now = schoolNow();
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
          for (var i = 0; i < group.value.length; i++) ...[
            if (calendarDate(group.key) == calendarDate(now) &&
                (i == 0 ||
                    (agendaInstant(group.value[i - 1])?.isBefore(now) ??
                        false)) &&
                (agendaInstant(group.value[i])?.isAfter(now) ?? false))
              currentTimeRule(now),
            weekAgendaRow(group.value[i], group.key),
            const Divider(height: 1, color: CampusColors.line),
          ],
          if (group.value.isNotEmpty &&
              calendarDate(group.key) == calendarDate(now) &&
              !(agendaInstant(group.value.last)?.isAfter(now) ?? false))
            currentTimeRule(now),
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
                  final selected = calendarDate(day) == calendarDate(date);
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

  @override
  Widget build(BuildContext context) {
    final entries = repository.entries
        .where((e) => kind == 'all' || e['resource_type'] == kind)
        .toList();
    final untimed = [
      ...entries.where((e) => e['time_precision'] == 'week'),
      ...repository.undated,
    ].where((e) => kind == 'all' || e['resource_type'] == kind).toList();
    final now = schoolNow(), date = selectedDay ?? first;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3,
        weekMode = grid,
        phoneWeek = MediaQuery.sizeOf(context).width < 600 || large;
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
        if (large) ...[
          Text(
            '${first.year}年${first.month}月',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text('第$week周')),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                    ],
                  ),
                ),
              ),
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
          Text(
            '${first.month}/${first.day}—${first.add(const Duration(days: 6)).month}/${first.add(const Duration(days: 6)).day}',
            style: const TextStyle(fontSize: 14, color: CampusColors.muted),
          ),
        ] else
          Row(
            children: [
              Expanded(
                child: AppTextButton(
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: chooseWeek,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${first.year}年${first.month}月',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: CampusColors.ink,
                        ),
                      ),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '第$week周 · ${first.month}/${first.day}—${first.add(const Duration(days: 6)).month}/${first.add(const Duration(days: 6)).day}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: CampusColors.muted,
                            ),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: CampusColors.muted,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
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
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 164,
              child: AppSegmentedControl<bool>(
                value: weekMode,
                options: const {false: '日', true: '周'},
                onChanged: (value) => setState(() => grid = value),
              ),
            ),
            AppTextButton(
              onPressed: () {
                final today = DateTime.utc(now.year, now.month, now.day);
                final next = widget.app.weekNow(semester);
                if (next != week) changeWeek(next);
                setState(
                  () =>
                      selectedDay = today.isBefore(start) || today.isAfter(end)
                      ? first
                      : today,
                );
              },
              child: const Text('本周'),
            ),
            Tooltip(
              message: '筛选日程',
              child: AppTextButton.icon(
                onPressed: chooseKind,
                icon: const Icon(Icons.tune_rounded, size: 20),
                label: Text(kind == 'all' ? '筛选' : kinds[kind]!),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  backgroundColor: kind == 'all' ? null : CampusColors.blueSoft,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!weekMode || phoneWeek) dateStrip(date, now, duration),
        const SizedBox(height: 12),
        if (repository.busy) const LinearProgressIndicator(minHeight: 2),
        if (repository.offline)
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
        AnimatedCrossFade(
          duration: duration,
          alignment: Alignment.topCenter,
          crossFadeState: weekMode
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: phoneWeek
              ? weekAgenda(entries, date)
              : TickerMode(
                  enabled: weekMode,
                  child: SizedBox(
                    height: (MediaQuery.sizeOf(context).height * .58).clamp(
                      320.0,
                      560.0,
                    ),
                    child: NotificationListener<OverscrollNotification>(
                      onNotification: (n) {
                        if (n.metrics.axis == Axis.vertical) {
                          final outer = Scrollable.maybeOf(context)?.position;
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
                        loading: repository.busy,
                        resourceFilter: kind,
                        revision: currentRevision,
                        showHeader: true,
                        selectedDay: date,
                        visible: weekMode,
                        onOpen: open,
                        onDay: selectDay,
                        onWeek: (d) =>
                            changeWeek(d.difference(start).inDays ~/ 7 + 1),
                      ),
                    ),
                  ),
                ),
          secondChild: agenda(entries, date),
        ),
        if (weekMode &&
            !phoneWeek &&
            entries.any(
              (e) =>
                  e['time_precision'] != 'week' &&
                  (e['resource_type'] == 'deadline' ||
                      e['start_at'] == null ||
                      e['end_at'] == null),
            )) ...[
          const Padding(
            padding: EdgeInsets.only(top: 16, bottom: 10),
            child: Text(
              '截止与待定事项',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          for (final r in entries.where(
            (e) =>
                e['time_precision'] != 'week' &&
                (e['resource_type'] == 'deadline' ||
                    e['start_at'] == null ||
                    e['end_at'] == null),
          ))
            tile(r),
        ],
        DayContextPanel(
          items: widget.items,
          semesterId: sid!,
          day: date,
          revision: currentRevision,
        ),
        if (untimed.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 18, bottom: 10),
            child: Text(
              '时间待确认',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          for (final r in untimed) tile(r),
        ],
      ],
    );
  }
}
