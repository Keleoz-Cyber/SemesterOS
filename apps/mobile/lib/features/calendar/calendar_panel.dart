import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';
import '../timetable/week_view.dart';
import 'calendar_repository.dart';

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
  late int week;
  bool grid = true;
  String kind = 'all';
  String? sid;
  int? seenRevision;
  Map<String, dynamic> get semester => widget.app.semester!;
  DateTime get first => DateTime.parse(
    semester['first_monday'],
  ).add(Duration(days: (week - 1) * 7));
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    repository = CalendarRepository(widget.app.api, widget.app.cache);
    sid = semester['id'];
    seenRevision = semester['revision'];
    week = widget.todayOnly ? widget.app.weekNow(semester) : widget.app.week;
    repository.addListener(changed);
    reload();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant CalendarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (sid != semester['id'] ||
        seenRevision != semester['revision'] ||
        oldWidget.todayOnly != widget.todayOnly ||
        (widget.todayOnly && week != widget.app.weekNow(semester))) {
      sid = semester['id'];
      seenRevision = semester['revision'];
      if (widget.todayOnly || oldWidget.todayOnly != widget.todayOnly) {
        week = widget.app.weekNow(semester);
      }
      week = week.clamp(1, semester['total_weeks'] as int);
      reload();
    }
  }

  Future<void> reload() {
    if (widget.todayOnly) week = widget.app.weekNow(semester);
    return repository.load(semester['id'], first);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    repository.removeListener(changed);
    repository.dispose();
    super.dispose();
  }

  Future<void> chooseWeek() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 1; i <= semester['total_weeks']; i++)
              ChoiceChip(
                label: Text('第$i周'),
                selected: i == week,
                onSelected: (_) => Navigator.pop(c, i),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => week = selected);
      await reload();
    }
  }

  bool onDay(Map<String, dynamic> row, DateTime day) {
    final a = DateTime.utc(
          day.year,
          day.month,
          day.day,
        ).subtract(const Duration(hours: 8)),
        b = a.add(const Duration(days: 1));
    if (row['start_at'] != null) {
      final start = DateTime.parse(row['start_at']);
      final end = row['end_at'] == null
          ? start.add(const Duration(microseconds: 1))
          : DateTime.parse(row['end_at']);
      return start.isBefore(b) && end.isAfter(a);
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

  Future<void> add() async {
    await context.push('/events/new');
    if (mounted) await reload();
  }

  Color color(Map<String, dynamic> row) => switch (row['resource_type']) {
    'course' => const Color(0xFF6F60C7),
    'event' => const Color(0xFF278A75),
    'exam' => const Color(0xFFB88037),
    'plan' => const Color(0xFF9B72BC),
    _ => const Color(0xFFB46D83),
  };
  String label(Map<String, dynamic> row) => switch (row['resource_type']) {
    'course' => '课程',
    'event' => '活动',
    'exam' => '考试',
    'plan' => '个人计划',
    _ => '截止事项',
  };
  Widget tile(Map<String, dynamic> row) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () => open(row),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: color(row),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['title'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      calendarTimeLabel(row),
                      style: const TextStyle(
                        fontSize: 12,
                        color: CampusColors.muted,
                      ),
                    ),
                    if ('${row['location'] ?? ''}'.isNotEmpty)
                      Text(
                        row['location'],
                        style: const TextStyle(
                          fontSize: 12,
                          color: CampusColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label(row),
                style: TextStyle(fontSize: 11, color: color(row)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final entries = repository.entries
        .where((e) => kind == 'all' || e['resource_type'] == kind)
        .toList();
    final segments = calendarGridEntries(entries, first);
    final now = schoolNow();
    final data = widget.todayOnly
        ? entries.where((e) => onDay(e, now)).toList()
        : entries.where((e) => e['time_precision'] != 'week').toList();
    final untimed = [
      ...entries.where((e) => e['time_precision'] == 'week'),
      ...repository.undated,
    ].where((e) => kind == 'all' || e['resource_type'] == kind).toList();
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.todayOnly ? '今日安排' : '日程',
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    widget.todayOnly
                        ? '${now.month}月${now.day}日 · 周${'一二三四五六日'[now.weekday - 1]}'
                        : '${semester['name']}',
                    style: const TextStyle(
                      color: CampusColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: repository.offline ? null : add,
              tooltip: '添加日程',
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        if (repository.busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (repository.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  repository.data == null
                      ? repository.error!
                      : '更新未完成，正在显示本机记录。',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: repository.busy ? null : reload,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        if (!widget.todayOnly) ...[
          Row(
            children: [
              IconButton(
                onPressed: week > 1
                    ? () {
                        setState(() => week--);
                        reload();
                      }
                    : null,
                tooltip: '上一周',
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: chooseWeek,
                  child: Text('第$week周 · ${first.month}/${first.day}'),
                ),
              ),
              IconButton(
                onPressed: week < semester['total_weeks']
                    ? () {
                        setState(() => week++);
                        reload();
                      }
                    : null,
                tooltip: '下一周',
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(
                onPressed: () {
                  setState(() => week = widget.app.weekNow(semester));
                  reload();
                },
                child: const Text('本周'),
              ),
            ],
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('周课表')),
              ButtonSegment(value: false, label: Text('日程列表')),
            ],
            selected: {grid},
            onSelectionChanged: (s) => setState(() => grid = s.first),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              for (final k in {
                'all': '全部',
                'course': '课程',
                'event': '活动',
                'exam': '考试',
                'plan': '个人计划',
                'deadline': '截止',
              }.entries)
                ChoiceChip(
                  label: Text(k.value),
                  selected: kind == k.key,
                  onSelected: (_) => setState(() => kind = k.key),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (repository.data != null) ...[
          if (!widget.todayOnly && grid && !largeText && segments.isNotEmpty)
            SizedBox(
              height: 430,
              child: SingleChildScrollView(
                child: TimetableGrid(
                  semester: semester,
                  week: week,
                  events: segments,
                  now: DateTime.now(),
                  onCourse: open,
                ),
              ),
            ),
          if (data.isEmpty && !repository.busy)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                widget.todayOnly ? '今天没有已记录的安排' : '这一周没有这类安排',
                textAlign: TextAlign.center,
              ),
            ),
          if (widget.todayOnly || !grid || largeText)
            for (final row in data) tile(row)
          else ...[
            if (entries.any(
              (e) =>
                  e['time_precision'] != 'week' &&
                  (e['start_at'] == null || e['end_at'] == null),
            ))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '截止与待定事项',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            for (final row in entries.where(
              (e) =>
                  e['time_precision'] != 'week' &&
                  (e['start_at'] == null || e['end_at'] == null),
            ))
              tile(row),
          ],
          if (untimed.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '时间待确认',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            for (final row in untimed) tile(row),
          ],
        ],
      ],
    );
  }
}
