import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../../ui/campus_widgets.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import '../planning/date_time_picker.dart';
import '../planning/risk_widgets.dart';
import '../planning/plan_list.dart';
import 'hub_data.dart';

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
              const CampusHero(
                eyebrow: '提前准备',
                title: '考试有安排，复习有余量',
                subtitle: '考试是固定安排\n复习是独立的个人任务',
              ),
              if (widget.examId == null) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('考试安排'),
                      selected: !cancelled,
                      onSelected: (_) => setState(() => cancelled = false),
                    ),
                    ChoiceChip(
                      label: const Text('已取消'),
                      selected: cancelled,
                      onSelected: (_) => setState(() => cancelled = true),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () async {
                    await context.push('/items/new?kind=exam');
                    await reload();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('记录考试'),
                ),
              ],
              if (rows.isEmpty) const CampusPanel(child: Text('这里还没有考试记录')),
              for (final row in rows) ...[
                const SizedBox(height: 12),
                ItemCard(
                  item: Map<String, dynamic>.from(row['exam']),
                  onTap: () async {
                    await context.push('/items/${row['exam']['id']}');
                    await reload();
                  },
                ),
                CampusPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        (row['reviews'] as List).isEmpty
                            ? '复习目标尚未设置'
                            : '复习剩余：${row['review_remaining_minutes'] == null ? '耗时待确认' : minutesLabel(row['review_remaining_minutes'])}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if ((row['reviews'] as List).isNotEmpty)
                        Text(
                          fresh
                              ? '已安排复习 ${minutesLabel(row['review_planned_minutes'])} · 还需安排 ${row['review_unplanned_minutes'] == null ? '待确认' : minutesLabel(row['review_unplanned_minutes'])}'
                              : '复习安排待更新',
                        ),
                      if ((row['completed_review_count'] ?? 0) > 0)
                        Text('已确认完成 ${row['completed_review_count']} 项复习任务'),
                      if ((row['reviews'] as List).isEmpty)
                        const Text('尚未建立复习任务；复习提醒不会自动生成任务'),
                      for (final issue in row['issues'] ?? [])
                        SoftNotice('$issue', warning: true),
                      for (final task in widget.controller.rows(row['reviews']))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(task['title']),
                          subtitle: Text(
                            '${itemTimeLabel(task)} · ${task['lifecycle'] == 'completed'
                                ? '已完成'
                                : task['lifecycle'] == 'cancelled'
                                ? '已取消'
                                : '待完成'}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await context.push('/items/${task['id']}');
                            await reload();
                          },
                        ),
                      if (row['exam']['lifecycle'] == 'active')
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () async {
                                final active = widget.controller
                                    .rows(row['reviews'])
                                    .where((r) => r['lifecycle'] == 'active')
                                    .firstOrNull;
                                if (active != null) {
                                  await context.push('/items/${active['id']}');
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
                                        .any((r) => r['lifecycle'] == 'active')
                                    ? '更新复习目标与进度'
                                    : '设置 / 关联复习任务',
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
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
                              child: const Text('考试改期 / 确认正式安排'),
                            ),
                          ],
                        ),
                      TextButton(
                        onPressed: () async {
                          await context.push('/items/${row['exam']['id']}');
                          await reload();
                        },
                        child: const Text('管理提醒、原文与历史'),
                      ),
                    ],
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
        children: [
          Text(
            widget.exam['title'],
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(itemTimeLabel(widget.exam)),
          const SoftNotice(
            '复习耗时由你估计。这里保存任务，不会直接安排时间，也不会把已安排视为完成。已有复习请从任务详情更新进度。',
          ),
          SwitchListTile(
            title: const Text('关联已有个人任务'),
            value: link,
            onChanged: busy ? null : (v) => setState(() => link = v),
          ),
          if (link)
            DropdownButtonFormField<String>(
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
            )
          else ...[
            Wrap(
              spacing: 8,
              children: [
                for (final p in {
                  '轻量 · 2h': 120,
                  '标准 · 4h': 240,
                  '充分 · 8h': 480,
                }.entries)
                  ActionChip(
                    label: Text(p.key),
                    onPressed: () =>
                        setState(() => minutes.text = '${p.value}'),
                  ),
              ],
            ),
            TextField(
              key: const Key('review-minutes'),
              controller: minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '预计还需复习多久（分钟）'),
            ),
            DropdownButtonFormField<String>(
              initialValue: mode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '复习截止依据'),
              items: [
                const DropdownMenuItem(value: 'unknown', child: Text('截止待确认')),
                if (examKnown)
                  const DropdownMenuItem(
                    value: 'exam',
                    child: Text('确认以考试开始时刻为截止'),
                  ),
                const DropdownMenuItem(
                  value: 'custom',
                  child: Text('指定自己的复习截止'),
                ),
              ],
              onChanged: busy ? null : (v) => setState(() => mode = v!),
            ),
            if (mode == 'custom')
              TextButton(
                onPressed: () async {
                  final d = await pickSchoolDateTime(
                    context,
                    initial: deadline,
                  );
                  if (d != null && mounted) setState(() => deadline = d);
                },
                child: Text(
                  deadline == null
                      ? '选择复习截止'
                      : displayInstant(deadline!.toIso8601String()),
                ),
              ),
            CheckboxListTile(
              title: const Text('我确认从现在起即可安排复习'),
              subtitle: const Text('暂不勾选也能保存，生成计划前再确认开始时间'),
              value: startNow,
              onChanged: busy ? null : (v) => setState(() => startNow = v!),
            ),
          ],
          if (error != null) SoftNotice(error!, warning: true),
          if (busy) const LinearProgressIndicator(),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(link ? '关联这项任务，保留原进度和截止时间' : '确认创建复习任务'),
          ),
        ],
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
  late DateTime? start = DateTime.tryParse(
        widget.exam['time']['at'] ?? widget.exam['time']['date'] ?? '',
      ),
      end = DateTime.tryParse(
        widget.exam['time']['end_at'] ?? widget.exam['time']['end_date'] ?? '',
      );
  bool align = false, busy = false;
  late bool reserve = widget.exam['reserve_time'] ?? true;
  String? error;
  late final generation = widget.controller.api.generation;
  @override
  void dispose() {
    location.dispose();
    week.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> pick(bool ending) async {
    DateTime? v;
    if (precision == 'exact') {
      v = await pickSchoolDateTime(context, initial: ending ? end : start);
    } else {
      v = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
    }
    if (v != null && mounted) {
      setState(() {
        if (ending) {
          end = v;
        } else {
          start = v;
        }
      });
    }
  }

  String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Future<void> preview() async {
    if (generation != widget.controller.api.generation ||
        widget.exam['semester_id'] != widget.controller.semesterId) {
      setState(() => error = '账号或学期已切换，请返回');
      return;
    }
    if (reason.text.trim().isEmpty) {
      setState(() => error = '请填写考试变更通知或核对依据');
      return;
    }
    if (['date', 'range', 'exact'].contains(precision) && start == null) {
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
        'at': start!.toUtc().toIso8601String(),
        'end_at': end?.toUtc().toIso8601String(),
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
      'reserve_time': certainty == 'formal' || reserve,
      'reason': reason.text.trim(),
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
        Text(
          widget.exam['title'],
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text('原：${itemTimeLabel(widget.exam)}'),
        TextField(
          controller: reason,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: '变更通知 / 核对依据'),
        ),
        DropdownButtonFormField<String>(
          initialValue: precision,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '新通知提供的时间'),
          items:
              {
                    'exact': '具体时刻',
                    'date': '仅日期',
                    'week': '学期周次',
                    'range': '日期范围',
                    'unknown': '待通知',
                  }.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
          onChanged: busy
              ? null
              : (v) => setState(() {
                  precision = v!;
                  start = null;
                  end = null;
                  align = false;
                }),
        ),
        if (['date', 'range', 'exact'].contains(precision))
          TextButton(
            onPressed: () => pick(false),
            child: Text(
              start == null
                  ? '选择新开始'
                  : precision == 'exact'
                  ? displayInstant(start!.toIso8601String())
                  : day(start!),
            ),
          ),
        if (precision == 'exact' || precision == 'range')
          TextButton(
            onPressed: () => pick(true),
            child: Text(
              end == null
                  ? '选择新结束（具体考试结束可待确认）'
                  : precision == 'exact'
                  ? displayInstant(end!.toIso8601String())
                  : day(end!),
            ),
          ),
        if (precision == 'exact' && end != null)
          TextButton(
            onPressed: () => setState(() => end = null),
            child: const Text('结束时刻待确认'),
          ),
        if (precision == 'week')
          TextField(
            controller: week,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '第几周'),
          ),
        DropdownButtonFormField<String>(
          initialValue: certainty,
          decoration: const InputDecoration(labelText: '时间是否确定'),
          items: {'formal': '正式', 'tentative': '暂定', 'unknown': '待确认'}.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: busy
              ? null
              : (v) => setState(() {
                  certainty = v!;
                  if (certainty != 'formal') align = false;
                }),
        ),
        TextField(
          controller: location,
          decoration: const InputDecoration(labelText: '新地点'),
        ),
        if (certainty != 'formal')
          SwitchListTile(
            title: const Text('为暂定考试预留时间'),
            value: reserve,
            onChanged: (v) => setState(() => reserve = v),
          ),
        if (certainty == 'formal' && precision == 'exact')
          CheckboxListTile(
            title: const Text('将相关复习任务的截止时间一起改到考试开始前'),
            subtitle: const Text('只更新复习截止时间，保留原进度和计划安排'),
            value: align,
            onChanged: (v) => setState(() => align = v!),
          ),
        if (error != null) SoftNotice(error!, warning: true),
        if (busy) const LinearProgressIndicator(),
        FilledButton(
          onPressed: busy ? null : preview,
          child: const Text('预览考试、提醒与复习影响'),
        ),
      ],
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
      if (mounted) setState(() => applied = true);
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
    final conflict = (p['fixed_conflict_count'] ?? 0) > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('考试改期确认')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            p['before']['title'],
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SectionHeading('考试变化'),
          if (p['before']['title'] != p['after']['title'])
            Text('标题：${p['before']['title']} → ${p['after']['title']}'),
          if (p['before']['course_id'] != p['after']['course_id'])
            Text(
              '关联课程：${p['before']['course_title'] ?? '未关联'} → ${p['after']['course_title'] ?? '未关联'}',
            ),
          if (p['before']['notes'] != p['after']['notes'])
            Text('新备注：${p['after']['notes']}'),
          Text('原：${itemTimeLabel(Map<String, dynamic>.from(p['before']))}'),
          Text('新：${itemTimeLabel(Map<String, dynamic>.from(p['after']))}'),
          Text('新地点：${p['after']['location']}'),
          Text('依据：${widget.request['reason']}'),
          const SectionHeading('复习截止'),
          if ((p['reviews'] as List).isEmpty) const Text('没有关联的未完成复习任务'),
          for (final r in p['reviews'])
            Text(
              '${r['title']}\n${r['will_align'] == true ? '将同步截止' : '保持原截止，需自行核对'}：${itemTimeLabel({'kind': 'task', 'time': r['after_time']})}',
            ),
          const SectionHeading('更新后的提醒'),
          if ((p['reminders_after'] as List).isEmpty) const Text('未设置考试提醒'),
          for (final r in p['reminders_after'])
            Text(
              '${reminderLabel(Map<String, dynamic>.from(r))} · ${displayInstant(r['trigger_at'])} · ${reminderState(r['schedule_state'])}',
            ),
          const SectionHeading('个人计划影响'),
          for (final r in p['review_reminders_after'] ?? [])
            Text(
              '复习提醒 ${r['title']}：${displayInstant(r['trigger_at'])} · ${reminderState(r['schedule_state'])}',
            ),
          for (final b in p['affected_blocks'])
            Text(
              '${b['title']} · ${displayInstant(b['start_at'])}${b['locked'] == true ? ' · 已锁定' : ''}',
            ),
          if ((p['affected_blocks'] as List).isEmpty)
            const Text('现有个人计划没有与新考试时间冲突'),
          for (final r in p['risk_changes'])
            Text(
              '${r['title']}：余量 ${r['before_slack'] ?? '待确认'} → ${r['after_slack'] ?? '待确认'} 分钟',
            ),
          for (final r in p['fixed_conflicts'])
            SoftNotice(
              '${(r['titles'] as List).join(' 与 ')}\n${displayInstant(r['start_at'])} — ${displayInstant(r['end_at'])}',
              warning: true,
            ),
          if (conflict && !applied)
            CheckboxListTile(
              title: const Text('我已核实新考试时间，确认保存并保留冲突提示'),
              value: confirmConflict,
              onChanged: busy
                  ? null
                  : (v) => setState(() => confirmConflict = v!),
            ),
          const SoftNotice('确认后保存考试和所选复习任务的新时间。已有计划暂不移动，你可以接着查看并调整。'),
          if (stale && !applied)
            const SoftNotice('账号、学期或安排已变化，请重新预览', warning: true),
          if (error != null) SoftNotice(error!, warning: true),
          if (busy) const LinearProgressIndicator(),
          if (!applied)
            FilledButton(
              onPressed: busy || stale || (conflict && !confirmConflict)
                  ? null
                  : apply,
              child: const Text('确认考试新安排'),
            ),
          if (applied) ...[
            const SoftNotice('考试新安排已保存'),
            OutlinedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlanListPage(controller: widget.controller),
                ),
              ),
              child: const Text('查看个人计划并按需重排'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('完成核对'),
            ),
          ],
        ],
      ),
    );
  }
}
