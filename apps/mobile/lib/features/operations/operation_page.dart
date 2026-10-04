import '../../ui/app_loading.dart';
import '../../ui/app_controls.dart';
import '../../ui/campus_theme.dart';
import '../../ui/app_picker_field.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/record_actions.dart';
import '../../core/api.dart' show userError;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../ui/campus_widgets.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import '../items/task_surfaces.dart';
import '../items/reminder_editor.dart';
import '../planning/date_time_picker.dart';
import '../planning/plan_change_confirmation.dart';
import '../planning/proposal_page.dart';
import '../planning/risk_widgets.dart';
import '../media/drafts.dart';

String operationValue(dynamic field, dynamic value) {
  if (value == null) return '移除此项设置';
  if (field == 'splittable') return value == true ? '可以分次完成' : '需要一次完成';
  if (field == 'remaining_minutes') return minutesLabel(value);
  return '$value';
}

class OperationPage extends StatefulWidget {
  final ItemsController controller;
  final String initialText;
  final String? referenceAt, contextItemId, sourceId;
  final int? sourceVersion;
  const OperationPage({
    super.key,
    required this.controller,
    this.initialText = '',
    this.referenceAt,
    this.contextItemId,
    this.sourceId,
    this.sourceVersion,
  });
  @override
  State<OperationPage> createState() => _OperationPageState();
}

class _OperationPageState extends State<OperationPage> {
  late final text = TextEditingController(text: widget.initialText);
  final title = TextEditingController(), effort = TextEditingController();
  final targets = <String, TextEditingController>{}, selected = <String>{};
  late final sid = widget.controller.semesterId,
      owner = widget.controller.owner;
  late final generation = widget.controller.api.generation;
  late final drafts = CaptureDrafts(
    widget.controller.cache,
    owner!,
    () => same,
  );
  late String reference =
      widget.referenceAt ?? DateTime.now().toUtc().toIso8601String();
  Map<String, dynamic>? operation, target, reminderValue;
  late String? sourceId = widget.sourceId, contextId = widget.contextItemId;
  late int? sourceVersion = widget.sourceVersion;
  List<Map<String, dynamic>> history = [];
  String? targetId, ruleId, error;
  String split = 'keep', reminderAction = 'edit', planMode = 'schedule';
  int days = 7, chunk = 45;
  bool busy = false,
      editing = true,
      direct = false,
      customWindow = false,
      useDefault = false,
      finished = false;
  DateTime? start, end;
  Timer? clock, saveTimer;
  bool get same =>
      owner == widget.controller.owner &&
      sid == widget.controller.semesterId &&
      generation == widget.controller.api.generation;
  String get intent => operation?['suggestion']?['intent'] ?? '';
  String get draftKey => widget.contextItemId == null
      ? 'operation:$sid'
      : 'operation:$sid:${widget.contextItemId}';
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
    clock = Timer.periodic(const Duration(seconds: 10), (_) => changed());
    init();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> init() async {
    if (widget.initialText.isEmpty) {
      final d = await drafts.read(draftKey);
      if (mounted && same && d != null) {
        setState(() {
          text.text = d['text'] ?? '';
          reference = d['reference_at'] ?? reference;
          sourceId = d['source_id'];
          sourceVersion = d['source_version'];
          contextId = d['context_item_id'] ?? contextId;
        });
      }
    }
    await recent();
    if (widget.initialText.isNotEmpty && mounted && same) await parse();
  }

