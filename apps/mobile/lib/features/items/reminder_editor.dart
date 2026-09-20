import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_widgets.dart';

Future<Map<String, dynamic>?> editReminder(
  BuildContext context, {
  required String kind,
  Map<String, dynamic>? initial,
}) => showModalBottomSheet<Map<String, dynamic>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => ReminderEditor(kind: kind, initial: initial),
);

class ReminderEditor extends StatefulWidget {
  final String kind;
  final Map<String, dynamic>? initial;
  const ReminderEditor({super.key, required this.kind, this.initial});
  @override
  State<ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<ReminderEditor> {
  late String mode, purpose;
  late bool enabled;
  late final TextEditingController lead;
  DateTime? date;
  TimeOfDay? clock;
  String? error;
  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    mode = r?['mode'] ?? 'relative';
    purpose = r?['purpose'] ?? 'item';
    enabled = r?['enabled'] ?? true;
    lead = TextEditingController(text: '${r?['lead_minutes'] ?? 1440}');
    if (mode == 'absolute' && r?['trigger_at'] != null) {
      final local = schoolTime(r!['trigger_at']);
      date = DateTime(local.year, local.month, local.day);
      clock = TimeOfDay(hour: local.hour, minute: local.minute);
    }
  }

  @override
  void dispose() {
    lead.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final now = schoolNow();
    final day = await showDatePicker(
      context: context,
      initialDate: date ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: clock ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (time != null && mounted) {
      setState(() {
        date = day;
        clock = time;
      });
    }
  }

  void save() {
    final minutes = int.tryParse(lead.text);
    if (mode == 'relative' &&
        (minutes == null || minutes < 0 || minutes > 525600)) {
      setState(() => error = '请填写有效的提前分钟数');
      return;
    }
    if (mode == 'absolute' && (date == null || clock == null)) {
      setState(() => error = '请明确选择提醒日期和时间');
      return;
    }
    if (purpose == 'check_notice' && mode != 'absolute') {
      setState(() => error = '核实通知请使用指定时刻');
      return;
    }
    final at = mode == 'absolute'
        ? '${date!.toIso8601String().substring(0, 10)}T${clock!.hour.toString().padLeft(2, '0')}:${clock!.minute.toString().padLeft(2, '0')}:00+08:00'
        : null;
    if (enabled && at != null && !DateTime.parse(at).isAfter(DateTime.now())) {
      setState(() => error = '提醒时刻已过去，请重新选择');
      return;
    }
    Navigator.pop(context, {
      'mode': mode,
      'lead_minutes': mode == 'relative' ? minutes : null,
      'trigger_at': at,
      'purpose': purpose,
      'enabled': enabled,
      if (widget.initial?['version'] != null)
        'expected_version': widget.initial!['version'],
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      22,
      0,
      22,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.initial == null ? '添加提醒' : '修改提醒',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'relative', label: Text('提前提醒')),
            ButtonSegment(value: 'absolute', label: Text('指定时刻')),
          ],
          selected: {mode},
          onSelectionChanged: (s) => setState(() => mode = s.first),
        ),
        const SizedBox(height: 16),
        if (mode == 'relative') ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final minutes in [
                if (widget.kind == 'exam') ...[20160, 10080],
                1440,
                120,
              ])
                ActionChip(
                  label: Text(
                    minutes == 20160
                        ? '14天 · 开始复习'
                        : '${minutes >= 1440 ? '${minutes ~/ 1440}天' : '2小时'}前',
                  ),
                  onPressed: () => setState(() {
                    lead.text = '$minutes';
                    if (minutes == 20160) purpose = 'start_review';
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: lead,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '提前多少分钟'),
          ),
          const SizedBox(height: 12),
          const SoftNotice('提前1天就是提前24小时。如果还不知道事项的具体时间，可以直接指定提醒日期和时刻。'),
        ] else
          OutlinedButton.icon(
            onPressed: pick,
            icon: const Icon(Icons.event_outlined),
            label: Text(
              date == null
                  ? '选择提醒日期和时间（北京时间）'
                  : '${date!.toIso8601String().substring(0, 10)} ${clock!.format(context)}',
            ),
          ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: purpose,
          key: ValueKey(purpose),
          isExpanded: true,
          decoration: const InputDecoration(labelText: '提醒用途'),
          items: const [
            DropdownMenuItem(value: 'item', child: Text('事项提醒')),
            DropdownMenuItem(value: 'start_review', child: Text('开始复习')),
            DropdownMenuItem(value: 'check_notice', child: Text('核实正式通知')),
          ],
          onChanged: (v) => setState(() => purpose = v!),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('启用这条提醒'),
          value: enabled,
          onChanged: (v) => setState(() => enabled = v),
        ),
        if (error != null) ...[
          SoftNotice(error!, warning: true),
          const SizedBox(height: 12),
        ],
        FilledButton(onPressed: save, child: const Text('确认这条提醒')),
        const SizedBox(height: 8),
        const Text(
          '保存后，请开启系统通知。手机省电设置可能让提醒延迟。',
          style: TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}
