import '../../ui/app_controls.dart';
import '../agent/agent_widgets.dart';
import '../../ui/app_picker_field.dart';
import '../../core/api.dart' show userError;
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/campus_theme.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/record_actions.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import '../items/task_surfaces.dart';
import '../notices/notice_fields.dart' show noticeTime;
import '../planning/date_time_picker.dart';
import '../planning/proposal_page.dart';
import '../planning/risk_widgets.dart' show minutesLabel;
import '../media/source_view.dart';
import 'course_change_display.dart';

const changeNames = {
  'move': '调课',
  'cancel': '停课',
  'suspend': '多次停课',
  'add': '补课',
  'block': '固定活动',
};

class ChangesPage extends StatefulWidget {
  final ItemsController controller;
  final String initialText;
  final String? initialSourceId, initialReferenceAt;
  const ChangesPage({
    super.key,
    required this.controller,
    this.initialText = '',
    this.initialSourceId,
    this.initialReferenceAt,
  });
  @override
  State<ChangesPage> createState() => _ChangesPageState();
}

class _ChangesPageState extends State<ChangesPage> {
  late final source = TextEditingController(text: widget.initialText);
  final title = TextEditingController(), location = TextEditingController();
  late final sid = widget.controller.semesterId;
  late final generation = widget.controller.api.generation;
  String kind = 'move';
  Map<String, dynamic>? feed, suggestion;
  final targets = <String>{};
  DateTime? start, end;
  bool busy = false;
  String? error;
  bool get same =>
      sid == widget.controller.semesterId &&
      generation == widget.controller.api.generation;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    source.dispose();
    title.dispose();
    location.dispose();
    super.dispose();
  }

  Future<void> act(Future<void> Function() fn) async {
    if (!same) {
      setState(() => error = '账号或学期已切换，请返回');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() => act(() async {
    final result = await widget.controller.changeRequest(
      'GET',
      '/semesters/$sid/changes',
    );
    if (mounted && same) setState(() => feed = result);
  });
  Future<void> parse() => act(() async {
    if (source.text.trim().isEmpty) throw Exception('请输入要修改的安排');
    final r = await widget.controller.changeRequest(
      'POST',
      '/changes/parse',
      data: {
        'semester_id': sid,
        'text': source.text.trim(),
        'reference_at':
            widget.initialReferenceAt ??
            DateTime.now().toUtc().toIso8601String(),
      },
    );
    if (!mounted || !same) return;
    final s = Map<String, dynamic>.from(r['suggestion']);
    setState(() {
      suggestion = s;
      if (s['kind'] == 'clarify') {
        error = '通知尚不明确，请核对下面的问题后手工填写';
        return;
      }
      kind = s['kind'];
      title.text = s['title'] ?? '';
      location.text = s['location'] ?? '';
      start = DateTime.tryParse(s['start_at'] ?? '');
      end = DateTime.tryParse(s['end_at'] ?? '');
      targets.clear();
      if ((r['target_candidates'] as List).length == 1) {
        targets.add(r['target_candidates'][0]);
      }
    });
  });
  Future<void> chooseWindow() async {
    if (busy || !same) return;
    final previousStart = start, previousEnd = end, previousKind = kind;
    final previousTargets = {...targets};
    final selected = widget.controller
        .rows(feed?['occurrences'])
        .where((row) => targets.contains(row['id']))
        .toList();
    final original = selected.length == 1 ? selected.first : null;
    final originalStart = DateTime.tryParse('${original?['start_at'] ?? ''}');
    final originalEnd = DateTime.tryParse('${original?['end_at'] ?? ''}');
    final duration =
        originalStart != null &&
            originalEnd != null &&
            originalEnd.isAfter(originalStart)
        ? originalEnd.difference(originalStart)
        : null;
    final value = await pickSchoolDateTimeRange(
      context,
      initialStart:
          start ??
          (end != null && duration != null
              ? end!.subtract(duration)
              : originalStart),
      initialEnd:
          end ??
          (start != null && duration != null
              ? start!.add(duration)
              : originalEnd),
      title: '${kind == 'block' ? '活动' : changeNames[kind] ?? '安排'}时间',
    );
    if (value == null || !mounted || !same || busy || kind != previousKind) {
      return;
    }
    if (start != previousStart ||
        end != previousEnd ||
        !setEquals(targets, previousTargets)) {
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

  Future<void> preview() => act(() async {
    final selectedRows = widget.controller
        .rows(feed?['occurrences'])
        .where((e) => targets.contains(e['id']))
        .toList();
    final name = title.text.trim().isNotEmpty
        ? title.text.trim()
        : selectedRows.length == 1
        ? '${selectedRows.first['title']}'
        : kind == 'suspend'
        ? '课程停课'
        : '';
    if (name.isEmpty) throw Exception('请填写课程或活动名称');
    if (['move', 'cancel', 'suspend'].contains(kind) && targets.isEmpty) {
      throw Exception('请选择实际受影响的课次');
    }
    if (['move', 'add', 'block'].contains(kind) &&
        (start == null || end == null || !end!.isAfter(start!))) {
      throw Exception('请核对新安排的开始和结束时间');
    }
    final p = await widget.controller.changeRequest(
      'POST',
      '/semesters/$sid/changes',
      data: {
        'kind': kind,
        'targets': targets.toList(),
        'title': name,
        'source_text': source.text.trim().isEmpty
            ? '用户更正个人安排'
            : source.text.trim(),
        if (widget.initialSourceId != null) 'source_id': widget.initialSourceId,
        'location': location.text.trim(),
        if (['move', 'add', 'block'].contains(kind)) ...{
          'start_at': start!.toUtc().toIso8601String(),
          'end_at': end!.toUtc().toIso8601String(),
        },
      },
    );
    if (!mounted || !same) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChangePreviewPage(controller: widget.controller, preview: p),
      ),
    );
    if (mounted && same) {
      final r = await widget.controller.changeRequest(
        'GET',
        '/semesters/$sid/changes',
      );
      if (mounted) {
        setState(() {
          feed = r;
          targets.clear();
        });
      }
    }
  });
  Future<void> chooseTargets() async {
    final selected = Set<String>.from(targets);
    final all = widget.controller.rows(feed?['occurrences']);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AppDialog(
          title: const Text('选择课次'),
          content: SizedBox(
            width: 500,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final e in all)
                  AppCheckRow(
                    title: Text('${e['title']}'),
                    subtitle: Text(displayInterval(e['start_at'], e['end_at'])),
                    value: selected.contains(e['id']),
                    onChanged: (v) => update(() {
                      if (v == true) {
                        if (kind != 'suspend') selected.clear();
                        selected.add(e['id']);
                      } else {
                        selected.remove(e['id']);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            AppTextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('返回'),
            ),
            AppButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('确认选择'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        targets.clear();
        targets.addAll(result);
        if (targets.length == 1) {
          final e = all.firstWhere((e) => e['id'] == targets.first);
          title.text = e['title'];
          location.text = e['location'] ?? '';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('修改课程安排'),
      actions: [
        AppIconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
          tooltip: '刷新变化',
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const RecordHeading(
          label: '课程与固定活动',
          title: '修改安排',
          icon: Icons.edit_calendar_outlined,
        ),

        EditorSection(
          title: '一句话修改',
          icon: Icons.description_outlined,
          accent: CampusColors.teal,
          children: [
            AppField(
              controller: source,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '修改内容（可选）',
                hintText: '例如：10月1日至7日停课',
              ),
            ),
            AppTextButton.icon(
              onPressed: busy ? null : parse,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('智能填写'),
            ),
            if (suggestion != null) ...[
              const SoftNotice('AI已整理出通知内容。请检查课程、日期和时间，确认后才会保存。'),
              for (final q in suggestion!['questions'] ?? []) Text('需核对：$q'),
              for (final e in (suggestion!['evidence'] as Map? ?? {}).entries)
                Text('来源片段：${e.value}'),
            ],
          ],
        ),
        EditorSection(
          title: '变化内容',
          icon: Icons.swap_horiz_rounded,
          children: [
            AppPickerField<String>(
              initialValue: kind,
              key: ValueKey(kind),
              isExpanded: true,
              decoration: const InputDecoration(labelText: '变化类型'),
              items: changeNames.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      kind = v!;
                      targets.clear();
                    }),
            ),
            const SizedBox(height: 12),
            AppField(
              controller: title,
              decoration: const InputDecoration(labelText: '课程 / 活动标题'),
            ),
            if (['move', 'cancel', 'suspend'].contains(kind)) ...[
              const SizedBox(height: 12),
              AppOutlineButton(
                onPressed: busy || feed == null ? null : chooseTargets,
                child: Text('选择受影响课次（已选${targets.length}次）'),
              ),
              if (targets.isNotEmpty)
                CourseChangeSummary(
                  showTitle: false,
                  showSource: false,
                  change: {
                    'kind': kind,
                    'before': widget.controller
                        .rows(feed?['occurrences'])
                        .where((e) => targets.contains(e['id']))
                        .toList(),
                    'after': const [],
                  },
                ),
            ],
          ],
        ),
        if (['move', 'add', 'block'].contains(kind))
          EditorSection(
            title: '新的时间与地点',
            icon: Icons.event_outlined,
            children: [
              RecordActionTile(
                key: const ValueKey('change-time-range'),
                onTap: busy ? null : chooseWindow,
                icon: Icons.calendar_month_outlined,
                title: windowLabel,
                subtitle: start != null && end != null && end!.isAfter(start!)
                    ? '时长 ${minutesLabel(end!.difference(start!).inMinutes)}'
                    : null,
              ),
              const SizedBox(height: 12),
              AppField(
                controller: location,
                decoration: const InputDecoration(labelText: '新地点（可留空）'),
              ),
            ],
          ),
        const SizedBox(height: 12),

        const Divider(height: 32),
        const SectionHeading('最近的课程调整'),
        for (final p in widget.controller.rows(feed?['changes']))
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CourseChangeSummary(
                change: p,
                onOpen: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangePreviewPage(
                      controller: widget.controller,
                      preview: p,
                    ),
                  ),
                ),
              ),
              if (p['phase'] != 'applied')
                Text(
                  p['phase'] == 'stale' ? '此预览已失效' : '尚未保存',
                  style: const TextStyle(
                    fontSize: 13,
                    color: CampusColors.muted,
                  ),
                ),
              const Divider(height: 24),
            ],
          ),
      ],
    ),
    bottomNavigationBar: ActionFooter(
      secondary: Column(
        mainAxisSize: MainAxisSize.min,
        children: [if (error != null) SoftNotice(error!, warning: true)],
      ),
      label: '预览变化与影响',
      onPressed: busy ? null : preview,
      icon: Icons.arrow_forward_rounded,
    ),
  );
}

class ChangePreviewPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> preview;
  const ChangePreviewPage({
    super.key,
    required this.controller,
    required this.preview,
  });
  @override
  State<ChangePreviewPage> createState() => _ChangePreviewPageState();
}

class _ChangePreviewPageState extends State<ChangePreviewPage> {
  late final p = widget.preview;
  late final generation = widget.controller.api.generation;
  bool busy = false, confirmConflict = false;
  late bool applied = p['phase'] == 'applied';
  String? error;
  bool get same =>
      generation == widget.controller.api.generation &&
      p['semester_id'] == widget.controller.semesterId;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(refresh);
    super.dispose();
  }

  Future<void> act(bool replan) async {
    if (!same) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (replan) {
        final result = await widget.controller.generateSchedule({
          'mode': 'replan',
          'lead_minutes': 5,
        });
        if (mounted && same) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ProposalPage(controller: widget.controller, proposal: result),
            ),
          );
        }
      } else {
        await widget.controller.changeRequest(
          'POST',
          '/changes/${p['id']}/apply',
          data: {
            'expected_revision': p['base_revision'],
            'confirm_fixed_conflicts': confirmConflict,
          },
          apply: true,
        );
        if (mounted && same) setState(() => applied = true);
      }
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final impact = p['impact'];
    final blocks = widget.controller.rows(impact['affected_blocks']);
    final risks = widget.controller
        .rows(impact['risk_changes'])
        .where((r) => r['before_slack'] is num && r['after_slack'] is num)
        .toList();
    final conflicts =
        impact['new_fixed_conflicts'] ?? impact['fixed_conflicts'] ?? [];
    final conflict = conflicts.isNotEmpty;
    final display = CourseChangeDisplay(p);
    final stale = widget.controller.revisionIsStale(
      p['semester_id'],
      p['base_revision'],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          applied
              ? display.restoration
                    ? '已恢复原安排'
                    : '调整已保存'
              : '核对课程调整',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          RecordHeading(
            label: display.action,
            title: display.title.isEmpty ? '课程安排' : display.title,
            icon: display.icon,
          ),

          CourseChangeSummary(change: p, showTitle: false, showSource: false),
          if ('${p['request']['source_text'] ?? ''}'.trim().isNotEmpty)
            AppDisclosure(
              tilePadding: EdgeInsets.zero,
              title: const Text('查看通知'),
              children: [
                SelectableText(
                  '${p['request']['source_text']}',
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
                if (p['request']['source_id'] != null)
                  AppTextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SourceViewPage(
                          controller: widget.controller,
                          id: p['request']['source_id'],
                        ),
                      ),
                    ),
                    child: const Text('查看原图 / 原录音'),
                  ),
              ],
            ),
          if (blocks.isNotEmpty || risks.isNotEmpty)
            EditorSection(
              title: '相关个人计划',
              icon: Icons.event_note_outlined,
              children: [
                if (blocks.isNotEmpty) Text('${blocks.length} 段个人计划需要调整'),
                for (final b in blocks)
                  RecordFact(
                    label: b['locked'] == true ? '已锁定的个人计划' : '个人计划',
                    value: '${b['title']} · ${displayInstant(b['start_at'])}',
                    icon: b['locked'] == true
                        ? Icons.lock_outline_rounded
                        : Icons.event_note_outlined,
                  ),
                if (risks.isNotEmpty)
                  AppDisclosure(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('查看任务时间变化'),
                    children: [
                      for (final r in risks)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${r['title']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TaskChangeFacts(
                                beforeLabel: '原剩余可用时间',
                                afterLabel: '修改后',
                                before: minutesLabel(r['before_slack']),
                                after: minutesLabel(r['after_slack']),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          for (final collision in conflicts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SoftNotice(
                '${(collision['titles'] as List).join(' 与 ')}时间重叠\n${noticeTime({'at': collision['start_at'], 'end_at': collision['end_at']})}',
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
          if (!same) const SoftNotice('账号或学期已切换，请返回', warning: true),
          if (stale && !applied)
            const SoftNotice('此预览已失效，请返回重新预览', warning: true),
          if (error != null) SoftNotice(error!, warning: true),

          if (!applied)
            AppButton(
              onPressed:
                  busy || !same || stale || (conflict && !confirmConflict)
                  ? null
                  : () => act(false),
              child: const Text('保存修改'),
            ),
          if (applied) ...[
            const AssistantSavedAction(text: '调整已保存'),
            if (blocks.isNotEmpty)
              Text(
                '${blocks.length} 段个人计划受影响，可查看调整方案。',
                style: const TextStyle(
                  fontSize: 14,
                  color: CampusColors.muted,
                  height: 1.5,
                ),
              ),
            AppTextButton(
              onPressed: busy || !same ? null : () => act(true),
              child: const Text('查看个人计划调整方案'),
            ),
          ],
        ],
      ),
    );
  }
}
