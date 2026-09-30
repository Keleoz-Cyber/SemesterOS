import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import 'semester_validation.dart';

class PeriodEditor extends StatefulWidget {
  final TextEditingController controller;
  final GlobalKey<FormFieldState<String>> fieldKey;
  final bool enabled;
  const PeriodEditor({
    super.key,
    required this.controller,
    required this.fieldKey,
    required this.enabled,
  });
  @override
  State<PeriodEditor> createState() => _PeriodEditorState();
}

class _PeriodEditorState extends State<PeriodEditor> {
  bool expanded = false;
  final controlsKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
  }

  void changed() {
    widget.fieldKey.currentState?.didChange(widget.controller.text);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    super.dispose();
  }

  Future<void> edit(
    List<Map<String, dynamic>> periods,
    int index,
    String field,
  ) async {
    final old = (periods[index][field] as String).split(':');
    final value = await showTimePicker(
      context: context,
      initialEntryMode: MediaQuery.textScalerOf(context).scale(1) > 1.3
          ? TimePickerEntryMode.inputOnly
          : TimePickerEntryMode.dial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
      initialTime: TimeOfDay(
        hour: int.parse(old[0]),
        minute: int.parse(old[1]),
      ),
      helpText:
          '第${periods[index]['number']}节${field == 'start' ? '开始' : '结束'}时间',
    );
    if (value == null || !mounted) return;
    periods[index][field] =
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    widget.controller.text = periods
        .map((r) => '${r['number']} ${r['start']} ${r['end']}')
        .join('\n');
    widget.fieldKey.currentState?.validate();
  }

  int minuteOf(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  String clockOf(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  bool canAppend(List<Map<String, dynamic>> periods) {
    if (periods.isEmpty ||
        periods.length >= 30 ||
        periods.last['number'] as int >= 30) {
      return false;
    }
    final last = periods.last;
    final start = minuteOf(last['start'] as String);
    final end = minuteOf(last['end'] as String);
    return end + 10 + end - start <= 23 * 60 + 59;
  }

  void write(List<Map<String, dynamic>> periods) {
    widget.controller.text = periods
        .map((p) => '${p['number']} ${p['start']} ${p['end']}')
        .join('\n');
    widget.fieldKey.currentState?.validate();
  }

  void append(List<Map<String, dynamic>> periods) {
    if (!canAppend(periods)) return;
    final last = periods.last;
    final start = minuteOf(last['start'] as String);
    final end = minuteOf(last['end'] as String);
    final number = (last['number'] as int) + 1;
    setState(() => expanded = true);
    write([
      ...periods,
      {
        'number': number,
        'start': clockOf(end + 10),
        'end': clockOf(end + 10 + end - start),
      },
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controlsKey.currentContext != null) {
        Scrollable.ensureVisible(
          controlsKey.currentContext!,
          duration: const Duration(milliseconds: 220),
          alignment: .85,
        );
      }
    });
  }

  void removeLast(List<Map<String, dynamic>> periods) {
    if (periods.length <= 1) return;
    write(periods.sublist(0, periods.length - 1));
  }

  @override
  Widget build(BuildContext context) => FormField<String>(
    key: widget.fieldKey,
    initialValue: widget.controller.text,
    enabled: widget.enabled,
    validator: validateSemesterPeriods,
    builder: (field) {
      List<Map<String, dynamic>> periods = [];
      try {
        periods = parseSemesterPeriods(widget.controller.text);
      } on FormatException {
        /* Raw editing remains available for invalid drafts. */
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (
            var i = 0;
            i < (expanded ? periods.length : periods.length.clamp(0, 4));
            i++
          )
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: CampusColors.blueSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${periods[i]['number']}',
                      style: const TextStyle(
                        color: CampusColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppTextButton(
                      onPressed: widget.enabled
                          ? () => edit(periods, i, 'start')
                          : null,
                      child: Text(
                        periods[i]['start'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const Text('至', style: TextStyle(color: CampusColors.muted)),
                  Expanded(
                    child: AppTextButton(
                      onPressed: widget.enabled
                          ? () => edit(periods, i, 'end')
                          : null,
                      child: Text(
                        periods[i]['end'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (periods.length > 4)
            AppTextButton(
              onPressed: () => setState(() => expanded = !expanded),
              child: Text(expanded ? '收起节次' : '查看全部 ${periods.length} 节'),
            ),
          Padding(
            key: controlsKey,
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIconButton.outlined(
                  onPressed: widget.enabled && canAppend(periods)
                      ? () => append(periods)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: '添加一节',
                ),
                const SizedBox(width: 12),
                AppIconButton.outlined(
                  onPressed: widget.enabled && periods.length > 1
                      ? () => removeLast(periods)
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                  tooltip: '减少一节',
                ),
              ],
            ),
          ),
          if (field.errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                field.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          AppDisclosure(
            key: ValueKey(periods.isEmpty),
            initiallyExpanded: periods.isEmpty,
            maintainState: true,
            tilePadding: EdgeInsets.zero,
            title: const Text('批量编辑节次'),
            childrenPadding: const EdgeInsets.only(top: 12),
            children: [
              AppField(
                controller: widget.controller,
                enabled: widget.enabled,
                minLines: 4,
                maxLines: 12,
                decoration: const InputDecoration(
                  labelText: '节次与时间（示例，可修改）',
                  helperText: '每行：节次 开始时间 结束时间',
                  helperMaxLines: 2,
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}
