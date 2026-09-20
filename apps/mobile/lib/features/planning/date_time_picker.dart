import 'package:flutter/material.dart';
import '../../app/controller.dart';

Future<DateTime?> pickSchoolDateTime(
  BuildContext context, {
  DateTime? initial,
}) async {
  final local = initial == null
      ? schoolNow()
      : schoolTime(initial.toIso8601String());
  final date = await showDatePicker(
    context: context,
    initialDate: DateTime(local.year, local.month, local.day),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: local.hour, minute: local.minute),
  );
  if (time == null) return null;
  return DateTime.parse(
    '${date.toIso8601String().substring(0, 10)}T${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00+08:00',
  );
}
