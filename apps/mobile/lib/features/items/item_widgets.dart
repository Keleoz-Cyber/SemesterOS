import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';

String kindLabel(String? kind) => switch (kind) {
  'exam' => '考试',
  'assignment' => '作业',
  _ => '个人任务',
};
String itemTimeLabel(Map<String, dynamic> item, {bool includeMissing = true}) {
  final t = Map<String, dynamic>.from(item['time'] ?? {});
  final suffix = item['kind'] == 'exam' ? '开始' : '截止';
  return switch (t['precision']) {
    'exact' =>
      item['kind'] == 'exam' && t['end_at'] != null
          ? '${displayInstant(t['at'])} 至 ${displayInstant(t['end_at'])}'
          : '${displayInstant(t['at'])} $suffix',
    'date' =>
      '${t['date']} $suffix${t['day_end_confirmed'] == true ? ' · 已确认当天结束前' : (includeMissing ? ' · 时刻待确认' : '')}',
    'week' => '第${t['week']}周${includeMissing ? ' · 具体日期待确认' : ''}',
    'range' =>
      '${t['date']} 至 ${t['end_date']}${includeMissing ? ' · 具体时间待确认' : ''}',
    _ => '时间待确认',
  };
}

String displayInstant(String? value) {
  if (value == null) return '时间待确认';
  final t = schoolTime(value);
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${hhmm(t)}';
}

String _shortDate(DateTime date) {
  final monthDay = '${date.month}月${date.day}日';
  return date.year == DateTime.now().year ? monthDay : '${date.year}年$monthDay';
}

String _compactTimeLabel(Map<String, dynamic> item) {
  final time = Map<String, dynamic>.from(item['time'] ?? {});
  final suffix = item['kind'] == 'exam' ? '开始' : '截止';
  final at = DateTime.tryParse('${time['at']}');
  final end = DateTime.tryParse('${time['end_at']}');
  switch (time['precision']) {
    case 'exact' when at != null:
      final local = schoolTime(time['at']);
      if (item['kind'] == 'exam' && end != null) {
        final localEnd = schoolTime(time['end_at']);
        return local.year == localEnd.year &&
                local.month == localEnd.month &&
                local.day == localEnd.day
            ? '${_shortDate(local)} ${hhmm(local)}–${hhmm(localEnd)}'
            : '${_shortDate(local)} ${hhmm(local)}–${_shortDate(localEnd)} ${hhmm(localEnd)}';
      }
      return '${_shortDate(local)} ${hhmm(local)} $suffix';
    case 'date':
      final date = DateTime.tryParse('${time['date']}');
      return date == null ? '' : '${_shortDate(date)} $suffix';
    case 'week':
      return '第${time['week']}周';
    case 'range':
      final start = DateTime.tryParse('${time['date']}');
      final endDate = DateTime.tryParse('${time['end_date']}');
      return start == null || endDate == null
          ? ''
          : '${_shortDate(start)}–${_shortDate(endDate)}';
    default:
      return '';
  }
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
          ? '到时间时'
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
  final Widget? riskFooter;
  const ItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.riskFooter,
  });
  @override
  Widget build(BuildContext context) {
    final active = item['lifecycle'] == 'active';
    final exam = item['kind'] == 'exam';
    final overdue =
        active &&
        DateTime.tryParse(
              '${item['anchor_at'] ?? item['time']?['at']}',
            )?.isBefore(DateTime.now()) ==
            true;
    final course = '${item['course_title'] ?? ''}'.trim();
    final timeLabel = _compactTimeLabel(item);
    final remaining = item['remaining_minutes'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: CampusColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CampusColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    7,
                    12,
                    riskFooter == null ? 8 : 4,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: exam
                              ? CampusColors.teal.withValues(alpha: .1)
                              : CampusColors.blueSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          exam ? Icons.school_outlined : Icons.task_alt_rounded,
                          color: exam ? CampusColors.teal : CampusColors.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${item['title']}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: CampusColors.ink,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: CampusColors.muted,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 40),
                    child: Text(
                      [
                        kindLabel(item['kind']),
                        if (course.isNotEmpty) course,
                        if (item['certainty'] == 'tentative') '暂定',
                        if (!active)
                          item['lifecycle'] == 'completed' ? '已完成' : '已取消',
                        if (active && item['priority'] == 'high') '优先',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CampusColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (timeLabel.isNotEmpty || (!exam && active && remaining != null))
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        children: [
                          if (timeLabel.isNotEmpty)
                            Text(
                              '$timeLabel${overdue ? ' · 已过期' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: overdue
                                    ? Theme.of(context).colorScheme.error
                                    : CampusColors.primary,
                              ),
                            ),
                          if (!exam && active && remaining != null)
                            Text(
                              '还需 $remaining 分钟',
                              style: const TextStyle(
                                fontSize: 13,
                                color: CampusColors.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
                    ),
                  ),
                ),
              ),
            ),
            if (riskFooter != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: riskFooter!,
              ),
          ],
        ),
      ),
    );
  }
}
