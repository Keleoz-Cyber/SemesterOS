import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/core/cache.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;

class MemoryStore implements CalendarStore {
  final data = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>?> read(String owner) async => data[owner] == null
      ? null
      : Map<String, dynamic>.from(jsonDecode(jsonEncode(data[owner])));
  @override
  Future<void> write(String owner, Map<String, dynamic> value) async {
    data[owner] = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));
  }

  @override
  Future<void> clear(String owner) async {
    data.remove(owner);
  }

  @override
  Future<void> close() async {}
}

Map<String, dynamic> semester(int revision) => {
  'id': 'semester-a',
  'name': '测试',
  'first_monday': '2026-08-31',
  'total_weeks': 20,
  'revision': revision,
  'periods': [],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'startup exposes saved calendar before waiting for the network',
    () async {
      final api = SemesterApi();
      final store = MemoryStore();
      final pending = Completer<ResponseBody>(), started = Completer<void>();
      final controller = AppController(
        api,
        store,
        clearSchoolSession: () async {},
      );
      final s = semester(1);
      final key = 'semester-a/${controller.weekNow(s)}';
      store.data['a'] = {
        'semesters': [s],
        'weeks': {
          key: {
            'revision': 1,
            'events': [
              {'title': 'cached'},
            ],
          },
        },
      };
      api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/me')) {
          started.complete();
          return pending.future;
        }
        if (r.path.endsWith('/semesters')) return body([s]);
        return body({
          'revision': 1,
          'events': [
            {'title': 'cached'},
          ],
        });
      });
      await api.saveSession(account('a'));
      final opening = controller.initialize();
      await started.future;
      final wasReady = controller.ready;
      final shown = List.of(controller.events);
      pending.complete(body({'id': 'a'}));
      await opening;
      expect(wasReady, true);
      expect(shown.single['title'], 'cached');
    },
  );
  test('old catalog response cannot populate the next account cache', () async {
    final api = SemesterApi();
    final store = MemoryStore();
    final pending = Completer<ResponseBody>(), started = Completer<void>();
    api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/semesters') &&
          '${r.headers['Authorization']}'.contains('access-a')) {
        started.complete();
        return pending.future;
      }
      return body(r.path.endsWith('/semesters') ? [] : {'id': 'b'});
    });
    final controller = AppController(
      api,
      store,
      clearSchoolSession: () async {},
    );
    await api.saveSession(account('a'));
    final old = controller.openSession();
    await started.future;
    await controller.logout(remote: false);
    await api.saveSession(account('b'));
    await controller.openSession();
    pending.complete(body([semester(1)]));
    await old;
    expect(controller.user['id'], 'b');
    expect(controller.semesters, isEmpty);
    expect(store.data['b']!['semesters'], isEmpty);
    expect(store.data.containsKey('a'), false);
  });
  test(
    'known stale week cache is invalidated after a confirmed import',
    () async {
      final api = SemesterApi();
      final store = MemoryStore();
      store.data['a'] = {
        'semesters': [semester(1)],
        'weeks': {
          'semester-a/5': {'revision': 1, 'events': []},
        },
      };
      api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/semesters')) return body([semester(2)]);
        if (r.path.contains('/timetable')) {
          throw DioException.connectionTimeout(
            timeout: const Duration(seconds: 1),
            requestOptions: r,
          );
        }
        return body({'id': 'a'});
      });
      await api.saveSession(account('a'));
      final controller = AppController(
        api,
        store,
        clearSchoolSession: () async {},
      );
      await controller.openSession();
      await controller.loadWeek(5);
      expect(controller.savedWeeks.containsKey('semester-a/5'), false);
      expect(controller.notice, contains('尚无缓存'));
      expect(controller.loggedIn, true);
    },
  );
  test('deleting the last semester clears its offline timetable', () async {
    final api = SemesterApi()..session = account('a');
    final store = MemoryStore();
    final s = semester(1);
    var deleted = false;
    final controller = AppController(
      api,
      store,
      clearSchoolSession: () async {},
    );
    final key = 'semester-a/${controller.weekNow(s)}';
    store.data['a'] = {
      'semesters': [s],
      'weeks': {
        key: {
          'revision': 1,
          'events': [
            {'title': '旧课程'},
          ],
        },
      },
    };
    api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.method == 'DELETE') {
        deleted = true;
        return body({'deleted_semester_id': 'semester-a'});
      }
      if (r.path.endsWith('/semesters')) return body(deleted ? [] : [s]);
      if (r.path.contains('/timetable')) {
        return body({
          'revision': 1,
          'events': [
            {'title': '旧课程'},
          ],
        });
      }
      return body({'id': 'a'});
    });
    await controller.openSession();
    expect(controller.events.single['title'], '旧课程');
    await controller.deleteSemester('semester-a', 1);
    expect(controller.semester, isNull);
    expect(controller.events, isEmpty);
    expect(controller.savedWeeks, isEmpty);
    expect(store.data['a']!['weeks'], isEmpty);
    controller.dispose();
  });
}
