import 'academic_visuals.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_date_time_picker.dart';
import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/campus_theme.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/app_selection.dart';
import '../../ui/record_actions.dart';
import '../../ui/app_picker_field.dart';
import '../../ui/time_input_options.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import '../notices/notice_fields.dart' show noticeTime;
import '../planning/date_time_picker.dart';
import '../planning/risk_widgets.dart';
import '../planning/plan_list.dart';
import 'hub_data.dart';

String _examLocation(Map<String, dynamic> exam) {
  final value = '${exam['location'] ?? ''}'.trim();
  return {'待通知', '待定', '待确认', '未确定', '暂无', '未填写'}.contains(value) ? '' : value;
}

class ExamCenterPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> semester;
  final String? examId;
  const ExamCenterPage({
    super.key,
    required this.controller,
    required this.semester,
    this.examId,
  });
  @override
  State<ExamCenterPage> createState() => _ExamCenterPageState();
}

class _ExamCenterPageState extends State<ExamCenterPage> {
  bool cancelled = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.examId == null ? '考试中心' : '考试与复习')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: HubData(
        controller: widget.controller,
        path: '/semesters/${widget.semester['id']}/hub',
        builder: (context, data, fresh, reload) {
          final rows = widget.controller
              .rows(data['exams'])
              .where(
                (r) => widget.examId != null
                    ? r['exam']['id'] == widget.examId
                    : (r['exam']['lifecycle'] == 'cancelled') == cancelled,
              )
              .toList();
          String order(Map row) {
            final t = row['exam']['time'];
            if (t['at'] != null) return schoolTime(t['at']).toIso8601String();
            if (t['date'] != null) return t['date'];
            if (t['week'] != null) {
              return DateTime.parse(widget.semester['first_monday'])
                  .add(Duration(days: ((t['week'] as int) - 1) * 7))
                  .toIso8601String();
            }
            return '9999';
          }

          rows.sort((a, b) => order(a).compareTo(order(b)));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.examId == null) ...[
                AppSegmentedControl<bool>(
                  value: cancelled,
                  options: const {false: '考试安排', true: '已取消'},
                  onChanged: (value) => setState(() => cancelled = value),
                ),
                AppTextButton.icon(
                  onPressed: () async {
                    await context.push('/items/new?kind=exam');
                    await reload();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('记录考试'),
                ),
              ],
              if (rows.isEmpty)
                CampusPanel(child: Text(cancelled ? '没有已取消的考试' : '这里还没有考试记录')),
              for (final row in rows) ...[
                const SizedBox(height: 12),
                _ExamRecord(
                  exam: Map<String, dynamic>.from(row['exam']),
                  onOpen: () async {
                    await context.push('/items/${row['exam']['id']}');
                    await reload();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Material(
                    color: CampusColors.surface,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if ((row['reviews'] as List).isNotEmpty) ...[
                            const Row(
                              children: [
                                Icon(
                                  Icons.checklist_rounded,
                                  size: 20,
                                  color: CampusColors.teal,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '复习任务',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: CampusColors.teal,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (row['review_remaining_minutes'] != null &&
                              (row['reviews'] as List).isNotEmpty)
                            Text(
                              '还需复习 ${minutesLabel(row['review_remaining_minutes'])}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if ((row['reviews'] as List).isNotEmpty)
                            Text(
                              fresh
                                  ? '已安排复习 ${minutesLabel(row['review_planned_minutes'])} · 还需安排 ${row['review_unplanned_minutes'] == null ? '待确认' : minutesLabel(row['review_unplanned_minutes'])}'
                                  : '复习安排待更新',
                              style: const TextStyle(
                                fontSize: 13,
                                color: CampusColors.muted,
                                height: 1.4,
                              ),
                            ),
                          if (fresh &&
                              row['review_remaining_minutes'] is num &&
                              (row['review_remaining_minutes'] as num) > 0 &&
                              row['review_planned_minutes'] is num)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  minHeight: 8,
                                  value:
                                      ((row['review_planned_minutes'] as num) /
                                              (row['review_remaining_minutes']
                                                  as num))
                                          .clamp(0.0, 1.0)
                                          .toDouble(),
                                  color: CampusColors.teal,
                                  backgroundColor: CampusColors.tealSoft,
                                  semanticsLabel: '剩余复习任务的时间安排覆盖，不代表完成进度',
                                ),
                              ),
                            ),
                          if ((row['completed_review_count'] ?? 0) > 0)
                            Text(
                              '已确认完成 ${row['completed_review_count']} 项复习任务',
                            ),
                          for (final issue in row['issues'] ?? [])
                            SoftNotice('$issue', warning: true),
                          if ((row['reviews'] as List).isNotEmpty)
                            const SizedBox(height: 8),
                          for (final task in widget.controller.rows(
                            row['reviews'],
                          ))
                            AppTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(task['title']),
                              subtitle: Text(
                                [
                                  if (itemTimeLabel(task).isNotEmpty)
                                    itemTimeLabel(task),
                                  task['lifecycle'] == 'completed'
                                      ? '已完成'
                                      : task['lifecycle'] == 'cancelled'
                                      ? '已取消'
                                      : '待完成',
                                ].join(' · '),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                await context.push('/items/${task['id']}');
                                await reload();
                              },
                            ),
                          if (row['exam']['lifecycle'] == 'active')
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AppButton(
                                  onPressed: () async {
                                    final active = widget.controller
                                        .rows(row['reviews'])
                                        .where(
                                          (r) => r['lifecycle'] == 'active',
                                        )
                                        .firstOrNull;
                                    if (active != null) {
                                      await context.push(
                                        '/items/${active['id']}',
                                      );
                                      await reload();
                                      return;
                                    }
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ReviewSetupPage(
                                          controller: widget.controller,
                                          exam: Map<String, dynamic>.from(
                                            row['exam'],
                                          ),
                                        ),
                                      ),
                                    );
                                    await reload();
                                  },
                                  child: Text(
                                    widget.controller
                                            .rows(row['reviews'])
                                            .any(
                                              (r) => r['lifecycle'] == 'active',
                                            )
                                        ? '继续复习'
                                        : '添加复习任务',
                                  ),
                                ),
                                RecordActionTile(
                                  title: '调整考试安排',
                                  icon: Icons.edit_calendar_outlined,
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ExamReschedulePage(
                                          controller: widget.controller,
                                          exam: Map<String, dynamic>.from(
                                            row['exam'],
                                          ),
                                        ),
                                      ),
                                    );
                                    await reload();
                                  },
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
}

class ReviewSetupPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> exam;
  const ReviewSetupPage({
    super.key,
    required this.controller,
    required this.exam,
  });
  @override
  State<ReviewSetupPage> createState() => _ReviewSetupPageState();
}

class _ReviewSetupPageState extends State<ReviewSetupPage> {
  final minutes = TextEditingController();
  String mode = 'unknown';
  String? taskId;
  bool link = false, startNow = false, busy = false;
  DateTime? deadline;
  String? error;
  late final generation = widget.controller.api.generation;
  @override
  void dispose() {
    minutes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final c = widget.controller, e = widget.exam;
    if (generation != c.api.generation || e['semester_id'] != c.semesterId) {
      setState(() => error = '账号或学期已切换，请返回');
      return;
    }
    final effort = int.tryParse(minutes.text);
    if (!link && (effort == null || effort < 1 || effort > 525600)) {
      setState(() => error = '请明确填写复习剩余分钟数');
      return;
    }
    if (link && taskId == null) {
      setState(() => error = '请选择要关联的个人任务');
      return;
    }
    if (!link && mode == 'custom' && deadline == null) {
      setState(() => error = '请选择自定义截止时刻');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await c.changeRequest(
        'POST',
        '/exams/${e['id']}/reviews',
        data: {
          'expected_exam_version': e['version'],
          if (link) ...{
            'task_id': taskId,
            'expected_task_version': c.items.firstWhere(
              (i) => i['id'] == taskId,
            )['version'],
          } else ...{
            'remaining_minutes': effort,
            'deadline_mode': mode,
            'start_policy': startNow ? 'now' : 'unconfirmed',
            if (mode == 'custom')
              'deadline_at': deadline!.toUtc().toIso8601String(),
          },
        },
      );
      await c.refresh();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = widget.controller.items
        .where(
          (i) =>
              i['kind'] == 'task' &&
              i['lifecycle'] == 'active' &&
              i['review_exam_id'] == null,
        )
        .toList();
    final examKnown =
        widget.exam['certainty'] == 'formal' &&
        widget.exam['time']['precision'] == 'exact';
    return Scaffold(
      appBar: AppBar(title: const Text('复习目标')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          AcademicRecordHeading(
            label: '',
            title: widget.exam['title'],
            icon: Icons.checklist_rounded,
            subtitle: itemTimeLabel(widget.exam),
          ),
          if (candidates.isNotEmpty)
            AcademicEditorSection(
              title: '复习任务',
              icon: Icons.link_rounded,
              children: [
                AppSwitchRow(
                  title: const Text('关联已有个人任务'),
                  subtitle: link ? const Text('保留原进度和截止时间') : null,
                  value: link,
                  onChanged: busy ? null : (v) => setState(() => link = v),
                ),
                if (link)
                  AppPickerField<String>(
                    initialValue: taskId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '选择任务'),
                    items: candidates
                        .map(
                          (i) => DropdownMenuItem<String>(
                            value: i['id'],
                            child: Text(i['title']),
                          ),
                        )
                        .toList(),
                    onChanged: busy ? null : (v) => setState(() => taskId = v),
                  ),
              ],
            ),
          if (!link) ...[
            AcademicEditorSection(
              title: '预计投入',
              icon: Icons.timer_outlined,
              accent: CampusColors.teal,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in {
                      '2小时': 120,
                      '4小时': 240,
                      '8小时': 480,
                    }.entries)
                      Semantics(
                        selected: int.tryParse(minutes.text) == p.value,
                        child: AppOutlineButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor:
                                int.tryParse(minutes.text) == p.value
                                ? CampusColors.blueSoft
                                : CampusColors.surface,
                            side: BorderSide(
                              color: int.tryParse(minutes.text) == p.value
                                  ? CampusColors.primary
                                  : CampusColors.line,
                            ),
                          ),
                          onPressed: busy
                              ? null
                              : () =>
                                    setState(() => minutes.text = '${p.value}'),
                          child: Text(p.key),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                AppField(
                  key: const Key('review-minutes'),
                  controller: minutes,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: '预计还需复习多久（分钟）'),
                ),
              ],
            ),
            AcademicEditorSection(
              title: '复习时间',
              icon: Icons.event_available_outlined,
              children: [
                AppPickerField<String>(
                  initialValue: mode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '复习截止'),
                  items: [
                    const DropdownMenuItem(
                      value: 'unknown',
                      child: Text('不设截止'),
                    ),
                    if (examKnown)
                      const DropdownMenuItem(
                        value: 'exam',
                        child: Text('考试开始前'),
                      ),
                    const DropdownMenuItem(
                      value: 'custom',
                      child: Text('选择截止时间'),
                    ),
                  ],
                  onChanged: busy ? null : (v) => setState(() => mode = v!),
                ),
                if (mode == 'custom')
                  AppTextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final d = await pickSchoolDateTime(
                              context,
                              initial: deadline,
                            );
                            if (d != null && mounted) {
                              setState(() => deadline = d);
                            }
                          },
                    child: Text(
                      deadline == null
                          ? '选择复习截止'
                          : displayInstant(deadline!.toIso8601String()),
                    ),
                  ),
                AppCheckRow(
                  title: const Text('现在即可安排复习'),
                  value: startNow,
                  onChanged: busy ? null : (v) => setState(() => startNow = v!),
                ),
              ],
            ),
          ],
        ],
      ),
      bottomNavigationBar: ActionFooter(
        secondary: Column(
          mainAxisSize: MainAxisSize.min,
          children: [if (error != null) SoftNotice(error!, warning: true)],
        ),
        label: link ? '关联任务' : '创建复习任务',
        onPressed: busy ? null : save,
        icon: Icons.check_rounded,
      ),
    );
  }
}

