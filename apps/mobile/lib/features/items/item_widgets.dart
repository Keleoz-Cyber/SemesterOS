import 'package:flutter/material.dart';
import 'dart:async';
import '../../ui/app_controls.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../../ui/time_urgency.dart';
import '../../ui/accessibility.dart';
import '../notices/notice_fields.dart';
import '../../ui/date_labels.dart';
import 'task_state_glyph.dart';
import '../../ui/v2/shiri_tokens.dart';
import '../../ui/v2/motion/completion_check.dart';
import '../../ui/v2/motion/reduced_motion.dart';
import '../../ui/v2/widgets/performance_scope.dart';
import '../planning/risk_widgets.dart' show minutesLabel;

String kindLabel(String? kind) => switch (kind) {
  'exam' => '考试',
  'assignment' => '作业',
  _ => '任务',
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
  final FutureOr<void> Function()? onComplete;
  final Widget? riskFooter;
  final bool animateUrgency;
  const ItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onComplete,
    this.riskFooter,
    this.animateUrgency = false,
  });
  Widget _surface(BuildContext context, Widget child) {
    final id = item['id'];
    if (id == null ||
        item.containsKey('_completion_reveal') ||
        reduceMotion(context) ||
        ShiriPerformance.lowEndOf(context)) {
      return child;
    }
    return Hero(
      tag: 'item-surface-$id',
      transitionOnUserGestures: true,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = item['lifecycle'] == 'active';
    final exam = item['kind'] == 'exam';
    if (!exam) return _surface(context, _TaskChecklistRow(card: this));
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
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: CampusColors.ink,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (onComplete != null && active && !exam)
                              AppTextButton.icon(
                                guardAsync: true,
                                onPressed: onComplete,
                                icon: const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 18,
                                ),
                                label: const Text('完成'),
                              )
                            else
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
      child: _surface(context, card),
    );
  }
}

class _TaskChecklistRow extends StatefulWidget {
  final ItemCard card;
  const _TaskChecklistRow({required this.card});
  @override
  State<_TaskChecklistRow> createState() => _TaskChecklistRowState();
}

