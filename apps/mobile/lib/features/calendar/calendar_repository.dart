import 'package:flutter/foundation.dart';
import '../../core/api.dart';
import '../../core/cache.dart';
import '../../app/controller.dart';
import '../../ui/date_labels.dart';

String calendarDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

Map<String, dynamic> calendarTime(Map<String, dynamic> row) =>
    row['time'] is Map ? Map<String, dynamic>.from(row['time']) : const {};

String? calendarMeaning(Map<String, dynamic> row) =>
    row['meaning'] ?? calendarTime(row)['meaning'];

bool calendarReservesTime(Map<String, dynamic> row) =>
    row['attendance_status'] != 'leave' &&
    row['attendance_exempt'] != true &&
    row['reserve_time'] != false &&
    calendarMeaning(row) != 'window';

bool _calendarIsCourseOccurrence(Map<String, dynamic> row) {
  final resource = row['resource_type'];
  if (resource != null) return resource == 'course';
  final reality = row['reality_kind'];
  if (reality != null) return reality == 'course';
  // Older timetable rows lack the projection's resource discriminator.
  // A course association alone also appears on exams and tasks.
  return row['course_id'] is String &&
      (row['course_id'] as String).isNotEmpty &&
      row['weekday'] is int &&
      row['weeks'] is List &&
      row['sections'] is List;
}

/// Current arrangements omit an excused occurrence; source records remain
/// available in course details and change receipts for restoring attendance.
List<Map<String, dynamic>> calendarScheduleEntries(
  Iterable<Map<String, dynamic>> entries,
) => entries
    .where(
      (row) =>
          !_calendarIsCourseOccurrence(row) ||
          row['attendance_status'] != 'leave',
    )
    .map(calendarDisplayEntry)
    .toList();

Map<String, dynamic> calendarDisplayEntry(Map<String, dynamic> row) {
  final time = calendarTime(row);
  return {
    ...row,
    if ({'leave', 'plan_leave'}.contains(row['attendance_status']) &&
        !'${row['title'] ?? ''}'.startsWith(
          '${row['attendance_status'] == 'leave' ? '已请假' : '待请假'} · ',
        ))
      'title':
          '${row['attendance_status'] == 'leave' ? '已请假' : '待请假'} · ${row['title'] ?? ''}',
    if (row['attendance_exempt'] == true &&
        !'${row['title'] ?? ''}'.contains('免听'))
      'title': '免听 · ${row['title'] ?? ''}',
    if (row['start_at'] == null &&
        calendarMeaning(row) == 'start' &&
        time['at'] != null)
      'start_at': time['at'],
    if (row['time_precision'] == null && time['precision'] != null)
      'time_precision': time['precision'],
    if (row['date'] == null && time['date'] != null) 'date': time['date'],
    if (row['end_date'] == null && time['end_date'] != null)
      'end_date': time['end_date'],
    if (row['week'] == null && time['week'] != null) 'week': time['week'],
  };
}

String calendarParticipationLabel(Map<String, dynamic> row) {
  if (row['attendance_status'] == 'leave') return '已请假';
  if (row['attendance_status'] == 'plan_leave') return '待请假';
  if (row['attendance_exempt'] == true) {
    return '${row['title'] ?? ''}'.contains('免听') ? '' : '免听';
  }
  if (row['reserve_time'] != false) return '';
  final details = row['details'];
  return details is Map && details['participation_status'] == 'optional'
      ? '可选'
      : '参考';
}

String calendarArrivalLabel(Map<String, dynamic> row) {
  if (row['arrival_at'] == null) return '';
  final arrival = schoolTime(row['arrival_at']);
  return '${hhmm(arrival)}到场';
}

/// Split only the visual projection; the original interval stays on the server.
List<Map<String, dynamic>> calendarGridEntries(
  List<Map<String, dynamic>> entries,
  DateTime firstDay,
) {
  final result = <Map<String, dynamic>>[];
  for (final entry in calendarScheduleEntries(entries)) {
    if (entry['start_at'] == null ||
        entry['end_at'] == null ||
        calendarMeaning(entry) == 'window' ||
        !calendarReservesTime(entry)) {
      continue;
    }
    final start = DateTime.parse(
      entry['occupancy_start_at'] ?? entry['start_at'],
    ).toUtc();
    final end = DateTime.parse(entry['end_at']).toUtc();
    for (var day = 0; day < 7; day++) {
      final local = firstDay.add(Duration(days: day));
      final begin = DateTime.utc(
        local.year,
        local.month,
        local.day,
      ).subtract(const Duration(hours: 8));
      final until = begin.add(const Duration(days: 1));
      if (!start.isBefore(until) || !end.isAfter(begin)) continue;
      final a = start.isAfter(begin) ? start : begin;
      final b = end.isBefore(until) ? end : until;
      result.add({
        ...entry,
        'id': '${entry['id']}/${calendarDate(local)}',
        'original_start_at': entry['start_at'],
        'original_end_at': entry['end_at'],
        'start_at': a.toIso8601String(),
        'end_at': b.toIso8601String(),
        'weekday': day + 1,
        'sections': <int>[],
      });
    }
  }
  return result;
}

