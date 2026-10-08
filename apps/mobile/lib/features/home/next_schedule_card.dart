import 'package:flutter/material.dart';
import '../../app/controller.dart' show schoolTime, hhmm;
import '../../ui/v2/shiri_tokens.dart' as v2;
import '../../ui/v2/motion/rolling_number.dart';
import '../../ui/v2/motion/now_pulse.dart';

class NextScheduleCard extends StatelessWidget {
  const NextScheduleCard({
    super.key,
    required this.row,
    required this.now,
    required this.onOpen,
  });
  final Map<String, dynamic> row;
  final DateTime now;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final shiri = context.shiri, start = schoolTime(row['start_at']);
    final end = row['end_at'] == null ? null : schoolTime(row['end_at']);
    final ongoing = !start.isAfter(now) && end?.isAfter(now) == true;
    final minutes = (ongoing ? end! : start).difference(now).inMinutes;
    final course = row['resource_type'] == 'course';
    final palette = v2.CoursePalette.forTitle('${row['title']}');
    final details = [
      '${hhmm(start)}${end == null ? '' : '–${DateUtils.isSameDay(start, end) ? hhmm(end) : '${end.month}/${end.day} ${hhmm(end)}'}'}',
      if ('${row['location'] ?? ''}'.trim().isNotEmpty) '${row['location']}',
      if (row['resource_type'] == 'exam') '考试',
      if (row['resource_type'] == 'plan') '学习安排',
    ];
    return Container(
      key: const Key('today-next-card'),
      decoration: shiri.raisedDecoration(borderRadius: v2.ShiriRadius.xlAll),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 5,
                child: ColoredBox(
                  color: course ? palette.accent : shiri.colors.successAccent,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        NowDot(time: now),
                        Text(
                          ongoing
                              ? (course ? '正在上课' : '正在进行')
                              : (course ? '下一节' : '下一项'),
                          style: shiri.text.bodyStrong.copyWith(
                            color: shiri.colors.ink500,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: shiri.colors.primarySoft,
                            borderRadius: v2.ShiriRadius.smAll,
                          ),
                          child: RollingNumber.text(
                            ongoing ? '还剩 $minutes 分钟' : '$minutes 分钟后',
                            style: shiri.text.label.copyWith(
                              color: shiri.colors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(hhmm(start), style: shiri.text.numL),
                        Text('${row['title']}', style: shiri.text.title),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      details.join(' · '),
                      style: shiri.text.bodySmall.copyWith(
                        color: shiri.colors.ink500,
                      ),
                    ),
                    if (ongoing && end != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        label: '正在进行',
                        child: ClipRRect(
                          borderRadius: v2.ShiriRadius.pillAll,
                          child: SizedBox(
                            height: 4,
                            width: double.infinity,
                            child: Stack(
                              children: [
                                ColoredBox(
                                  color: shiri.colors.surfaceSunken,
                                  child: const SizedBox.expand(),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    heightFactor: 1,
                                    widthFactor:
                                        (now.difference(start).inSeconds /
                                                end.difference(start).inSeconds)
                                            .clamp(0.0, 1.0),
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: v2.ShiriGradients.brand,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
