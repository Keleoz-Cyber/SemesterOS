import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../ui/app_controls.dart';
import '../../ui/v2/shiri_tokens.dart';
import '../../ui/v2/motion/reduced_motion.dart';
import 'time_stats_card.dart';
import '../calendar/calendar_repository.dart';
import '../../ui/v2/motion/skeleton.dart';

/// Adapter from the complete weekly calendar response to the shared 7 × 24
/// grid. Date-only records remain labelled outside hour occupancy.
class WeekHeatmap extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final DateTime now;
  final ValueChanged<DateTime>? onDayTap;
  final bool available;
  final bool loading;
  final bool offline;
  final bool updating;
  final VoidCallback? onRetry;
  const WeekHeatmap({
    super.key,
    required this.items,
    required this.now,
    this.onDayTap,
    this.available = true,
    this.loading = false,
    this.offline = false,
    this.updating = false,
    this.onRetry,
  });
  @override
  Widget build(BuildContext context) {
    final monday = DateTime.utc(now.year, now.month, now.day - now.weekday + 1);
    if (!available && loading) {
      final shiri = context.shiri;
      return SkeletonScope(
        semanticLabel: '正在读取完整周日程',
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: shiri.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: SkeletonLine(
                  widthFactor: .35,
                  style: shiri.text.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              SkeletonLine(widthFactor: .75, style: shiri.text.bodySmall),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        children: [
                          const SkeletonBox(height: 14),
                          const SizedBox(height: 6),
                          const SkeletonBox(height: 72),
                          const SizedBox(height: 8),
                          const SkeletonBox(height: 14),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (!available) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CampusColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CampusColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('本周忙闲', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              loading ? '正在读取完整周日程…' : '暂时无法读取本周安排',
              style: const TextStyle(color: CampusColors.muted),
            ),
            if (!loading && onRetry != null)
              AppTextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
    }
    final values = [
      for (var i = 0; i < 7; i++)
        recordedTimeStats(
          items,
          monday.add(Duration(days: i)),
          monday.add(Duration(days: i + 1)),
        ),
    ];
    final dateOnly = <int, int>{};
    for (final original in items) {
      final row = calendarDisplayEntry(original);
      if (row['start_at'] != null || row['due_at'] != null) continue;
      final date = DateTime.tryParse(
        '${row['date'] ?? calendarTime(row)['date']}',
      );
      if (date != null &&
          !date.isBefore(monday) &&
          date.isBefore(monday.add(const Duration(days: 7)))) {
        dateOnly.update(date.weekday, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final undatedCount = dateOnly.values.fold<int>(0, (n, value) => n + value);
    final max = values.fold<int>(1, (m, r) => r.minutes > m ? r.minutes : m);
    final unknown = values.fold<int>(0, (n, r) => n + r.unknownDuration);
    final shiri = context.shiri;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: shiri.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(child: Text('本周忙闲', style: shiri.text.titleSmall)),
                const SizedBox(width: 8),
                Text(
                  updating ? '正在更新' : '',
                  style: shiri.text.label.copyWith(color: shiri.colors.ink500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (offline)
            Text(
              '离线查看已保存的完整周日程',
              style: shiri.text.bodySmall.copyWith(color: shiri.colors.ink500),
            ),
          Text(
            '已排时长 · 仅统计起止已知的占用',
            style: shiri.text.bodySmall.copyWith(color: shiri.colors.ink500),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth / 7).clamp(48.0, double.infinity);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 7; i++)
                      SizedBox(
                        width: width,
                        child: Semantics(
                          label:
                              '周${'一二三四五六日'[i]}，已排${values[i].minutes}分钟${values[i].unknownDuration > 0 ? '，${values[i].unknownDuration}项时长待核对' : ''}${(dateOnly[i + 1] ?? 0) > 0 ? '，${dateOnly[i + 1]}项未定时刻' : ''}',
                          button: onDayTap != null,
                          child: InkWell(
                            onTap: onDayTap == null
                                ? null
                                : () =>
                                      onDayTap!(monday.add(Duration(days: i))),
                            borderRadius: ShiriRadius.smAll,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    values[i].minutes == 0
                                        ? '0'
                                        : '${(values[i].minutes / 60).toStringAsFixed(1)}h',
                                    style: shiri.text.caption.copyWith(
                                      color: shiri.colors.ink500,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    height: 72,
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween(begin: 0, end: 1),
                                        duration: motionDuration(
                                          context,
                                          ShiriMotion.emphasized,
                                        ),
                                        curve: ShiriMotion.easeReveal,
                                        builder: (context, t, _) => Container(
                                          width: 20,
                                          height:
                                              (values[i].minutes / max * 64 +
                                                  4) *
                                              t,
                                          decoration: BoxDecoration(
                                            borderRadius: ShiriRadius.pillAll,
                                            gradient: i < 5
                                                ? ShiriGradients.brand
                                                : null,
                                            color: i >= 5
                                                ? shiri.colors.primarySoftStrong
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '一二三四五六日'[i],
                                    style: shiri.text.label.copyWith(
                                      color: shiri.colors.ink700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: now.weekday == i + 1
                                          ? ShiriColors.light.warningAccent
                                          : Colors.transparent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          if (undatedCount > 0)
            Text(
              '另有$undatedCount项未定时刻安排，未计入时长',
              style: shiri.text.bodySmall.copyWith(color: shiri.colors.ink500),
            ),
          if (unknown > 0)
            Text(
              '$unknown项时长待核对，未计入条形',
              style: shiri.text.bodySmall.copyWith(color: shiri.colors.ink500),
            ),
        ],
      ),
    );
  }
}
