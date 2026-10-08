import '../../ui/app_date_time_picker.dart';
import '../../ui/app_selection.dart';
import '../../ui/app_controls.dart';
import '../../ui/date_labels.dart';
import '../../core/api.dart' show ApiFailure, userError;
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/app_picker_field.dart';
import '../../ui/time_input_options.dart';
import '../../ui/campus_theme.dart';
import 'items_controller.dart';
import 'item_widgets.dart';
import 'task_surfaces.dart';
import 'reminder_editor.dart';
import '../planning/date_time_picker.dart';
import '../centers/exam_pages.dart';
import '../notices/notice_fields.dart';
import '../tags/tag_picker_field.dart';
import '../calendar/event_conflict_review.dart';

class ItemFormPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> semester;
  final Map<String, dynamic>? initial, candidate;
  final String kind;
  const ItemFormPage({
    super.key,
    required this.controller,
    required this.semester,
    this.initial,
    this.candidate,
    this.kind = 'assignment',
  });
  @override
  State<ItemFormPage> createState() => _ItemFormPageState();
}

class _ItemFormPageState extends State<ItemFormPage> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(),
      minutes = TextEditingController(),
      location = TextEditingController(),
      notes = TextEditingController(),
      source = TextEditingController(),
      reason = TextEditingController(),
      expression = TextEditingController(),
      week = TextEditingController();
  List<String> tags = [];
  Map<String, dynamic> originalTime = {}, details = {};
  late String kind, precision, certainty, priority;
  String? course;
  String? categoryId;
  bool categoryChosen = false;
  DateTime? date, endDate;
  TimeOfDay? time;
  DateTime? examEndAt, earliestAt;
  String startPolicy = 'unconfirmed';
  bool reserveTime = true;
  bool dayEnd = false, split = true, reviewed = false, busy = false;
  String? error, timeError, _requestKey, _requestBody;
  String? _confirmedExamSource;
  Map<String, dynamic>? _confirmedExamData;
  List<Map<String, dynamic>> reminders = [];
  late final generation = widget.controller.api.generation;
  bool get sameSession => generation == widget.controller.api.generation;
  bool get editing => widget.initial != null;
  bool get parsed => widget.candidate?['id'] != null;
  bool get window => originalTime['meaning'] == 'window' && kind != 'exam';
  @override
  void initState() {
    super.initState();
    final data =
        widget.initial ?? widget.candidate?['item'] ?? <String, dynamic>{};
    final t = data['time'] ?? {};
    originalTime = noticeMap(t);
    details = noticeMap(data['details']);
    expression.text = t['expression'] ?? '';
    kind = data['kind'] ?? widget.kind;
    categoryId = data.containsKey('category_id')
        ? data['category_id']
        : (kind == 'task' ? null : 'study');
    tags = (data['tags'] is List ? data['tags'] as List : [])
        .map((t) => t is Map ? t['name'] : t)
        .whereType<String>()
        .toList();
    precision = t['precision'] ?? 'unknown';
    certainty = data['certainty'] ?? 'formal';
    priority = data['priority'] ?? 'normal';
    course = data['course_id'];
    title.text = data['title'] ?? '';
    minutes.text = data['remaining_minutes']?.toString() ?? '';
    location.text = data['location'] ?? '';
    notes.text = data['notes'] ?? '';
    source.text = data['source_text'] ?? widget.candidate?['source_text'] ?? '';
    split = data['splittable'] ?? true;
    startPolicy = data['start_policy'] ?? 'unconfirmed';
    if (data['earliest_start_at'] != null) {
      earliestAt = DateTime.parse(data['earliest_start_at']);
    }
    if (t['end_at'] != null) examEndAt = DateTime.parse(t['end_at']);
    reserveTime = data['reserve_time'] ?? true;
    dayEnd = t['day_end_confirmed'] ?? false;
    week.text = t['week']?.toString() ?? '';
    if (t['date'] != null) date = DateTime.parse(t['date']);
    if (t['end_date'] != null) endDate = DateTime.parse(t['end_date']);
    if (t['at'] != null) {
      final at = schoolTime(t['at']);
      date = DateTime(at.year, at.month, at.day);
      time = TimeOfDay(hour: at.hour, minute: at.minute);
    }
  }

  @override
  void dispose() {
    for (final c in [
      title,
      minutes,
      location,
      notes,
      source,
      reason,
      week,
      expression,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String day(DateTime value) => value.toIso8601String().substring(0, 10);
  Future<void> selectPrecision(String value) async {
    final previous = precision;
    setState(() {
      precision = value;
      timeError = null;
    });
    if (value == 'exact' &&
        (date == null || time == null || previous != 'exact')) {
      final chosen = await pickExact(
        initialSection: date == null
            ? AppDateTimeSection.date
            : AppDateTimeSection.time,
      );
      if (!chosen && mounted && sameSession) {
        setState(() => precision = previous);
      }
      return;
    }
    if ({'date', 'exact', 'range'}.contains(value) && date == null) {
      await pickDate();
      if (!mounted || !sameSession) return;
      if (date == null) {
        setState(() => precision = previous);
        return;
      }
    }
  }

  Future<bool> pickExact({
    AppDateTimeSection initialSection = AppDateTimeSection.date,
  }) async {
    if (!sameSession) return false;
    final now = schoolNow();
    final selectedDay = date ?? DateTime(now.year, now.month, now.day);
    final clock = time ?? const TimeOfDay(hour: 9, minute: 0);
    final selected = await showAppDateTimePicker(
      context: context,
      initialDate: DateTime.utc(
        selectedDay.year,
        selectedDay.month,
        selectedDay.day,
        clock.hour,
        clock.minute,
      ),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: kind == 'exam' ? '考试开始时间' : '选择日期和时间',
      initialSection: initialSection,
    );
    if (selected == null ||
        !mounted ||
        !sameSession ||
        widget.controller.semesterId != widget.semester['id']) {
      return false;
    }
    setState(() {
      date = DateUtils.dateOnly(selected);
      time = TimeOfDay.fromDateTime(selected);
      timeError = null;
    });
    return true;
  }

  Future<void> pickDate({bool end = false}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final now = schoolNow();
    final initial =
        (end ? (endDate ?? date) : date) ??
        DateTime(now.year, now.month, now.day);
    final bounds = appDatePickerBounds(
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    final selected = await showDatePicker(
      context: context,
      currentDate: appSchoolToday(),
      initialDate: initial,
      firstDate: bounds.start,
      lastDate: bounds.end,
    );
    if (selected != null &&
        mounted &&
        sameSession &&
        widget.controller.semesterId == widget.semester['id']) {
      setState(() {
        if (end) {
          endDate = selected;
        } else {
          date = selected;
        }
        timeError = null;
      });
    }
  }

  Map<String, dynamic> timeData() {
    if (['date', 'range', 'exact'].contains(precision) && date == null) {
      throw const FormatException('请先选择日期');
    }
    if (precision == 'exact' && time == null) {
      throw const FormatException('请选择具体时刻；不确定时可改为仅日期');
    }
    if ((kind == 'exam' || window) &&
        precision == 'exact' &&
        examEndAt != null) {
      final start = DateTime.parse(
        '${day(date!)}T${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}:00+08:00',
      );
      if (!examEndAt!.isAfter(start)) {
        throw const FormatException('结束时间应晚于开始时间');
      }
    }
    if (precision == 'range' && (endDate == null || endDate!.isBefore(date!))) {
      throw const FormatException('请核对日期范围');
    }
    final number = int.tryParse(week.text);
    if (precision == 'week' &&
        (number == null ||
            number < 1 ||
            number > (widget.semester['total_weeks'] as int))) {
      throw const FormatException('请填写当前学期内的周次');
    }
    return {
      'meaning':
          precision != 'unknown' &&
              {'candidate', 'course_anchor'}.contains(originalTime['meaning'])
          ? kind == 'exam'
                ? 'start'
                : 'deadline'
          : originalTime['meaning'] ?? 'unspecified',
      'expression': expression.text.trim(),
      if (precision == 'unknown') ...{
        if (originalTime['candidate_dates'] != null)
          'candidate_dates': originalTime['candidate_dates'],
        if (originalTime['course_anchor'] != null)
          'course_anchor': originalTime['course_anchor'],
      },
      'precision': precision,
      'end_at': (kind == 'exam' || window) && precision == 'exact'
          ? examEndAt?.toIso8601String()
          : null,
      if (precision == 'exact')
        'at':
            '${day(date!)}T${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}:00+08:00',
      if (precision == 'date' || precision == 'range') 'date': day(date!),
      if (precision == 'range') 'end_date': day(endDate!),
      if (precision == 'week') 'week': number,
      'day_end_confirmed':
          precision == 'date' && kind != 'exam' && !window && dayEnd,
    };
  }

  Future<void> save() async {
    if (!sameSession || widget.controller.semesterId != widget.semester['id']) {
      setState(() => error = '账号或学期已切换，请重新打开');
      return;
    }
    if (title.text.trim().isEmpty) {
      form.currentState?.validate();
      setState(() => error = '请输入事项标题');
      return;
    }

    if (kind != 'exam' && startPolicy == 'at' && earliestAt == null) {
      setState(() => error = '请选择开始时间，或移除开始条件');
      return;
    }
    final effortText = minutes.text.trim();
    final effort = int.tryParse(effortText);
    if (kind != 'exam' &&
        effortText.isNotEmpty &&
        (effort == null || effort < 1 || effort > 525600)) {
      setState(() => error = '预计耗时请填写整数分钟');
      return;
    }
    if (kind != 'exam') {
      if (tags.length > 12 || tags.any((s) => s.length > 24)) {
        setState(() => error = '最多12个标签，每个不超过24字');
        return;
      }
    }
    if (!validateAppForm(form)) return;
    Map<String, dynamic> t;
    try {
      t = timeData();
    } on FormatException catch (e) {
      setState(() {
        timeError = e.message;
        error = e.message;
      });
      return;
    }
    var data = <String, dynamic>{
      'semester_id': widget.semester['id'],
      'kind': kind,
      'title': title.text.trim(),
      'course_id': course,
      'time': t,
      'details': details,
      'certainty': certainty,
      'start_policy': kind == 'exam' ? 'unconfirmed' : startPolicy,
      'earliest_start_at': kind != 'exam' && startPolicy == 'at'
          ? earliestAt?.toIso8601String()
          : null,
      'reserve_time': kind == 'exam' ? reserveTime : true,
      'remaining_minutes': kind == 'exam' || minutes.text.trim().isEmpty
          ? null
          : effort,
      'splittable': split,
      'priority': priority,
      if (kind != 'exam') 'category_id': categoryId,
      if (kind != 'exam') 'tags': tags,
      'location': location.text.trim(),
      'notes': notes.text.trim(),
      'source_text': source.text.trim(),
      'candidate_id':
          widget.candidate?['id'] ?? widget.initial?['candidate_id'],
      'source_id':
          widget.candidate?['item']?['source_id'] ??
          widget.initial?['source_id'],
      if (!editing)
        'reminders': reminders
            .map(
              (r) => Map<String, dynamic>.from(r)..remove('expected_version'),
            )
            .toList(),
      if (editing) ...{
        'expected_version': widget.initial!['version'],
        'change_reason': reason.text.trim().isEmpty
            ? '用户修改'
            : reason.text.trim(),
      },
    };
    final sourceBody = jsonEncode(data);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (editing && kind == 'exam') {
        final request = <String, dynamic>{
          'expected_version': data['expected_version'],
          'time': t,
          'details': data['details'],
          'certainty': certainty,
          'location': data['location'],
          'reserve_time': data['reserve_time'],
          'reason': data['change_reason'],
          'title': data['title'],
          'course_id': data['course_id'],
          'notes': data['notes'],
          'align_review_deadlines': false,
        };
        final preview = await widget.controller.changeRequest(
          'POST',
          '/exams/${widget.initial!['id']}/reschedule/preview',
          data: request,
        );
        if (!mounted || !sameSession) return;
        final applied = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ExamChangePreviewPage(
              controller: widget.controller,
              preview: preview,
              request: request,
            ),
          ),
        );
        if (applied == true && mounted) Navigator.pop(context, true);
        return;
      }
      if (kind == 'exam') {
        if (_confirmedExamSource == sourceBody &&
            _confirmedExamData != null &&
            !widget.controller.revisionIsStale(
              widget.semester['id'],
              _confirmedExamData!['expected_revision'] as int,
            )) {
          data = Map<String, dynamic>.from(_confirmedExamData!);
        } else {
          _confirmedExamSource = null;
          _confirmedExamData = null;
          final preview = await widget.controller.changeRequest(
            'POST',
            '/items/conflict-preview',
            data: data,
          );
          if (!mounted ||
              !sameSession ||
              widget.controller.semesterId != widget.semester['id']) {
            return;
          }
          final impact = Map<String, dynamic>.from(preview['impact'] ?? {});
          if (eventConflicts(impact).isNotEmpty) {
            final choice = await confirmEventConflicts(context, impact);
            if (!mounted ||
                !sameSession ||
                widget.controller.semesterId != widget.semester['id']) {
              return;
            }
            if (choice == null || choice.adjustTime) {
              setState(() => busy = false);
              if (choice?.adjustTime == true) await pickExact();
              return;
            }
            data = {
              ...data,
              if (choice.keepConflicts) 'confirm_fixed_conflicts': true,
              if (choice.courseLeaveTargets.isNotEmpty)
                'course_leave_targets': choice.courseLeaveTargets,
            };
          }
          data['expected_revision'] = preview['base_revision'];
          _confirmedExamSource = sourceBody;
          _confirmedExamData = Map<String, dynamic>.from(data);
        }
      }
      final encoded = jsonEncode(data);
      if (_requestBody != encoded) {
        _requestBody = encoded;
        _requestKey = List.generate(
          20,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
      }
      await widget.controller.save(
        data,
        id: widget.initial?['id'],
        idempotencyKey: _requestKey,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (e is ApiFailure && {409, 422}.contains(e.statusCode)) {
        _confirmedExamSource = null;
        _confirmedExamData = null;
      }
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget estimate() => WorkMinuteField(
    fieldKey: const Key('item-minutes'),
    controller: minutes,
    enabled: !busy,
    label: '预计还需',
    validator: (v) =>
        v!.trim().isEmpty ||
            (int.tryParse(v) != null &&
                int.parse(v) > 0 &&
                int.parse(v) <= 525600)
        ? null
        : '请输入1至525600之间的整数分钟',
  );
  String reminderPreview(Map<String, dynamic> rule) {
    if (rule['mode'] == 'absolute') return displayInstant(rule['trigger_at']);
    try {
      final t = timeData();
      DateTime? anchor;
      if (t['precision'] == 'exact') anchor = DateTime.parse(t['at']);
      if (t['precision'] == 'date' && t['day_end_confirmed'] == true) {
        anchor = DateTime.parse(
          '${t['date']}T00:00:00+08:00',
        ).add(const Duration(days: 1));
      }
      if (anchor == null) return '待确认事项的具体时间，暂不能安排此提醒';
      final when = anchor.subtract(
        Duration(minutes: rule['lead_minutes'] as int),
      );
      return '${displayInstant(when.toIso8601String())}${when.isBefore(DateTime.now()) ? ' · 已过期，请修改' : ''}';
    } on FormatException {
      return '待确认事项的具体时间，暂不能安排此提醒';
    }
  }

  Future<void> addReminder([int? index]) async {
    var hasReferenceTime = false;
    try {
      hasReferenceTime = reminderHasReferenceTime(kind, timeData());
    } on FormatException {
      // An unset event time does not prevent choosing a reminder time.
    }
    final result = await editReminder(
      context,
      kind: kind,
      hasReferenceTime: hasReferenceTime,
      initial: index == null ? null : reminders[index],
    );
    if (result != null && mounted) {
      setState(() {
        if (index == null) {
          reminders.add(result);
        } else {
          reminders[index] = result;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        editing
            ? '修改${kindLabel(kind)}'
            : parsed
            ? '核对这条记录'
            : '记录${kindLabel(kind)}',
      ),
    ),
    bottomNavigationBar: ActionFooter(
      label: busy
          ? '正在保存…'
          : editing
          ? '保存修改'
          : '保存',
      icon: Icons.check_rounded,
      secondary: error == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
      onPressed: busy ? null : save,
    ),
    body: Form(
      key: form,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const SizedBox(height: 12),
          if (parsed) ...[
            DocumentPanel(
              title: '识别原文 · 请核对',
              text: source.text,
              footer: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((widget.candidate?['inferred_fields'] as List? ?? [])
                      .isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text('有些内容是AI根据上下文推测的，请重点检查下面标出的信息。'),
                    ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final field
                          in (widget.candidate?['inferred_fields'] as List? ??
                                  [])
                              .map((f) => '$f'.split('.').first)
                              .toSet())
                        StatusPill(
                          '核对${{'title': '标题', 'time': '时间', 'remaining_minutes': '耗时', 'course_id': '课程关联', 'certainty': '时间是否确定', 'kind': '事项类型'}[field] ?? '这项信息'}',
                        ),
                    ],
                  ),
                  for (final q in widget.candidate?['questions'] ?? [])
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('需核对：$q'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          EditorSection(
            title: '任务内容',
            icon: Icons.edit_note_rounded,
            children: [
              AppSegmentedControl<String>(
                key: const Key('item-kind'),
                value: kind,
                enabled: !editing,
                options: const {
                  'assignment': '作业',
                  'exam': '考试',
                  'task': '个人任务',
                },
                onChanged: (value) => setState(() {
                  kind = value;
                  if (!categoryChosen) {
                    categoryId = kind == 'task' ? null : 'study';
                  }
                }),
              ),
              const SizedBox(height: 14),
              AppFormField(
                key: const Key('item-title'),
                controller: title,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: '任务标题',
                  hintText: '要完成什么？',
                  counterText: '',
                ),
                validator: (v) => v!.trim().isEmpty ? '请输入任务标题' : null,
              ),
              const SizedBox(height: 16),
              AppPickerField<String>(
                initialValue: course,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '关联课程（可不选）'),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('不关联课程'),
                  ),
                  if (course != null &&
                      !widget.controller.courses.any((c) => c['id'] == course))
                    DropdownMenuItem(
                      value: course,
                      child: Text(widget.initial?['course_title'] ?? '已关联课程'),
                    ),
                  for (final c in widget.controller.courses)
                    DropdownMenuItem(
                      value: c['id'],
                      child: Text(
                        [
                          '${c['title']}',
                          '周${'一二三四五六日'[(c['weekday'] as int) - 1]}',
                          if ('${c['teacher'] ?? ''}'.trim().isNotEmpty)
                            '${c['teacher']}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => course = v),
              ),
            ],
          ),
          if (kind != 'exam')
            AppDisclosure(
              title: const Text('安排学习时间'),
              leading: const Icon(Icons.timelapse_outlined),
              initiallyExpanded:
                  minutes.text.isNotEmpty || startPolicy != 'unconfirmed',
              children: [
                estimate(),
                const SizedBox(height: 14),
                AppPickerField<String>(
                  key: const Key('task-start-policy'),
                  initialValue: startPolicy,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '最早何时可以开始'),
                  items: const [
                    DropdownMenuItem(value: 'unconfirmed', child: Text('未设置')),
                    DropdownMenuItem(value: 'now', child: Text('从现在起可开始')),
                    DropdownMenuItem(value: 'at', child: Text('指定最早开始时间')),
                  ],
                  onChanged: (v) => setState(() => startPolicy = v!),
                ),
                if (startPolicy == 'at')
                  AppOutlineButton(
                    guardAsync: false,
                    onPressed: () async {
                      final selected = await pickSchoolDateTime(
                        context,
                        initial: earliestAt,
                      );
                      if (selected != null &&
                          mounted &&
                          sameSession &&
                          widget.controller.semesterId ==
                              widget.semester['id']) {
                        setState(() => earliestAt = selected);
                      }
                    },
                    child: Text(
                      earliestAt == null
                          ? '选择最早开始时间'
                          : displayInstant(earliestAt!.toIso8601String()),
                    ),
                  ),
                const SizedBox(height: 14),
              ],
            ),
          EditorSection(
            title: kind == 'exam'
                ? '考试时间'
                : window
                ? '办理时间'
                : '时间',
            icon: Icons.schedule_rounded,
            children: [
              if (['date', 'range'].contains(precision))
                AppOutlineButton.icon(
                  key: const Key('item-date'),
                  onPressed: () => pickDate(),
                  guardAsync: false,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    date == null ? '选择日期' : studentDate(date!, weekday: true),
                  ),
                ),
              if (precision == 'exact')
                AppOutlineButton.icon(
                  key: const Key('item-date-time'),
                  onPressed: () => pickExact(
                    initialSection: date == null
                        ? AppDateTimeSection.date
                        : AppDateTimeSection.time,
                  ),
                  guardAsync: false,
                  icon: const Icon(Icons.schedule),
                  label: Text(
                    time == null || date == null
                        ? '选择日期和时间'
                        : '${studentDate(date!, weekday: true)} ${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              if (precision == 'range')
                AppOutlineButton.icon(
                  onPressed: () => pickDate(end: true),
                  guardAsync: false,
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    endDate == null
                        ? '选择范围结束日期'
                        : '至 ${studentDate(endDate!, weekday: true)}',
                  ),
                ),
              if (precision == 'week')
                AppFormField(
                  key: const Key('item-week'),
                  controller: week,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '第几周（1—${widget.semester['total_weeks']}）',
                  ),
                ),
              if (precision == 'date' && kind != 'exam' && !window)
                AppCheckRow(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('在这一天结束前完成'),
                  value: dayEnd,
                  onChanged: (v) => setState(() => dayEnd = v!),
                ),
              if (timeError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    timeError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if ((kind == 'exam' || window) && precision == 'exact') ...[
                AppOutlineButton.icon(
                  key: const Key('exam-end'),
                  guardAsync: false,
                  onPressed: () async {
                    final selected = await pickSchoolDateTime(
                      context,
                      initial:
                          examEndAt ??
                          (date != null && time != null
                              ? DateTime.utc(
                                  date!.year,
                                  date!.month,
                                  date!.day,
                                  time!.hour,
                                  time!.minute,
                                ).subtract(const Duration(hours: 8))
                              : null),
                    );
                    if (mounted &&
                        selected != null &&
                        sameSession &&
                        widget.controller.semesterId == widget.semester['id']) {
                      setState(() => examEndAt = selected);
                    }
                  },
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text(
                    examEndAt == null
                        ? '添加结束时间'
                        : '结束：${displayInstant(examEndAt!.toIso8601String())}',
                  ),
                ),
                if (examEndAt != null)
                  AppTextButton(
                    onPressed: () => setState(() => examEndAt = null),
                    child: const Text('移除结束时间'),
                  ),
                const SizedBox(height: 12),
              ],
              TimeInputOptions(
                precision: precision,
                onChanged: selectPrecision,
              ),
              if (precision == 'unknown')
                AppFormField(
                  key: const Key('item-time-expression'),
                  controller: expression,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: '时间说明（选填）',
                    hintText: '例如：等老师通知',
                    counterText: '',
                  ),
                ),
              TentativeSwitch(
                certainty: certainty,
                onChanged: (value) => setState(() => certainty = value),
              ),
              if (kind == 'exam') ...[
                const SizedBox(height: 16),
                AppFormField(
                  controller: location,
                  decoration: const InputDecoration(labelText: '考试地点（可留空）'),
                ),
              ],
            ],
          ),
          if (!editing)
            EditorSection(
              title: '提醒',
              icon: Icons.notifications_outlined,
              action: AppTextButton(
                onPressed: () => addReminder(),
                child: const Text('添加提醒'),
              ),
              children: [
                for (var i = 0; i < reminders.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: CampusColors.background,
                      borderRadius: BorderRadius.circular(12),
                      child: AppTile(
                        title: Text(
                          '${reminderLabel(reminders[i])}${reminders[i]['enabled'] == false ? ' · 已停用' : ''}',
                        ),
                        subtitle: Text(reminderPreview(reminders[i])),
                        onTap: () => addReminder(i),
                        trailing: AppIconButton(
                          tooltip: '移除此提醒',
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              setState(() => reminders.removeAt(i)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          AppDisclosure(
            title: const Text('更多设置'),
            leading: const Icon(Icons.tune_rounded),
            initiallyExpanded: false,
            subtitle: const Text('分类、标签与补充说明'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 12, bottom: 16),
            children: [
              if (kind != 'exam') ...[
                AppPickerField<String>(
                  key: const Key('item-category'),
                  initialValue: categoryId ?? 'unclassified',
                  decoration: const InputDecoration(labelText: '分类'),
                  items: [
                    for (final e in {
                      'study': '学业',
                      'research': '科研',
                      'affairs': '校园事务',
                      'life': '生活',
                      'unclassified': '未分类',
                    }.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (value) => setState(() {
                    categoryChosen = true;
                    categoryId = value == 'unclassified' ? null : value;
                  }),
                ),
                const SizedBox(height: 14),
                TagPickerField(
                  key: const Key('item-tags'),
                  controller: widget.controller,
                  values: tags,
                  enabled: !busy && sameSession,
                  onChanged: (values) => setState(() => tags = values),
                ),
                const SizedBox(height: 14),
              ],
              if (kind == 'exam')
                AppSwitchRow(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('为这场考试预留时间'),
                  value: reserveTime,
                  onChanged: (v) => setState(() => reserveTime = v),
                ),
              if (kind != 'exam')
                AppSwitchRow(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('以后允许分段安排'),
                  value: split,
                  onChanged: (v) => setState(() => split = v),
                ),
              AppPickerField<String>(
                initialValue: priority,
                decoration: const InputDecoration(labelText: '优先级'),
                items: const [
                  DropdownMenuItem(value: 'normal', child: Text('普通')),
                  DropdownMenuItem(value: 'high', child: Text('高')),
                  DropdownMenuItem(value: 'low', child: Text('低')),
                ],
                onChanged: (v) => setState(() => priority = v!),
              ),
              const SizedBox(height: 14),
              if (kind != 'exam')
                AppFormField(
                  controller: location,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: '地点（选填）',
                    counterText: '',
                  ),
                ),
              if (!parsed && !editing)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: AppFormField(
                    controller: source,
                    maxLines: 3,
                    maxLength: 10000,
                    decoration: const InputDecoration(
                      labelText: '来源原文（可留空）',
                      counterText: '',
                    ),
                  ),
                ),
              if (editing)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: AppFormField(
                    key: const Key('item-change-reason'),
                    controller: reason,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: '修改原因（选填）',
                      counterText: '',
                    ),
                  ),
                ),
            ],
          ),
          NoticeDetailsEditor(
            value: details,
            onChanged: (value) => details = value,
            notesController: notes,
          ),

          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