String calendarTimeLabel(
  Map<String, dynamic> row, {
  bool includeMissing = false,
}) {
  String at(dynamic value) {
    final t = schoolTime('$value');
    return '${t.month}/${t.day} ${hhmm(t)}';
  }

  final time = calendarTime(row);
  if (row['start_at'] == null &&
      calendarMeaning(row) == 'start' &&
      time['at'] != null) {
    return at(time['at']);
  }
  if (calendarMeaning(row) == 'window' && time['at'] != null) {
    return '办理窗口：${at(time['at'])}${time['end_at'] == null ? '' : '—${at(time['end_at'])}'}';
  }

  if (row['start_at'] != null) {
    return row['end_at'] == null
        ? '${at(row['start_at'])}${includeMissing ? ' · 开始' : ''}'
        : '${at(row['start_at'])}—${at(row['end_at'])}';
  }
  if (row['due_at'] != null) return '${at(row['due_at'])} 截止';
  final date = row['date'] ?? time['date'];
  final endDate = row['end_date'] ?? time['end_date'];
  if (date != null) {
    final allDay = calendarMeaning(row) == 'all_day' || row['all_day'] == true;
    return '${studentDate(DateTime.parse(date))}${endDate == null ? '' : ' 至 ${studentDate(DateTime.parse(endDate))}'}${allDay
        ? ' · 全天'
        : includeMissing
        ? ' · 仅日期'
        : ''}';
  }
  if (row['week'] != null) {
    return '第${row['week']}周${includeMissing ? ' · 日期待定' : ''}';
  }
  final expression = '${row['expression'] ?? time['expression'] ?? ''}'.trim();
  if (expression.isNotEmpty) return expression;
  if (time['candidate_dates'] is List &&
      (time['candidate_dates'] as List).isNotEmpty) {
    return '候选日期：${(time['candidate_dates'] as List).map((date) => studentDate(DateTime.parse(date))).join(' / ')}';
  }
  return '';
}

class CalendarRepository extends ChangeNotifier {
  final SemesterApi api;
  final CalendarStore cache;
  CalendarRepository(this.api, this.cache);
  Map<String, dynamic>? data;
  bool busy = false, offline = false, _disposed = false;
  String? error, _key;
  int _request = 0;
  List<Map<String, dynamic>> get entries => calendarScheduleEntries(
    List<Map<String, dynamic>>.from(data?['entries'] ?? []),
  );
  List<Map<String, dynamic>> get undated => calendarScheduleEntries(
    List<Map<String, dynamic>>.from(data?['undated'] ?? []),
  );
  int? get revision => data?['revision'] as int?;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load(String sid, DateTime from) async {
    final stamp = ++_request, generation = api.generation;
    final owner = api.session?['user']?['id'];
    final key = 'calendar:$owner:$sid:${calendarDate(from)}';
    bool current() =>
        !_disposed &&
        stamp == _request &&
        generation == api.generation &&
        owner == api.session?['user']?['id'];
    if (_key != key) {
      data = null;
      _key = key;
    }
    busy = true;
    error = null;
    changed();
    try {
      final cached = await cache.read(key);
      if (!current()) return;
      if (data == null &&
          cached != null &&
          cached['semester_id'] == sid &&
          cached['revision'] is int &&
          cached['entries'] is List) {
        data = cached;
        changed();
      }
      final value = Map<String, dynamic>.from(
        await api.request(
          'GET',
          '/semesters/$sid/calendar?from_date=${calendarDate(from)}&to_date=${calendarDate(from.add(const Duration(days: 6)))}',
        ),
      );
      if (!current()) return;
      if (value['semester_id'] != sid || value['revision'] is! int) {
        throw ApiFailure('日程数据暂时无法读取，请重试');
      }
      if (data != null && (data!['revision'] as int) > value['revision']) {
        throw ApiFailure('日程已更新，请重试获取最新记录');
      }
      data = value;
      offline = false;
      await cache.write(key, value);
    } catch (e) {
      if (current()) {
        offline = true;
        error = userError(e);
      }
    } finally {
      if (current()) {
        busy = false;
        changed();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
