import 'package:flutter/material.dart';
import 'app_controls.dart';
import 'app_date_time_picker.dart';
import 'app_sheet.dart';
import 'campus_theme.dart';
import 'clock_controls.dart';
import 'date_labels.dart';

@immutable
class AppClockRange {
  final int startMinutes, endMinutes;
  const AppClockRange({required this.startMinutes, required this.endMinutes});
  int get durationMinutes => endMinutes - startMinutes;
  String get startText => _minuteText(startMinutes);
  String get endText => _minuteText(endMinutes);
}

@immutable
class AppDateTimeRange {
  /// Public values are wall-clock fields; school wrappers convert explicitly.
  final DateTime start, end;
  final String label;
  const AppDateTimeRange({
    required this.start,
    required this.end,
    this.label = '',
  });
}

String _minuteText(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
DateTime _wall(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day, value.hour, value.minute);

Future<AppClockRange?> showAppClockRangePicker({
  required BuildContext context,
  required int initialStartMinutes,
  required int initialEndMinutes,
  String title = '设置时间段',
  bool allowEndOfDay = false,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showAppSheet<AppClockRange>(
    context: context,
    swipeDismissible: false,
    builder: (_) => AppClockRangePicker(
      key: const ValueKey('app-clock-range-picker'),
      initialStartMinutes: initialStartMinutes,
      initialEndMinutes: initialEndMinutes,
      title: title,
      allowEndOfDay: allowEndOfDay,
    ),
  );
}

class AppClockRangePicker extends StatefulWidget {
  final int initialStartMinutes, initialEndMinutes;
  final String title;
  final bool allowEndOfDay;
  const AppClockRangePicker({
    super.key,
    required this.initialStartMinutes,
    required this.initialEndMinutes,
    this.title = '设置时间段',
    this.allowEndOfDay = false,
  });
  @override
  State<AppClockRangePicker> createState() => _AppClockRangePickerState();
}

class _AppClockRangePickerState extends State<AppClockRangePicker> {
  late int start = widget.initialStartMinutes, end = widget.initialEndMinutes;
  bool showError = false;
  void confirm() {
    if (start < 0 ||
        start >= 1440 ||
        end <= start ||
        end > (widget.allowEndOfDay ? 1440 : 1439)) {
      setState(() => showError = true);
      return;
    }
    Navigator.pop(context, AppClockRange(startMinutes: start, endMinutes: end));
  }

  @override
  Widget build(BuildContext context) => AppTimeSheetLayout(
    heading: AppSheetHeading(title: widget.title),
    body: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _ClockPair(
            start: start,
            end: end,
            allowEndOfDay: widget.allowEndOfDay,
            onChanged: (ending, value) => setState(() {
              if (ending) {
                end = value;
              } else {
                start = value;
              }
              showError = false;
            }),
          ),
        ),
        if (showError) const _RangeError(),
      ],
    ),
    footer: Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: AppButton(
        key: const Key('clock-range-confirm'),
        onPressed: confirm,
        child: const Text('确定'),
      ),
    ),
  );
}

