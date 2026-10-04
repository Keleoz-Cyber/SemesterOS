import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../notices/notice_fields.dart';

List<String> eventDisplayTags(Map<String, dynamic> row, String? category) {
  String normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s（）()·\-]'), '');
  final title = normalize('${row['title'] ?? ''}');
  final names = <String>{};
  for (final value in row['tags'] as List? ?? []) {
    final name = '${value is Map ? value['name'] ?? '' : value}'.trim();
    if (name.isNotEmpty &&
        name != category &&
        !title.contains(normalize(name))) {
      names.add(name);
    }
  }
  return names.toList();
}

class EventOverview extends StatelessWidget {
  final Map<String, dynamic> row;
  final String? category;
  const EventOverview({super.key, required this.row, this.category});

  @override
  Widget build(BuildContext context) {
    final time = noticeMap(row['time']);
    final at = DateTime.tryParse('${time['at']}');
    final local = at == null ? null : schoolTime('${time['at']}');
    final end = DateTime.tryParse('${time['end_at']}');
    final endLocal = end == null ? null : schoolTime('${time['end_at']}');
    final sameDay =
        local != null &&
        endLocal != null &&
        calendarDay(local) == calendarDay(endLocal);
    final when = local == null
        ? noticeTime(time)
        : '${hhmm(local)}${endLocal == null ? '' : '—${sameDay ? hhmm(endLocal) : noticeClock(time['end_at'])}'}';
    final date = local == null
        ? null
        : '${local.year == schoolNow().year ? '' : '${local.year}年'}${local.month}月${local.day}日 · 周${'一二三四五六日'[local.weekday - 1]}';
    final location = '${row['location'] ?? ''}'.trim();
    final tags = eventDisplayTags(row, category);
    final states = <String>[
      if (row['lifecycle'] == 'cancelled') '已取消',
      if (row['certainty'] == 'tentative') '暂定',
      if (row['reserve_time'] == false) '仅作参考',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${row['title']}',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: CampusColors.ink,
            height: 1.3,
          ),
        ),
        if (states.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              states.join(' · '),
              style: const TextStyle(fontSize: 13, color: CampusColors.muted),
            ),
          ),
        if (when.isNotEmpty || location.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: CampusColors.surface,
                border: const Border(
                  top: BorderSide(color: CampusColors.teal, width: 3),
                  bottom: BorderSide(color: CampusColors.line),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (when.isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 4, right: 14),
                          child: Icon(
                            Icons.schedule_rounded,
                            size: 23,
                            color: CampusColors.teal,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                date ??
                                    (time['precision'] == 'date' ||
                                            time['precision'] == 'range'
                                        ? '日期'
                                        : '时间'),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: CampusColors.muted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              LayoutBuilder(
                                key: const ValueKey('event-when'),
                                builder: (context, bounds) {
                                  var style = TextStyle(
                                    fontSize: local == null && when.length > 16
                                      ? 16 :
                                        local == null ||
                                            !sameDay && endLocal != null
                                        ? 22
                                        : 30,
                                    fontWeight: FontWeight.w700,
                                    color: CampusColors.ink,
                                    height: 1.2,
                                  );
                                  if (sameDay) {
                                    bool fits(TextStyle value) {
                                      final painter = TextPainter(
                                        text: TextSpan(
                                          text: when,
                                          style: DefaultTextStyle.of(
                                            context,
                                          ).style.merge(value),
                                        ),
                                        textDirection: Directionality.of(
                                          context,
                                        ),
                                        textScaler: MediaQuery.textScalerOf(
                                          context,
                                        ),
                                      )..layout();
                                      final width = painter.width;
                                      painter.dispose();
                                      return width <= bounds.maxWidth;
                                    }

                                    if (!fits(style)) {
                                      style = style.copyWith(fontSize: 22);
                                      if (!fits(style)) {
                                        Widget clock(
                                          String label,
                                          DateTime value,
                                        ) => Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 48,
                                              child: Text(
                                                label,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: CampusColors.muted,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                hhmm(value),
                                                style: style,
                                              ),
                                            ),
                                          ],
                                        );
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            clock('开始', local),
                                            const SizedBox(height: 6),
                                            clock('结束', endLocal),
                                          ],
                                        );
                                      }
                                    }
                                    return Text(
                                      when,
                                      softWrap: false,
                                      style: style,
                                    );
                                  }
                                  return Text(when, style: style);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  if (when.isNotEmpty && location.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(height: 1, color: CampusColors.line),
                    ),
                  if (location.isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3, right: 14),
                          child: Icon(
                            Icons.place_outlined,
                            size: 23,
                            color: CampusColors.teal,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '地点',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CampusColors.muted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                location,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: CampusColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (category != null || tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              [?category, ...tags].join(' · '),
              style: const TextStyle(fontSize: 12, color: CampusColors.muted),
            ),
          ),
      ],
    );
  }

  String calendarDay(DateTime date) => '${date.year}-${date.month}-${date.day}';
}
