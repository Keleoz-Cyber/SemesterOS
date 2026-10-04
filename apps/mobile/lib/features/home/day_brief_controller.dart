import 'package:flutter/foundation.dart';
import '../../core/api.dart';
import '../../core/cache.dart';
import '../calendar/calendar_repository.dart';

class DayBriefController extends ChangeNotifier {
  final SemesterApi api;
  final CalendarStore cache;
  DayBriefController(this.api, this.cache);
  Map<String, dynamic>? data;
  String? error, key;
  bool busy = false, offline = false, _closed = false;
  int _request = 0;
  List<Map<String, dynamic>> get entries =>
      briefRows(data?['entries']).map(calendarDisplayEntry).toList();
  List<Map<String, dynamic>> get suggestions => briefRows(
    data?['suggestions'],
  ).where((row) => row['kind'] != 'missing_time').toList();
  bool fresh(int revision) =>
      !offline &&
      data?['revision'] is int &&
      data!['revision'] >= revision &&
      (DateTime.tryParse('${data?['valid_until']}')?.isAfter(DateTime.now()) ??
          false);
  void emit() {
    if (!_closed) notifyListeners();
  }

  Future<void> load(String sid, DateTime day) async {
    final stamp = ++_request, generation = api.generation;
    final owner = api.session?['user']?['id'];
    final date = calendarDate(day),
        nextKey =
            'day-brief:${api.session?['user']?['id']}:$sid:${calendarDate(day)}';
    bool current() =>
        !_closed &&
        stamp == _request &&
        generation == api.generation &&
        owner == api.session?['user']?['id'];
    if (key != nextKey) {
      key = nextKey;
      data = null;
    }
    busy = true;
    error = null;
    emit();
    try {
      final saved = await cache.read(nextKey);
      if (!current()) return;
      if (data == null &&
          saved?['semester_id'] == sid &&
          saved?['date'] == date &&
          saved?['entries'] is List &&
          saved?['revision'] is int) {
        data = saved;
        offline = true;
        emit();
      }
      final result = Map<String, dynamic>.from(
        await api.request('GET', '/semesters/$sid/day-brief?day=$date'),
      );
      if (!current()) return;
      if (result['semester_id'] != sid ||
          result['date'] != date ||
          result['revision'] is! int ||
          result['entries'] is! List) {
        throw ApiFailure('这一天的安排暂时无法读取');
      }
      if (data?['revision'] is int && data!['revision'] > result['revision']) {
        throw ApiFailure('安排已有更新，请重试');
      }
      data = result;
      offline = false;
      await cache.write(nextKey, result);
    } catch (e) {
      if (current()) {
        error = userError(e);
        offline = true;
      }
    } finally {
      if (current()) {
        busy = false;
        emit();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _request++;
    super.dispose();
  }
}

List<Map<String, dynamic>> briefRows(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : [];
