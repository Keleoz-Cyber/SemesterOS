import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../ui/app_controls.dart';
import '../../ui/date_labels.dart';
import '../../ui/app_sheet.dart';
import '../../ui/motion.dart';

Map<String, dynamic> noticeMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

String noticeClock(dynamic value, {bool clockOnly = false}) {
  final parsed = DateTime.tryParse('$value');
  if (parsed == null) return '';
  final day = parsed.toUtc().add(const Duration(hours: 8));
  final clock =
      '${day.hour.toString().padLeft(2, '0')}:${day.minute.toString().padLeft(2, '0')}';
  if (clockOnly) return clock;
  return '${studentDate(day, weekday: true)} $clock';
}

String noticeDate(dynamic value) {
  final parsed = DateTime.tryParse('$value');
  return parsed == null ? '$value' : studentDate(parsed);
}

String noticeTime(dynamic value, {bool task = false}) {
  final time = noticeMap(value);
  final meaning = time['meaning'];
  final expression = '${time['expression'] ?? ''}'.trim();
  if (time['at'] != null) {
    final start = noticeClock(time['at']);
    if (start.isEmpty) return expression;
    if (time['end_at'] != null) {
      final a = DateTime.tryParse('${time['at']}'),
          b = DateTime.tryParse('${time['end_at']}');
      final sameDay =
          a != null &&
          b != null &&
          a
                  .toUtc()
                  .add(const Duration(hours: 8))
                  .toIso8601String()
                  .substring(0, 10) ==
              b
                  .toUtc()
                  .add(const Duration(hours: 8))
                  .toIso8601String()
                  .substring(0, 10);
      final end = noticeClock(time['end_at'], clockOnly: sameDay);
      return '$start—$end${meaning == 'window' ? ' 可办理' : ''}';
    }
    return '$start${meaning == 'deadline' || task && !{'start', 'window', 'course_anchor'}.contains(meaning) ? ' 截止' : ''}';
  }
  if (time['date'] != null) {
    final range = time['end_date'] != null
        ? '—${noticeDate(time['end_date'])}'
        : '';
    final qualifier =
        RegExp(
          r'上午|下午|晚上|中午|早晨|凌晨|傍晚|白天|夜间|课后|下课|饭后|晚自习|\d{1,2}点',
        ).hasMatch(expression)
        ? ' · $expression'
        : '';
    return '${noticeDate(time['date'])}$range$qualifier${meaning == 'window'
        ? ' 可办理'
        : time['day_end_confirmed'] == true
        ? ' 当日结束前'
        : ''}';
  }
  if (time['week'] != null) return '第${time['week']}周';
  if (expression.isNotEmpty) return expression;
  final choices = (time['candidate_dates'] as List? ?? [])
      .map(noticeDate)
      .toList();
  return choices.join('或');
}

bool noticeTimePresent(dynamic value) => noticeTime(value).isNotEmpty;

List<({String label, String value})> noticeDetailRows(
  dynamic value, {
  String? location,
  String? title,
}) {
  final detail = noticeMap(value);
  final result = <({String label, String value})>[];
  void add(String key, String label) {
    final raw = detail[key];
    String audienceKey(String value) => value
        .replaceAll(RegExp(r'\s+|的学生|学生|的同学|同学'), '')
        .replaceAll('尚未', '未');
    if (key == 'conditions' && '${detail['audience'] ?? ''}'.isNotEmpty) {
      final conditions = raw is List ? raw.map((v) => '$v').toList() : ['$raw'];
      final audience = audienceKey('${detail['audience']}');
      if (conditions.isNotEmpty &&
          conditions.every(
            (v) =>
                audienceKey(v).length >= 2 && audience.contains(audienceKey(v)),
          )) {
        return;
      }
    }
    var text = raw is List
        ? raw.where((v) => '$v'.trim().isNotEmpty).join('、')
        : '${raw ?? ''}'.trim();
    if (key == 'submission_channel' &&
        location != null &&
        location.trim().isNotEmpty) {
      text = text
          .replaceFirst(RegExp('^${RegExp.escape(location.trim())}'), '')
          .trim()
          .replaceFirst(RegExp(r'^[，、:：\s]+'), '');
    }
    if (key == 'responsibility' &&
        title != null &&
        title.contains(
          text.replaceFirst(RegExp(r'^(请|需|需要|按要求|务必)'), '').trim(),
        )) {
      return;
    }
    if (key == 'submission_channel' &&
        title != null &&
        text.isNotEmpty &&
        title.contains(text)) {
      return;
    }
    if (key == 'audience' &&
        {
          '所有人',
          '全体同学',
          '全体学生',
          '各班',
          '各位同学',
          '大家',
          '本班同学',
          '在校学生',
        }.contains(text)) {
      return;
    }
    if (key == 'materials' &&
        raw is List &&
        raw.length == 1 &&
        title != null &&
        title.contains(text)) {
      return;
    }
    if (text.isNotEmpty && !{'unknown', 'unspecified', 'none'}.contains(text)) {
      result.add((label: label, value: text));
    }
  }

  add('recipient', '交给');
  add('submission_channel', '提交方式');
  add('materials', '材料');
  add('conditions', '适用条件');
  add('responsibility', '需要处理');
  add('applicability', '适用对象');
  final arrival = detail['early_arrival_minutes'];
  if (arrival is num && arrival > 0) {
    result.add((label: '到场', value: '提前$arrival分钟'));
  }
  final participation = '${detail['participation'] ?? ''}'.trim();
  if (participation.isNotEmpty &&
      !{'mandatory', 'unknown', 'unspecified'}.contains(participation)) {
    result.add((
      label: '参加方式',
      value:
          {'optional': '自愿参加', 'conditional': '符合条件时参加'}[participation] ??
          participation,
    ));
  }
  return result;
}

