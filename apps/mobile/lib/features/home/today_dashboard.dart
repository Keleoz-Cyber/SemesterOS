import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import '../calendar/calendar_repository.dart';
import '../../ui/campus_theme.dart';
import '../../ui/assistant_scope.dart';
import 'home_preferences.dart';
import 'day_brief_controller.dart';

class TodayDashboard extends StatefulWidget {
  final AppController app;
  final ItemsController items;
  final VoidCallback onCalendar;
  final DateTime Function()? now;
  const TodayDashboard({
    super.key,
    required this.app,
    required this.items,
    required this.onCalendar,
    this.now,
  });
  @override
  State<TodayDashboard> createState() => TodayDashboardState();
}

class TodayDashboardState extends State<TodayDashboard>
    with WidgetsBindingObserver {
  late final DayBriefController brief;
  late final HomePreferences preferences;
  Timer? clock;
  int? revision;
  bool active = true, foreground = true;
  int get expectedRevision {
    final calendar = widget.app.semester!['revision'] as int;
    final items = widget.items.itemsRevision ?? 0;
    return calendar > items ? calendar : items;
  }

  DateTime get now => widget.now?.call() ?? schoolNow();
  DateTime get day => DateTime.utc(now.year, now.month, now.day);
  String get sid => widget.app.semester!['id'];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final generation = widget.items.api.generation, semester = sid;
    preferences = HomePreferences(
      widget.items.cache,
      widget.items.owner!,
      semester,
      () =>
          generation == widget.items.api.generation &&
          semester == widget.items.semesterId,
    );
    preferences.addListener(changed);
    preferences.restore().catchError((Object _) {});
    brief = DayBriefController(widget.app.api, widget.app.cache)
      ..addListener(changed);
    widget.items.addListener(changed);
    revision = expectedRevision;
    reload();
    updateClock();
  }

  void updateClock() {
    if (!active || !foreground) {
      clock?.cancel();
      clock = null;
      return;
    }
    if (clock != null) return;
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!active || !foreground || !mounted) return;
      if (!brief.busy &&
          (brief.data?['date'] != calendarDate(day) ||
              !brief.fresh(revision ?? 0))) {
        reload();
      } else {
        setState(() {});
      }
    });
  }

  void changed() {
    if (!mounted) return;
    if (revision != expectedRevision) {
      revision = expectedRevision;
      if (active && foreground) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && active && foreground) reload();
        });
      }
    }
    if (active) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final was = active;
    active = TickerMode.valuesOf(context).enabled;
    updateClock();
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
    if (revision != expectedRevision) {
      revision = expectedRevision;
      if (active) reload();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    updateClock();
    if (foreground && active) reload();
  }

  Future<void> reload() => brief.load(sid, day);
  @override
  void dispose() {
    clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.items.removeListener(changed);
    preferences.dispose();
    brief.dispose();
    super.dispose();
  }

  DateTime? at(dynamic value) => value is String
      ? DateTime.tryParse(value)?.toUtc().add(const Duration(hours: 8))
      : null;
  Future<void> open(Map<String, dynamic> row) async {
    final id = row['resource_id'] ?? row['id'];
    if (id == null) return;
    await context.push(switch (row['resource_type']) {
      'course' => '/courses/$id',
      'event' => '/events/$id',
      'exam' => '/exams/$id',
      _ => '/items/$id',
    });
    if (mounted) await reload();
  }

  DateTime? deadline(Map<String, dynamic> item) {
    final t = Map<String, dynamic>.from(item['time'] ?? {});
    return at(item['anchor_at'] ?? t['at']) ??
        (t['precision'] == 'date' && t['date'] is String
            ? DateTime.tryParse('${t['date']}T23:59:59Z')
            : null);
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
  }) async {
    try {
      await preferences.change(order: order, enabled: enabled);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('本机设置未保存，请重试')));
      }
    }
  }

  Future<void> editModules() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => AnimatedBuilder(
        animation: preferences,
        builder: (context, _) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '调整首页内容',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '课程和紧急事项始终显示。拖动排序，关闭不常用的内容。',
                      style: TextStyle(color: CampusColors.muted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView(
                  buildDefaultDragHandles: false,
                  onReorderItem: (oldIndex, newIndex) {
                    final next = [...preferences.order];
                    final id = next.removeAt(oldIndex);
                    next.insert(newIndex, id);
                    savePreferences(order: next);
                  },
                  children: [
                    for (var i = 0; i < preferences.order.length; i++)
                      AppTile(
                        key: ValueKey(preferences.order[i]),
                        leading: ReorderableDragStartListener(
                          index: i,
                          child: const SizedBox(
                            width: 48,
                            height: 48,
                            child: Tooltip(
                              message: '拖动排序',
                              child: Icon(Icons.drag_handle_rounded),
                            ),
                          ),
                        ),
                        title: Text(homeModules[preferences.order[i]]!),
                        trailing: AppSwitch(
                          value: preferences.enabled.contains(
                            preferences.order[i],
                          ),
                          onChanged: (value) {
                            final enabled = {...preferences.enabled};
                            value
                                ? enabled.add(preferences.order[i])
                                : enabled.remove(preferences.order[i]);
                            savePreferences(enabled: enabled);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    AppTextButton(
                      onPressed: () => savePreferences(
                        order: homeModules.keys.toList(),
                        enabled: homeModules.keys.toSet(),
                      ),
                      child: const Text('恢复默认'),
                    ),
                    const Spacer(),
                    AppButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Duration get motionDuration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final entries = brief.entries;
    final timeline =
        entries
            .where(
              (r) => const [
                'course',
                'event',
                'exam',
              ].contains(r['resource_type']),
            )
            .toList()
          ..sort(
            (a, b) => (at(a['start_at']) ?? DateTime.utc(9999)).compareTo(
              at(b['start_at']) ?? DateTime.utc(9999),
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
              (deadline(t) != null &&
                  deadline(t)!.isBefore(day.add(const Duration(days: 1)))),
        )
        .firstOrNull;
    final next = entries
        .where(
          (r) =>
              r['start_at'] != null &&
              (at(r['end_at']) ??
                      at(r['start_at'])!.add(const Duration(minutes: 1)))
                  .isAfter(now),
        )
        .firstOrNull;
    final start = DateTime.parse(
      '${widget.app.semester!['first_monday']}T00:00:00Z',
    );
    final week = (day.difference(start).inDays ~/ 7) + 1;
    final weekLabel = day.isBefore(start)
        ? '尚未开学'
        : week > widget.app.semester!['total_weeks']
        ? '学期已结束'
        : '第$week周';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${now.month}月${now.day}日 · 周${'一二三四五六日'[now.weekday - 1]}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: CampusColors.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '今日',
                    style: TextStyle(
                      fontSize: 32,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: CampusColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    weekLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      color: CampusColors.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            AppIconButton.outlined(
              tooltip: '调整首页内容',
              onPressed: editModules,
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (brief.busy && brief.data == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: LinearProgressIndicator(
              minHeight: 3,
              semanticsLabel: '正在读取今日安排',
            ),
          ),
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
                  onPressed: brief.busy ? null : reload,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        if (brief.data != null)
          AnimatedSwitcher(
            duration: motionDuration,
            child: next != null
                ? nextPanel(next)
                : emptyNextPanel(entries.isEmpty),
          ),
        if (urgent != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: urgentRow(urgent),
          ),
        Row(
          children: [
            const Expanded(
              child: Text(
                '全天安排',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            AppTextButton.icon(
              onPressed: widget.onCalendar,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('周日程'),
            ),
          ],
        ),
        if (brief.data != null) ...[
          if (timeline.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '今天没有已记录的课程或活动',
                style: TextStyle(fontSize: 16, color: CampusColors.muted),
              ),
            ),
          for (var i = 0; i < timeline.length; i++)
            timelineRow(timeline[i], last: i == timeline.length - 1),
        ],
        for (final id in preferences.order.where(preferences.enabled.contains))
          module(id, tasks, urgent),
      ],
    );
  }

  Widget nextPanel(Map<String, dynamic> row) {
    final begin = at(row['start_at'])!;
    final running = !begin.isAfter(now);
    final type = switch (row['resource_type']) {
      'course' => '课程',
      'exam' => '考试',
      'plan' => '个人计划',
      _ => '活动',
    };
    return Material(
      key: ValueKey('next-${row['id']}-$running'),
      color: CampusColors.blueSoft,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => open(row),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: running ? CampusColors.teal : CampusColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${running ? '进行中' : '下一安排'} · $type',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CampusColors.primary,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: CampusColors.primary,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                hhmm(begin),
                style: const TextStyle(
                  fontSize: 42,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  color: CampusColors.primary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${row['title']}',
                style: const TextStyle(
                  fontSize: 22,
                  height: 1.35,
                  color: CampusColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if ('${row['location'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 18,
                      color: CampusColors.muted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${row['location']}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: CampusColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget emptyNextPanel(bool empty) => Container(
    key: ValueKey('next-empty-$empty'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: CampusColors.surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.event_available_outlined,
          color: CampusColors.muted,
          size: 28,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                empty ? '今日暂无安排' : '暂无后续安排',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '可在日程中添加或查看安排',
                style: TextStyle(fontSize: 14, color: CampusColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget urgentRow(Map<String, dynamic> item) {
    final due = deadline(item);
    final label = due != null && due.isBefore(day)
        ? '截止日期已过'
        : due != null && due.isBefore(day.add(const Duration(days: 1)))
        ? '今日截止'
        : '优先处理';
    return Material(
      color: CampusColors.errorSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => open(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.priority_high_rounded,
                  color: CampusColors.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: CampusColors.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item['title']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget timelineRow(Map<String, dynamic> row, {required bool last}) {
    final begin = at(row['start_at']), end = at(row['end_at']);
    final past = end != null && !end.isAfter(now);
    final current =
        begin != null && end != null && !begin.isAfter(now) && end.isAfter(now);
    final palette = CoursePalette.forTitle('${row['title']}');
    final type = switch (row['resource_type']) {
      'course' => '课程',
      'exam' => '考试',
      _ => '活动',
    };
    return Semantics(
      container: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: MediaQuery.textScalerOf(context).scale(52),
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      begin == null ? '待定' : hhmm(begin),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: current
                            ? CampusColors.primary
                            : CampusColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (end != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        hhmm(end),
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
            SizedBox(
              width: 16,
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    bottom: last ? 30 : 0,
                    left: 4,
                    child: Container(width: 2, color: CampusColors.line),
                  ),
                  Positioned(
                    top: 18,
                    left: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: current ? CampusColors.primary : palette.ink,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AnimatedContainer(
                  constraints: const BoxConstraints(minHeight: 72),
                  duration: motionDuration,
                  decoration: BoxDecoration(
                    color: past ? CampusColors.background : palette.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: current ? palette.ink : Colors.transparent,
                      width: current ? 1.5 : 1,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => open(row),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${row['title']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: past ? CampusColors.muted : palette.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                type,
                                if ('${row['location'] ?? ''}'.isNotEmpty)
                                  '${row['location']}',
                                if (current) '进行中' else if (past) '已结束',
                              ].join(' · '),
                              style: TextStyle(
                                fontSize: 12,
                                color: past ? CampusColors.muted : palette.ink,
                              ),
                            ),
                            if (begin == null)
                              Text(
                                calendarTimeLabel(row),
                                style: const TextStyle(
                                  fontSize: 12,
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
            ),
          ],
        ),
      ),
    );
  }

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
        subtitle: Padding(
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
    if (id == 'plans') {
      final rows = brief.entries
          .where((r) => r['resource_type'] == 'plan')
          .toList();
      if (rows.isEmpty) return const SizedBox();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section('个人计划', icon: Icons.event_note_outlined),
          for (final r in rows) recordRow(r),
        ],
      );
    }
    if (id == 'windows') {
      if (!brief.fresh(revision ?? 0)) return const SizedBox();
      final suggestions = brief.suggestions;
      if (suggestions.isEmpty) return const SizedBox();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section('可以处理的事', icon: Icons.auto_awesome_outlined),
          for (final suggestion in suggestions.take(2))
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
                    child: Text(suggestion['action_label']),
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
        .where((r) => r['id'] != urgent?['id'] && upcoming(r))
        .take(3)
        .toList();
    if (list.isEmpty) return const SizedBox();
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
                itemTimeLabel(list[i]),
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
