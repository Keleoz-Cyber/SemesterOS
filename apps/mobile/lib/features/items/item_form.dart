import '../../core/api.dart' show userError;
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_widgets.dart';
import 'items_controller.dart';
import 'item_widgets.dart';
import 'reminder_editor.dart';
import '../planning/date_time_picker.dart';
import '../centers/exam_pages.dart';

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
      week = TextEditingController();
  late String kind, precision, certainty, priority;
  String? course;
  DateTime? date, endDate;
  TimeOfDay? time;
  DateTime? examEndAt, earliestAt;
  String startPolicy = 'unconfirmed';
  bool reserveTime = true;
  bool dayEnd = false, split = true, reviewed = false, busy = false;
  String? error, timeError, _requestKey, _requestBody;
  List<Map<String, dynamic>> reminders = [];
  bool get editing => widget.initial != null;
  bool get parsed => widget.candidate?['id'] != null;
  @override
  void initState() {
    super.initState();
    final data =
        widget.initial ?? widget.candidate?['item'] ?? <String, dynamic>{};
    final t = data['time'] ?? {};
    kind = data['kind'] ?? widget.kind;
    precision = t['precision'] ?? 'unknown';
    certainty = data['certainty'] ?? 'unknown';
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
    for (final c in [title, minutes, location, notes, source, reason, week]) {
      c.dispose();
    }
    super.dispose();
  }

  String day(DateTime value) => value.toIso8601String().substring(0, 10);
  Future<void> pickDate({bool end = false}) async {
    final now = schoolNow();
    final selected = await showDatePicker(
      context: context,
      initialDate:
          (end ? endDate : date) ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
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
    if (kind == 'exam' && precision == 'exact' && examEndAt != null) {
      final start = DateTime.parse(
        '${day(date!)}T${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}:00+08:00',
      );
      if (!examEndAt!.isAfter(start)) {
        throw const FormatException('考试结束必须晚于开始时间');
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
      'precision': precision,
      'end_at': kind == 'exam' && precision == 'exact'
          ? examEndAt?.toIso8601String()
          : null,
      if (precision == 'exact')
        'at':
            '${day(date!)}T${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}:00+08:00',
      if (precision == 'date' || precision == 'range') 'date': day(date!),
      if (precision == 'range') 'end_date': day(endDate!),
      if (precision == 'week') 'week': number,
      'day_end_confirmed': precision == 'date' && kind != 'exam' && dayEnd,
    };
  }

  Future<void> save() async {
    if (kind != 'exam' && startPolicy == 'at' && earliestAt == null) {
      setState(() => error = '请选择最早开始时间，暂时不确定也可以选择“待确认”');
      return;
    }
    final effortText = minutes.text.trim();
    final effort = int.tryParse(effortText);
    if (kind != 'exam' &&
        effortText.isNotEmpty &&
        (effort == null || effort < 1 || effort > 525600)) {
      setState(() => error = '预计耗时请填写1至525600之间的整数分钟，可在更多设置中修改');
      return;
    }
    if (!form.currentState!.validate()) return;
    if (parsed && !reviewed) {
      setState(() => error = '请核对原文、日期和标出的推断后确认');
      return;
    }
    Map<String, dynamic> t;
    try {
      t = timeData();
    } on FormatException catch (e) {
      setState(() => timeError = e.message);
      return;
    }
    final data = <String, dynamic>{
      'semester_id': widget.semester['id'],
      'kind': kind,
      'title': title.text.trim(),
      'course_id': course,
      'time': t,
      'certainty': certainty,
      'start_policy': kind == 'exam' ? 'unconfirmed' : startPolicy,
      'earliest_start_at': kind != 'exam' && startPolicy == 'at'
          ? earliestAt?.toIso8601String()
          : null,
      'reserve_time': kind == 'exam' && certainty != 'formal'
          ? reserveTime
          : true,
      'remaining_minutes': kind == 'exam' || minutes.text.trim().isEmpty
          ? null
          : effort,
      'splittable': split,
      'priority': priority,
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
        'change_reason': reason.text.trim(),
      },
    };
    final encoded = jsonEncode(data);
    if (_requestBody != encoded) {
      _requestBody = encoded;
      _requestKey = List.generate(
        20,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (editing && kind == 'exam') {
        final request = <String, dynamic>{
          'expected_version': data['expected_version'],
          'time': t,
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
        if (!mounted) return;
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
      await widget.controller.save(
        data,
        id: widget.initial?['id'],
        idempotencyKey: _requestKey,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget estimate() => TextFormField(
    key: const Key('item-minutes'),
    controller: minutes,
    keyboardType: TextInputType.number,
    decoration: const InputDecoration(labelText: '预计剩余耗时（分钟，可留空）'),
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
    final result = await editReminder(
      context,
      kind: kind,
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
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          CampusHero(
            eyebrow: editing ? '修改后会更新相关提醒' : '把事情记下来',
            title: editing ? '核对修改内容' : '先记下重要的事',
            subtitle: '不确定的信息可以保留\n时间与提醒由你确认',
          ),
          const SizedBox(height: 18),
          if (parsed) ...[
            CampusPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '原文',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(source.text),
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
          DropdownButtonFormField<String>(
            initialValue: kind,
            key: ValueKey('item-kind-$kind'),
            isExpanded: true,
            decoration: const InputDecoration(labelText: '事项类型'),
            items: const [
              DropdownMenuItem(value: 'assignment', child: Text('作业')),
              DropdownMenuItem(value: 'exam', child: Text('考试')),
              DropdownMenuItem(value: 'task', child: Text('个人任务')),
            ],
            onChanged: editing
                ? null
                : (value) => setState(() => kind = value!),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('item-title'),
            controller: title,
            maxLength: 120,
            decoration: const InputDecoration(labelText: '标题（必填）'),
            validator: (v) => v!.trim().isEmpty ? '请输入事项标题' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: course,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '关联课程（可不选）'),
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('不关联课程')),
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
                    '${c['title']} · 周${'一二三四五六日'[(c['weekday'] as int) - 1]} ${c['teacher']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => course = v),
          ),
          const SectionHeading('时间安排'),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final e in {
                'exact': '具体时间',
                'date': '仅日期',
                'week': '学期周次',
                'range': '日期范围',
                'unknown': '待确认',
              }.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: precision == e.key,
                  onSelected: (_) => setState(() {
                    precision = e.key;
                    timeError = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (['date', 'range', 'exact'].contains(precision))
            OutlinedButton.icon(
              key: const Key('item-date'),
              onPressed: () => pickDate(),
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(date == null ? '选择日期' : day(date!)),
            ),
          if (precision == 'exact')
            OutlinedButton.icon(
              onPressed: () async {
                final selected = await showTimePicker(
                  context: context,
                  initialTime: time ?? const TimeOfDay(hour: 9, minute: 0),
                );
                if (mounted && selected != null) {
                  setState(() => time = selected);
                }
              },
              icon: const Icon(Icons.schedule),
              label: Text(
                time == null ? '选择具体时间（北京时间）' : time!.format(context),
              ),
            ),
          if (precision == 'range')
            OutlinedButton.icon(
              onPressed: () => pickDate(end: true),
              icon: const Icon(Icons.date_range),
              label: Text(endDate == null ? '选择范围结束日期' : '至 ${day(endDate!)}'),
            ),
          if (precision == 'week')
            TextFormField(
              key: const Key('item-week'),
              controller: week,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '第几周（1—${widget.semester['total_weeks']}）',
              ),
            ),
          if (precision == 'date' && kind != 'exam')
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('在这一天结束前完成'),
              subtitle: const Text('用于计算提醒和安排计划，原通知只写了日期的情况也会保留。'),
              value: dayEnd,
              onChanged: (v) => setState(() => dayEnd = v!),
            ),
          if (timeError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                timeError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          if (kind == 'exam' && precision == 'exact') ...[
            OutlinedButton.icon(
              key: const Key('exam-end'),
              onPressed: () async {
                final selected = await pickSchoolDateTime(
                  context,
                  initial: examEndAt,
                );
                if (mounted && selected != null) {
                  setState(() => examEndAt = selected);
                }
              },
              icon: const Icon(Icons.schedule_outlined),
              label: Text(
                examEndAt == null
                    ? '补充考试结束时间'
                    : '结束：${displayInstant(examEndAt!.toIso8601String())}',
              ),
            ),
            if (examEndAt != null)
              TextButton(
                onPressed: () => setState(() => examEndAt = null),
                child: const Text('结束时间改为待确认'),
              ),
            const Text(
              '缺少结束时间可以先记录，相关余量会提示信息不足。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            initialValue: certainty,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: kind == 'exam' ? '考试是否确定' : '截止是否确定',
            ),
            items: const [
              DropdownMenuItem(value: 'unknown', child: Text('待确认')),
              DropdownMenuItem(value: 'tentative', child: Text('暂定')),
              DropdownMenuItem(value: 'formal', child: Text('已正式确定')),
            ],
            onChanged: (v) => setState(() => certainty = v!),
          ),
          if (kind == 'exam') ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: location,
              decoration: const InputDecoration(labelText: '考试地点（可留空）'),
            ),
          ],
          if (kind != 'exam' &&
              (widget.initial?['remaining_minutes'] ??
                      widget.candidate?['item']?['remaining_minutes']) !=
                  null) ...[
            const SizedBox(height: 16),
            estimate(),
          ],
          if (!editing) ...[
            SectionHeading('提醒', action: '添加提醒', onAction: () => addReminder()),
            if (reminders.isEmpty)
              CampusPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('当前不设置提醒'),
                    TextButton(
                      onPressed: () => addReminder(),
                      child: const Text('选择提醒 · 建议提前1天'),
                    ),
                  ],
                ),
              ),
            for (var i = 0; i < reminders.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CampusPanel(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    title: Text(
                      '${reminderLabel(reminders[i])}${reminders[i]['enabled'] == false ? ' · 已停用' : ''}',
                    ),
                    subtitle: Text(reminderPreview(reminders[i])),
                    onTap: () => addReminder(i),
                    trailing: IconButton(
                      tooltip: '移除此提醒',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => reminders.removeAt(i)),
                    ),
                  ),
                ),
              ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: SoftNotice('提醒在事项详情中独立管理。日期修改后，相对提醒会重算，需核对的指定时刻提醒会暂停。'),
            ),
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('更多设置'),
            initiallyExpanded: editing,
            subtitle: kind == 'exam'
                ? null
                : Text(
                    '最早开始：${startPolicy == 'now'
                        ? '从现在起'
                        : startPolicy == 'at'
                        ? displayInstant(earliestAt?.toIso8601String())
                        : '待确认'}',
                    style: const TextStyle(fontSize: 12),
                  ),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 16),
            children: [
              if (kind != 'exam') ...[
                DropdownButtonFormField<String>(
                  key: const Key('task-start-policy'),
                  initialValue: startPolicy,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '最早何时可以开始'),
                  items: const [
                    DropdownMenuItem(value: 'unconfirmed', child: Text('待确认')),
                    DropdownMenuItem(value: 'now', child: Text('从现在起可开始')),
                    DropdownMenuItem(value: 'at', child: Text('指定最早开始时间')),
                  ],
                  onChanged: (v) => setState(() => startPolicy = v!),
                ),
                if (startPolicy == 'at')
                  OutlinedButton(
                    onPressed: () async {
                      final selected = await pickSchoolDateTime(
                        context,
                        initial: earliestAt,
                      );
                      if (selected != null && mounted) {
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
              if (kind == 'exam' && certainty != 'formal')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('为尚未确定的考试预留时间'),
                  subtitle: const Text('开始和结束完整后才扣除时段；信息缺失时提示核对。'),
                  value: reserveTime,
                  onChanged: (v) => setState(() => reserveTime = v),
                ),
              if (kind != 'exam' &&
                  (widget.initial?['remaining_minutes'] ??
                          widget.candidate?['item']?['remaining_minutes']) ==
                      null)
                estimate(),
              if (kind != 'exam')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('以后允许分段安排'),
                  value: split,
                  onChanged: (v) => setState(() => split = v),
                ),
              DropdownButtonFormField<String>(
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
              TextFormField(
                controller: notes,
                maxLines: 3,
                maxLength: 3000,
                decoration: const InputDecoration(labelText: '补充说明'),
              ),
              if (!parsed && !editing)
                TextFormField(
                  controller: source,
                  maxLines: 3,
                  maxLength: 10000,
                  decoration: const InputDecoration(labelText: '来源原文（可留空）'),
                ),
            ],
          ),
          if (editing)
            TextFormField(
              key: const Key('item-change-reason'),
              controller: reason,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: '修改依据（必填）',
                hintText: '例如：根据老师的新通知核对截止时间',
              ),
              validator: (v) => v!.trim().isEmpty ? '请说明修改依据' : null,
            ),
          if (parsed)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('我已核对原文、日期和标出的推断'),
              value: reviewed,
              onChanged: (v) => setState(() => reviewed = v!),
            ),
          if (error != null) ...[
            SoftNotice(error!, warning: true),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(
              busy
                  ? '正在保存…'
                  : editing
                  ? '确认修改事项'
                  : '确认保存事项',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '只有确认保存后才会创建事项。未填写耗时不影响记录。',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
