import 'package:flutter/material.dart';
import 'app_selection.dart';
import 'app_controls.dart';
import 'app_sheet.dart';
import 'clock_controls.dart';
import 'date_labels.dart';

enum AppDateTimeSection { date, time }

DateTime appSchoolToday() {
  final wall = DateTime.now().toUtc().add(const Duration(hours: 8));
  return DateTime.utc(wall.year, wall.month, wall.day);
}

/// Keep a saved date editable even when it predates the picker defaults.
/// The bounds never rewrite the selected value.
DateTimeRange appDatePickerBounds({
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  final initial = _dateWall(initialDate);
  final first = _dateWall(firstDate);
  final last = _dateWall(lastDate);
  return DateTimeRange(
    start: initial.isBefore(first) ? initial : first,
    end: initial.isAfter(last) ? initial : last,
  );
}

/// Initial and returned values are school wall-clock fields. UTC is only a
/// DST-free container here; callers retain their existing +08 serialization.
Future<DateTime?> showAppDateTimePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
  AppDateTimeSection initialSection = AppDateTimeSection.date,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showAppSheet<DateTime>(
    context: context,
    swipeDismissible: false,
    builder: (_) => _DateTimeSheet(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: helpText,
      initialSection: initialSection,
    ),
  );
}

class _DateTimeSheet extends StatefulWidget {
  final DateTime initialDate, firstDate, lastDate;
  final String? helpText;
  final AppDateTimeSection initialSection;
  const _DateTimeSheet({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.helpText,
    required this.initialSection,
  });
  @override
  State<_DateTimeSheet> createState() => _DateTimeSheetState();
}

class _DateTimeSheetState extends State<_DateTimeSheet> {
  late DateTime _value = _wall(widget.initialDate);
  void confirm() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, _value);
  }

  @override
  Widget build(BuildContext context) => AppTimeSheetLayout(
    heading: AppSheetHeading(title: widget.helpText ?? '选择日期和时间'),
    body: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: AppDateTimeSelection(
        value: _value,
        firstDate: widget.firstDate,
        lastDate: widget.lastDate,
        initialSection: widget.initialSection,
        onChanged: (value) => setState(() {
          _value = value;
        }),
      ),
    ),
    footer: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: AppButton(
        key: const Key('date-time-confirm'),
        onPressed: confirm,
        child: const Text('确定'),
      ),
    ),
  );
}

DateTime _wall(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day, value.hour, value.minute);
DateTime _dateWall(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
bool _sameParts(DateTime a, DateTime b) =>
    a.year == b.year &&
    a.month == b.month &&
    a.day == b.day &&
    a.hour == b.hour &&
    a.minute == b.minute;

/// A date/calendar switch and one precise clock, sharing one confirmation.
class AppDateTimeSelection extends StatefulWidget {
  final DateTime value, firstDate, lastDate;
  final ValueChanged<DateTime> onChanged;
  final AppDateTimeSection initialSection;
  const AppDateTimeSelection({
    super.key,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    this.initialSection = AppDateTimeSection.date,
  });
  @override
  State<AppDateTimeSelection> createState() => _AppDateTimeSelectionState();
}

class _AppDateTimeSelectionState extends State<AppDateTimeSelection> {
  late DateTime _date = _dateWall(widget.value);
  late TimeOfDay _clock = TimeOfDay.fromDateTime(widget.value);
  late AppDateTimeSection _section = widget.initialSection;
  DateTime get result => DateTime.utc(
    _date.year,
    _date.month,
    _date.day,
    _clock.hour,
    _clock.minute,
  );
  @override
  void didUpdateWidget(covariant AppDateTimeSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameParts(widget.value, oldWidget.value)) {
      _date = _dateWall(widget.value);
      _clock = TimeOfDay.fromDateTime(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bounds = appDatePickerBounds(
      initialDate: _date,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSegmentedControl<AppDateTimeSection>(
          value: _section,
          options: {
            AppDateTimeSection.date: _section == AppDateTimeSection.time
                ? studentDate(_date)
                : '日期',
            AppDateTimeSection.time: _section == AppDateTimeSection.date
                ? appClockText(_clock)
                : '时间',
          },
          onChanged: (value) => setState(() => _section = value),
        ),
        const SizedBox(height: 12),
        if (_section == AppDateTimeSection.date)
          LayoutBuilder(
            builder: (context, constraints) =>
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: (constraints.maxWidth / 280).clamp(1.0, 1.3),
                  child: CalendarDatePicker(
                    key: const Key('date-time-calendar'),
                    initialDate: _date,
                    currentDate: appSchoolToday(),
                    firstDate: bounds.start,
                    lastDate: bounds.end,
                    onDateChanged: (value) {
                      setState(() {
                        _date = _dateWall(value);
                        _section = AppDateTimeSection.time;
                      });
                      widget.onChanged(result);
                    },
                  ),
                ),
          )
        else
          Align(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: AppClockWheel(
                value: _clock,
                onChanged: (value) {
                  setState(() => _clock = value);
                  widget.onChanged(result);
                },
              ),
            ),
          ),
      ],
    );
  }
}
