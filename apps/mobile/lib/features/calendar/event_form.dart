import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../core/api.dart';
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
  String precision = 'exact', certainty = 'formal';
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

  Future<void> save() async {
    if (!same || !ready || busy) return;
    if (submitted == null) {
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
                TextFormField(
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
                DropdownButtonFormField<String>(
                  initialValue: precision,
                  decoration: const InputDecoration(labelText: '时间'),
                  items: const [
                    DropdownMenuItem(value: 'exact', child: Text('已确定开始和结束时间')),
                    DropdownMenuItem(
                      value: 'exact_start',
                      child: Text('只确定开始时间'),
                    ),
                    DropdownMenuItem(value: 'date', child: Text('只确定日期')),
                    DropdownMenuItem(value: 'week', child: Text('只确定周次')),
                    DropdownMenuItem(value: 'range', child: Text('日期范围')),
                    DropdownMenuItem(value: 'unknown', child: Text('时间待确认')),
                  ],
                  onChanged: (v) => setState(() => precision = v!),
                ),
                if (!['unknown', 'week'].contains(precision)) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => pick(false),
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      '${precision.startsWith('exact') ? '开始' : '日期'}：${calendarDate(start)}${precision.startsWith('exact') ? ' ${hhmm(start)}' : ''}',
                    ),
                  ),
                  if (precision == 'exact' || precision == 'range')
                    OutlinedButton.icon(
                      onPressed: () => pick(true),
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        '结束：${calendarDate(end)}${precision == 'exact' ? ' ${hhmm(end)}' : ''}',
                      ),
                    ),
                ],
                if (precision == 'week')
                  DropdownButtonFormField<int>(
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
                const SizedBox(height: 14),
                TextFormField(
                  controller: location,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: '地点（选填）'),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in [15, 30, 60, 1440])
                      FilterChip(
                        label: Text(value == 1440 ? '提前1天' : '提前$value分钟'),
                        selected: reminders.contains(value),
                        onSelected: (on) => setState(() {
                          if (on) {
                            reminders.add(value);
                          } else {
                            reminders.remove(value);
                          }
                        }),
                      ),
                  ],
                ),
                if (!precision.startsWith('exact'))
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('补全开始时间后，提前提醒才会生效。'),
                  ),
                const SizedBox(height: 14),
                ExpansionTile(
                  title: const Text('分类与更多设置'),
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: category ?? '',
                      decoration: const InputDecoration(labelText: '主分类'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('未分类')),
                        for (final c in eventCategories.entries)
                          DropdownMenuItem(value: c.key, child: Text(c.value)),
                      ],
                      onChanged: (v) =>
                          setState(() => category = v == '' ? null : v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: tags,
                      decoration: const InputDecoration(
                        labelText: '标签（选填）',
                        hintText: '组会、项目讨论',
                        helperText: '用逗号或顿号分隔',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: certainty,
                      decoration: const InputDecoration(labelText: '确定程度'),
                      items: const [
                        DropdownMenuItem(value: 'formal', child: Text('已确定')),
                        DropdownMenuItem(value: 'tentative', child: Text('暂定')),
                        DropdownMenuItem(value: 'unknown', child: Text('待确认')),
                      ],
                      onChanged: (v) => setState(() => certainty = v!),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
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
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!ready && error != null)
            TextButton(onPressed: loadRevision, child: const Text('重新连接')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy || !ready || !same ? null : save,
            child: Text(
              busy
                  ? '正在保存…'
                  : submitted != null
                  ? '重试保存'
                  : widget.original == null
                  ? '确认添加日程'
                  : '保存修改',
            ),
          ),
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
      builder: (c) => AlertDialog(
        title: const Text('取消这条日程？'),
        content: const Text('取消后将停止提醒并释放占用时间。已有个人计划不会自动移动。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('保留日程'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      final semesters = List<Map<String, dynamic>>.from(
        await widget.controller.api.request('GET', '/semesters'),
      );
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

  @override
  Widget build(BuildContext context) {
    final row = data;
    return Scaffold(
      appBar: AppBar(title: const Text('日程详情')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (row == null)
            const LinearProgressIndicator()
          else ...[
            Text(
              row['title'],
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 18),
            Text(
              calendarTimeLabel({
                'time_precision': row['time']['precision'],
                ...Map<String, dynamic>.from(row['time']),
                'start_at': row['time']['at'],
                'end_at': row['time']['end_at'],
              }),
            ),
            if (row['certainty'] != 'formal') const Text('时间或安排尚待确认'),
            if ('${row['location']}'.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: Text(row['location']),
              ),
            Wrap(
              spacing: 8,
              children: [
                if (row['category_id'] != null)
                  Chip(label: Text(eventCategories[row['category_id']]!)),
                for (final tag in row['tags']) Chip(label: Text(tag['name'])),
              ],
            ),
            const SizedBox(height: 16),
            const Text('提醒', style: TextStyle(fontWeight: FontWeight.bold)),
            if ((row['reminders'] as List).isEmpty) const Text('未设置提醒'),
            for (final r in row['reminders'])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_none),
                title: Text(reminderLabel(Map<String, dynamic>.from(r))),
                subtitle: Text(reminderState(r['schedule_state'])),
              ),
            if ('${row['source_text']}'.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('通知原文', style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(row['source_text']),
            ],
            if (row['source_id'] != null)
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SourceViewPage(
                      controller: widget.controller,
                      id: row['source_id'],
                    ),
                  ),
                ),
                icon: const Icon(Icons.description_outlined),
                label: const Text('查看原始通知'),
              ),
            const SizedBox(height: 24),
            if (row['lifecycle'] == 'cancelled')
              const Text('这条日程已取消')
            else ...[
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EventFormPage(
                              controller: widget.controller,
                              semester: widget.semester,
                              original: row,
                            ),
                          ),
                        );
                        await load();
                      },
                child: const Text('修改日程'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: busy ? null : cancel,
                child: const Text('取消日程'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
