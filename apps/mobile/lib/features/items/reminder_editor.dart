import '../../ui/app_date_time_picker.dart';
import '../../ui/app_selection.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_picker_field.dart';
import '../../ui/app_sheet.dart';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/date_labels.dart';

bool reminderHasReferenceTime(String kind, Map<String, dynamic> time) {
  if (const {
    'window',
    'candidate',
    'course_anchor',
  }.contains(time['meaning'])) {
    return false;
  }
  return (time['precision'] == 'exact' && time['at'] != null) ||
      (time['precision'] == 'date' &&
          time['day_end_confirmed'] == true &&
          kind != 'exam');
}

Future<Map<String, dynamic>?> editReminder(
  BuildContext context, {
  required String kind,
  Map<String, dynamic>? initial,
  bool relativeOnly = false,
  bool hasReferenceTime = true,
}) => showAppSheet<Map<String, dynamic>>(
  context: context,
  builder: (_) => ReminderEditor(
    kind: kind,
    initial: initial,
    relativeOnly: relativeOnly,
    hasReferenceTime: hasReferenceTime,
  ),
);

class ReminderEditor extends StatefulWidget {
  final String kind;
  final bool relativeOnly;
  final bool hasReferenceTime;
  final Map<String, dynamic>? initial;
  const ReminderEditor({
    super.key,
    required this.kind,
    this.initial,
    this.relativeOnly = false,
    this.hasReferenceTime = true,
  });
  @override
  State<ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<ReminderEditor> {
  late String mode, purpose;
  late bool enabled;
  late bool customLead;
  late final TextEditingController lead;
  DateTime? date;
  TimeOfDay? clock;
  String? error;
  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    mode = widget.relativeOnly
        ? 'relative'
        : r?['mode'] ?? (widget.hasReferenceTime ? 'relative' : 'absolute');
    purpose = widget.relativeOnly ? 'item' : r?['purpose'] ?? 'item';
    enabled = widget.relativeOnly ? true : r?['enabled'] ?? true;
    lead = TextEditingController(
      text: '${r?['lead_minutes'] ?? (widget.kind == 'event' ? 30 : 1440)}',
    );
    customLead = !presets.contains(int.tryParse(lead.text));
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
    final day = date ?? DateTime(now.year, now.month, now.day);
    final time = clock ?? const TimeOfDay(hour: 9, minute: 0);
    final selected = await showAppDateTimePicker(
      context: context,
      initialDate: DateTime.utc(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '提醒日期和时间',
      initialSection: date == null
          ? AppDateTimeSection.date
          : AppDateTimeSection.time,
    );
    if (selected != null && mounted) {
      setState(() {
        date = DateUtils.dateOnly(selected);
        clock = TimeOfDay.fromDateTime(selected);
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

  List<int> get presets => widget.kind == 'event'
      ? [0, 15, 30, 60, 1440]
      : [
          if (widget.kind == 'exam') ...[20160, 10080],
          1440,
          120,
        ];

  String leadLabel(int minutes) => minutes == 0
      ? '到时间时'
      : minutes % 1440 == 0
      ? '提前${minutes ~/ 1440}天'
      : minutes % 60 == 0
      ? '提前${minutes ~/ 60}小时'
      : '提前$minutes分钟';

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetHeading(
          title: widget.initial == null ? '添加提醒' : '修改提醒',
          leading: const Icon(Icons.notifications_active_outlined),
          padding: EdgeInsets.zero,
        ),
        if (!widget.relativeOnly &&
            (widget.hasReferenceTime ||
                widget.initial?['mode'] == 'relative')) ...[
          AppSegmentedControl<String>(
            value: mode,
            options: const {'relative': '提前提醒', 'absolute': '指定时刻'},
            onChanged: (value) => setState(() => mode = value),
          ),
          const SizedBox(height: 16),
        ],
        EditorSection(
          title: mode == 'relative' ? '提前多久' : '提醒时刻',
          icon: Icons.schedule_rounded,
          children: [
            if (mode == 'relative') ...[
              AppPickerField<int>(
                key: ValueKey('lead-$customLead-${lead.text}'),
                initialValue: customLead ? -1 : int.tryParse(lead.text),
                isExpanded: true,
                decoration: const InputDecoration(labelText: '提醒时间'),
                items: [
                  for (final minutes in presets)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(leadLabel(minutes)),
                    ),
                  const DropdownMenuItem(value: -1, child: Text('自定义')),
                ],
                onChanged: (value) => setState(() {
                  customLead = value == -1;
                  lead.text = value == -1 ? '' : '$value';
                }),
              ),
              if (customLead) ...[
                const SizedBox(height: 16),
                AppField(
                  controller: lead,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => save(),
                  decoration: const InputDecoration(
                    labelText: '提前多久',
                    suffixText: '分钟',
                  ),
                ),
              ],
            ] else
              AppOutlineButton.icon(
                onPressed: pick,
                guardAsync: false,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  date == null
                      ? '选择提醒日期和时间'
                      : '${studentDate(date!, weekday: true)} ${clock!.hour.toString().padLeft(2, '0')}:${clock!.minute.toString().padLeft(2, '0')}',
                ),
              ),
          ],
        ),
        if (!widget.relativeOnly)
          AppDisclosure(
            title: const Text('更多设置'),
            initiallyExpanded: purpose != 'item' || !enabled,
            childrenPadding: const EdgeInsets.only(top: 12),
            children: [
              AppPickerField<String>(
                initialValue: purpose,
                key: ValueKey(purpose),
                isExpanded: true,
                decoration: const InputDecoration(labelText: '提醒用途'),
                items: const [
                  DropdownMenuItem(value: 'item', child: Text('事项提醒')),
                  DropdownMenuItem(value: 'start_review', child: Text('开始复习')),
                  DropdownMenuItem(
                    value: 'check_notice',
                    child: Text('核实正式通知'),
                  ),
                ],
                onChanged: (v) => setState(() => purpose = v!),
              ),
              AppSwitchRow(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用这条提醒'),
                value: enabled,
                onChanged: (v) => setState(() => enabled = v),
              ),
            ],
          ),
        if (error != null) ...[
          SoftNotice(error!, warning: true),
          const SizedBox(height: 12),
        ],
        AppButton(onPressed: save, child: const Text('确认这条提醒')),
      ],
    ),
  );
}
