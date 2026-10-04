import '../../ui/app_date_time_picker.dart';
import '../../ui/app_time_range_picker.dart';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
export '../../ui/app_time_range_picker.dart' show AppDateTimeRange;

DateTime _schoolWall(DateTime? initial) {
  final local = initial == null
      ? schoolNow()
      : schoolTime(initial.toIso8601String());
  // UTC is a timezone-neutral container for school wall-clock fields. Only
  // _schoolInstant converts these fields into an actual UTC instant.
  return DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
  );
}

DateTime _schoolInstant(DateTime wall) => DateTime.utc(
  wall.year,
  wall.month,
  wall.day,
  wall.hour,
  wall.minute,
).subtract(const Duration(hours: 8));

Future<DateTime?> pickSchoolDateTime(
  BuildContext context, {
  DateTime? initial,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final selected = await showAppDateTimePicker(
    context: context,
    initialDate: _schoolWall(initial),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  return selected == null ? null : _schoolInstant(selected);
}

Future<AppDateTimeRange?> pickSchoolDateTimeRange(
  BuildContext context, {
  DateTime? initialStart,
  DateTime? initialEnd,
  String title = '设置起止时间',
  bool initiallyEditingEnd = false,
  String? initialLabel,
  bool showLabel = false,
}) async {
  final start = _schoolWall(initialStart);
  final selected = await showAppDateTimeRangePicker(
    context: context,
    initialStart: start,
    initialEnd: initialEnd == null
        ? start.add(const Duration(hours: 1))
        : _schoolWall(initialEnd),
    title: title,
    initiallyEditingEnd: initiallyEditingEnd,
    initialLabel: initialLabel,
    showLabel: showLabel,
  );
  if (selected == null || !context.mounted) return null;
  return AppDateTimeRange(
    start: _schoolInstant(selected.start),
    end: _schoolInstant(selected.end),
    label: selected.label,
  );
}
