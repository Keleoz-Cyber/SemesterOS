import '../centers/academic_visuals.dart';
import '../../ui/app_date_time_picker.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_loading.dart';
import '../../ui/date_labels.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../core/api.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/record_actions.dart';
import '../../ui/app_picker_field.dart';
import '../../ui/time_input_options.dart';
import '../items/reminder_editor.dart';
import '../agent/assistant_sheet.dart';
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import 'calendar_repository.dart';
import 'event_overview.dart';
import 'event_conflict_review.dart';
import '../media/source_view.dart';
import '../notices/notice_fields.dart';
import '../tags/tag_picker_field.dart';

const eventCategories = {
  'study': '学业',
  'research': '科研',
  'affairs': '校园事务',
  'life': '生活',
};
String schoolInstant(DateTime local) => DateTime.utc(
  local.year,
  local.month,
  local.day,
  local.hour,
  local.minute,
).subtract(const Duration(hours: 8)).toIso8601String();

class EventFormPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> semester;
  final Map<String, dynamic>? original;
  final Map<String, dynamic>? candidate;
  const EventFormPage({
    super.key,
    required this.controller,
    required this.semester,
    this.original,
    this.candidate,
  });
  @override
  State<EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends State<EventFormPage> {
  final title = TextEditingController(),
      location = TextEditingController(),
      expression = TextEditingController(),
      notes = TextEditingController(),
      source = TextEditingController();
  final form = GlobalKey<FormState>();
  List<String> tags = [];
  String precision = 'unknown', certainty = 'formal';
  Map<String, dynamic> originalTime = {}, details = {};
  bool reserveTime = true, hasStart = false, hasEnd = false;
  String? category, error;
  late DateTime start, end;
  int week = 1, revision = 0;
  List<int> reminders = [];
  bool busy = false, ready = false;
  Map<String, dynamic>? submitted;
  final key = List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  late final generation = widget.controller.api.generation;
  bool get same =>
      generation == widget.controller.api.generation &&
      widget.controller.semesterId == widget.semester['id'];
  @override
  void initState() {
    super.initState();
    final now = schoolNow().add(const Duration(hours: 1));
    start = DateTime.utc(now.year, now.month, now.day, now.hour);
    end = start.add(const Duration(hours: 1));
    final old = widget.original ?? widget.candidate?['event'];
    if (old != null) {
      title.text = old['title'];
      location.text = old['location'] ?? '';
      tags = (old['tags'] as List? ?? [])
          .map((t) => t is Map ? t['name'] : t)
          .whereType<String>()
          .toList();
      source.text = old['source_text'] ?? '';
      category = old['category_id'];
      certainty = old['certainty'] ?? 'formal';
      details = noticeMap(old['details']);
      notes.text = old['notes'] ?? '';
      reserveTime =
          old['reserve_time'] ??
          !{
            'optional',
            'conditional',
            'other',
          }.contains(details['participation_status']);
      final time = Map<String, dynamic>.from(old['time']);
      originalTime = time;
      expression.text = time['expression'] ?? '';
      hasStart = time['at'] != null || time['date'] != null;
      hasEnd = time['end_at'] != null || time['end_date'] != null;
      precision = time['precision'];
      week = time['week'] ?? 1;
      if (time['at'] != null) {
        final wall = schoolTime(time['at']);
        start = DateTime.utc(
          wall.year,
          wall.month,
          wall.day,
          wall.hour,
          wall.minute,
        );
      }
      if (time['end_at'] != null) {
        final wall = schoolTime(time['end_at']);
        end = DateTime.utc(
          wall.year,
          wall.month,
          wall.day,
          wall.hour,
          wall.minute,
        );
      } else {
        end = start.add(const Duration(hours: 1));
      }
      if (time['date'] != null) start = DateTime.parse(time['date']);
      if (time['end_date'] != null) end = DateTime.parse(time['end_date']);
      reminders = List<int>.from(old['reminder_minutes'] ?? []);
      // An unknown end stays unknown; opening an editor must not invent a duration.
      if (precision == 'exact' && time['end_at'] == null) {
        precision = 'exact_start';
      }
    }
    loadRevision();
  }

  Future<void> loadRevision() async {
    try {
      final values = List<Map<String, dynamic>>.from(
        await widget.controller.api.request('GET', '/semesters'),
      );
      if (!mounted || !same) return;
      final semester = values
          .where((s) => s['id'] == widget.semester['id'])
          .first;
      setState(() {
        revision = semester['revision'];
        ready = true;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    }
  }

  @override
  void dispose() {
    title.dispose();
    location.dispose();
    source.dispose();
    expression.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<bool> pick(bool ending) async {
    FocusManager.instance.primaryFocus?.unfocus();
    var value = ending ? end : start;
    if (precision.startsWith('exact')) {
      final selected = await showAppDateTimePicker(
        context: context,
        initialDate: value,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: ending ? '结束时间' : '开始时间',
        initialSection: AppDateTimeSection.time,
      );
      if (selected == null || !mounted || !same) return false;
      setState(() {
        if (ending) {
          end = selected;
          hasEnd = true;
        } else {
          start = selected;
          hasStart = true;
        }
      });
      return true;
    }
    final bounds = appDatePickerBounds(
      initialDate: value,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    final date = await showDatePicker(
      context: context,
      currentDate: appSchoolToday(),
      initialDate: DateTime(value.year, value.month, value.day),
      firstDate: bounds.start,
      lastDate: bounds.end,
    );
    if (date == null || !mounted || !same) return false;
    var time = TimeOfDay.fromDateTime(value);
    setState(() {
      value = DateTime.utc(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (ending) {
        end = value;
        hasEnd = true;
      } else {
        start = value;
        hasStart = true;
      }
    });
    return true;
  }

  Future<void> selectPrecision(String value) async {
    final previous = precision;
    setState(() => precision = value);
    if (previous == 'date' && hasStart && value.startsWith('exact')) {
      FocusManager.instance.primaryFocus?.unfocus();
      final selected = await showAppDateTimePicker(
        context: context,
        initialDate: start,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: '开始时间',
        initialSection: AppDateTimeSection.time,
      );
      if (!mounted || !same) return;
      setState(() {
        if (selected == null) {
          precision = previous;
        } else {
          start = selected;
        }
      });
      return;
    }
    if (!{'unknown', 'week'}.contains(value) &&
        (!hasStart ||
            value.startsWith('exact') && !previous.startsWith('exact'))) {
      final chosen = await pick(false);
      if (!chosen && mounted && same) setState(() => precision = previous);
    }
  }

  Future<DateTime?> pickEnd() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showAppDateTimePicker(
      context: context,
      initialDate: hasEnd ? end : start,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '结束时间',
      initialSection: AppDateTimeSection.time,
    );
    return mounted && same ? selected : null;
  }

  Future<void> editEventReminder([int? index]) async {
    final result = await editReminder(
      context,
      kind: 'event',
      relativeOnly: true,
      initial: index == null
          ? null
          : {'mode': 'relative', 'lead_minutes': reminders[index]},
    );
    if (result == null || !mounted) return;
    final minutes = result['lead_minutes'] as int;
    setState(() {
      if (index != null) reminders.removeAt(index);
      if (!reminders.contains(minutes)) reminders.add(minutes);
    });
  }

  Future<void> save() async {
    if (!same || !ready || busy) return;
    final requiresPreview = submitted == null;
    if (submitted == null) {
      if (title.text.trim().isEmpty) {
        form.currentState?.validate();
        setState(() => error = '请填写日程名称');
        return;
      }
      if (!(form.currentState?.validate() ?? false)) return;
      if ((!{'unknown', 'week'}.contains(precision) && !hasStart) ||
          ({'exact', 'range'}.contains(precision) && !hasEnd)) {
        setState(() => error = '请选择时间，或暂不填写');
        return;
      }
      if ((precision == 'exact' && !end.isAfter(start)) ||
          (precision == 'range' && end.isBefore(start))) {
        setState(() => error = '结束时间应晚于开始时间，请重新选择');
        return;
      }
      final time = <String, dynamic>{
        'meaning':
            originalTime['meaning'] == 'all_day' &&
                !{'date', 'range'}.contains(precision)
            ? 'unspecified'
            : precision != 'unknown' &&
                  {
                    'candidate',
                    'course_anchor',
                  }.contains(originalTime['meaning'])
            ? 'start'
            : originalTime['meaning'] ?? 'unspecified',
        'expression': expression.text.trim(),
        if (precision == 'unknown') ...{
          if (originalTime['candidate_dates'] != null)
            'candidate_dates': originalTime['candidate_dates'],
          if (originalTime['course_anchor'] != null)
            'course_anchor': originalTime['course_anchor'],
        },
        'precision': precision == 'exact_start' ? 'exact' : precision,
      };
      if (precision.startsWith('exact')) time['at'] = schoolInstant(start);
      if (precision == 'exact') time['end_at'] = schoolInstant(end);
      if (precision == 'date' || precision == 'range') {
        time['date'] = calendarDate(start);
      }
      if (precision == 'range') time['end_date'] = calendarDate(end);
      if (precision == 'week') time['week'] = week;
      submitted = {
        'semester_id': widget.semester['id'],
        'title': title.text.trim(),
        'time': time,
        'details': details,
        'reserve_time': reserveTime,
        'certainty': certainty,
        'location': location.text.trim(),
        'category_id': category,
        'tags': tags,
        'source_text': source.text.trim(),
        'notes': notes.text.trim(),
        'reminder_minutes': reminders,
        'expected_revision': revision,
        if (widget.candidate != null) 'candidate_id': widget.candidate!['id'],
        if (widget.original != null)
          'expected_version': widget.original!['version'],
      };
    }
    setState(() {
      busy = true;
      error = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    var writeStarted = false;
    try {
      if (requiresPreview) {
        final preview = await widget.controller.changeRequest(
          'POST',
          '/events/conflict-preview',
          data: {
            ...submitted!,
            if (widget.original != null) 'event_id': widget.original!['id'],
          },
        );
        if (!mounted || !same) return;
        final impact = Map<String, dynamic>.from(preview['impact'] ?? {});
        if (eventConflicts(impact).isNotEmpty) {
          final choice = await confirmEventConflicts(context, impact);
          if (!mounted || !same) return;
          if (choice == null || choice.adjustTime) {
            setState(() {
              submitted = null;
              busy = false;
            });
            if (choice?.adjustTime == true) await pick(false);
            return;
          }
          submitted = {
            ...submitted!,
            if (choice.keepConflicts) 'confirm_fixed_conflicts': true,
            if (choice.courseLeaveTargets.isNotEmpty)
              'course_leave_targets': choice.courseLeaveTargets,
          };
        }
      }
      writeStarted = true;
      final result = await widget.controller.changeRequest(
        widget.original == null ? 'POST' : 'PATCH',
        widget.original == null
            ? '/events'
            : '/events/${widget.original!['id']}',
        data: jsonDecode(jsonEncode(submitted)),
        apply: true,
        idempotencyKey: key,
      );
      if (!mounted || !same) return;
      final affected = (result['affected_plan_ids'] as List? ?? []).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(affected == 0 ? '日程已保存' : '日程已保存，$affected段学习安排需要核对'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (e is ApiFailure && e.statusCode == 409) {
        submitted = null;
        if (widget.original == null) {
          await loadRevision();
        } else if (mounted) {
          setState(() => ready = false);
        }
      }
      if (mounted) {
        setState(() {
          if (!writeStarted || e is ApiFailure && e.statusCode == 422) {
            submitted = null;
            error = userError(e);
          } else {
            error = userError(e);
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.original == null ? '添加日程' : '修改日程')),
    bottomNavigationBar: ActionFooter(
      label: busy
          ? '正在保存…'
          : submitted != null
          ? '重试保存'
          : widget.original == null
          ? '添加日程'
          : '保存修改',
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
      onPressed: busy || !ready || !same ? null : save,
    ),
    body: AppLoadingOverlay(
      loading: !ready && error == null,
      label: '正在读取日程',
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if ((widget.candidate?['questions'] as List? ?? []).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text((widget.candidate!['questions'] as List).join('；')),
              ),
            AbsorbPointer(
              absorbing: busy || submitted != null,
              child: ExcludeFocus(
                excluding: busy || submitted != null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AcademicEditorSection(
                      title: '日程内容',
                      icon: Icons.edit_note_rounded,
                      children: [
                        AppFormField(
                          controller: title,
                          maxLength: 120,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '日程名称',
                            hintText: '例如：课题组组会',
                          ),
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? '请填写日程名称' : null,
                        ),
                        const SizedBox(height: 12),
                        AppFormField(
                          controller: location,
                          maxLength: 120,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: '地点（选填）',
                          ),
                        ),
                      ],
                    ),
                    AcademicEditorSection(
                      title: '时间安排',
                      icon: Icons.schedule_rounded,
                      children: [
                        if (!['unknown', 'week'].contains(precision)) ...[
                          AcademicMomentControl(
                            label: precision == 'exact_start'
                                ? '时间'
                                : precision == 'exact'
                                ? '开始'
                                : '日期',
                            value:
                                '${studentDate(start, weekday: true)}${precision.startsWith('exact') ? ' ${hhmm(start)}' : ''}',
                            onTap: () => pick(false),
                          ),
                          if (precision == 'exact' || precision == 'range')
                            Row(
                              children: [
                                Expanded(
                                  child: AcademicMomentControl(
                                    label: '结束',
                                    ending: true,
                                    value:
                                        '${studentDate(end, weekday: true)}${precision == 'exact' ? ' ${hhmm(end)}' : ''}',
                                    onTap: () => pick(true),
                                  ),
                                ),
                                if (precision == 'exact')
                                  AppIconButton(
                                    tooltip: '移除结束时间',
                                    onPressed: () => setState(
                                      () => precision = 'exact_start',
                                    ),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 20,
                                    ),
                                  ),
                              ],
                            ),
                        ],
                        if (precision == 'week')
                          AppPickerField<int>(
                            initialValue: week,
                            decoration: const InputDecoration(labelText: '周次'),
                            items: List.generate(
                              widget.semester['total_weeks'],
                              (i) => DropdownMenuItem(
                                value: i + 1,
                                child: Text('第${i + 1}周'),
                              ),
                            ),
                            onChanged: (v) => setState(() => week = v!),
                          ),
                        if (precision == 'exact_start')
                          AppTextButton.icon(
                            onPressed: () async {
                              final value = await pickEnd();
                              if (value != null && mounted) {
                                setState(() {
                                  end = value;
                                  hasEnd = true;
                                  precision = 'exact';
                                });
                              }
                            },
                            guardAsync: false,
                            icon: const Icon(Icons.add),
                            label: const Text('添加结束时间'),
                          ),
                        const SizedBox(height: 12),
                        TimeInputOptions(
                          precision: precision,
                          exactValue: 'exact_start',
                          onChanged: selectPrecision,
                        ),
                        if (precision == 'unknown')
                          AppFormField(
                            key: const Key('event-time-expression'),
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
                          onChanged: (value) =>
                              setState(() => certainty = value),
                        ),
                        if (!reserveTime ||
                            details['participation_status'] != null &&
                                details['participation_status'] !=
                                    'unspecified')
                          AppSwitchRow(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('安排到我的日程'),
                            value: reserveTime,
                            onChanged: (value) =>
                                setState(() => reserveTime = value),
                          ),
                      ],
                    ),
                    NoticeDetailsEditor(
                      value: details,
                      onChanged: (value) => details = value,
                      notesController: notes,
                    ),
                    AcademicEditorSection(
                      title: '提醒',
                      icon: Icons.notifications_outlined,
                      accent: CampusColors.teal,
                      trailing: AppIconButton.filledTonal(
                        tooltip: '添加提醒',
                        icon: const Icon(Icons.add_rounded),
                        color: CampusColors.teal,
                        onPressed: () => editEventReminder(),
                      ),
                      children: [
                        for (var i = 0; i < reminders.length; i++)
                          AppTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${reminderLabel({'mode': 'relative', 'lead_minutes': reminders[i]})}提醒',
                            ),
                            trailing: AppIconButton(
                              tooltip: '删除这条提醒',
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(() => reminders.removeAt(i)),
                            ),
                            onTap: () => editEventReminder(i),
                          ),
                        if (reminders.isNotEmpty &&
                            !precision.startsWith('exact'))
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('补全开始时间后，这些提醒才会生效。'),
                          ),
                      ],
                    ),
                    AppDisclosure(
                      leading: const Icon(Icons.tune_rounded),
                      title: const Text('分类与更多设置'),
                      childrenPadding: const EdgeInsets.only(top: 12),
                      children: [
                        AppPickerField<String>(
                          initialValue: category ?? '',
                          decoration: const InputDecoration(labelText: '分类'),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('未分类'),
                            ),
                            for (final c in eventCategories.entries)
                              DropdownMenuItem(
                                value: c.key,
                                child: Text(c.value),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => category = v == '' ? null : v),
                        ),
                        const SizedBox(height: 12),
                        TagPickerField(
                          key: const Key('event-tags'),
                          controller: widget.controller,
                          values: tags,
                          enabled: !busy && same,
                          onChanged: (values) => setState(() => tags = values),
                        ),
                        const SizedBox(height: 12),
                        AppFormField(
                          controller: source,
                          readOnly:
                              widget.candidate != null ||
                              widget.original != null,
                          maxLines: 3,
                          maxLength: 10000,
                          decoration: const InputDecoration(
                            labelText: '通知原文（选填）',
                            counterText: '',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (!ready && error != null)
              AppTextButton(onPressed: loadRevision, child: const Text('重新连接')),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}

class EventDetailPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> semester;
  final String eventId;
  const EventDetailPage({
    super.key,
    required this.controller,
    required this.semester,
    required this.eventId,
  });
  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  late final generation = widget.controller.api.generation;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() => error = null);
    try {
      final result = Map<String, dynamic>.from(
        await widget.controller.api.request('GET', '/events/${widget.eventId}'),
      );
      if (mounted && generation == widget.controller.api.generation) {
        setState(() => data = result);
      }
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    }
  }

  Future<void> cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AppDialog(
        title: const Text('取消这条日程？'),
        content: const Text('取消后将停止提醒并释放占用时间。已有学习安排不会自动移动。'),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('保留日程'),
          ),
          AppButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (ok != true ||
        !mounted ||
        generation != widget.controller.api.generation) {
      return;
    }
    setState(() => busy = true);
    try {
      final semesters = List<Map<String, dynamic>>.from(
        await widget.controller.api.request('GET', '/semesters'),
      );
      if (!mounted || generation != widget.controller.api.generation) return;
      final revision = semesters.firstWhere(
        (s) => s['id'] == data!['semester_id'],
      )['revision'];
      await widget.controller.changeRequest(
        'POST',
        '/events/${widget.eventId}/cancel',
        data: {
          'expected_version': data!['version'],
          'expected_revision': revision,
        },
        apply: true,
      );
      await load();
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventFormPage(
          controller: widget.controller,
          semester: widget.semester,
          original: data!,
        ),
      ),
    );
    if (mounted) await load();
  }

  Future<void> setReminder({Map<String, dynamic>? existing}) async {
    if (data == null || busy) return;
    final row = Map<String, dynamic>.from(data!);
    final choice = await editReminder(
      context,
      kind: 'event',
      relativeOnly: true,
      initial: existing,
    );
    if (choice == null ||
        !mounted ||
        generation != widget.controller.api.generation) {
      return;
    }
    final leads = List<int>.from(row['reminder_minutes'] ?? []);
    if (existing?['lead_minutes'] is int) {
      leads.remove(existing!['lead_minutes']);
    }
    leads.add(choice['lead_minutes'] as int);
    setState(() => busy = true);
    try {
      final semesters = List<Map<String, dynamic>>.from(
        await widget.controller.api.request('GET', '/semesters'),
      );
      if (!mounted || generation != widget.controller.api.generation) return;
      await widget.controller.changeRequest(
        'PATCH',
        '/events/${widget.eventId}',
        apply: true,
        data: {
          for (final key in [
            'semester_id',
            'title',
            'time',
            'certainty',
            'reserve_time',
            'location',
            'notes',
            'source_text',
            'details',
            'category_id',
            'candidate_id',
          ])
            if (row.containsKey(key)) key: row[key],
          'tags': (row['tags'] as List? ?? [])
              .map((t) => t is Map ? t['name'] : t)
              .whereType<String>()
              .toList(),
          'reminder_minutes': leads.toSet().toList(),
          'expected_version': row['version'],
          'expected_revision': semesters.firstWhere(
            (s) => s['id'] == row['semester_id'],
          )['revision'],
          'change_reason': '设置提醒',
        },
      );
      await widget.controller.syncNotifications(requestPermission: true);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日程详情'),
        actions: [
          if (row != null && row['lifecycle'] != 'cancelled')
            AppIconButton(
              tooltip: '编辑日程',
              onPressed: busy ? null : edit,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (row != null)
            RecordMenuButton<String>(
              enabled: !busy,
              onSelected: (value) async {
                if (value == 'cancel') await cancel();
                if (value == 'refresh') await load();
                if (value == 'source' && context.mounted) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SourceViewPage(
                        controller: widget.controller,
                        id: row['source_id'],
                      ),
                    ),
                  );
                }
              },
              actions: [
                if (row['source_id'] != null)
                  const RecordMenuAction(
                    'source',
                    '原始通知',
                    Icons.description_outlined,
                  ),
                const RecordMenuAction('refresh', '刷新', Icons.refresh_rounded),
                if (row['lifecycle'] != 'cancelled')
                  const RecordMenuAction(
                    'cancel',
                    '取消日程',
                    Icons.event_busy_outlined,
                    destructive: true,
                  ),
              ],
            ),
        ],
      ),
      bottomNavigationBar: row?['lifecycle'] == 'cancelled'
          ? ActionFooter(
              label: '恢复日程',
              icon: Icons.undo_rounded,
              onPressed: () => openAssistantSheet(
                context,
                controller: widget.controller,
                semester: widget.semester,
                initialText: '恢复这条日程，保留原来的时间、地点和提醒。',
                selectedRecordIds: [widget.eventId],
                autoSubmit: true,
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (row == null)
            if (error == null)
              const Center(child: AppLoadingIndicator(label: '正在读取日程'))
            else
              AppTextButton(onPressed: load, child: const Text('重新读取日程'))
          else ...[
            EventOverview(
              row: row,
              category: eventCategories[row['category_id']],
            ),
            if (row['lifecycle'] != 'cancelled')
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    AppOutlineButton.icon(
                      onPressed: busy ? null : () => setReminder(),
                      icon: const Icon(
                        Icons.notifications_none_rounded,
                        size: 19,
                      ),
                      label: Text(
                        (row['reminders'] as List? ?? []).isEmpty
                            ? '添加提醒'
                            : '再添加提醒',
                      ),
                    ),
                    AppTextButton.icon(
                      onPressed: () => openAssistantSheet(
                        context,
                        controller: widget.controller,
                        semester: widget.semester,
                        initialText: '关于“${row['title']}”：',
                        selectedRecordIds: [widget.eventId],
                      ),
                      icon: const Icon(Icons.auto_awesome_outlined, size: 19),
                      label: const Text('询问或修改'),
                    ),
                  ],
                ),
              ),
            if (noticeDetailRows(
              row['details'],
              location: row['location'],
              title: row['title'],
            ).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '通知要求',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    NoticeDetails(
                      row['details'],
                      location: row['location'],
                      title: row['title'],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            if ((row['reminders'] as List? ?? []).isNotEmpty)
              AcademicEditorSection(
                title: '提醒',
                icon: Icons.notifications_outlined,
                accent: CampusColors.teal,
                children: [
                  for (final r in row['reminders'])
                    AppTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        r['schedule_state'] == 'scheduled'
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_none,
                        color: CampusColors.teal,
                      ),
                      title: Text(reminderLabel(Map<String, dynamic>.from(r))),
                      subtitle: Text(reminderState(r['schedule_state'])),
                      trailing: row['lifecycle'] == 'cancelled'
                          ? null
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: busy || row['lifecycle'] == 'cancelled'
                          ? null
                          : () => setReminder(
                              existing: Map<String, dynamic>.from(r),
                            ),
                    ),
                ],
              ),
            if ('${row['notes'] ?? ''}'.trim().isNotEmpty)
              DocumentPanel(title: '补充说明', text: row['notes']),
            if ('${row['source_text'] ?? ''}'.trim().isNotEmpty)
              AppDisclosure(
                tilePadding: EdgeInsets.zero,
                title: const Text('通知原文'),
                children: [
                  Text(
                    row['source_text'],
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: CampusColors.muted,
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
