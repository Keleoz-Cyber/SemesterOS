import 'package:flutter/foundation.dart';
import '../../core/api.dart';
import '../items/items_controller.dart';
import '../calendar/calendar_repository.dart';

class InsightsController extends ChangeNotifier {
  final ItemsController items;
  final String semesterId;
  final int generation;
  DateTime from, to;
  String? category, error;
  Set<String> tags = {};
  Map<String, dynamic>? data;
  bool busy = false, offline = false, _closed = false;
  int _request = 0;
  String? _key, _dataKey;
  InsightsController(this.items, this.semesterId, this.from, this.to)
    : generation = items.api.generation;
  bool get active =>
      !_closed &&
      items.api.generation == generation &&
      items.semesterId == semesterId;
  bool get matchesCurrentQuery => _dataKey == _key;
  void emit() {
    if (active) notifyListeners();
  }

  Future<void> load() async {
    if (!active) return;
    final stamp = ++_request;
    final params = {
      'from_date': calendarDate(from),
      'to_date': calendarDate(to),
      'category_id': ?category,
      if (tags.isNotEmpty) 'tag_ids': (tags.toList()..sort()).join(','),
    };
    final path = Uri(
      path: '/semesters/$semesterId/insights',
      queryParameters: params,
    ).toString();
    final key = 'insights:${items.owner}:$path';
    if (_key != key) {
      _key = key;
    }
    bool current() => active && stamp == _request;
    busy = true;
    error = null;
    emit();
    try {
      final cached = await items.cache.read(key);
      if (!current()) return;
      if (_dataKey != key &&
          cached?['semester_id'] == semesterId &&
          cached?['revision'] is int) {
        data = cached;
        _dataKey = key;
        offline = true;
        emit();
      }
      final value = Map<String, dynamic>.from(
        await items.api.request('GET', path),
      );
      if (!current()) return;
      if (value['semester_id'] != semesterId ||
          value['revision'] is! int ||
          value['from_date'] != params['from_date'] ||
          value['to_date'] != params['to_date']) {
        throw ApiFailure('统计范围与返回内容不一致，请重试');
      }
      if (data != null && (data!['revision'] as int) > value['revision']) {
        throw ApiFailure('安排已有更新，请重新获取统计');
      }
      data = value;
      _dataKey = key;
      offline = false;
      await items.cache.write(key, value);
    } catch (e) {
      if (current()) {
        if (_dataKey != key) data = null;
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

  Future<void> range(DateTime a, DateTime b) {
    from = a;
    to = b;
    return load();
  }

  Future<void> filterCategory(String? id) {
    category = id;
    return load();
  }

  Future<void> toggleTag(String id) {
    tags = {...tags};
    tags.contains(id) ? tags.remove(id) : tags.add(id);
    return load();
  }

  @override
  void dispose() {
    _closed = true;
    _request++;
    super.dispose();
  }
}

List<Map<String, dynamic>> insightRows(dynamic value) => value is List
    ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
    : [];
String insightHours(dynamic value) => value is num
    ? '${(value / 60).toStringAsFixed(value % 60 == 0 ? 0 : 1)}h'
    : '未记录';
