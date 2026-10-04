import '../../ui/app_time_range_picker.dart';
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
  String? lastValidDraft;
  final controlsKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    rememberValidDraft();
    widget.controller.addListener(changed);
  }

  void rememberValidDraft() {
    if (validateSemesterPeriods(widget.controller.text) == null) {
      lastValidDraft = widget.controller.text;
    }
  }

  void changed() {
    rememberValidDraft();
    if (widget.fieldKey.currentState?.value == widget.controller.text) return;
    widget.fieldKey.currentState?.didChange(widget.controller.text);
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant PeriodEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(changed);
      lastValidDraft = null;
      rememberValidDraft();
      widget.controller.addListener(changed);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) changed();
      });
    }
  }

  // A temporary overlap or reversed end time still needs visible time buttons
  // so the user can fix it. Internal serialization is never shown as a field.
  List<Map<String, dynamic>> editablePeriods(String text) {
    final result = <Map<String, dynamic>>[];
    final seen = <int>{};
    final pattern = RegExp(
      r'^(\d{1,2})\s+((?:[01]\d|2[0-3]):[0-5]\d)\s+((?:[01]\d|2[0-3]):[0-5]\d)$',
    );
    for (final line in text.trim().split('\n')) {
      final match = pattern.firstMatch(line.trim());
      if (match == null) return [];
      final number = int.parse(match[1]!);
      if (number < 1 || number > 30 || !seen.add(number)) return [];
      result.add({'number': number, 'start': match[2]!, 'end': match[3]!});
    }
    if (result.length > 30) return [];
    return result
      ..sort((a, b) => (a['number'] as int).compareTo(b['number'] as int));
  }

  void recoverDraft() {
    FocusManager.instance.primaryFocus?.unfocus();
    widget.controller.text = lastValidDraft ?? '1 08:00 08:50';
    widget.fieldKey.currentState?.validate();
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
    // A picker route otherwise restores the last editable field on dismissal.
    // Time buttons must not reopen an unrelated keyboard after confirmation.
    FocusManager.instance.primaryFocus?.unfocus();
    final source = widget.controller;
    final number = periods[index]['number'];
    final latest = editablePeriods(source.text);
    final before = latest
        .where((period) => period['number'] == number)
        .firstOrNull;
    if (!widget.enabled || before == null) return;
    final value = await showAppClockRangePicker(
      context: context,
      initialStartMinutes: minuteOf(before['start'] as String),
      initialEndMinutes: minuteOf(before['end'] as String),
      title: '第$number节',
      allowEndOfDay: false,
    );
    if (value == null ||
        !mounted ||
        !widget.enabled ||
        source != widget.controller) {
      return;
    }
    final current = editablePeriods(source.text);
    final target = current.indexWhere((period) => period['number'] == number);
    if (target < 0) return;
    if (current[target]['start'] != before['start'] ||
        current[target]['end'] != before['end']) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这节时间已更新，请重新打开')));
      return;
    }
    current[target]['start'] = clockOf(value.startMinutes);
    current[target]['end'] = clockOf(value.endMinutes);
    widget.controller.text = current
        .map((r) => '${r['number']} ${r['start']} ${r['end']}')
        .join('\n');
    widget.fieldKey.currentState?.validate();
  }

  int minuteOf(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  String errorForPeriod(String error) {
    final lines = widget.controller.text.trim().split('\n');
    return error.replaceAllMapped(RegExp(r'第(\d+)行(?:的)?'), (match) {
      final line = int.parse(match[1]!) - 1;
      final number = line >= 0 && line < lines.length
          ? int.tryParse(lines[line].trim().split(RegExp(r'\s+')).first)
          : null;
      return number == null ? match[0]! : '第$number节';
    });
  }

  String clockOf(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  bool canAppend(List<Map<String, dynamic>> periods) {
    if (validateSemesterPeriods(widget.controller.text) != null ||
        periods.isEmpty ||
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

  Widget clockButton(
    List<Map<String, dynamic>> periods,
    int index,
    String field, {
    bool label = false,
  }) => Semantics(
    label: '第${periods[index]['number']}节${field == 'start' ? '开始' : '结束'}时间',
    child: AppTextButton(
      key: ValueKey('period-${periods[index]['number']}-$field'),
      onPressed: widget.enabled ? () => edit(periods, index, field) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: label
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    field == 'start' ? '开始' : '结束',
                    style: const TextStyle(
                      fontSize: 12,
                      color: CampusColors.muted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${periods[index][field]}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              )
            : Text(
                '${periods[index][field]}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
      ),
    ),
  );

  Widget periodRow(List<Map<String, dynamic>> periods, int index) =>
      LayoutBuilder(
        builder: (context, bounds) {
          final stacked =
              bounds.maxWidth < 420 &&
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          return Container(
            key: ValueKey('period-${periods[index]['number']}'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: CampusColors.line)),
            ),
            child: Row(
              crossAxisAlignment: stacked
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: stacked ? 14 : 0),
                  child: SizedBox(
                    width: 36 * MediaQuery.textScalerOf(context).scale(1),
                    child: Text(
                      '${periods[index]['number']}'.padLeft(2, '0'),
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 16,
                        color: CampusColors.muted,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            clockButton(periods, index, 'start', label: true),
                            clockButton(periods, index, 'end', label: true),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: clockButton(periods, index, 'start'),
                            ),
                            const Icon(
                              Icons.arrow_right_alt_rounded,
                              color: CampusColors.muted,
                              size: 20,
                            ),
                            Expanded(child: clockButton(periods, index, 'end')),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) => FormField<String>(
    key: widget.fieldKey,
    initialValue: widget.controller.text,
    enabled: widget.enabled,
    validator: validateSemesterPeriods,
    builder: (field) {
      List<Map<String, dynamic>> periods;
      try {
        periods = parseSemesterPeriods(widget.controller.text);
      } on FormatException {
        periods = editablePeriods(widget.controller.text);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (periods.isNotEmpty &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.3)
            const Padding(
              padding: EdgeInsets.only(left: 44, bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Text(
                        '开始',
                        style: TextStyle(
                          fontSize: 12,
                          color: CampusColors.muted,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 20),
                  Expanded(
                    child: Center(
                      child: Text(
                        '结束',
                        style: TextStyle(
                          fontSize: 12,
                          color: CampusColors.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (
            var i = 0;
            i < (expanded ? periods.length : periods.length.clamp(0, 4));
            i++
          )
            periodRow(periods, i),
          if (periods.length > 4)
            AppTextButton(
              onPressed: () => setState(() => expanded = !expanded),
              child: Text(expanded ? '收起节次' : '查看全部 ${periods.length} 节'),
            ),
          if (periods.isNotEmpty)
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
          if (periods.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '节次时间需要重新设置',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppOutlineButton(
                    onPressed: widget.enabled ? recoverDraft : null,
                    child: Text(lastValidDraft == null ? '重新设置节次' : '恢复作息'),
                  ),
                ],
              ),
            ),
          if (field.errorText != null && periods.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                errorForPeriod(field.errorText!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      );
    },
  );
}
