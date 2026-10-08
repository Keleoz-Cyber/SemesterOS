import '../../ui/app_controls.dart';
import '../../ui/app_time_range_picker.dart';
import '../../ui/app_selection.dart';
import '../../core/api.dart' show userError;
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import 'date_time_picker.dart';
import 'availability_bulk_sheet.dart';
import '../../ui/v2/motion/skeleton.dart';
import '../../ui/v2/shiri_tokens.dart';

class AvailabilityPage extends StatefulWidget {
  final ItemsController controller;
  const AvailabilityPage({super.key, required this.controller});
  @override
  State<AvailabilityPage> createState() => _AvailabilityPageState();
}

class _AvailabilityPageState extends State<AvailabilityPage> {
  List<Map<String, dynamic>> weekly = [], exclusions = [];
  int? version;
  bool busy = false;
  int selectedDay = 1;
  String? error, lastBody, requestKey;
  late final String? openedSemester, openedOwner;
  late final int openedGeneration;
  bool get sameContext =>
      widget.controller.semesterId == openedSemester &&
      widget.controller.owner == openedOwner &&
      widget.controller.api.generation == openedGeneration;
  @override
  void initState() {
    super.initState();
    openedSemester = widget.controller.semesterId;
    openedOwner = widget.controller.owner;
    openedGeneration = widget.controller.api.generation;
    load();
  }