class NoticeDetailsEditor extends StatefulWidget {
  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final TextEditingController? notesController;
  const NoticeDetailsEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.notesController,
  });
  @override
  State<NoticeDetailsEditor> createState() => _NoticeDetailsEditorState();
}

class _NoticeDetailsEditorState extends State<NoticeDetailsEditor> {
  static const labels = {
    'recipient': '交给谁',
    'materials': '材料清单',
    'submission_channel': '提交信息',
    'conditions': '办理条件',
    'applicability': '哪些人需要处理',
    'responsibility': '办理要求',
    'participation': '参加说明',
    'early_arrival_minutes': '提前到场（分钟）',
  };
  final fields = <String, TextEditingController>{};
  final removed = <String>{};
  final initialTexts = <String, String>{};
  final blockKeys = <String, GlobalKey>{};
  final notesKey = GlobalKey();
  bool notesVisible = false;
  bool get hasNotes =>
      widget.notesController != null &&
      (notesVisible || widget.notesController!.text.trim().isNotEmpty);
  static const common = [
    'submission_channel',
    'materials',
    'responsibility',
    'participation',
  ];
  bool hasValue(dynamic value) =>
      value != null &&
      (value is List
          ? value.isNotEmpty
          : value is String
          ? value.trim().isNotEmpty
          : true);
  String fieldText(dynamic value) =>
      value is List ? value.join('\n') : '$value';
  @override
  void initState() {
    super.initState();
    for (final key in labels.keys) {
      final value = widget.value[key];
      if (hasValue(value)) {
        fields[key] = TextEditingController(text: fieldText(value));
        initialTexts[key] = fields[key]!.text;
      }
    }
    notesVisible = widget.notesController?.text.trim().isNotEmpty == true;
  }

  @override
  void didUpdateWidget(covariant NoticeDetailsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final key in labels.keys) {
      if (removed.contains(key)) continue;
      final next = widget.value[key];
      if (!fields.containsKey(key) && hasValue(next)) {
        fields[key] = TextEditingController(text: fieldText(next));
        initialTexts[key] = fields[key]!.text;
      }
    }
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void changed() {
    final next = {...widget.value};
    for (final key in removed) {
      next[key] = clearValue(key);
    }
    for (final entry in fields.entries) {
      if (initialTexts[entry.key] == entry.value.text &&
          widget.value.containsKey(entry.key)) {
        continue;
      }
      final text = entry.value.text.trim();
      next[entry.key] = {'materials', 'conditions'}.contains(entry.key)
          ? text
                .split('\n')
                .map((v) => v.trim())
                .where((v) => v.isNotEmpty)
                .toList()
          : entry.key == 'early_arrival_minutes'
          ? int.tryParse(text)
          : text;
    }
    widget.onChanged(next);
  }

  dynamic clearValue(String key) => {'materials', 'conditions'}.contains(key)
      ? <String>[]
      : key == 'early_arrival_minutes'
      ? null
      : '';

  void remove(String key) {
    final field = fields[key];
    if (field == null) return;
    setState(() {
      fields.remove(key);
      initialTexts.remove(key);
      blockKeys.remove(key);
      removed.add(key);
    });
    changed();
    // Let the old editable detach before releasing its controller.
    WidgetsBinding.instance.addPostFrameCallback((_) => field.dispose());
  }

  IconData fieldIcon(String key) => switch (key) {
    'recipient' => Icons.person_outline_rounded,
    'materials' => Icons.description_outlined,
    'submission_channel' => Icons.outbox_outlined,
    'responsibility' => Icons.checklist_rounded,
    'participation' => Icons.groups_outlined,
    'early_arrival_minutes' => Icons.schedule_rounded,
    _ => Icons.info_outline_rounded,
  };

