import '../../ui/campus_widgets.dart';
import '../../ui/app_controls.dart';
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
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import 'calendar_repository.dart';
import '../media/source_view.dart';

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
      tags = TextEditingController(),
      source = TextEditingController();
  final form = GlobalKey<FormState>();
  String precision = 'exact_start', certainty = 'formal';
  String? category, error;
  late DateTime start, end;
  int week = 1, revision = 0;
  List<int> reminders = [30];
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
    start = DateTime(now.year, now.month, now.day, now.hour);
    end = start.add(const Duration(hours: 1));
    final old = widget.original ?? widget.candidate?['event'];
    if (old != null) {
      title.text = old['title'];
      location.text = old['location'] ?? '';
      tags.text = (old['tags'] as List? ?? [])
          .map((t) => t is Map ? t['name'] : t)
          .join('、');
      source.text = old['source_text'] ?? '';
      category = old['category_id'];
      certainty = old['certainty'];
      final time = Map<String, dynamic>.from(old['time']);
      precision = time['precision'];
      week = time['week'] ?? 1;
      if (time['at'] != null) start = schoolTime(time['at']);
      if (time['end_at'] != null) {
        end = schoolTime(time['end_at']);
      } else {
        end = start.add(const Duration(hours: 1));
      }
      if (time['date'] != null) start = DateTime.parse(time['date']);
      if (time['end_date'] != null) end = DateTime.parse(time['end_date']);
      reminders = List<int>.from(old['reminder_minutes'] ?? []);
      if (widget.candidate != null && reminders.isEmpty) reminders = [30];
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
    tags.dispose();
    source.dispose();
    super.dispose();
  }

  Future<void> pick(bool ending) async {
    var value = ending ? end : start;
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(value.year, value.month, value.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    var time = TimeOfDay.fromDateTime(value);
    if (precision.startsWith('exact')) {
      final selected = await showTimePicker(
        context: context,
        initialTime: time,
      );
      if (selected == null || !mounted) return;
      time = selected;
    }
    setState(() {
      value = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      if (ending) {
        end = value;
      } else {
        start = value;
      }
    });
  }

  Future<DateTime?> pickEnd() async {
    final date = await showDatePicker(
      context: context,
      initialDate: end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final clock = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(end),
    );
    if (clock == null) return null;
    return DateTime(date.year, date.month, date.day, clock.hour, clock.minute);
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
    if (submitted == null) {
      if (title.text.trim().isEmpty) {
        form.currentState?.validate();
        setState(() => error = '请填写日程名称');
        return;
      }
      if (!(form.currentState?.validate() ?? false)) return;
      if ((precision == 'exact' && !end.isAfter(start)) ||
          (precision == 'range' && end.isBefore(start))) {
        setState(() => error = '结束时间应晚于开始时间，请重新选择');
        return;
      }
      final time = <String, dynamic>{
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
        'certainty': certainty,
        'location': location.text.trim(),
        'category_id': category,
        'tags': tags.text
            .split(RegExp('[,，、\n]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'source_text': source.text.trim(),
        'notes': widget.original?['notes'] ?? '',
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
    try {
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
          content: Text(affected == 0 ? '日程已保存' : '日程已保存，$affected段个人计划需要核对'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e is ApiFailure && e.statusCode == 422) {
            submitted = null;
            error = '${userError(e)}\n可以修改后重新保存。';
          } else {
            error = '${userError(e)}\n重试会使用同一份记录，不会重复创建。若安排已被修改，请返回后重新打开。';
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
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!ready && error == null) const LinearProgressIndicator(),
          if ((widget.candidate?['questions'] as List? ?? []).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text((widget.candidate!['questions'] as List).join('；')),
            ),
          AbsorbPointer(
            absorbing: busy || submitted != null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EditorSection(
                  title: '日程内容',
                  icon: Icons.event_note_outlined,
                  children: [
                    AppFormField(
                      controller: title,
                      maxLength: 120,
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
                      decoration: const InputDecoration(labelText: '地点（选填）'),
                    ),
                  ],
                ),
                EditorSection(
                  title: '时间安排',
                  icon: Icons.schedule_rounded,
                  children: [
                    if (!['unknown', 'week'].contains(precision)) ...[
                      const SizedBox(height: 12),
                      AppOutlineButton.icon(
                        onPressed: () => pick(false),
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          '${precision.startsWith('exact') ? '开始' : '日期'}：${calendarDate(start)}${precision.startsWith('exact') ? ' ${hhmm(start)}' : ''}',
                        ),
                      ),
                      if (precision == 'exact' || precision == 'range')
                        AppOutlineButton.icon(
                          onPressed: () => pick(true),
                          icon: const Icon(Icons.schedule),
                          label: Text(
                            '结束：${calendarDate(end)}${precision == 'exact' ? ' ${hhmm(end)}' : ''}',
                          ),
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
                              precision = 'exact';
                            });
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('添加结束时间'),
                      ),
                    if (precision == 'exact')
                      AppTextButton(
                        onPressed: () =>
                            setState(() => precision = 'exact_start'),
                        child: const Text('移除结束时间'),
                      ),
                    TimeInputOptions(
                      precision: precision,
                      exactValue: 'exact_start',
                      onChanged: (value) => setState(() => precision = value),
                    ),
                    TentativeSwitch(
                      certainty: certainty,
                      onChanged: (value) => setState(() => certainty = value),
                    ),
                  ],
                ),
                EditorSection(
                  title: '提醒',
                  icon: Icons.notifications_outlined,
                  accent: CampusColors.teal,
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
                    AppTextButton.icon(
                      onPressed: () => editEventReminder(),
                      icon: const Icon(Icons.add),
                      label: Text(reminders.isEmpty ? '添加提醒' : '再添加一条提醒'),
                    ),
                    if (reminders.isNotEmpty && !precision.startsWith('exact'))
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
                        const DropdownMenuItem(value: '', child: Text('未分类')),
                        for (final c in eventCategories.entries)
                          DropdownMenuItem(value: c.key, child: Text(c.value)),
                      ],
                      onChanged: (v) =>
                          setState(() => category = v == '' ? null : v),
                    ),
                    const SizedBox(height: 12),
                    AppFormField(
                      controller: tags,
                      decoration: const InputDecoration(
                        labelText: '标签（选填）',
                        hintText: '组会、项目讨论',
                        helperText: '用逗号或顿号分隔',
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppFormField(
                      controller: source,
                      readOnly:
                          widget.candidate != null || widget.original != null,
                      maxLines: 3,
                      maxLength: 10000,
                      decoration: const InputDecoration(labelText: '通知原文（选填）'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!ready && error != null)
            AppTextButton(onPressed: loadRevision, child: const Text('重新连接')),
          const SizedBox(height: 16),
        ],
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
        content: const Text('取消后将停止提醒并释放占用时间。已有个人计划不会自动移动。'),
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

  @override
  Widget build(BuildContext context) {
    final row = data;
    final timing = Map<String, dynamic>.from(row?['time'] ?? {});
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
              const LinearProgressIndicator()
            else
              AppTextButton(onPressed: load, child: const Text('重新读取日程'))
          else ...[
            RecordHeading(
              title: row['title'],
              label: row['lifecycle'] == 'cancelled'
                  ? '日程 · 已取消'
                  : row['certainty'] == 'formal'
                  ? '日程'
                  : '日程 · 暂定',
              icon: Icons.event_outlined,
              color: CampusColors.teal,
            ),
            if ((timing['precision'] != null &&
                    timing['precision'] != 'unknown') ||
                '${row['location'] ?? ''}'.trim().isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: CampusColors.tealSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    if (timing['at'] != null) ...[
                      RecordFact(
                        label: '开始',
                        value: displayInstant(timing['at']),
                        icon: Icons.play_circle_outline_rounded,
                        color: CampusColors.teal,
                      ),
                      if (timing['end_at'] != null) ...[
                        const Divider(height: 1),
                        RecordFact(
                          label: '结束',
                          value: displayInstant(timing['end_at']),
                          icon: Icons.stop_circle_outlined,
                          color: CampusColors.teal,
                        ),
                      ],
                    ] else if (timing['precision'] != null &&
                        timing['precision'] != 'unknown')
                      RecordFact(
                        label: '时间',
                        value: calendarTimeLabel({
                          'time_precision': timing['precision'],
                          ...timing,
                          'start_at': timing['at'],
                          'end_at': timing['end_at'],
                        }, includeMissing: false),
                        icon: Icons.schedule_rounded,
                        color: CampusColors.teal,
                      ),
                    if ('${row['location'] ?? ''}'.isNotEmpty) ...[
                      const Divider(height: 1),
                      RecordFact(
                        label: '地点',
                        value: row['location'],
                        icon: Icons.place_outlined,
                      ),
                    ],
                  ],
                ),
              ),
            if (row['category_id'] != null ||
                (row['tags'] as List? ?? []).isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (row['category_id'] != null)
                      StatusPill(eventCategories[row['category_id']] ?? '其他'),
                    for (final tag in row['tags'] ?? [])
                      StatusPill(tag['name']),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            if ((row['reminders'] as List? ?? []).isNotEmpty)
              EditorSection(
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
                          : edit,
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
                  DocumentPanel(title: '通知原文', text: row['source_text']),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