class ExamReschedulePage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> exam;
  const ExamReschedulePage({
    super.key,
    required this.controller,
    required this.exam,
  });
  @override
  State<ExamReschedulePage> createState() => _ExamReschedulePageState();
}

class _ExamReschedulePageState extends State<ExamReschedulePage> {
  late String precision = widget.exam['time']['precision'],
      certainty = widget.exam['certainty'];
  late final location = TextEditingController(
    text: widget.exam['location'] ?? '',
  );
  late final week = TextEditingController(
    text: widget.exam['time']['week']?.toString() ?? '',
  );
  final reason = TextEditingController();
  late DateTime? start = originalWall('at', 'date'),
      end = originalWall('end_at', 'end_date');
  late bool startClockConfirmed = widget.exam['time']['at'] != null,
      endClockConfirmed = widget.exam['time']['end_at'] != null;
  bool align = false, busy = false;
  late bool reserve = widget.exam['reserve_time'] ?? true;
  String? error;
  late final generation = widget.controller.api.generation;
  bool get same =>
      generation == widget.controller.api.generation &&
      widget.exam['semester_id'] == widget.controller.semesterId;

  DateTime? originalWall(String instantKey, String dateKey) {
    final time = widget.exam['time'];
    final instant = time[instantKey];
    if (instant != null) {
      final wall = schoolTime(instant);
      return DateTime.utc(
        wall.year,
        wall.month,
        wall.day,
        wall.hour,
        wall.minute,
      );
    }
    final date = DateTime.tryParse(time[dateKey] ?? '');
    return date == null ? null : DateTime.utc(date.year, date.month, date.day);
  }