  Future<void> saveDraft() => drafts.save(draftKey, {
    'text': text.text,
    'reference_at': reference,
    'source_id': sourceId,
    'source_version': sourceVersion,
    'context_item_id': contextId,
  });
  @override
  void dispose() {
    clock?.cancel();
    saveTimer?.cancel();
    if (!finished) saveDraft().catchError((_) {});
    widget.controller.removeListener(changed);
    text.dispose();
    title.dispose();
    effort.dispose();
    for (final c in targets.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (!same) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted && same) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> recent() async {
    try {
      final rows = await widget.controller.api.request(
        'GET',
        '/semesters/$sid/operations',
      );
      if (mounted && same) {
        setState(() => history = widget.controller.rows(rows));
      }
    } catch (_) {}
  }

  Future<void> setOperation(Map<String, dynamic> p) async {
    if (!mounted || !same) return;
    final suggestion = Map<String, dynamic>.from(p['suggestion']),
        selection = Map<String, dynamic>.from(p['selection'] ?? {});
    final patch = Map<String, dynamic>.from(
      selection['task_patch'] ?? suggestion['task_patch'] ?? {},
    );
    for (final c in targets.values) {
      c.dispose();
    }
    targets.clear();
    selected.clear();
    setState(() {
      operation = p;
      text.text = p['source_text'];
      reference = p['reference_at'];
      sourceId = p['source']?['id'];
      sourceVersion = p['source']?['version'];
      editing = !['ready', 'applied', 'rejected'].contains(p['phase']);
      targetId = selection['target_item_id'] ?? p['suggested_target_id'];
      target = p['preview']?['before'] == null
          ? null
          : Map<String, dynamic>.from(p['preview']['before']);
      title.text = patch['title'] ?? '';
      effort.text = patch['remaining_minutes']?.toString() ?? '';
      split = patch['splittable'] == null
          ? 'keep'
          : patch['splittable'] == true
          ? 'yes'
          : 'no';
      reminderAction =
          selection['reminder_action'] ??
          suggestion['reminder_action'] ??
          'edit';
      ruleId = selection['reminder_id'];
      reminderValue = p['preview']?['reminder_payload'] == null
          ? null
          : Map<String, dynamic>.from(p['preview']['reminder_payload']);
      planMode =
          selection['plan_mode'] ?? suggestion['plan_mode'] ?? 'schedule';
      days = selection['days'] ?? 7;
      chunk = selection['chunk_minutes'] ?? 45;
      direct = selection['confirm_direct_request'] == true;
      useDefault = selection['use_default_window'] == true;
      start = DateTime.tryParse(
        selection['window_start_at'] ?? suggestion['window_start_at'] ?? '',
      );
      end = DateTime.tryParse(
        selection['window_end_at'] ?? suggestion['window_end_at'] ?? '',
      );
      customWindow = start != null || suggestion['needs_window'] == true;
      for (final t in widget.controller.rows(selection['tasks'])) {
        selected.add(t['item_id']);
        targets[t['item_id']] = TextEditingController(
          text: t['target_minutes']?.toString() ?? '',
        );
      }
    });
    if (targetId != null && target == null) await pickTarget(targetId!);
  }

  Future<void> parse() => run(() async {
    if (text.text.trim().isEmpty) throw Exception('先写下你希望修改什么');
    await saveDraft();
    Map<String, dynamic>? source;
    if (sourceId != null) {
      source = Map<String, dynamic>.from(
        await widget.controller.api.request('GET', '/sources/$sourceId'),
      );
    }
    final p = await widget.controller.changeRequest(
      'POST',
      '/operations/parse',
      data: {
        'semester_id': sid,
        'text': text.text.trim(),
        'reference_at': reference,
        if (contextId != null) 'context_item_id': contextId,
        if (source != null) ...{
          'source_id': source['id'],
          'source_version': sourceVersion ?? source['version'],
        },
      },
    );
    await setOperation(p);
    await recent();
  });
  Future<void> pickTarget(String id) async {
    setState(() {
      targetId = id;
      ruleId = null;
      reminderValue = null;
      target = null;
    });
    final r = await widget.controller.get(id);
    if (!mounted || !same || targetId != id) return;
    setState(() {
      target = r;
      final rules = widget.controller.rows(r['reminders']);
      if (rules.length == 1) ruleId = rules.first['id'];
    });
  }

  List<Map<String, dynamic>> get choices {
    final map = {
      for (final i in widget.controller.rows(operation?['choices'])) i['id']: i,
    };
    for (final i in widget.controller.items) {
      if (i['lifecycle'] == 'active' &&
          (intent == 'update_reminder' || i['kind'] != 'exam')) {
        map[i['id']] = i;
      }
    }
    return map.values.toList();
  }

  Future<void> reminderSettings() async {
    if (target == null) throw Exception('请先选择事项');
    final rules = widget.controller.rows(target!['reminders']);
    final old = rules.where((r) => r['id'] == ruleId).firstOrNull;
    final suggested = Map<String, dynamic>.from(
      operation!['suggestion']['reminder_patch'] ?? {},
    );
    final initial = <String, dynamic>{...?old, ...?reminderValue};
    if (reminderValue == null) {
      for (final e in suggested.entries) {
        if (e.value != null) initial[e.key] = e.value;
      }
      if (suggested['mode'] == 'absolute' && suggested['trigger_at'] == null) {
        initial['trigger_at'] = null;
      }
    }
    final value = await editReminder(
      context,
      kind: target!['kind'],
      initial: initial,
    );
    if (value != null && mounted) {
      value.remove('expected_version');
      setState(() => reminderValue = value);
    }
  }

  Future<void> chooseWindow() async {
    if (busy || !same || !customWindow || operation == null) return;
    final operationId = operation!['id'], version = operation!['version'];
    final previousStart = start, previousEnd = end;
    final value = await pickSchoolDateTimeRange(
      context,
      initialStart: start,
      initialEnd: end,
      title: '安排时段',
    );
    if (value == null ||
        !mounted ||
        !same ||
        busy ||
        !customWindow ||
        operation?['id'] != operationId ||
        operation?['version'] != version ||
        start != previousStart ||
        end != previousEnd) {
      return;
    }
    setState(() {
      start = value.start;
      end = value.end;
      error = null;
    });
  }

  String get windowLabel => start != null && end != null
      ? displayInterval(start!.toIso8601String(), end!.toIso8601String())
      : start != null
      ? '${displayInstant(start!.toIso8601String())} 起'
      : end != null
      ? '至 ${displayInstant(end!.toIso8601String())}'
      : '选择起止时间';

  Future<void> resolve() => run(() async {
    final p = operation!;
    final data = <String, dynamic>{
      'expected_version': p['version'],
      'confirm_direct_request': direct,
    };
    if (intent == 'update_task') {
      final minutes = effort.text.trim().isEmpty
          ? null
          : int.tryParse(effort.text.trim());
      if (effort.text.trim().isNotEmpty && (minutes == null || minutes < 1)) {
        throw Exception('请输入大于0的剩余分钟数；已经做完的任务，请到详情页标记完成。');
      }
      data.addAll({
        'target_item_id': targetId,
        'task_patch': {
          if (title.text.trim().isNotEmpty) 'title': title.text.trim(),
          'remaining_minutes': ?minutes,
          if (split != 'keep') 'splittable': split == 'yes',
        },
      });
    } else if (intent == 'update_reminder') {
      data.addAll({
        'target_item_id': targetId,
        'reminder_action': reminderAction,
        'reminder_id': ruleId,
        if (reminderValue != null) ...{
          'reminder': reminderValue,
          'expected_item_version': target?['version'],
          'expected_reminder_version': widget.controller
              .rows(target?['reminders'])
              .where((r) => r['id'] == ruleId)
              .firstOrNull?['version'],
        },
      });
    } else if (intent == 'request_plan') {
      final rows = <Map<String, dynamic>>[];
      for (final id in selected) {
        final raw = targets[id]?.text.trim() ?? '';
        final minutes = raw.isEmpty ? null : int.tryParse(raw);
        if (raw.isNotEmpty && (minutes == null || minutes < 1)) {
          throw Exception('请输入大于0的分钟数');
        }
        rows.add({
          'item_id': id,
          'target_minutes': planMode == 'schedule' ? minutes : null,
        });
      }
      if (customWindow && (start == null || end == null)) {
        throw Exception('请选择开始和结束时间，或使用已设置的学习时间');
      }
      if (customWindow && !end!.isAfter(start!)) {
        throw Exception('结束时间需晚于开始时间');
      }
      data.addAll({
        'plan_mode': planMode,
        'tasks': rows,
        'days': days,
        'chunk_minutes': chunk,
        'use_default_window': useDefault,
        if (customWindow) ...{
          'window_start_at': start!.toUtc().toIso8601String(),
          'window_end_at': end!.toUtc().toIso8601String(),
        },
      });
    }
    final updated = await widget.controller.changeRequest(
      'POST',
      '/operations/${p['id']}/resolve',
      data: data,
    );
    await setOperation(updated);
  });
  Future<void> generate(Map<String, dynamic> receipt) async {
    if (!same) return;
    final proposal = await widget.controller.generateSchedule(
      Map<String, dynamic>.from(receipt['planning_request']),
      idempotencyKey:
          'operation-plan-${receipt['operation_id']}-${receipt['operation_version']}',
    );
    if (mounted && same) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ProposalPage(controller: widget.controller, proposal: proposal),
        ),
      );
    }
  }

  Future<void> apply() async {
    final p = operation!,
        preview = Map<String, dynamic>.from(operation!['preview']);
    Map<String, dynamic> decisions = {};
    final blocks = widget.controller.rows(preview['affected_blocks']);
    if (blocks.isNotEmpty) {
      final selection = await confirmPlanChange(
        context,
        title: '核对修改与已有计划',
        message: '只取消勾选的计划，其他安排保留。',
        confirmLabel: '确认修改',
        blocks: blocks,
        remaining: preview['task_patch']?['remaining_minutes'],
        maxKeptBlocks: preview['task_patch']?['splittable'] == false ? 1 : null,
      );
      if (selection == null || !mounted || !same) return;
      decisions = selection;
    }
    await run(() async {
      final receipt = await widget.controller.changeRequest(
        'POST',
        '/operations/${p['id']}/apply',
        data: {'expected_version': p['version'], ...decisions},
        apply: true,
      );
      if (!mounted || !same) return;
      setState(
        () => operation = {
          ...p,
          'phase': 'applied',
          'version': receipt['operation_version'],
          'receipt': receipt,
        },
      );
      finished = true;
      saveTimer?.cancel();
      await drafts.save(draftKey, null);
      if (receipt['planning_request'] != null) await generate(receipt);
      await recent();
    });
  }

  Future<void> reject() => run(() async {
    final p = operation!;
    final r = await widget.controller.changeRequest(
      'POST',
      '/operations/${p['id']}/reject',
      data: {'expected_version': p['version']},
    );
    if (mounted && same) setState(() => operation = r);
    await recent();
  });
  bool get stale {
    final p = operation;
    if (p == null) return false;
    if (!same || p['phase'] == 'stale') return true;
    if (intent != 'update_reminder') {
      return widget.controller.revisionIsStale(sid, p['base_revision']);
    }
    final before = p['preview']?['before'];
    if (before == null) return false;
    final current = widget.controller.items
        .where((i) => i['id'] == before['id'])
        .firstOrNull;
    if (current != null &&
        (current['version'] as int) > (before['version'] as int)) {
      return true;
    }
    final r = p['preview']?['reminder_after'];
    return r?['enabled'] == true &&
        r?['trigger_at'] != null &&
        !DateTime.parse(r['trigger_at']).isAfter(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final p = operation;
    final preview = p?['preview'];
    final applied = p?['phase'] == 'applied';
    final rejected = p?['phase'] == 'rejected';
    final compactRequest =
        p != null && preview != null && !editing && !rejected;
    return Scaffold(
      appBar: AppBar(title: const Text('智能修改')),
      body: !same
          ? const Center(child: Text('账号或学期已切换，请返回'))
          : AppLoadingOverlay(
              loading: busy,
              label: '正在整理',
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (!compactRequest) ...[
                    EditorSection(
                      title: '修改要求',
                      icon: Icons.edit_note_rounded,
                      children: [
                        AppField(
                          key: const Key('operation-text'),
                          controller: text,
                          minLines: 2,
                          maxLines: 5,
                          maxLength: 10000,
                          enabled: !busy,
                          onChanged: (_) {
                            setState(() {
                              operation = null;
                              finished = false;
                            });
                            saveTimer?.cancel();
                            saveTimer = Timer(
                              const Duration(milliseconds: 350),
                              () => saveDraft(),
                            );
                          },
                          decoration: const InputDecoration(
                            labelText: '想怎么调整',
                            hintText: 'Java报告还需要两小时；提醒改到周四晚上八点',
                            counterText: '',
                          ),
                        ),
                      ],
                    ),
                    AppDisclosure(
                      title: const Text('原通知时间'),
                      children: [
                        AppTextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  final date = await pickSchoolDateTime(
                                    context,
                                    initial: DateTime.parse(reference),
                                  );
                                  if (date != null && mounted) {
                                    setState(() {
                                      reference = date
                                          .toUtc()
                                          .toIso8601String();
                                      operation = null;
                                    });
                                    await saveDraft();
                                  }
                                },
                          child: Text('消息时间：${displayInstant(reference)}'),
                        ),
                      ],
                    ),
                    AppButton(
                      onPressed: busy ? null : parse,
                      child: const Text('让AI整理修改'),
                    ),
                  ] else ...[
                    if (stale)
                      AppTextButton(
                        onPressed: busy ? null : parse,
                        child: const Text('重新整理修改'),
                      ),
                  ],
                  if (sourceId != null)
                    AppTextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              sourceId = null;
                              sourceVersion = null;
                              operation = null;
                              direct = false;
                            }),
                      child: const Text('不引用原图或录音，改用当前文字'),
                    ),
                  if (error != null) SoftNotice(error!, warning: true),
                  if (p != null) ...[
                    if (!editing || applied)
                      DocumentPanel(title: '修改要求', text: p['source_text']),
                    for (final q in p['suggestion']['questions'] ?? [])
                      SoftNotice('$q'),
                    if (p['clarification'] != null && editing)
                      SoftNotice(p['clarification'], warning: true),
                    if (stale && !applied)
                      const SoftNotice('事项或提醒已有更新，请重新查看修改内容。', warning: true),
                    if (applied)
                      SoftNotice(
                        intent == 'request_plan'
                            ? '已确认规划范围。请查看生成的方案，满意后再保存到日程。'
                            : '修改已保存',
                      ),
                    if (rejected) const SoftNotice('已放弃这次修改，原来的安排保留。'),
                    if (editing &&
                        !applied &&
                        !rejected &&
                        [
                          'update_task',
                          'update_reminder',
                          'request_plan',
                        ].contains(intent))
                      ...editor(),
                    if (!editing && preview != null)
                      ...previewWidgets(Map<String, dynamic>.from(preview)),
                    if (p['phase'] == 'ready' && !editing && !applied && !stale)
                      AppButton(
                        onPressed: busy ? null : apply,
                        child: Text(
                          intent == 'request_plan' ? '按这个范围生成计划' : '确认保存修改',
                        ),
                      ),
                    if (!applied && !rejected) ...[
                      AppTextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => editing = true),
                        child: const Text('调整修改内容'),
                      ),
                      AppTextButton(
                        onPressed: busy ? null : reject,
                        child: const Text('放弃这次修改'),
                      ),
                    ],
                    if (applied && p['receipt']?['planning_request'] != null)
                      AppOutlineButton(
                        onPressed: busy
                            ? null
                            : () => run(
                                () => generate(
                                  Map<String, dynamic>.from(p['receipt']),
                                ),
                              ),
                        child: const Text('继续查看计划方案'),
                      ),
                  ],
                  if (history.isNotEmpty)
                    AppDisclosure(
                      title: const Text('修改记录'),
                      children: [
                        for (final h in history)
                          AppTile(
                            title: Text(
                              h['source_text'],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              {
                                    'ready': '待确认',
                                    'needs_clarification': '待补充',
                                    'stale': '需重新核对',
                                    'applied': '已确认',
                                    'rejected': '已放弃',
                                  }[h['phase']] ??
                                  '',
                            ),
                            onTap: busy
                                ? null
                                : () => run(() async {
                                    final r = await widget.controller
                                        .changeRequest(
                                          'GET',
                                          '/operations/${h['id']}',
                                        );
                                    contextId = null;
                                    await setOperation(r);
                                  }),
                          ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }

  List<Widget> editor() {
    final result = <Widget>[];
    if (operation?['source']?['kind'] == 'image') {
      result.add(
        AppCheckRow(
          title: const Text('我确认要按图片中的内容修改我的安排'),
          value: direct,
          onChanged: busy ? null : (v) => setState(() => direct = v!),
        ),
      );
    }
    if (intent != 'request_plan') {
      result.add(
        AppPickerField<String>(
          key: ValueKey('${operation!['id']}/$targetId'),
          initialValue: targetId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '要修改哪件事'),
          items: choices
              .map(
                (i) => DropdownMenuItem<String>(
                  value: i['id'],
                  child: Text(
                    '${i['title']} · ${i['course_title'] ?? ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: busy ? null : (v) => run(() => pickTarget(v!)),
        ),
      );
      if (target != null) result.add(Text(itemTimeLabel(target!)));
      if (targetId != null) {
        result.add(
          AppTextButton(
            onPressed: busy ? null : () => run(() => pickTarget(targetId!)),
            child: const Text('查看事项和提醒的最新内容'),
          ),
        );
      }
    }
    if (intent == 'update_task') {
      result.addAll([
        AppField(
          controller: title,
          decoration: const InputDecoration(labelText: '新标题（留空不改）'),
        ),
        WorkMinuteField(
          controller: effort,
          enabled: !busy,
          label: '还需时间',
          helper: '留空不改',
        ),
        AppPickerField<String>(
          initialValue: split,
          key: ValueKey('split:$split'),
          decoration: const InputDecoration(labelText: '是否分次完成'),
          items: {'keep': '保持原设置', 'yes': '可以分次完成', 'no': '需要一次完成'}.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => setState(() => split = v!),
        ),
      ]);
    }
    if (intent == 'update_reminder') {
      result.addAll([
        AppPickerField<String>(
          initialValue: reminderAction,
          key: ValueKey('action:$reminderAction'),
          decoration: const InputDecoration(labelText: '提醒操作'),
          items: {'add': '新增一条', 'edit': '修改一条', 'disable': '停用一条'}.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => setState(() {
            reminderAction = v!;
            reminderValue = null;
          }),
        ),
        if (reminderAction != 'add')
          AppPickerField<String>(
            initialValue: ruleId,
            key: ValueKey('rule:$targetId:$ruleId'),
            isExpanded: true,
            decoration: const InputDecoration(labelText: '要修改哪条提醒'),
            items: widget.controller
                .rows(target?['reminders'])
                .map(
                  (r) => DropdownMenuItem<String>(
                    value: r['id'],
                    child: Text(
                      '${reminderLabel(r)} · ${displayInstant(r['trigger_at'])}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() {
              ruleId = v;
              reminderValue = null;
            }),
          ),
        if (reminderAction != 'disable')
          AppTextButton(
            onPressed: busy || target == null
                ? null
                : () => run(reminderSettings),
            child: Text(reminderValue == null ? '设置提醒时间' : '提醒已设置，点击修改'),
          ),
      ]);
    }
    if (intent == 'request_plan') {
      result.addAll([
        const SoftNotice('先选择要安排的任务，确认每项还需要多久。已经做完一部分？可以先更新任务进度。'),
        AppPickerField<String>(
          initialValue: planMode,
          key: ValueKey('plan:$planMode'),
          items: const [
            DropdownMenuItem(value: 'schedule', child: Text('安排还没排好的任务')),
            DropdownMenuItem(value: 'replan', child: Text('调整所选任务的已有安排')),
          ],
          onChanged: (v) => setState(() => planMode = v!),
        ),
      ]);
      for (final task in choices.where((i) => i['kind'] != 'exam')) {
        targets.putIfAbsent(
          task['id'],
          () => TextEditingController(
            text: operation!['suggestion']['target_minutes']?.toString() ?? '',
          ),
        );
        result.add(
          AppCheckRow(
            title: Text(task['title']),
            subtitle: Text(
              '剩余 ${task['remaining_minutes'] == null ? '待确认' : minutesLabel(task['remaining_minutes'])}',
            ),
            value: selected.contains(task['id']),
            onChanged: (v) => setState(() {
              if (v == true) {
                selected.add(task['id']);
              } else {
                selected.remove(task['id']);
              }
            }),
          ),
        );
        result.add(
          AppTextButton(
            onPressed: () async {
              await context.push('/items/${task['id']}');
              await widget.controller.refresh();
            },
            child: const Text('查看进度和开始时间'),
          ),
        );
        if (selected.contains(task['id']) && planMode == 'schedule') {
          result.add(
            WorkMinuteField(
              controller: targets[task['id']]!,
              enabled: !busy,
              label: '本次安排',
              helper: '含已有安排。该时段内到期的任务可留空。',
            ),
          );
        }
      }
      result.addAll([
        if (planMode == 'schedule')
          AppPickerField<int>(
            initialValue: days,
            key: ValueKey('days:$days'),
            items: [
              for (final d in [7, 14, 28])
                DropdownMenuItem(value: d, child: Text('默认未来$d天')),
            ],
            onChanged: (v) => setState(() => days = v!),
          ),
        AppSwitchRow(
          title: const Text('指定安排的起止时间'),
          value: customWindow,
          onChanged: (v) => setState(() => customWindow = v),
        ),
        if (customWindow)
          RecordActionTile(
            key: const ValueKey('operation-plan-range'),
            onTap: busy ? null : chooseWindow,
            icon: Icons.date_range_outlined,
            title: windowLabel,
          ),
        if (!customWindow && operation!['suggestion']['needs_window'] == true)
          AppCheckRow(
            title: const Text('改用上方天数和已设置的学习时间'),
            value: useDefault,
            onChanged: (v) => setState(() => useDefault = v!),
          ),
      ]);
    }
    result.add(
      AppButton(onPressed: busy ? null : resolve, child: const Text('查看修改前后')),
    );
    return result;
  }

  List<Widget> previewWidgets(Map<String, dynamic> preview) {
    if (intent == 'request_plan') {
      final request = preview['planning_request'];
      return [
        const SectionHeading('确认安排范围'),
        for (final item in widget.controller.rows(preview['tasks']))
          Text(
            '${item['title']} · 剩余${minutesLabel(item['remaining_minutes'])}',
          ),
        SoftNotice(
          request['mode'] == 'replan'
              ? '只调整所选任务的已有安排，其他任务和锁定计划不移动。'
              : request['window_start_at'] != null
              ? '限定 ${displayInstant(request['window_start_at'])} 至 ${displayInstant(request['window_end_at'])}'
              : '在未来${request['days']}天的可学习时间内生成',
        ),
        const Text('下一步先生成方案，你确认后才会保存到日程。'),
      ];
    }
    final before = Map<String, dynamic>.from(preview['before']);
    if (intent == 'update_task') {
      return [
        SectionHeading(before['title']),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CampusColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in (preview['task_patch'] as Map).entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: before[e.key] == null
                      ? TaskFactStrip(
                          label:
                              '${{'title': '标题', 'remaining_minutes': '还需时间', 'splittable': '完成方式'}[e.key]}',
                          value: operationValue(e.key, e.value),
                          icon: Icons.add_rounded,
                        )
                      : TaskChangeFacts(
                          beforeLabel:
                              '原${{'title': '标题', 'remaining_minutes': '还需时间', 'splittable': '完成方式'}[e.key]}',
                          afterLabel: '修改后',
                          before: operationValue(e.key, before[e.key]),
                          after: operationValue(e.key, e.value),
                        ),
                ),
            ],
          ),
        ),
        if (widget.controller.rows(preview['affected_blocks']).isNotEmpty)
          Text(
            '涉及 ${widget.controller.rows(preview['affected_blocks']).length}段后续安排',
          ),
      ];
    }
    final old = preview['reminder_before'],
        after = Map<String, dynamic>.from(preview['reminder_after']);
    const purposes = {
      'item': '事项提醒',
      'start_review': '开始复习',
      'check_notice': '核实正式通知',
    };
    return [
      SectionHeading(before['title']),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: CampusColors.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (old != null) ...[
              RecordFact(
                label: old['enabled'] == false ? '当前提醒 · 已停用' : '当前提醒',
                value:
                    '${reminderLabel(Map<String, dynamic>.from(old))}${old['trigger_at'] == null ? '' : ' · ${displayInstant(old['trigger_at'])}'}',
                icon: Icons.notifications_none_rounded,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Icon(
                  Icons.arrow_downward_rounded,
                  size: 18,
                  color: CampusColors.teal,
                ),
              ),
            ],
            RecordFact(
              label: after['enabled'] == false
                  ? '停用这条提醒'
                  : old == null
                  ? '添加提醒'
                  : old['enabled'] == false
                  ? '启用提醒'
                  : '调整后',
              value:
                  '${reminderLabel(after)}${after['trigger_at'] == null ? '' : ' · ${displayInstant(after['trigger_at'])}'}',
              icon: after['enabled'] == false
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_active_outlined,
              color: after['enabled'] == false
                  ? CampusColors.muted
                  : CampusColors.teal,
            ),
            if ((old?['purpose'] ?? 'item') != (after['purpose'] ?? 'item'))
              RecordFact(
                label: '提醒用途',
                value: old == null
                    ? purposes[after['purpose']] ?? '事项提醒'
                    : '${purposes[old['purpose'] ?? 'item']} → ${purposes[after['purpose'] ?? 'item']}',
                icon: Icons.label_outline_rounded,
              ),
          ],
        ),
      ),
    ];
  }
}
