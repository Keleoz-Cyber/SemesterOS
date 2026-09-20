import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';

String kindLabel(String? kind) => switch (kind) {
  'exam' => '考试',
  'assignment' => '作业',
  _ => '个人任务',
};
String itemTimeLabel(Map<String, dynamic> item) {
  final t = Map<String, dynamic>.from(item['time'] ?? {});
  final suffix = item['kind'] == 'exam' ? '开始' : '截止';
  return switch (t['precision']) {
    'exact' => '${displayInstant(t['at'])} $suffix',
    'date' =>
      '${t['date']} $suffix${t['day_end_confirmed'] == true ? ' · 已确认当天结束前' : ' · 时刻待确认'}',
    'week' => '第${t['week']}周 · 具体日期待确认',
    'range' => '${t['date']} 至 ${t['end_date']} · 具体时间待确认',
    _ => '时间待确认',
  };
}

String displayInstant(String? value) {
  if (value == null) return '时间待确认';
  final t = schoolTime(value);
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${hhmm(t)}';
}

String reminderState(String? value) => switch (value) {
  'scheduled' => '待提醒',
  'expired' => '已过期，不补发',
  'needs_review' => '时间变化，请核对',
  'disabled' => '已停用',
  _ => '待补充具体时间',
};
String reminderLabel(Map<String, dynamic> r) => r['mode'] == 'absolute'
    ? '指定时刻'
    : (r['lead_minutes'] == 0
          ? '事项开始时'
          : '提前${(r['lead_minutes'] as int) % 1440 == 0
                ? '${r['lead_minutes'] ~/ 1440}天'
                : (r['lead_minutes'] as int) % 60 == 0
                ? '${r['lead_minutes'] ~/ 60}小时'
                : '${r['lead_minutes']}分钟'}');

List<Map<String, dynamic>> orderedItems(List<Map<String, dynamic>> input) {
  String order(Map<String, dynamic> item) =>
      '${item['anchor_at'] ?? item['time']?['date'] ?? '9999'}';
  return [...input]..sort((a, b) => order(a).compareTo(order(b)));
}

class ItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  const ItemCard({super.key, required this.item, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final palette = CoursePalette.forTitle(
      '${item['course_title'] ?? item['title']}',
    );
    final active = item['lifecycle'] == 'active';
    final overdue =
        active &&
        item['anchor_at'] != null &&
        DateTime.parse(item['anchor_at']).isBefore(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(21),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    StatusPill(
                      kindLabel(item['kind']),
                      foreground: palette.ink,
                      background: palette.background,
                    ),
                    if (item['certainty'] == 'tentative')
                      const StatusPill(
                        '暂定',
                        foreground: Color(0xFF8B6417),
                        background: Color(0xFFFFF2CD),
                      ),
                    if (!active)
                      StatusPill(
                        item['lifecycle'] == 'completed' ? '已完成' : '已取消',
                      ),
                    if (overdue)
                      StatusPill(
                        item['kind'] == 'exam' ? '开始时间已过' : '已过截止',
                        foreground: const Color(0xFF9F241C),
                        background: const Color(0xFFFFF1EF),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${item['title']}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if ('${item['course_title'] ?? ''}'.isNotEmpty)
                  Text(
                    item['course_title'],
                    style: const TextStyle(color: CampusColors.muted),
                  ),
                const SizedBox(height: 8),
                Text(
                  itemTimeLabel(item),
                  style: const TextStyle(
                    fontSize: 13,
                    color: CampusColors.muted,
                  ),
                ),
                if (item['kind'] != 'exam' && active) ...[
                  const SizedBox(height: 6),
                  Text(
                    item['remaining_minutes'] == null
                        ? '耗时待补充'
                        : '预计剩余 ${item['remaining_minutes']} 分钟',
                    style: const TextStyle(
                      fontSize: 13,
                      color: CampusColors.primary,
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
}