Future<AppDateTimeRange?> showAppDateTimeRangePicker({
  required BuildContext context,
  DateTime? initialStart,
  DateTime? initialEnd,
  String title = '设置起止时间',
  bool initiallyEditingEnd = false,
  String? initialLabel,
  bool showLabel = false,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  final start = _wall(initialStart ?? DateTime.now());
  return showAppSheet<AppDateTimeRange>(
    context: context,
    swipeDismissible: false,
    builder: (_) => AppDateTimeRangePicker(
      key: const ValueKey('app-date-time-range-picker'),
      initialStart: start,
      initialEnd: _wall(initialEnd ?? start.add(const Duration(hours: 1))),
      title: title,
      initiallyEditingEnd: initiallyEditingEnd,
      initialLabel: initialLabel ?? '',
      showLabel: showLabel,
    ),
  );
}

class AppDateTimeRangePicker extends StatefulWidget {
  final DateTime initialStart, initialEnd;
  final String title, initialLabel;
  final bool initiallyEditingEnd, showLabel;
  const AppDateTimeRangePicker({
    super.key,
    required this.initialStart,
    required this.initialEnd,
    this.title = '设置起止时间',
    this.initiallyEditingEnd = false,
    this.initialLabel = '',
    this.showLabel = false,
  });
  @override
  State<AppDateTimeRangePicker> createState() => _AppDateTimeRangePickerState();
}

class _AppDateTimeRangePickerState extends State<AppDateTimeRangePicker> {
  late DateTime start = _wall(widget.initialStart),
      end = _wall(widget.initialEnd);
  late bool ending = widget.initiallyEditingEnd;
  bool calendar = false, showError = false;
  late final label = TextEditingController(text: widget.initialLabel);
  @override
  void dispose() {
    label.dispose();
    super.dispose();
  }

  void confirm() {
    if (!end.isAfter(start)) {
      setState(() => showError = true);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(
      context,
      AppDateTimeRange(start: start, end: end, label: label.text.trim()),
    );
  }

  Widget dateAction(bool edge) {
    final value = edge ? end : start;
    final selected = calendar && ending == edge;
    return Semantics(
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? CampusColors.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
        ),
        child: AppTextButton(
          key: ValueKey('range-date-${edge ? 'end' : 'start'}'),
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() {
              ending = edge;
              calendar = true;
            });
          },
          style: selected
              ? AppTextButton.styleFrom(backgroundColor: CampusColors.blueSoft)
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(studentDate(value), textAlign: TextAlign.center),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.expand_more_rounded, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final earliest = start.isBefore(end) ? start : end;
    final latest = start.isAfter(end) ? start : end;
    return AppTimeSheetLayout(
      heading: AppSheetHeading(
        title: widget.title,
        trailing: calendar
            ? AppTextButton(
                key: const Key('range-show-clock'),
                onPressed: () => setState(() => calendar = false),
                child: const Text('时间'),
              )
            : null,
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (calendar) ...[
                  Row(
                    children: [
                      for (final edge in [false, true]) ...[
                        if (edge) const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _EndpointLabel(ending: edge),
                              dateAction(edge),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) =>
                        MediaQuery.withClampedTextScaling(
                          maxScaleFactor: (constraints.maxWidth / 280).clamp(
                            1.0,
                            1.3,
                          ),
                          child: CalendarDatePicker(
                            key: ValueKey(
                              'range-calendar-${ending ? 'end' : 'start'}',
                            ),
                            initialDate: DateUtils.dateOnly(
                              ending ? end : start,
                            ),
                            currentDate: appSchoolToday(),
                            firstDate: earliest.year < 2000
                                ? DateUtils.dateOnly(earliest)
                                : DateTime(2000),
                            lastDate: latest.year > 2100
                                ? DateUtils.dateOnly(latest)
                                : DateTime(2100, 12, 31),
                            onDateChanged: (date) => setState(() {
                              final value = ending ? end : start;
                              final next = DateTime.utc(
                                date.year,
                                date.month,
                                date.day,
                                value.hour,
                                value.minute,
                              );
                              if (ending) {
                                end = next;
                              } else {
                                start = next;
                              }
                              calendar = false;
                              showError = false;
                            }),
                          ),
                        ),
                  ),
                ] else
                  _ClockPair(
                    start: start.hour * 60 + start.minute,
                    end: end.hour * 60 + end.minute,
                    startDate: dateAction(false),
                    endDate: dateAction(true),
                    onChanged: (edge, minute) => setState(() {
                      final value = edge ? end : start;
                      final next = DateTime.utc(
                        value.year,
                        value.month,
                        value.day,
                        minute ~/ 60,
                        minute % 60,
                      );
                      if (edge) {
                        end = next;
                      } else {
                        start = next;
                      }
                      showError = false;
                    }),
                  ),
                if (widget.showLabel) ...[
                  const SizedBox(height: 16),
                  AppField(
                    key: const Key('date-time-range-label'),
                    controller: label,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: '这段时间做什么（选填）',
                      counterText: '',
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showError) const _RangeError(),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: AppButton(
          key: const Key('date-time-range-confirm'),
          onPressed: confirm,
          child: const Text('确定'),
        ),
      ),
    );
  }
}

class _EndpointLabel extends StatelessWidget {
  final bool ending;
  const _EndpointLabel({required this.ending});
  @override
  Widget build(BuildContext context) => Text(
    ending ? '结束' : '开始',
    style: const TextStyle(fontSize: 13, color: CampusColors.muted),
  );
}

class _ClockPair extends StatelessWidget {
  final int start, end;
  final bool allowEndOfDay;
  final Widget? startDate, endDate;
  final void Function(bool ending, int value) onChanged;
  const _ClockPair({
    required this.start,
    required this.end,
    required this.onChanged,
    this.allowEndOfDay = false,
    this.startDate,
    this.endDate,
  });
  Widget endpoint(bool ending) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _EndpointLabel(ending: ending),
      if ((ending ? endDate : startDate) != null)
        (ending ? endDate : startDate)!
      else
        const SizedBox(height: 8),
      Align(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: AppMinuteWheel(
            key: ValueKey('range-clock-${ending ? 'end' : 'start'}'),
            label: ending ? '结束' : '开始',
            value: ending ? end : start,
            allowEndOfDay: ending && allowEndOfDay,
            onChanged: (value) => onChanged(ending, value),
          ),
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final stack =
          bounds.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.4;
      if (stack) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            endpoint(false),
            const SizedBox(height: 16),
            endpoint(true),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: endpoint(false)),
          const SizedBox(width: 20),
          Expanded(child: endpoint(true)),
        ],
      );
    },
  );
}

class _RangeError extends StatelessWidget {
  const _RangeError();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: Text('结束时间需要晚于开始时间', style: TextStyle(color: CampusColors.error)),
  );
}
