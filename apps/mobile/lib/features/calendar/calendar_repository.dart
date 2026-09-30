import 'package:flutter/foundation.dart';
import '../../core/api.dart';
import '../../core/cache.dart';
import '../../app/controller.dart';

String calendarDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Split only the visual projection; the original interval stays on the server.
List<Map<String, dynamic>> calendarGridEntries(
  List<Map<String, dynamic>> entries,
  DateTime firstDay,
) {
  final result = <Map<String, dynamic>>[];
  for (final entry in entries) {
    if (entry['start_at'] == null || entry['end_at'] == null) continue;
    final start = DateTime.parse(entry['start_at']).toUtc();
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
  bool includeMissing = true,
}) {
  String at(dynamic value) {
    final t = schoolTime('$value');
    return '${t.month}/${t.day} ${hhmm(t)}';
  }

  if (row['start_at'] != null) {
    return row['end_at'] == null
        ? '${at(row['start_at'])}${includeMissing ? ' · 结束时间待定' : ''}'
        : '${at(row['start_at'])}—${at(row['end_at'])}';
  }
  if (row['due_at'] != null) return '${at(row['due_at'])} 截止';
  if (row['date'] != null) {
    return '${row['date']}${row['end_date'] == null ? '' : ' 至 ${row['end_date']}'}${includeMissing ? ' · 时刻待定' : ''}';
  }
  if (row['week'] != null) {
    return '第${row['week']}周${includeMissing ? ' · 日期待定' : ''}';
  }
  return '时间待确认';
}

class CalendarRepository extends ChangeNotifier {
  final SemesterApi api;
  final CalendarStore cache;
  CalendarRepository(this.api, this.cache);
  Map<String, dynamic>? data;
  bool busy = false, offline = false, _disposed = false;
  String? error, _key;
  int _request = 0;
  List<Map<String, dynamic>> get entries =>
      List<Map<String, dynamic>>.from(data?['entries'] ?? []);
  List<Map<String, dynamic>> get undated =>
      List<Map<String, dynamic>>.from(data?['undated'] ?? []);
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
