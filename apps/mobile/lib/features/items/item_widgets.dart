import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../../ui/breathing_card.dart';
import '../../ui/accessibility.dart';
import '../notices/notice_fields.dart';
import '../../ui/date_labels.dart';
import 'task_state_glyph.dart';

String kindLabel(String? kind) => switch (kind) {
  'exam' => '考试',
  'assignment' => '作业',
  _ => '个人任务',
};
String itemTimeLabel(Map<String, dynamic> item, {bool includeMissing = true}) {
  final t = Map<String, dynamic>.from(item['time'] ?? {});
  if (t['meaning'] != null && t['meaning'] != 'unspecified' ||
      '${t['expression'] ?? ''}'.trim().isNotEmpty) {
    return noticeTime(t, task: item['kind'] != 'exam');
  }
  final suffix = item['kind'] == 'exam' ? '开始' : '截止';
  return switch (t['precision']) {
    'exact' =>
      item['kind'] == 'exam' && t['end_at'] != null
          ? '${displayInstant(t['at'])} 至 ${displayInstant(t['end_at'])}'
          : '${displayInstant(t['at'])} $suffix',
    'date' =>
      '${noticeDate(t['date'])} $suffix${t['day_end_confirmed'] == true ? ' · 当天结束前' : ''}',
    'week' => '第${t['week']}周',
    'range' => '${noticeDate(t['date'])} 至 ${noticeDate(t['end_date'])}',
    _ => '',
  };
}

String displayInstant(String? value) {
  if (value == null) return '';
  final t = schoolTime(value);
  return '${studentDate(t, weekday: true)} ${hhmm(t)}';
}

String displayInterval(String? start, String? end) {
  if (start == null) return '';
  if (end == null) return displayInstant(start);
  final a = schoolTime(start), b = schoolTime(end);
  if (a.year == b.year && a.month == b.month && a.day == b.day) {
    return '${studentDate(a, weekday: true)} ${hhmm(a)}–${hhmm(b)}';
  }
  return '${displayInstant(start)} 至 ${displayInstant(end)}';
}

String _shortDate(DateTime date) {
  final monthDay = '${date.month}月${date.day}日';
  return date.year == DateTime.now().year ? monthDay : '${date.year}年$monthDay';
}

String _compactTimeLabel(Map<String, dynamic> item) {
  final time = Map<String, dynamic>.from(item['time'] ?? {});
  if (time['meaning'] != null && time['meaning'] != 'unspecified' ||
      '${time['expression'] ?? ''}'.trim().isNotEmpty) {
    return noticeTime(time, task: item['kind'] != 'exam');
  }
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
  final VoidCallback? onDoubleTap, onLongPress;
  final Widget? riskFooter;
  final bool animateUrgency;
  const ItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.riskFooter,
    this.animateUrgency = false,
  });
  @override
  Widget build(BuildContext context) {
    final active = item['lifecycle'] == 'active';
    final exam = item['kind'] == 'exam';
    final deadline = itemDeadline(item);
    final minutesToDeadline = deadline?.difference(DateTime.now()).inMinutes;
    final overdue = active && deadline?.isBefore(DateTime.now()) == true;
    final timeLabel = _compactTimeLabel(item);
    final course = '${item['course_title'] ?? ''}'.trim();
    final remainingWork = item['remaining_minutes'] as num?;
    final stateLabel = !active
        ? item['lifecycle'] == 'completed'
              ? '已完成'
              : '已取消'
        : '';
    final color = !active
        ? CampusColors.muted
        : overdue
        ? CampusColors.error
        : TimeUrgency.getColor(minutesToDeadline);
    final timing = [
      if (active &&
          minutesToDeadline != null &&
          minutesToDeadline.abs() <= 4320)
        TimeUrgency.getLabel(minutesToDeadline),
      if (timeLabel.isNotEmpty) timeLabel,
    ].join(' · ');
    final card = SemanticCard(
      label: '${item['title']}，${kindLabel(item['kind'])}',
      value: [
        if (timing.isNotEmpty) timing,
        if (stateLabel.isNotEmpty) stateLabel,
      ].join('，'),
      hint: onLongPress == null ? null : '长按查看快捷操作',
      onTap: onTap,
      childHandlesInput: true,
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
                onDoubleTap: onDoubleTap,
                onLongPress: onLongPress,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    8,
                    12,
                    riskFooter == null ? 10 : 6,
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
                              decoration: BoxDecoration(
                                color: exam
                                    ? CampusColors.tealSoft
                                    : CampusColors.blueSoft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: exam
                                  ? const Icon(
                                      Icons.school_outlined,
                                      size: 18,
                                      color: CampusColors.teal,
                                    )
                                  : TaskStateGlyph(
                                      state: '${item['lifecycle']}',
                                      color: active
                                          ? CampusColors.primary
                                          : CampusColors.muted,
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${item['title']}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
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
                          padding: const EdgeInsets.only(top: 3, left: 40),
                          child: Text(
                            [
                              kindLabel(item['kind']),
                              if (course.isNotEmpty) course,
                              if (item['certainty'] == 'tentative') '暂定',
                              if (stateLabel.isNotEmpty) stateLabel,
                              if (overdue && minutesToDeadline!.abs() > 4320)
                                '已逾期',
                              if (active && item['priority'] == 'high') '优先',
                              if (active && !exam && remainingWork != null)
                                '还需 ${remainingWork.toInt()} 分钟',
                            ].join(' · '),
                            style: const TextStyle(
                              fontSize: 13,
                              color: CampusColors.muted,
                            ),
                          ),
                        ),
                        if (timing.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Icon(
                                  overdue
                                      ? Icons.warning_rounded
                                      : Icons.access_time_rounded,
                                  size: 16,
                                  color: color,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    timing,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: color,
                                    ),
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
            ?riskFooter,
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BreathingCard(
        enabled:
            animateUrgency &&
            active &&
            minutesToDeadline != null &&
            minutesToDeadline > 0 &&
            minutesToDeadline < 4320,
        remainingMinutes: minutesToDeadline,
        child: card,
      ),
    );
  }
}