  DateTime instant(DateTime wall) => DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
  ).subtract(const Duration(hours: 8));
  @override
  void dispose() {
    location.dispose();
    week.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> pick(bool ending) async {
    DateTime? v;
    final previous = ending ? (end ?? start) : start;
    if (precision == 'exact') {
      v = await showAppDateTimePicker(
        context: context,
        initialDate: previous ?? schoolNow(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: ending ? '考试结束时间' : '考试开始时间',
        initialSection: AppDateTimeSection.time,
      );
    } else {
      final initial = (ending ? (end ?? start) : start) ?? schoolNow();
      final bounds = appDatePickerBounds(
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      v = await showDatePicker(
        context: context,
        currentDate: appSchoolToday(),
        initialDate: initial,
        firstDate: bounds.start,
        lastDate: bounds.end,
      );
    }
    if (v != null && mounted && same) {
      final chosen = precision == 'exact'
          ? v
          : DateTime.utc(
              v.year,
              v.month,
              v.day,
              previous?.hour ?? 0,
              previous?.minute ?? 0,
            );
      setState(() {
        if (ending) {
          end = chosen;
          if (precision == 'exact') endClockConfirmed = true;
        } else {
          start = chosen;
          if (precision == 'exact') startClockConfirmed = true;
        }
      });
    }
  }

  Future<void> selectPrecision(String value) async {
    if (value == precision || busy || !same) return;
    DateTime? chosen;
    if (value == 'exact') {
      chosen = await showAppDateTimePicker(
        context: context,
        initialDate: start ?? schoolNow(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: '考试开始时间',
        initialSection: AppDateTimeSection.time,
      );
      if (chosen == null || !mounted || !same) return;
    }
    setState(() {
      precision = value;
      if (chosen != null) {
        start = chosen;
        startClockConfirmed = true;
      }
      align = false;
    });
  }

  String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Future<void> preview() async {
    if (generation != widget.controller.api.generation ||
        widget.exam['semester_id'] != widget.controller.semesterId) {
      setState(() => error = '账号或学期已切换，请返回');
      return;
    }
    if (['date', 'range', 'exact'].contains(precision) &&
        (start == null || (precision == 'exact' && !startClockConfirmed))) {
      setState(() => error = '请明确新的时间');
      return;
    }
    if (precision == 'range' && end == null) {
      setState(() => error = '请选择范围结束日期');
      return;
    }
    if (precision == 'week' && int.tryParse(week.text) == null) {
      setState(() => error = '请输入周次');
      return;
    }
    final time = <String, dynamic>{
      'precision': precision,
      if (precision == 'exact') ...{
        'at': instant(start!).toIso8601String(),
        'end_at': end != null && endClockConfirmed
            ? instant(end!).toIso8601String()
            : null,
      },
      if (precision == 'date' || precision == 'range') 'date': day(start!),
      if (precision == 'range') 'end_date': day(end!),
      if (precision == 'week') 'week': int.parse(week.text),
    };
    final request = {
      'expected_version': widget.exam['version'],
      'time': time,
      'certainty': certainty,
      'location': location.text.trim(),
      'reserve_time': reserve,
      'reason': reason.text.trim().isEmpty ? '用户修改考试安排' : reason.text.trim(),
      'align_review_deadlines': align,
    };
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final p = await widget.controller.changeRequest(
        'POST',
        '/exams/${widget.exam['id']}/reschedule/preview',
        data: request,
      );
      if (!mounted) return;
      final applied = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ExamChangePreviewPage(
            controller: widget.controller,
            preview: p,
            request: request,
          ),
        ),
      );
      if (applied == true && mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('核对考试新安排')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AcademicRecordHeading(
          label: '考试安排变更',
          title: widget.exam['title'],
          icon: Icons.edit_calendar_outlined,
        ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: CampusColors.blueSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: RecordFact(
            label: '原考试安排',
            value: itemTimeLabel(widget.exam),
            icon: Icons.history_rounded,
          ),
        ),
        AppDisclosure(
          title: const Text('补充说明'),
          children: [
            AppField(
              controller: reason,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: '说明（选填）'),
            ),
          ],
        ),
        AcademicEditorSection(
          title: '新的时间与地点',
          icon: Icons.event_outlined,
          children: [
            if (['date', 'range', 'exact'].contains(precision))
              AcademicMomentControl(
                label: '新开始',
                onTap: busy ? null : () => pick(false),
                value: start == null
                    ? '选择新开始'
                    : precision == 'exact'
                    ? displayInstant(instant(start!).toIso8601String())
                    : day(start!),
              ),
            if (precision == 'exact' || precision == 'range')
              AcademicMomentControl(
                label: '新结束',
                ending: true,
                onTap: busy ? null : () => pick(true),
                value:
                    end == null || (precision == 'exact' && !endClockConfirmed)
                    ? '添加结束时间'
                    : precision == 'exact'
                    ? displayInstant(instant(end!).toIso8601String())
                    : day(end!),
              ),
            if (precision == 'exact' && end != null && endClockConfirmed)
              AppTextButton(
                onPressed: () => setState(() => endClockConfirmed = false),
                child: const Text('结束时刻待确认'),
              ),
            TimeInputOptions(
              precision: precision,
              onChanged: busy ? null : selectPrecision,
            ),
            if (precision == 'week') const SizedBox(height: 12),
            if (precision == 'week')
              AppField(
                controller: week,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '第几周'),
              ),
            const SizedBox(height: 12),
            AppField(
              controller: location,
              decoration: const InputDecoration(labelText: '新地点'),
            ),
          ],
        ),
        AcademicEditorSection(
          title: '确认状态与复习',
          icon: Icons.verified_outlined,
          accent: CampusColors.teal,
          children: [
            TentativeSwitch(
              certainty: certainty,
              onChanged: busy
                  ? null
                  : (value) => setState(() {
                      certainty = value;
                      if (certainty != 'formal') align = false;
                    }),
            ),
            AppSwitchRow(
              title: const Text('为这场考试预留时间'),
              value: reserve,
              onChanged: busy ? null : (v) => setState(() => reserve = v),
            ),
            if (certainty == 'formal' && precision == 'exact')
              AppCheckRow(
                title: const Text('将相关复习任务的截止时间一起改到考试开始前'),
                subtitle: const Text('只更新复习截止时间，保留原进度和计划安排'),
                value: align,
                onChanged: (v) => setState(() => align = v!),
              ),
          ],
        ),
      ],
    ),
    bottomNavigationBar: ActionFooter(
      secondary: Column(
        mainAxisSize: MainAxisSize.min,
        children: [if (error != null) SoftNotice(error!, warning: true)],
      ),
      label: '查看改期影响',
      onPressed: busy ? null : preview,
      icon: Icons.arrow_forward_rounded,
    ),
  );
}

class ExamChangePreviewPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> preview, request;
  const ExamChangePreviewPage({
    super.key,
    required this.controller,
    required this.preview,
    required this.request,
  });
  @override
  State<ExamChangePreviewPage> createState() => _ExamChangePreviewPageState();
}

class _ExamChangePreviewPageState extends State<ExamChangePreviewPage> {
  bool busy = false, confirmConflict = false, applied = false;
  String? error;
  late final generation = widget.controller.api.generation;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(update);
  }

  void update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(update);
    super.dispose();
  }

  Future<void> apply() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.changeRequest(
        'POST',
        '/exams/${widget.preview['before']['id']}/reschedule',
        data: {
          ...widget.request,
          'expected_revision': widget.preview['base_revision'],
          'preview_token': widget.preview['preview_token'],
          'confirm_fixed_conflicts': confirmConflict,
        },
        apply: true,
      );
      if (mounted) {
        setState(() => applied = true);
        if (Navigator.canPop(context)) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('考试安排已更新')));
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final stale =
        generation != widget.controller.api.generation ||
        widget.controller.revisionIsStale(
          p['before']['semester_id'],
          p['base_revision'],
        );
    final conflicts = p['new_fixed_conflicts'] ?? p['fixed_conflicts'] ?? [];
    final conflict = conflicts.isNotEmpty;
    final timeChanged =
        itemTimeLabel(p['before'], includeMissing: false) !=
        itemTimeLabel(p['after'], includeMissing: false);
    final reviews = widget.controller
        .rows(p['reviews'])
        .where((r) => timeChanged || r['will_align'] == true)
        .toList();
    final riskChanges = widget.controller
        .rows(p['risk_changes'])
        .where((r) => r['before_slack'] != r['after_slack'])
        .toList();
    final reviewReminders = widget.controller.rows(p['review_reminders_after']);
    final affectedBlocks = widget.controller.rows(p['affected_blocks']);
    return Scaffold(
      appBar: AppBar(title: const Text('考试改期确认')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AcademicRecordHeading(
            label: applied ? '已保存' : '核对后保存',
            title: p['before']['title'],
            icon: applied
                ? Icons.check_circle_outline_rounded
                : Icons.compare_arrows_rounded,
          ),

          _ExamComparison(
            before: Map<String, dynamic>.from(p['before']),
            after: Map<String, dynamic>.from(p['after']),
          ),
          if (p['before']['title'] != p['after']['title'])
            Text('标题：${p['before']['title']} → ${p['after']['title']}'),
          if (p['before']['course_id'] != p['after']['course_id'])
            Text(
              '关联课程：${p['before']['course_title'] ?? '未关联'} → ${p['after']['course_title'] ?? '未关联'}',
            ),
          if (p['before']['notes'] != p['after']['notes'])
            Text('新备注：${p['after']['notes']}'),
          const SizedBox(height: 20),
          if (widget.request['reason'] != null &&
              widget.request['reason'] != '用户修改考试安排')
            DocumentPanel(title: '补充说明', text: '${widget.request['reason']}'),
          if (reviews.isNotEmpty)
            AcademicEditorSection(
              title: '复习截止',
              icon: Icons.checklist_rounded,
              accent: CampusColors.teal,
              children: [
                for (final r in reviews)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${r['title']}\n${r['will_align'] == true ? '将同步截止' : '保持原截止，需自行核对'}：${itemTimeLabel({'kind': 'task', 'time': r['after_time']})}',
                    ),
                  ),
              ],
            ),
          if (timeChanged && (p['reminders_after'] as List).isNotEmpty)
            AcademicEditorSection(
              title: '更新后的提醒',
              icon: Icons.notifications_outlined,
              children: [
                for (final r in p['reminders_after'])
                  Text(
                    '${reminderLabel(Map<String, dynamic>.from(r))} · ${displayInstant(r['trigger_at'])} · ${reminderState(r['schedule_state'])}',
                  ),
              ],
            ),
          if (affectedBlocks.isNotEmpty ||
              reviewReminders.isNotEmpty ||
              riskChanges.isNotEmpty)
            AcademicEditorSection(
              title: '个人计划影响',
              icon: Icons.event_note_outlined,
              children: [
                for (final r in reviewReminders)
                  Text(
                    '复习提醒 ${r['title']}：${displayInstant(r['trigger_at'])} · ${reminderState(r['schedule_state'])}',
                  ),
                for (final b in affectedBlocks)
                  RecordFact(
                    label: b['locked'] == true ? '已锁定的个人计划' : '个人计划',
                    value: '${b['title']} · ${displayInstant(b['start_at'])}',
                    icon: b['locked'] == true
                        ? Icons.lock_outline_rounded
                        : Icons.event_note_outlined,
                  ),
                for (final r in riskChanges)
                  Text(
                    '${r['title']}：余量 ${r['before_slack'] ?? '待确认'} → ${r['after_slack'] ?? '待确认'} 分钟',
                  ),
              ],
            ),
          for (final r in conflicts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SoftNotice(
                '${(r['titles'] as List).join(' 与 ')}时间重叠\n${noticeTime({'at': r['start_at'], 'end_at': r['end_at']})}',
                warning: true,
              ),
            ),
          if (conflict && !applied)
            AppCheckRow(
              title: const Text('保留这些重叠安排'),
              value: confirmConflict,
              onChanged: busy
                  ? null
                  : (v) => setState(() => confirmConflict = v!),
            ),
          if (affectedBlocks.isNotEmpty) const SoftNotice('已有计划会保留，可按需调整时间。'),
          if (stale && !applied)
            const SoftNotice('账号、学期或安排已变化，请重新预览', warning: true),
          if (error != null) SoftNotice(error!, warning: true),

          if (!applied)
            AppButton(
              onPressed: busy || stale || (conflict && !confirmConflict)
                  ? null
                  : apply,
              child: const Text('确认考试新安排'),
            ),
          if (applied) ...[
            const SoftNotice('考试新安排已保存'),
            AppOutlineButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlanListPage(controller: widget.controller),
                ),
              ),
              child: const Text('查看个人计划并按需重排'),
            ),
            AppButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('完成核对'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExamRecord extends StatelessWidget {
  final Map<String, dynamic> exam;
  final VoidCallback onOpen;
  const _ExamRecord({required this.exam, required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final overdue =
        exam['lifecycle'] == 'active' &&
        exam['anchor_at'] != null &&
        DateTime.parse(exam['anchor_at']).isBefore(DateTime.now());
    final status = exam['lifecycle'] == 'completed'
        ? '已完成'
        : exam['lifecycle'] == 'cancelled'
        ? '已取消'
        : exam['reserve_time'] == false
        ? '仅作参考'
        : switch (exam['certainty']) {
            'formal' => '正式',
            'tentative' => '暂定',
            _ => '暂定',
          };
    final accent = exam['certainty'] == 'formal'
        ? CampusColors.primary
        : CampusColors.teal;
    return Material(
      color: CampusColors.blueSoft,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: InkWell(
        onTap: onOpen,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.school_outlined, size: 20, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${exam['title']}',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: CampusColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                status,
                style: TextStyle(
                  fontSize: 12,
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if ('${exam['course_title'] ?? ''}'.trim().isNotEmpty &&
                  !'${exam['title']}'.contains('${exam['course_title']}'))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${exam['course_title']}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: CampusColors.muted,
                    ),
                  ),
                ),
              if (overdue)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '开始时间已过',
                    style: TextStyle(
                      fontSize: 14,
                      color: CampusColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (exam['time']?['precision'] != null &&
                  exam['time']?['precision'] != 'unknown')
                _ExamInlineFact(
                  value: noticeTime(exam['time']),
                  icon: Icons.schedule_rounded,
                ),
              if (_examLocation(exam).isNotEmpty)
                _ExamInlineFact(
                  value: _examLocation(exam),
                  icon: Icons.location_on_outlined,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExamInlineFact extends StatelessWidget {
  final String value;
  final IconData icon;
  const _ExamInlineFact({required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: CampusColors.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, color: CampusColors.ink),
          ),
        ),
      ],
    ),
  );
}

class _ExamComparison extends StatelessWidget {
  final Map<String, dynamic> before, after;
  const _ExamComparison({required this.before, required this.after});
  Widget facts(String title, Map<String, dynamic> item, bool changed) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: changed ? CampusColors.teal : CampusColors.line,
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: changed ? CampusColors.teal : CampusColors.muted,
              ),
            ),
            RecordFact(
              label: '时间',
              value: itemTimeLabel(item),
              icon: Icons.schedule_rounded,
            ),
            if (_examLocation(item).isNotEmpty)
              RecordFact(
                label: '地点',
                value: _examLocation(item),
                icon: Icons.location_on_outlined,
              ),
            Text(switch (item['certainty']) {
              'formal' => '正式安排',
              'tentative' => '暂定安排',
              _ => '暂定安排',
            }, style: const TextStyle(fontSize: 14, color: CampusColors.muted)),
          ],
        ),
      );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (itemTimeLabel(before, includeMissing: false) ==
              itemTimeLabel(after, includeMissing: false) &&
          before['certainty'] == after['certainty'] &&
          before['reserve_time'] == after['reserve_time'] &&
          before['location'] != after['location']) {
        final from = '${before['location'] ?? ''}',
            to = '${after['location'] ?? ''}';
        return RecordFact(
          label: '地点',
          value: from.isEmpty
              ? to
              : to.isEmpty
              ? '移除 $from'
              : '$from → $to',
          icon: Icons.location_on_outlined,
          color: CampusColors.teal,
        );
      }
      final old = facts('变更前', before, false), next = facts('变更后', after, true);
      if (box.maxWidth < 600 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.3) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            old,
            const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_downward_rounded,
                color: CampusColors.teal,
              ),
            ),
            next,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: old),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.arrow_forward_rounded, color: CampusColors.teal),
          ),
          Expanded(child: next),
        ],
      );
    },
  );
}