  Future<void> load() async {
    if (!sameContext) {
      setState(() => error = '账号或学期已切换，请返回后重新打开设置');
      return;
    }
    try {
      final data = await widget.controller.getAvailability();
      if (mounted && sameContext) {
        setState(() {
          version = data['version'];
          weekly = List<Map<String, dynamic>>.from(data['weekly']);
          exclusions = List<Map<String, dynamic>>.from(data['exclusions']);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    }
  }

  int minuteOf(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  Future<void> editWindow(int day, [Map<String, dynamic>? original]) async {
    if (!sameContext) return;
    final window = await showAppClockRangePicker(
      context: context,
      title: '周${'一二三四五六日'[day - 1]}学习时段',
      initialStartMinutes: minuteOf(original?['start'] ?? '19:00'),
      initialEndMinutes: minuteOf(original?['end'] ?? '21:00'),
      allowEndOfDay: true,
    );
    if (window == null || !mounted || !sameContext) return;
    setState(() {
      if (original != null) weekly.remove(original);
      weekly.add({
        'weekday': day,
        'start': window.startText,
        'end': window.endText,
      });
      weekly.sort(
        (a, b) => '${a['weekday']}${a['start']}'.compareTo(
          '${b['weekday']}${b['start']}',
        ),
      );
      error = null;
    });
  }

  Future<void> bulkSet() async {
    if (!sameContext || busy) return;
    final key = 'weekly-time-pattern:$openedOwner';
    WeeklyTimePattern? remembered;
    try {
      remembered = WeeklyTimePattern.fromJson(
        await widget.controller.cache.read(key),
      );
    } catch (_) {}
    if (!mounted || !sameContext) return;
    final dayWindows = weekly
        .where((row) => row['weekday'] == selectedDay)
        .map(
          (row) => AppClockRange(
            startMinutes: minuteOf(row['start']),
            endMinutes: minuteOf(row['end']),
          ),
        )
        .toList();
    final selected = await showWeeklyTimePattern(
      context,
      remembered ??
          WeeklyTimePattern(
            days: {1, 2, 3, 4, 5, 6, 7},
            windows: dayWindows.isEmpty
                ? [
                    const AppClockRange(
                      startMinutes: 19 * 60,
                      endMinutes: 21 * 60,
                    ),
                  ]
                : dayWindows,
          ),
    );
    if (selected == null || !mounted || !sameContext) return;
    setState(() {
      weekly = applyWeeklyPattern(weekly, selected);
      error = null;
    });
    try {
      await widget.controller.cache.write(key, selected.toJson());
    } catch (_) {}
  }

  Future<void> editExclusion([Map<String, dynamic>? original]) async {
    if (!sameContext) return;
    final selected = await pickSchoolDateTimeRange(
      context,
      title: '不可用时段',
      initialStart: original == null
          ? null
          : DateTime.parse(original['start_at']),
      initialEnd: original == null ? null : DateTime.parse(original['end_at']),
      initialLabel: original?['label'] ?? '',
      showLabel: true,
    );
    if (selected == null || !mounted || !sameContext) return;
    setState(() {
      if (original != null) exclusions.remove(original);
      exclusions.add({
        'start_at': selected.start.toIso8601String(),
        'end_at': selected.end.toIso8601String(),
        'label': selected.label,
      });
      error = null;
    });
  }

  List<Widget> summary(Map<String, dynamic> data) {
    final groups = <String, Set<int>>{};
    for (final row in data['weekly']) {
      groups
          .putIfAbsent('${row['start']}—${row['end']}', () => <int>{})
          .add(row['weekday'] as int);
    }
    String weekdays(Set<int> values) {
      final days = values.toList()..sort();
      if (days.length == 7) return '每天';
      if (days.length == 5 && days.first == 1 && days.last == 5) {
        return '周一至周五';
      }
      if (days.length == 2 && days.first == 6 && days.last == 7) return '周末';
      return days.map((day) => '周${'一二三四五六日'[day - 1]}').join('、');
    }

    final excluded = List<Map<String, dynamic>>.from(data['exclusions']);
    return [
      for (final entry in groups.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('${weekdays(entry.value)}  ${entry.key}'),
        ),
      if (groups.isEmpty) const Text('未安排每周学习时段'),
      if (excluded.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('临时不可用 · ${excluded.length}段'),
        for (final row in excluded)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              [
                if ('${row['label'] ?? ''}'.trim().isNotEmpty)
                  '${row['label']}',
                displayInterval(row['start_at'], row['end_at']),
              ].join('\n'),
              style: const TextStyle(fontSize: 13, color: CampusColors.muted),
            ),
          ),
      ],
    ];
  }

  Future<void> save() async {
    if (!sameContext) {
      setState(() => error = '账号或学期已切换，请返回后重新打开设置');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final input = {
        'expected_version': version,
        'weekly': weekly,
        'exclusions': exclusions,
      };
      final preview = await widget.controller.previewAvailability(input);
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AppDialog(
          title: const Text('确认新的可学习时间'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '原设置',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                ...summary(Map<String, dynamic>.from(preview['before'])),
                const Divider(),
                const Text(
                  '确认后采用',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                ...summary(Map<String, dynamic>.from(preview['after'])),
                const SizedBox(height: 12),
                if ((preview['affected_plan_count'] ?? 0) > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    '调整后，${preview['affected_plan_count']}段已有计划将落在不可用时段。保存后会标出冲突，你可以再调整这些计划。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  for (final b in preview['affected_blocks'])
                    Text(
                      '${displayInstant(b['start_at'])} 至 ${displayInstant(b['end_at'])}',
                    ),
                ],
              ],
            ),
          ),
          actions: [
            AppTextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            AppButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认保存学习时间'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
      if (!sameContext) {
        setState(() => error = '账号或学期已切换，请返回后重新打开设置');
        return;
      }
      final data = {...input, 'expected_revision': preview['base_revision']};
      data['confirm_plan_conflicts'] =
          (preview['affected_plan_count'] ?? 0) > 0;
      final encoded = jsonEncode(data);
      if (lastBody != encoded) {
        lastBody = encoded;
        requestKey =
            'availability-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
      }
      await widget.controller.saveAvailability(
        data,
        idempotencyKey: requestKey,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('学习时间')),
    bottomNavigationBar: version == null
        ? null
        : ActionFooter(
            label: busy ? '正在核对…' : '核对并保存学习时间',
            icon: Icons.fact_check_outlined,
            onPressed: busy ? null : save,
          ),
    body: version == null
        ? Center(
            child: error == null
                ? const SkeletonScope(
                    semanticLabel: '正在读取学习时间',
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SkeletonLine(widthFactor: .5),
                          SizedBox(height: 20),
                          SkeletonBox(
                            height: 48,
                            borderRadius: ShiriRadius.smAll,
                          ),
                          SizedBox(height: 20),
                          SkeletonBox(
                            height: 120,
                            borderRadius: ShiriRadius.lgAll,
                          ),
                          SizedBox(height: 28),
                          SkeletonLine(widthFactor: .6),
                        ],
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      AppTextButton(onPressed: load, child: const Text('重试')),
                    ],
                  ),
          )
        : ListView(
            padding: const EdgeInsets.all(20),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              EditorSection(
                title: '每周学习时段',
                icon: Icons.view_week_outlined,
                subtitle: '每周重复 · 已排课程会自动避开',
                action: AppTextButton.icon(
                  key: const Key('availability-bulk'),
                  onPressed: busy ? null : bulkSet,
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: const Text('批量设置'),
                ),
                children: [
                  AppSegmentedControl<int>(
                    value: selectedDay,
                    enabled: !busy,
                    options: {
                      for (var day = 1; day <= 7; day++)
                        day: '周${'一二三四五六日'[day - 1]}',
                    },
                    onChanged: (day) => setState(() => selectedDay = day),
                  ),
                  const Divider(height: 28),
                  for (final day in [selectedDay]) ...[
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Text(
                          '${weekly.where((row) => row['weekday'] == day).length}段学习时间',
                          style: const TextStyle(color: CampusColors.muted),
                        ),
                        AppTextButton.icon(
                          onPressed: busy ? null : () => editWindow(day),
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('添加时段'),
                        ),
                      ],
                    ),
                    for (final row in weekly.where((r) => r['weekday'] == day))
                      AppTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        leading: const Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: CampusColors.teal,
                        ),
                        title: Text(
                          '${row['start']}—${row['end']}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: busy ? null : () => editWindow(day, row),
                        trailing: AppIconButton(
                          tooltip: '移除此时段',
                          onPressed: busy
                              ? null
                              : () => setState(() => weekly.remove(row)),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    if (!weekly.any((row) => row['weekday'] == day))
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '这天还没有学习时段',
                          style: TextStyle(color: CampusColors.muted),
                        ),
                      ),
                  ],
                ],
              ),
              EditorSection(
                title: '临时不可用时段',
                icon: Icons.event_busy_outlined,
                accent: CampusColors.teal,
                action: AppIconButton.filledTonal(
                  tooltip: '添加临时不可用时段',
                  onPressed: busy ? null : () => editExclusion(),
                  icon: const Icon(Icons.add_rounded),
                ),
                children: [
                  if (exclusions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        '活动、休息等不能学习的时间，可以单独排除。',
                        style: TextStyle(color: CampusColors.muted),
                      ),
                    ),
                  for (final row in exclusions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0,
                          vertical: 8,
                        ),
                        title: Text(
                          displayInterval(row['start_at'], row['end_at']),
                        ),
                        subtitle: '${row['label'] ?? ''}'.trim().isEmpty
                            ? null
                            : Text('${row['label']}'),
                        onTap: busy ? null : () => editExclusion(row),
                        trailing: AppIconButton(
                          tooltip: '移除此不可用时段',
                          onPressed: busy
                              ? null
                              : () => setState(() => exclusions.remove(row)),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (error != null) ...[
                SoftNotice(error!, warning: true),
                const SizedBox(height: 12),
              ],
            ],
          ),
  );
}
