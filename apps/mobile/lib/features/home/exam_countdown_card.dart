import 'package:flutter/material.dart';
import '../../ui/v2/shiri_tokens.dart';
import '../../ui/v2/motion/rolling_number.dart';
import '../../ui/v2/motion/pressable.dart';
import '../items/item_widgets.dart';

class ExamCountdownCard extends StatelessWidget {
  const ExamCountdownCard({
    super.key,
    required this.item,
    required this.now,
    required this.date,
    required this.onOpen,
  });
  final Map<String, dynamic> item;
  final DateTime now;
  final DateTime? date;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final shiri = context.shiri;
    final days = date == null
        ? null
        : DateTime.utc(
            date!.year,
            date!.month,
            date!.day,
          ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
    final near = days != null && days <= 14;
    final accent = near ? shiri.colors.dangerAccent : shiri.colors.primary;
    final label = itemTimeLabel(item, includeMissing: false);
    return SizedBox(
      width: 232,
      child: Pressable(
        onPressed: onOpen,
        semanticLabel: '${item['title']}，考试',
        child: Container(
          decoration: shiri.cardDecoration(borderRadius: ShiriRadius.lgAll),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: near
                      ? LinearGradient(
                          colors: [accent, shiri.colors.dangerSoft],
                        )
                      : ShiriGradients.brand,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (days != null && days >= 0)
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          RollingNumber.text(
                            days == 0 ? '今天' : 'D-$days',
                            style: shiri.text.numXL.copyWith(
                              color: near
                                  ? shiri.colors.danger
                                  : shiri.colors.primary,
                            ),
                          ),
                          if (days > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Text(
                                '天后',
                                style: shiri.text.bodySmall.copyWith(
                                  color: shiri.colors.ink500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Text('${item['title']}', style: shiri.text.titleSmall),
                    if (label.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: shiri.text.bodySmall.copyWith(
                          color: shiri.colors.ink500,
                        ),
                      ),
                    ],
                    if ('${item['location'] ?? ''}'.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${item['location']}',
                        style: shiri.text.bodySmall.copyWith(
                          color: shiri.colors.ink500,
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
