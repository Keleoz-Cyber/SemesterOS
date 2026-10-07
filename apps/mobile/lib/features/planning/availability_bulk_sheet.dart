import 'package:flutter/material.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_sheet.dart';
import '../../ui/app_time_range_picker.dart';
import '../../ui/campus_theme.dart';

class WeeklyTimePattern {
  final Set<int> days;
  final List<AppClockRange> windows;
  final bool replace;
  const WeeklyTimePattern({
    required this.days,
    required this.windows,
    this.replace = false,
  });
  Map<String, dynamic> toJson() => {
    'days': days.toList()..sort(),
    'windows': [
      for (final w in windows) {'start': w.startMinutes, 'end': w.endMinutes},
    ],
  };
  static WeeklyTimePattern? fromJson(dynamic data) {
    if (data is! Map || data['days'] is! List || data['windows'] is! List) {
      return null;
    }
    final days = (data['days'] as List)
        .whereType<int>()
        .where((v) => v >= 1 && v <= 7)
        .toSet();
    final windows = <AppClockRange>[];
    for (final row in data['windows'] as List) {
      if (row is! Map || row['start'] is! int || row['end'] is! int) {
        return null;
      }
      final a = row['start'] as int, b = row['end'] as int;
      if (a < 0 || b <= a || b > 1440) return null;
      windows.add(AppClockRange(startMinutes: a, endMinutes: b));
    }
    return days.isEmpty || windows.isEmpty
        ? null
        : WeeklyTimePattern(days: days, windows: windows);
  }
}

/// Apply to the draft only. Existing ranges are retained unless replacement was chosen.
List<Map<String, dynamic>> applyWeeklyPattern(
  List<Map<String, dynamic>> existing,
  WeeklyTimePattern pattern,
) {
  int minute(String s) {
    final p = s.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  final result = <Map<String, dynamic>>[];
  for (var day = 1; day <= 7; day++) {
    final ranges = <AppClockRange>[
      if (!pattern.replace || !pattern.days.contains(day))
        for (final row in existing.where((r) => r['weekday'] == day))
          AppClockRange(
            startMinutes: minute(row['start']),
            endMinutes: minute(row['end']),
          ),
      if (pattern.days.contains(day)) ...pattern.windows,
    ]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    final merged = <AppClockRange>[];
    for (final range in ranges) {
      if (merged.isNotEmpty && range.startMinutes <= merged.last.endMinutes) {
        final old = merged.removeLast();
        merged.add(
          AppClockRange(
            startMinutes: old.startMinutes,
            endMinutes: old.endMinutes > range.endMinutes
                ? old.endMinutes
                : range.endMinutes,
          ),
        );
      } else {
        merged.add(range);
      }
    }
    for (final range in merged) {
      result.add({
        'weekday': day,
        'start': range.startText,
        'end': range.endText,
      });
    }
  }
  return result;
}

Future<WeeklyTimePattern?> showWeeklyTimePattern(
  BuildContext context,
  WeeklyTimePattern initial,
) => showAppSheet<WeeklyTimePattern>(
  context: context,
  heightFactor: .88,
  builder: (_) => _WeeklyTimePatternSheet(initial: initial),
);

class _WeeklyTimePatternSheet extends StatefulWidget {
  final WeeklyTimePattern initial;
  const _WeeklyTimePatternSheet({required this.initial});
  @override
  State<_WeeklyTimePatternSheet> createState() =>
      _WeeklyTimePatternSheetState();
}

class _WeeklyTimePatternSheetState extends State<_WeeklyTimePatternSheet> {
  late final Set<int> days = {...widget.initial.days};
  late final List<AppClockRange> windows = [...widget.initial.windows];
  bool replace = false;
  Future<void> edit([int? index]) async {
    final current = index == null ? null : windows[index];
    final next = await showAppClockRangePicker(
      context: context,
      title: '学习时段',
      initialStartMinutes: current?.startMinutes ?? 19 * 60,
      initialEndMinutes: current?.endMinutes ?? 21 * 60,
      allowEndOfDay: true,
    );
    if (next == null || !mounted) return;
    setState(() {
      if (index == null) {
        windows.add(next);
      } else {
        windows[index] = next;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AppSheetHeading(title: '批量设置学习时段'),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '应用到',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var d = 1; d <= 7; d++)
                    AppFilterChip(
                      key: ValueKey('bulk-weekday-$d'),
                      selected: days.contains(d),
                      label: Text('周${'一二三四五六日'[d - 1]}'),
                      onSelected: (v) => setState(() {
                        if (v) {
                          days.add(d);
                        } else {
                          days.remove(d);
                        }
                      }),
                    ),
                ],
              ),
              Wrap(
                spacing: 4,
                children: [
                  for (final entry in {
                    '每天': {1, 2, 3, 4, 5, 6, 7},
                    '工作日': {1, 2, 3, 4, 5},
                    '周末': {6, 7},
                  }.entries)
                    AppTextButton(
                      onPressed: () => setState(() {
                        days
                          ..clear()
                          ..addAll(entry.value);
                      }),
                      child: Text(entry.key),
                    ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '时间段',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AppIconButton(
                    tooltip: '添加批量时段',
                    onPressed: () => edit(),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              for (var i = 0; i < windows.length; i++)
                AppTile(
                  key: ValueKey('bulk-window-$i'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.schedule_rounded,
                    color: CampusColors.teal,
                    size: 20,
                  ),
                  title: Text(
                    '${windows[i].startText}—${windows[i].endText}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () => edit(i),
                  trailing: AppIconButton(
                    tooltip: '移除批量时段',
                    onPressed: () => setState(() => windows.removeAt(i)),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ),
              if (windows.isEmpty)
                const Text(
                  '添加一个时间段',
                  style: TextStyle(color: CampusColors.muted),
                ),
              const SizedBox(height: 12),
              AppCheckRow(
                title: const Text('替换所选星期的原有时段'),
                value: replace,
                onChanged: (v) => setState(() => replace = v ?? false),
              ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: AppButton(
          key: const Key('bulk-apply'),
          onPressed: days.isEmpty || windows.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  WeeklyTimePattern(
                    days: days,
                    windows: windows,
                    replace: replace,
                  ),
                ),
          child: Text('应用到 ${days.length} 天'),
        ),
      ),
    ],
  );
}
