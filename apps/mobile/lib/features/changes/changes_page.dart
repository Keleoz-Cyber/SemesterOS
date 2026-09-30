import '../../ui/app_controls.dart';
import '../../ui/app_picker_field.dart';
import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/campus_theme.dart';
import '../../ui/detail_widgets.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import '../planning/date_time_picker.dart';
import '../planning/proposal_page.dart';
import '../media/source_view.dart';

const changeNames = {
  'move': '调课',
  'cancel': '停课',
  'suspend': '放假停课（明确选择课次）',
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
    if (source.text.trim().isEmpty) throw Exception('先粘贴学校通知或填写变更依据');
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
  Future<void> preview() => act(() async {
    if (title.text.trim().isEmpty || source.text.trim().isEmpty) {
      throw Exception('请填写标题与原始通知/变更依据');
    }
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
        'title': title.text.trim(),
        'source_text': source.text.trim(),
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
          title: const Text('明确选择受影响课次'),
          content: SizedBox(
            width: 500,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text('每行代表一次课。放假只停用所选课次，不默认停掉所有课程。'),
                for (final e in all)
                  AppCheckRow(
                    title: Text(
                      '${e['title']}\n${displayInstant(e['start_at'])}',
                    ),
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
      title: const Text('现实变化'),
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
          title: '记录现实变化',
          icon: Icons.edit_calendar_outlined,
        ),

        EditorSection(
          title: '学校通知或变更依据',
          icon: Icons.description_outlined,
          accent: CampusColors.teal,
          children: [
            AppField(
              controller: source,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '变更通知或修改原因',
                hintText: '粘贴调课、停课、补课、放假或活动通知',
              ),
            ),
            AppTextButton.icon(
              onPressed: busy ? null : parse,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('让AI整理通知'),
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
              for (final e
                  in widget.controller
                      .rows(feed?['occurrences'])
                      .where((e) => targets.contains(e['id'])))
                RecordFact(
                  label: '已选课次',
                  value: '${e['title']} · ${displayInstant(e['start_at'])}',
                  icon: Icons.check_circle_outline_rounded,
                  color: CampusColors.teal,
                ),
            ],
          ],
        ),
        if (['move', 'add', 'block'].contains(kind))
          EditorSection(
            title: '新的时间与地点',
            icon: Icons.event_outlined,
            children: [
              AppOutlineButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final v = await pickSchoolDateTime(
                          context,
                          initial: start,
                        );
                        if (v != null && mounted) setState(() => start = v);
                      },
                icon: const Icon(Icons.schedule_rounded),
                label: Text(
                  start == null
                      ? '选择新的开始日期与时间'
                      : '新开始：${displayInstant(start!.toIso8601String())}',
                ),
              ),
              const SizedBox(height: 8),
              AppOutlineButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final v = await pickSchoolDateTime(
                          context,
                          initial: end ?? start,
                        );
                        if (v != null && mounted) setState(() => end = v);
                      },
                icon: const Icon(Icons.schedule_rounded),
                label: Text(
                  end == null
                      ? '选择新的结束日期与时间'
                      : '新结束：${displayInstant(end!.toIso8601String())}',
                ),
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
        const SectionHeading('最近50条变化预览与记录'),
        for (final p in widget.controller.rows(feed?['changes']))
          AppTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 4,
            ),
            leading: Icon(
              p['phase'] == 'applied'
                  ? Icons.check_circle_outline_rounded
                  : p['phase'] == 'stale'
                  ? Icons.history_rounded
                  : Icons.pending_actions_rounded,
              color: p['phase'] == 'applied'
                  ? CampusColors.teal
                  : CampusColors.muted,
            ),
            title: Text(
              '${p['request']['title']} · ${changeNames[p['request']['kind']]}',
            ),
            subtitle: Text(
              p['phase'] == 'applied'
                  ? '新安排已保存'
                  : p['phase'] == 'stale'
                  ? '旧预览已失效'
                  : '待确认',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChangePreviewPage(
                  controller: widget.controller,
                  preview: p,
                ),
              ),
            ),
          ),
      ],
    ),
    bottomNavigationBar: ActionFooter(
      secondary: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null) SoftNotice(error!, warning: true),
          if (busy) const LinearProgressIndicator(),
        ],
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

  Widget event(Map e) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${e['title']}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        RecordFact(
          label: '时间',
          value:
              '${displayInstant(e['start_at'])} — ${displayInstant(e['end_at'])}',
          icon: Icons.schedule_rounded,
        ),
        RecordFact(
          label: '地点',
          value: '${e['location'] ?? ''}'.isEmpty
              ? '地点待确认'
              : '${e['location']}',
          icon: Icons.location_on_outlined,
        ),
      ],
    ),
  );

  Widget comparison(Map patch) {
    Widget side(bool after) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: after ? CampusColors.tealSoft : CampusColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: after
              ? CampusColors.teal.withValues(alpha: .3)
              : CampusColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            after ? '变化后' : '变化前',
            style: TextStyle(
              fontSize: 14,
              color: after ? CampusColors.teal : CampusColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final e in patch[after ? 'after' : 'before']) event(e),
          if ((patch[after ? 'after' : 'before'] as List).isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(after ? '所选课次停课，其余课次保持' : '新增安排'),
            ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 600 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              side(false),
              const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_downward_rounded,
                  color: CampusColors.teal,
                ),
              ),
              side(true),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: side(false)),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: CampusColors.teal,
              ),
            ),
            Expanded(child: side(true)),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final impact = p['impact'], patch = p['patch'];
    final conflict = (impact['after_summary']['fixed_conflict_count'] ?? 0) > 0;
    final stale = widget.controller.revisionIsStale(
      p['semester_id'],
      p['base_revision'],
    );
    return Scaffold(
      appBar: AppBar(title: Text(applied ? '新安排已保存' : '确认课程或活动变更')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          RecordHeading(
            label: changeNames[p['request']['kind']] ?? '安排变化',
            title: '${p['request']['title']}',
            icon: Icons.compare_arrows_rounded,
          ),

          comparison(patch),
          const SizedBox(height: 20),
          DocumentPanel(
            title: '变更通知',
            text: '${p['request']['source_text']}',
            footer: p['request']['source_id'] != null
                ? AppTextButton(
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
                  )
                : null,
          ),
          EditorSection(
            title: '本次预览时的影响',
            icon: Icons.fact_check_outlined,
            children: [
              Text('个人计划需核对 ${(impact['affected_blocks'] as List).length} 段'),
              for (final b in impact['affected_blocks'])
                RecordFact(
                  label: b['locked'] == true ? '已锁定的个人计划' : '个人计划',
                  value: '${b['title']} · ${displayInstant(b['start_at'])}',
                  icon: b['locked'] == true
                      ? Icons.lock_outline_rounded
                      : Icons.event_note_outlined,
                ),
              for (final r in impact['risk_changes'])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '${r['title']}\n计划余量：${r['before_slack'] ?? '待确认'} → ${r['after_slack'] ?? '待确认'} 分钟',
                  ),
                ),
            ],
          ),
          if (conflict)
            const SoftNotice('固定安排之间已有冲突，个人重排不会移动学校安排。', warning: true),
          for (final collision in impact['fixed_conflicts'] ?? [])
            SoftNotice(
              '${(collision['titles'] as List).join(' 与 ')}\n冲突时段：${displayInstant(collision['start_at'])} — ${displayInstant(collision['end_at'])}',
              warning: true,
            ),
          if ((impact['after_summary']['fixed_conflict_count'] ?? 0) >
              (impact['fixed_conflicts'] as List? ?? []).length)
            const Text('此处列出前30处冲突，其余请在课表核对。'),
          if (conflict && !applied)
            AppCheckRow(
              title: const Text('我已核实通知，确认保存并保留时间冲突提示'),
              value: confirmConflict,
              onChanged: busy
                  ? null
                  : (v) => setState(() => confirmConflict = v!),
            ),
          if (!same) const SoftNotice('账号或学期已切换，请返回', warning: true),
          if (stale && !applied)
            const SoftNotice('此预览已失效，请返回重新预览', warning: true),
          if (error != null) SoftNotice(error!, warning: true),
          if (busy) const LinearProgressIndicator(),
          if (!applied)
            AppButton(
              onPressed:
                  busy || !same || stale || (conflict && !confirmConflict)
                  ? null
                  : () => act(false),
              child: const Text('确认现实变化，暂不移动个人计划'),
            ),
          if (applied) ...[
            const SoftNotice('新安排已保存。接下来可以调整受影响的个人计划，查看方案后再确认。'),
            AppButton(
              onPressed: busy || !same ? null : () => act(true),
              child: const Text('查看个人计划调整方案'),
            ),
          ],
        ],
      ),
    );
  }
}
