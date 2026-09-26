import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import 'agent_controller.dart';

class AgentPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> semester;
  const AgentPage({
    super.key,
    required this.controller,
    required this.semester,
  });
  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> with WidgetsBindingObserver {
  late final AgentController c;
  final input = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c = AgentController(widget.controller, widget.semester['id']);
    c.open();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) c.poll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.dispose();
    input.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (await c.send(text) && mounted && input.text.trim() == text) {
      input.clear();
    }
  }

  Future<void> history() async {
    await c.open(id: c.threadId);
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '最近对话',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          for (final t in c.threads)
            ListTile(
              title: Text(t['title']),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, t['id'] as String),
            ),
          if (c.threads.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('还没有对话')),
        ],
      ),
    );
    if (selected != null) c.open(id: selected);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('日程助手'),
        actions: [
          IconButton(
            tooltip: '最近对话',
            onPressed: c.busy ? null : history,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: '新对话',
            onPressed: c.busy ? null : () => c.open(fresh: true),
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                widget.semester['name'] ?? '当前学期',
                style: const TextStyle(color: CampusColors.muted, fontSize: 13),
              ),
            ),
            Expanded(
              child: c.loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                      children: [
                        if (c.runs.isEmpty) ...[
                          const SizedBox(height: 30),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: CircleAvatar(
                              radius: 27,
                              backgroundColor: Color(0xFFE9E5FF),
                              child: Icon(
                                Icons.auto_awesome_rounded,
                                color: CampusColors.primary,
                                size: 27,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '想查什么，或记点什么？',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 24),
                          for (final example in [
                            '我今天有哪些安排？',
                            '这周哪天有一小时空闲？',
                            '明天下午3点到4点开组会，提前30分钟提醒',
                          ])
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: OutlinedButton(
                                onPressed: () => input.text = example,
                                style: OutlinedButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.all(17),
                                ),
                                child: Text(example),
                              ),
                            ),
                        ],
                        for (final run in c.runs) turnView(run),
                      ],
                    ),
            ),
            if (c.error != null)
              Container(
                color: const Color(0xFFFFF1DE),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(child: Text(c.error!)),
                    TextButton(
                      onPressed: () =>
                          c.processing ? c.poll() : c.open(id: c.threadId),
                      child: const Text('刷新'),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: CampusColors.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 5,
                      enabled: !c.loading,
                      maxLength: 10000,
                      decoration: const InputDecoration(
                        hintText: '输入通知、问题或修改要求',
                        counterText: '',
                        filled: true,
                        fillColor: CampusColors.background,
                        border: OutlineInputBorder(
                          borderSide: BorderSide.none,
                          borderRadius: BorderRadius.all(Radius.circular(20)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: '发送',
                    onPressed: c.loading || c.busy || c.processing
                        ? null
                        : send,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget turnView(Map<String, dynamic> run) {
    final working = run['status'] == 'queued' || run['status'] == 'running';
    final p = run['preview'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(left: 35, bottom: 18),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CampusColors.primary,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(
                run['text'],
                style: const TextStyle(color: Colors.white, height: 1.5),
              ),
            ),
          ),
          if (working)
            Row(
              children: [
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(run['stage'] ?? '正在处理')),
                TextButton(
                  onPressed: () => c.stop(run),
                  child: const Text('停止'),
                ),
              ],
            ),
          if ((run['answer'] ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SelectableText(
                run['answer'],
                style: const TextStyle(height: 1.6),
              ),
            ),
          for (final card in rows(run['cards'])) factCard(card),
          if (p is Map) previewCard(run, Map<String, dynamic>.from(p)),
          if (run['error'] != null)
            Text(
              run['error'],
              style: const TextStyle(color: Color(0xFF9A5C13)),
            ),
          if (run['status'] == 'cancelled')
            const Text(
              '已停止，未保存这次修改',
              style: TextStyle(color: CampusColors.muted),
            ),
          if (run['status'] == 'superseded')
            const Text(
              '已按后续消息重新处理，这份预览未保存',
              style: TextStyle(color: CampusColors.muted),
            ),
        ],
      ),
    );
  }

  Widget panel(Widget child, {Color color = Colors.white}) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: CampusColors.line),
      borderRadius: BorderRadius.circular(22),
    ),
    child: child,
  );

  Widget factCard(Map<String, dynamic> card) {
    final d = Map<String, dynamic>.from(card['data'] ?? {});
    final kind = card['kind'];
    if (kind == 'calendar' || kind == 'records') {
      final entries = rows(d[kind == 'calendar' ? 'entries' : 'records']);
      return panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kind == 'calendar' ? '查到的安排' : '匹配的事项',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            if (kind == 'calendar')
              Text(
                '${d['from_date']} — ${d['to_date']}',
                style: const TextStyle(color: CampusColors.muted, fontSize: 12),
              ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('没有查到匹配的安排'),
              ),
            for (final e in entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(e['title'] ?? '日程'),
                subtitle: Text(
                  entryTime(e) +
                      (e['location'] != null && e['location'] != ''
                          ? ' · ${e['location']}'
                          : ''),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => openRecord(e),
              ),
            if (rows(d['undated']).isNotEmpty)
              Text(
                '另有${rows(d['undated']).length}项时间待确认',
                style: const TextStyle(color: CampusColors.muted),
              ),
          ],
        ),
      );
    }
    if (kind == 'analysis') {
      return panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '安排概况',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                metric(
                  '占用时间',
                  '${(d['occupied_union_minutes'] as num? ?? 0) / 60}h',
                ),
                metric(
                  '个人计划',
                  '${(d['personal_planned_minutes'] as num? ?? 0) / 60}h',
                ),
                metric('实际投入', '未统计'),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '占用时间已扣除重叠部分。${d['undated_count'] ?? 0}项日期待确认。',
              style: const TextStyle(color: CampusColors.muted, fontSize: 13),
            ),
          ],
        ),
        color: const Color(0xFFF0ECFF),
      );
    }
    if (kind == 'windows') {
      return panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '可用时段',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            for (final e in rows(d['windows']))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(entryTime(e)),
              ),
            if (rows(d['windows']).isEmpty)
              Text(
                rows(d['needs_input']).isNotEmpty
                    ? '有固定安排尚未确定起止时间，补齐后才能确认空闲时段。'
                    : '当前学习时间设置内没有找到足够长的空闲时段。',
              ),
          ],
        ),
        color: CampusColors.mint,
      );
    }
    return const SizedBox();
  }

  Widget metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      ),
      Text(
        label,
        style: const TextStyle(color: CampusColors.muted, fontSize: 12),
      ),
    ],
  );
  void openRecord(Map<String, dynamic> e) {
    final id = e['resource_id'] ?? e['id'];
    final type = e['resource_type'];
    final route = type == 'event'
        ? '/events/$id'
        : type == 'course'
        ? '/courses/$id'
        : type == 'exam'
        ? '/exams/$id'
        : '/items/$id';
    context.push(route);
  }

  String entryTime(Map<String, dynamic> e) {
    if (e['start_at'] != null) {
      return '${displayInstant(e['start_at'])}${e['end_at'] != null ? ' — ${displayInstant(e['end_at'])}' : ''}';
    }
    if (e['due_at'] != null) return '${displayInstant(e['due_at'])}截止';
    final t = Map<String, dynamic>.from(e['time'] ?? {});
    if (t['at'] != null) {
      return '${displayInstant(t['at'])}${t['end_at'] != null ? ' — ${displayInstant(t['end_at'])}' : ''}';
    }
    if ((t['date'] ?? e['date']) != null) {
      final end = t['end_date'] ?? e['end_date'];
      return '${t['date'] ?? e['date']}${end != null ? ' 至 $end' : ''}';
    }
    if ((t['week'] ?? e['week']) != null) return '第${t['week'] ?? e['week']}周';
    return '时间待确认';
  }

  Widget previewCard(Map<String, dynamic> run, Map<String, dynamic> p) {
    final before = Map<String, dynamic>.from(p['before'] ?? {}),
        after = Map<String, dynamic>.from(p['after'] ?? {});
    final pending = run['status'] == 'needs_confirmation',
        applied = run['status'] == 'applied';
    final action = p['action'];
    final create = action == 'create';
    final title = after['title'] ?? before['title'] ?? p['title'] ?? '修改提醒';
    final labels = {
      'title': '名称',
      'time': '时间',
      'location': '地点',
      'reminder_minutes': '提醒',
      'remaining_minutes': '预计剩余',
      'splittable': '允许分段安排',
      'category_id': '分类',
      'tags': '标签',
      'priority': '优先级',
      'notes': '备注',
      'trigger_at': '提醒时刻',
      'lead_minutes': '提前提醒',
      'enabled': '启用提醒',
      'mode': '提醒方式',
      'purpose': '提醒用途',
      'start_policy': '最早开始',
      'earliest_start_at': '开始时刻',
      'reminders': '提醒',
      'certainty': '时间是否确定',
      'kind': '事项类型',
      'course_id': '关联课程',
    };
    final fields = labels.keys
        .where(
          (key) =>
              after.containsKey(key) &&
              (create
                  ? key != 'title' &&
                        after[key] != null &&
                        after[key] != '' &&
                        !(after[key] is List && (after[key] as List).isEmpty)
                  : jsonEncode(before[key]) != jsonEncode(after[key])),
        )
        .toList();
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                applied ? Icons.check_circle : Icons.edit_calendar_outlined,
                color: CampusColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  applied
                      ? '已保存'
                      : action == 'cancel'
                      ? '取消日程'
                      : create
                      ? '添加到日程'
                      : '修改预览',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          for (final key in fields.where(
            (k) =>
                !create ||
                {
                  'time',
                  'location',
                  'reminder_minutes',
                  'reminders',
                }.contains(k),
          ))
            difference(labels[key]!, key, before, after, create),
          if (create)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('更多设置与来源'),
              children: [
                for (final key in fields.where(
                  (k) => !{
                    'time',
                    'location',
                    'reminder_minutes',
                    'reminders',
                  }.contains(k),
                ))
                  difference(labels[key]!, key, before, after, true),
                if ((after['source_text'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SelectableText(after['source_text']),
                  ),
              ],
            ),
          if (action == 'cancel') Text(entryTime(before)),
          if (rows(p['affected_blocks']).isNotEmpty)
            const Text('已有个人计划与这次修改有关，请核对后保存。'),
          if (pending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: c.busy ? null : () => c.decide(run, false),
                    child: const Text('不修改'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: c.busy ? null : () => c.decide(run, true),
                    child: Text(
                      action == 'cancel'
                          ? '确认取消'
                          : create
                          ? '确认添加'
                          : '确认修改',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '有不对的地方，可以继续输入修改要求。',
              style: TextStyle(color: CampusColors.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget difference(
    String label,
    String key,
    Map<String, dynamic> before,
    Map<String, dynamic> after,
    bool create,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: CampusColors.muted, fontSize: 12),
        ),
        if (!create && before.containsKey(key))
          Text(
            fieldValue(key, before[key]),
            style: const TextStyle(
              color: CampusColors.muted,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        Text(
          fieldValue(key, after[key]),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  String fieldValue(String key, dynamic value) {
    if (value == null) return '未设置';
    if (key == 'certainty') {
      return {'formal': '已确定', 'tentative': '暂定', 'unknown': '待核实'}[value] ??
          '待核实';
    }
    if (key == 'kind') return kindLabel(value);
    if (key == 'course_id') {
      return widget.controller.courses
              .where((r) => r['id'] == value)
              .firstOrNull?['title'] ??
          '关联课程（名称待加载）';
    }
    if (key == 'time') return entryTime({'time': value});
    if (key == 'category_id') {
      return {
            'study': '学业',
            'research': '科研',
            'affairs': '校园事务',
            'life': '生活',
          }[value] ??
          '未分类';
    }
    if (key == 'priority') {
      return {'high': '高', 'normal': '普通', 'low': '低'}[value] ?? '普通';
    }
    if (key == 'start_policy') {
      return {'now': '现在起', 'at': '指定时刻', 'unconfirmed': '待确认'}[value] ?? '待确认';
    }
    if (key == 'trigger_at' || key == 'earliest_start_at') {
      return displayInstant(value);
    }
    if (key == 'mode') return value == 'absolute' ? '指定时刻' : '提前提醒';
    if (key == 'purpose') {
      return {
            'item': '事项提醒',
            'start_review': '开始复习',
            'check_notice': '核实通知',
          }[value] ??
          '事项提醒';
    }
    if (value is bool) return value ? '是' : '否';
    if (key == 'remaining_minutes' || key == 'lead_minutes') return '$value分钟';
    if (value is List) {
      if (value.isEmpty) return '未设置';
      if (key == 'reminder_minutes') {
        return value.map((v) => v == 0 ? '开始时' : '提前$v分钟').join('、');
      }
      if (key == 'reminders') {
        return value
            .map(
              (v) => v['mode'] == 'absolute'
                  ? displayInstant(v['trigger_at'])
                  : '提前${v['lead_minutes']}分钟',
            )
            .join('、');
      }
      return value.map((v) => v is Map ? v['name'] : v).join('、');
    }
    return '$value';
  }
}