class _TaskChecklistRowState extends State<_TaskChecklistRow>
    with WidgetsBindingObserver {
  bool _pending = false, _revealDone = false, _revealStrike = false;
  bool _sequenceStarted = false, _settledInstantly = false, _attached = true;
  int _completionEpoch = 0;
  Timer? _strikeTimer;
  bool get _retiringCompletion =>
      widget.card.item['_completion_reveal'] == true &&
      widget.card.item['lifecycle'] == 'completed';
  bool get _canAnimateCompletion =>
      mounted &&
      _attached &&
      !reduceMotion(context) &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.isCurrentOf(context) != false &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _finishRetirement() {
    _strikeTimer?.cancel();
    _strikeTimer = null;
    _sequenceStarted = true;
    _revealDone = _revealStrike = true;
    if (!_settledInstantly) _completionEpoch++;
    _settledInstantly = true;
  }

  void _startRetirement() {
    if (!_retiringCompletion) return;
    if (!_canAnimateCompletion) {
      _finishRetirement();
      return;
    }
    if (_sequenceStarted) return;
    _sequenceStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_attached || !_retiringCompletion || _settledInstantly) {
        return;
      }
      if (!_canAnimateCompletion) {
        setState(_finishRetirement);
        return;
      }
      setState(() => _revealDone = true);
      _strikeTimer = Timer(
        CompletionCheck.fillDuration + CompletionCheck.checkDuration,
        () {
          _strikeTimer = null;
          if (!mounted || !_attached || !_retiringCompletion) return;
          if (!_canAnimateCompletion) {
            setState(_finishRetirement);
            return;
          }
          setState(() => _revealStrike = true);
        },
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _startRetirement();
  }

  @override
  void didUpdateWidget(_TaskChecklistRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.item['id'] != widget.card.item['id'] ||
        oldWidget.card.item['_completion_reveal'] !=
            widget.card.item['_completion_reveal']) {
      _strikeTimer?.cancel();
      _strikeTimer = null;
      _sequenceStarted = _settledInstantly = _revealDone = _revealStrike =
          false;
      _startRetirement();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted &&
        _attached &&
        _retiringCompletion &&
        state != AppLifecycleState.resumed) {
      setState(_finishRetirement);
    }
  }

  @override
  void deactivate() {
    _attached = false;
    if (_retiringCompletion) _finishRetirement();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
  }

  @override
  void dispose() {
    _strikeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> complete() async {
    if (_pending || widget.card.onComplete == null) return;
    setState(() => _pending = true);
    try {
      await widget.card.onComplete!();
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final item = card.item, active = item['lifecycle'] == 'active';
    final completed = item['lifecycle'] == 'completed';
    final drawDone =
        completed && (item['_completion_reveal'] != true || _revealDone);
    final drawStrike =
        completed && (item['_completion_reveal'] != true || _revealStrike);
    final time = _compactTimeLabel(item);
    final deadline = itemDeadline(item);
    final overdue = active && deadline?.isBefore(DateTime.now()) == true;
    final shiri = context.shiri, c = shiri.colors;
    final timeColor = overdue ? c.danger : c.ink700;
    final now = schoolNow();
    final schoolDeadline = itemDeadline(item, schoolClock: true);
    final statedDate = DateTime.tryParse('${item['time']?['date']}');
    final timeDate = schoolDeadline ?? statedDate;
    final today = timeDate != null && DateUtils.isSameDay(timeDate, now);
    final day = DateTime.utc(now.year, now.month, now.day);
    final weekEnd = day.add(Duration(days: 8 - now.weekday));
    final inWeek =
        timeDate != null &&
        timeDate.isBefore(weekEnd) &&
        !timeDate.isBefore(day);
    final source = [
      if (item['kind'] == 'assignment') '作业',
      if ('${item['course_title'] ?? ''}'.trim().isNotEmpty)
        '${item['course_title']}',
      if (item['certainty'] == 'tentative') '暂定',
      if (active && item['priority'] == 'high') '优先',
      if (!active) completed ? '已完成' : '已取消',
    ].join(' · ');
    final remaining = item['remaining_minutes'] is num && active
        ? (item['remaining_minutes'] as num).toInt()
        : null;
    final chipColor = overdue || today
        ? c.danger
        : inWeek
        ? c.warning
        : timeColor;
    final chipFill = overdue || today
        ? c.dangerSoft
        : inWeek
        ? c.warningSoft
        : c.surfaceSunken;
    final row = SemanticCard(
      label: '${item['title']}，${kindLabel(item['kind'])}',
      value: [
        source,
        if (remaining != null) '还需$remaining分钟',
      ].where((v) => v.isNotEmpty).join('，'),
      onTap: card.onTap,
      childHandlesInput: true,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: card.onTap,
                onLongPress: card.onLongPress,
                onDoubleTap: card.onDoubleTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: '标记完成：${item['title']}',
                        child: completed || active
                            ? CompletionCheck(
                                key: ValueKey(
                                  'complete-${item['id']}-$_completionEpoch',
                                ),
                                status: drawDone
                                    ? CompletionStatus.done
                                    : _pending
                                    ? CompletionStatus.pending
                                    : CompletionStatus.idle,
                                semanticLabel: '标记完成：${item['title']}',
                                onPressed:
                                    card.onComplete != null &&
                                        active &&
                                        !_pending
                                    ? complete
                                    : null,
                              )
                            : SizedBox.square(
                                dimension: 48,
                                child: TaskStateGlyph(
                                  state: '${item['lifecycle']}',
                                  color: c.ink500,
                                ),
                              ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: LayoutBuilder(
                                builder: (context, box) {
                                  final text = StrikeThroughText(
                                    '${item['title']}',
                                    key: ValueKey(
                                      'strike-${item['id']}-$_completionEpoch',
                                    ),
                                    struck: drawStrike,
                                    struckColor: c.ink500,
                                    style: shiri.text.titleSmall.copyWith(
                                      color: active ? c.ink900 : c.ink500,
                                    ),
                                  );
                                  final work = remaining == null
                                      ? null
                                      : Text(
                                          '还需${minutesLabel(remaining)}',
                                          style: shiri.text.bodySmall.copyWith(
                                            color: c.ink500,
                                          ),
                                        );
                                  if (work == null) return text;
                                  final scaler = MediaQuery.textScalerOf(
                                    context,
                                  );
                                  final measure = TextPainter(
                                    text: TextSpan(
                                      text: '还需${minutesLabel(remaining)}',
                                      style: shiri.text.bodySmall,
                                    ),
                                    textDirection: Directionality.of(context),
                                    textScaler: scaler,
                                  )..layout();
                                  final workWidth = measure.width;
                                  measure.dispose();
                                  if (box.maxWidth <
                                      scaler.scale(17) * 4 + workWidth + 12) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        text,
                                        const SizedBox(height: 4),
                                        work,
                                      ],
                                    );
                                  }
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: text),
                                      const SizedBox(width: 12),
                                      work,
                                    ],
                                  );
                                },
                              ),
                            ),
                            if (time.isNotEmpty || source.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (time.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: chipFill,
                                          borderRadius: ShiriRadius.xsAll,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              overdue
                                                  ? Icons.warning_amber_rounded
                                                  : Icons.schedule_rounded,
                                              size: 15,
                                              color: chipColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                '${overdue ? '已逾期 · ' : ''}$time',
                                                style: shiri.text.label
                                                    .copyWith(color: chipColor),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (source.isNotEmpty)
                                      Text(
                                        source,
                                        style: shiri.text.bodySmall.copyWith(
                                          color: c.ink500,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (card.onComplete == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12, left: 4),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: c.ink500,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (card.riskFooter != null)
              Padding(
                padding: const EdgeInsets.only(left: 60, bottom: 8),
                child: card.riskFooter!,
              ),
          ],
        ),
      ),
    );
    if (card.onComplete == null || !active) return row;
    return Dismissible(
      key: ValueKey('complete-swipe-${item['id']}'),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {DismissDirection.startToEnd: .3},
      background: Container(
        color: c.successSoft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, color: c.success),
            const SizedBox(width: 8),
            Text('完成', style: shiri.text.bodyStrong.copyWith(color: c.success)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        await complete();
        return false;
      },
      child: row,
    );
  }
}
