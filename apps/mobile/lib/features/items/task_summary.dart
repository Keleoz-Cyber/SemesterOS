import 'package:flutter/material.dart';
import '../../app/controller.dart' show schoolNow;
import '../../ui/time_urgency.dart' show itemDeadline;
import '../../ui/v2/shiri_tokens.dart';
import '../../ui/v2/motion/rolling_number.dart';
import '../../ui/v2/motion/skeleton.dart';

/// Presentation grouping keeps the original time precision. A stated date is
/// grouped as that date, without inventing a midnight deadline.
DateTime? taskDisplayDate(Map<String, dynamic> row) {
  final time = row['time'] as Map?;
  if (time?['precision'] == 'date' &&
      (time?['meaning'] == null ||
          time?['meaning'] == 'deadline' ||
          time?['meaning'] == 'unspecified')) {
    return DateTime.tryParse('${time?['date']}');
  }
  return itemDeadline(row, schoolClock: true);
}

int taskDisplayGroup(Map<String, dynamic> row, DateTime now) {
  if (row['kind'] == 'exam') return 6;
  final meaning = row['time']?['meaning'];
  if (meaning != null && meaning != 'deadline' && meaning != 'unspecified') {
    return 5;
  }
  final point = taskDisplayDate(row);
  if (point == null) return 4;
  final date = DateTime.utc(point.year, point.month, point.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  if (date.isBefore(today)) return 0;
  if (date == today) return 1;
  final end = today.add(Duration(days: 8 - today.weekday));
  return date.isBefore(end) ? 2 : 3;
}

class TaskSummaryCards extends StatelessWidget {
  const TaskSummaryCards({
    super.key,
    required this.rows,
    this.available = true,
    this.loading = false,
  });
  final List<Map<String, dynamic>> rows;
  final bool available, loading;
  @override
  Widget build(BuildContext context) {
    final now = schoolNow(), shiri = context.shiri;
    if (!available) {
      if (!loading) return const SizedBox.shrink();
      return SkeletonScope(
        semanticLabel: '正在读取任务统计',
        child: _SummaryLayout(
          builder: (context, wideText) => [
            for (var i = 0; i < 3; i++)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: shiri.cardDecoration(
                  borderRadius: ShiriRadius.lgAll,
                ),
                child: wideText
                    ? Row(
                        children: [
                          Expanded(
                            child: SkeletonLine(
                              widthFactor: .5,
                              style: shiri.text.label,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 52,
                            child: SkeletonLine(style: shiri.text.numL),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SkeletonLine(widthFactor: .5, style: shiri.text.numL),
                          const SizedBox(height: 6),
                          Text(
                            const ['今天截止', '本周', '未定日期'][i],
                            style: shiri.text.label.copyWith(
                              color: shiri.colors.ink500,
                            ),
                          ),
                        ],
                      ),
              ),
          ],
        ),
      );
    }
    final active = rows.where(
      (r) => r['lifecycle'] == 'active' && r['kind'] != 'exam',
    );
    final groups = [for (final row in active) taskDisplayGroup(row, now)];
    final today = DateTime.utc(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final until = monday.add(const Duration(days: 7));
    final weekCount = active.where((row) {
      final date = taskDisplayDate(row);
      return date != null && !date.isBefore(monday) && date.isBefore(until);
    }).length;
    final counts = [
      groups.where((g) => g == 1).length,
      weekCount,
      groups.where((g) => g == 4).length,
    ];
    const labels = ['今天截止', '本周', '未定日期'];
    return _SummaryLayout(
      values: counts.map((v) => '$v').toList(),
      builder: (context, wideText) => [
        for (var i = 0; i < labels.length; i++)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: shiri.cardDecoration(borderRadius: ShiriRadius.lgAll),
            child: wideText
                ? Row(
                    children: [
                      Expanded(
                        child: Text(
                          labels[i],
                          style: shiri.text.label.copyWith(
                            color: shiri.colors.ink500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      RollingNumber(
                        value: counts[i],
                        style: shiri.text.numL.copyWith(
                          color: i == 0 && counts[i] > 0
                              ? shiri.colors.danger
                              : shiri.colors.ink900,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RollingNumber(
                        value: counts[i],
                        style: shiri.text.numL.copyWith(
                          color: i == 0 && counts[i] > 0
                              ? shiri.colors.danger
                              : shiri.colors.ink900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        labels[i],
                        style: shiri.text.label.copyWith(
                          color: shiri.colors.ink500,
                        ),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}

class _SummaryLayout extends StatelessWidget {
  const _SummaryLayout({
    required this.builder,
    this.values = const ['0', '0', '0'],
  });
  final List<String> values;
  final List<Widget> Function(BuildContext, bool) builder;
  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final width = MediaQuery.sizeOf(context).width;
    return LayoutBuilder(
      builder: (context, box) {
        final columnWidth = (box.maxWidth - 24) / 3;
        var requiredWidth = 0.0;
        for (final value in values) {
          final text = TextPainter(
            text: TextSpan(text: value, style: context.shiri.text.numL),
            textScaler: scaler,
            textDirection: Directionality.of(context),
          )..layout();
          if (text.width > requiredWidth) requiredWidth = text.width;
          text.dispose();
        }
        final wideText = requiredWidth + 32 > columnWidth || width < 280;
        final cells = builder(context, wideText);
        if (wideText) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                cells[i],
              ],
            ],
          );
        }
        var labelHeight = 0.0, numberHeight = 0.0;
        for (final label in const ['今天截止', '本周', '未定日期']) {
          final text = TextPainter(
            text: TextSpan(text: label, style: context.shiri.text.label),
            textScaler: scaler,
            textDirection: Directionality.of(context),
          )..layout(maxWidth: (columnWidth - 32).clamp(1.0, double.infinity));
          if (text.height > labelHeight) labelHeight = text.height;
          text.dispose();
        }
        for (final value in values) {
          final text = TextPainter(
            text: TextSpan(text: value, style: context.shiri.text.numL),
            textScaler: scaler,
            textDirection: Directionality.of(context),
          )..layout();
          if (text.height > numberHeight) numberHeight = text.height;
          text.dispose();
        }
        final height = 32 + numberHeight + 6 + labelHeight;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: height),
                  child: cells[i],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class TaskGroupHeading extends StatelessWidget {
  const TaskGroupHeading({super.key, required this.group, required this.count});
  final int group, count;
  @override
  Widget build(BuildContext context) {
    final shiri = context.shiri;
    final color = group == 7
        ? shiri.colors.primary
        : group == 8
        ? shiri.colors.warningAccent
        : group <= 1
        ? shiri.colors.dangerAccent
        : group == 2
        ? shiri.colors.warningAccent
        : shiri.colors.lineStrong;
    const labels = [
      '已逾期',
      '今天',
      '本周',
      '下周及以后',
      '未定日期',
      '其他事项',
      '考试',
      '优先处理',
      '需要留意',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  labels[group],
                  style: shiri.text.bodyStrong.copyWith(
                    color: shiri.colors.ink500,
                  ),
                ),
                RollingNumber(
                  value: count,
                  style: shiri.text.bodySmall.copyWith(
                    color: shiri.colors.ink500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