  Future<void> add() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final key = await showAppSheet<String>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppSheetHeading(title: '补充信息', padding: EdgeInsets.zero),
            const SizedBox(height: 12),
            for (final key in common.where((key) => !fields.containsKey(key)))
              AppTile(
                leading: Icon(
                  fieldIcon(key),
                  size: 20,
                  color: CampusColors.primary,
                ),
                title: Text(labels[key]!),
                trailing: const Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: CampusColors.muted,
                ),
                onTap: () => Navigator.pop(context, key),
              ),
            if (widget.notesController != null && !hasNotes)
              AppTile(
                leading: const Icon(
                  Icons.notes_rounded,
                  size: 20,
                  color: CampusColors.primary,
                ),
                title: const Text('其他说明'),
                trailing: const Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: CampusColors.muted,
                ),
                onTap: () => Navigator.pop(context, '_notes'),
              ),
            if (labels.keys.any(
              (key) => !common.contains(key) && !fields.containsKey(key),
            ))
              AppDisclosure(
                title: const Text('更多补充项'),
                children: [
                  for (final key in labels.keys.where(
                    (key) => !common.contains(key) && !fields.containsKey(key),
                  ))
                    AppTile(
                      leading: Icon(
                        fieldIcon(key),
                        size: 20,
                        color: CampusColors.muted,
                      ),
                      title: Text(labels[key]!),
                      trailing: const Icon(
                        Icons.add_rounded,
                        size: 18,
                        color: CampusColors.muted,
                      ),
                      onTap: () => Navigator.pop(context, key),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
    if (!mounted || key == null) return;
    if (key == '_notes') {
      setState(() => notesVisible = true);
    } else {
      setState(() {
        removed.remove(key);
        initialTexts.remove(key);
        fields[key] = TextEditingController();
      });
      changed();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = key == '_notes'
          ? notesKey.currentContext
          : blockKeys[key]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: .15,
          duration: AppMotion.change(context),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Icon(Icons.notes_outlined, size: 20, color: CampusColors.teal),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '补充信息',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          if (fields.length < labels.length ||
              widget.notesController != null && !hasNotes)
            AppTextButton.icon(
              onPressed: add,
              guardAsync: false,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加'),
            ),
        ],
      ),
      for (final entry in fields.entries)
        Padding(
          key: blockKeys.putIfAbsent(entry.key, GlobalKey.new),
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              fieldHeading(
                entry.key,
                labels[entry.key]!,
                () => remove(entry.key),
              ),
              Semantics(
                label: labels[entry.key],
                child: AppFormField(
                  key: ValueKey('notice-detail-${entry.key}'),
                  controller: entry.value,
                  minLines: 1,
                  maxLines: entry.key == 'early_arrival_minutes' ? 1 : 4,
                  keyboardType: entry.key == 'early_arrival_minutes'
                      ? TextInputType.number
                      : TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: {'materials', 'conditions'}.contains(entry.key)
                        ? '每行一项'
                        : null,
                    suffixText: entry.key == 'early_arrival_minutes'
                        ? '分钟'
                        : null,
                  ),
                  onChanged: (_) => changed(),
                  validator: (raw) {
                    final text = (raw ?? '').trim();
                    if (entry.key == 'early_arrival_minutes') {
                      final minutes = int.tryParse(text);
                      return text.isEmpty ||
                              minutes != null && minutes >= 0 && minutes <= 1440
                          ? null
                          : '请输入0至1440分钟';
                    }
                    final limit = entry.key == 'recipient'
                        ? 200
                        : {
                            'materials',
                            'conditions',
                            'submission_channel',
                          }.contains(entry.key)
                        ? 300
                        : 500;
                    final rows = {'materials', 'conditions'}.contains(entry.key)
                        ? text.split('\n')
                        : [text];
                    return rows.length > 30 ||
                            rows.any((row) => row.length > limit)
                        ? '内容过长，请简化后保存'
                        : null;
                  },
                ),
              ),
            ],
          ),
        ),
      if (hasNotes)
        Padding(
          key: notesKey,
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              fieldHeading(
                '_notes',
                '其他说明',
                () => setState(() {
                  widget.notesController!.clear();
                  notesVisible = false;
                }),
              ),
              Semantics(
                label: '其他说明',
                child: AppFormField(
                  key: const Key('notice-other-notes'),
                  controller: widget.notesController,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 3000,
                  decoration: const InputDecoration(counterText: ''),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget fieldHeading(String key, String label, VoidCallback onRemove) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, color: CampusColors.muted),
        ),
      ),
      Tooltip(
        message: '移除$label',
        child: AppTextButton.icon(
          key: ValueKey('notice-remove-$key'),
          onPressed: onRemove,
          guardAsync: false,
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: const Text('移除'),
        ),
      ),
    ],
  );
}

class NoticeDetails extends StatelessWidget {
  final dynamic value;
  final String? location, title;
  const NoticeDetails(this.value, {super.key, this.location, this.title});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final row in noticeDetailRows(
        value,
        location: location,
        title: title,
      ))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${row.label}：',
                  style: const TextStyle(color: CampusColors.muted),
                ),
                TextSpan(
                  text: row.value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
    ],
  );
}
