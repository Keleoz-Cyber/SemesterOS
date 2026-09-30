import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/api.dart';
import '../core/cache.dart';

final appControllerProvider = Provider<AppController>((ref) {
  final controller = AppController(SemesterApi(), CalendarCache());
  ref.onDispose(controller.dispose);
  return controller;
});

DateTime schoolNow() => DateTime.now().toUtc().add(const Duration(hours: 8));
DateTime schoolTime(String value) =>
    DateTime.parse(value).toUtc().add(const Duration(hours: 8));
String hhmm(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

class AppController extends ChangeNotifier {
  final SemesterApi api;
  final CalendarStore cache;
  final Future<void> Function() clearSchoolSession;
  int _weekRequest = 0;
  int _catalogRequest = 0;
  bool ready = false, busy = false, offline = false;
  String? notice;
  List<Map<String, dynamic>> semesters = [];
  Map<String, dynamic>? semester;
  List<Map<String, dynamic>> events = [];
  Map<String, dynamic> savedWeeks = {};
  int week = 1;
  AppController(
    this.api,
    this.cache, {
    Future<void> Function()? clearSchoolSession,
  }) : clearSchoolSession =
           clearSchoolSession ??
           (() async {
             await WebViewCookieManager().clearCookies();
           });
  bool get loggedIn => api.session != null;
  Map<String, dynamic> get user =>
      Map<String, dynamic>.from(api.session?['user'] ?? {});

  int weekNow(Map<String, dynamic> s) {
    final now = schoolNow();
    final date = DateTime.utc(now.year, now.month, now.day);
    final start = DateTime.parse('${s['first_monday']}T00:00:00Z');
    return (date.difference(start).inDays ~/ 7 + 1).clamp(
      1,
      s['total_weeks'] as int,
    );
  }

  Future<void> initialize() async {
    try {
      await api.restore();
      if (loggedIn) await openSession();
    } catch (e) {
      notice = userError(e);
    }
    ready = true;
    notifyListeners();
  }

  Future<void> openSession([
    Map<String, dynamic>? session,
    String? preferredSemesterId,
  ]) async {
    final selected =
        preferredSemesterId ?? (session == null ? (semester?['id']) : null);
    if (session != null) await api.saveSession(session);
    final stamp = api.generation;
    final sequence = ++_catalogRequest;
    final local = await cache.read('${user['id']}');
    if (stamp != api.generation || sequence != _catalogRequest) return;
    if (local != null) {
      semesters = List<Map<String, dynamic>>.from(local['semesters'] ?? []);
      savedWeeks = Map<String, dynamic>.from(local['weeks'] ?? {});
      final matching = semesters.where((s) => s['id'] == selected);
      semester = semesters.isEmpty
          ? null
          : matching.isEmpty
          ? semesters.first
          : matching.first;
      if (semester == null) {
        events = [];
        week = 1;
      }
      if (semester != null) {
        week = weekNow(semester!);
        final saved = savedWeeks['${semester!['id']}/$week'];
        events = saved?['revision'] == semester!['revision']
            ? List<Map<String, dynamic>>.from(saved['events'])
            : [];
      }
      ready = true;
      notice = '正在更新，先显示本机保存的课表';
      notifyListeners();
    } else {
      semesters = [];
      savedWeeks = {};
    }
    try {
      await api.request('GET', '/me');
      final catalog = List<Map<String, dynamic>>.from(
        await api.request('GET', '/semesters'),
      );
      if (stamp != api.generation || sequence != _catalogRequest) return;
      semesters = catalog;
      final knownIds = semesters.map((s) => '${s['id']}').toSet();
      savedWeeks.removeWhere(
        (key, _) => !knownIds.contains(key.split('/').first),
      );
      for (final s in semesters) {
        savedWeeks.removeWhere(
          (key, value) =>
              key.startsWith('${s['id']}/') &&
              value['revision'] != s['revision'],
        );
      }
      offline = false;
    } on ApiFailure catch (e) {
      if (stamp != api.generation ||
          sequence != _catalogRequest ||
          e.staleSession) {
        return;
      }
      if (e.unauthorized) {
        await logout(remote: false);
        rethrow;
      }
      offline = true;
      notice = e.message;
    }
    if (stamp != api.generation || sequence != _catalogRequest) return;
    final matching = semesters.where((s) => s['id'] == selected);
    semester = semesters.isEmpty
        ? null
        : matching.isEmpty
        ? semesters.first
        : matching.first;
    if (semester != null) {
      await loadWeek(weekNow(semester!));
    } else {
      events = [];
      week = 1;
    }
    if (stamp != api.generation || sequence != _catalogRequest) return;
    await saveCache();
    notifyListeners();
  }

  Future<void> saveCache() async {
    if (loggedIn) {
      await cache.write('${user['id']}', {
        'semesters': semesters,
        'weeks': savedWeeks,
      });
    }
  }

  Future<void> selectSemester(Map<String, dynamic> s) async {
    _catalogRequest++;
    semester = s;
    events = [];
    await loadWeek(weekNow(s));
  }

  Future<Map<String, dynamic>> deleteSemester(
    String sid,
    int expectedRevision,
  ) async {
    final receipt = Map<String, dynamic>.from(
      await api.request(
        'DELETE',
        '/semesters/$sid?expected_revision=$expectedRevision',
      ),
    );
    ++_weekRequest;
    ++_catalogRequest;
    semesters.removeWhere((s) => s['id'] == sid);
    savedWeeks.removeWhere((key, _) => key.startsWith('$sid/'));
    if (semester?['id'] == sid) {
      semester = null;
      events = [];
      week = 1;
    }
    await saveCache();
    notifyListeners();
    await openSession();
    return receipt;
  }

  Future<void> acknowledgeImport(Map<String, dynamic> receipt) async {
    _catalogRequest++;
    final sid = receipt['semester_id'];
    for (final s in semesters.where((s) => s['id'] == sid)) {
      s['revision'] = receipt['revision'];
    }
    savedWeeks.removeWhere((key, _) => key.startsWith('$sid/'));
    if (semester?['id'] == sid) events = [];
    await saveCache();
    notifyListeners();
  }

  Future<void> loadWeek(int value) async {
    if (semester == null) return;
    final stamp = api.generation;
    final sequence = ++_weekRequest;
    final selectedId = semester!['id'];
    week = value.clamp(1, semester!['total_weeks'] as int);
    final selectedWeek = week;
    final key = '$selectedId/$selectedWeek';
    final cached = savedWeeks[key];
    final local = cached?['revision'] == semester!['revision'] ? cached : null;
    events = local == null
        ? []
        : List<Map<String, dynamic>>.from(local['events']);
    busy = true;
    notifyListeners();
    try {
      final data = Map<String, dynamic>.from(
        await api.request(
          'GET',
          '/semesters/$selectedId/timetable?week=$selectedWeek',
        ),
      );
      if (stamp != api.generation) return;
      final ownerSemester = semesters
          .where((s) => s['id'] == selectedId)
          .firstOrNull;
      if (ownerSemester != null &&
          (data['revision'] as int) >= (ownerSemester['revision'] as int)) {
        ownerSemester['revision'] = data['revision'];
        savedWeeks.removeWhere(
          (k, v) =>
              k.startsWith('$selectedId/') && v['revision'] != data['revision'],
        );
        savedWeeks[key] = data;
      } else {
        return;
      }
      if (semester?['id'] == selectedId && week == selectedWeek) {
        events = List<Map<String, dynamic>>.from(data['events']);
        offline = false;
        notice = null;
      }
      await saveCache();
    } on ApiFailure catch (e) {
      if (stamp != api.generation || e.staleSession) return;
      if (e.unauthorized) {
        await logout(remote: false);
        return;
      }
      if (semester?['id'] == selectedId && week == selectedWeek) {
        offline = true;
        notice = local == null ? '离线：这一周尚无缓存，联网后可读取' : '离线：正在查看上次保存的课表';
      }
    } finally {
      if (stamp == api.generation && sequence == _weekRequest) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> logout({bool remote = true}) async {
    final owner = '${user['id']}';
    Future<dynamic>? revoking;
    if (remote && loggedIn) {
      revoking = api.revokeSession(Map<String, dynamic>.from(api.session!));
    }
    final forgetting = api.forget();
    ready = false;
    _weekRequest++;
    _catalogRequest++;
    semesters = [];
    semester = null;
    events = [];
    savedWeeks = {};
    offline = false;
    busy = false;
    notice = null;
    notifyListeners();
    await forgetting;
    await clearSchoolSession();
    await cache.clear(owner);
    ready = true;
    notifyListeners();
    if (revoking != null) unawaited(revoking);
  }

  @override
  void dispose() {
    cache.close();
    api.dio.close();
    super.dispose();
  }
}
