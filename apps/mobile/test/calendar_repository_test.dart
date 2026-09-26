import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/calendar/calendar_repository.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'controller_test.dart' show MemoryStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cross-day fixed event is split for display without changing source times',
    () {
      final event = {
        'id': 'event:e',
        'resource_id': 'e',
        'resource_type': 'event',
        'title': '组会',
        'start_at': '2026-09-21T15:00:00Z',
        'end_at': '2026-09-21T17:00:00Z',
      };
      final parts = calendarGridEntries([event], DateTime(2026, 9, 21));
      expect(parts.length, 2);
      expect(parts.map((p) => p['weekday']), [1, 2]);
      expect(
        DateTime.parse(
          parts.first['end_at'],
        ).difference(DateTime.parse(parts.first['start_at'])).inMinutes,
        60,
      );
      expect(event['start_at'], '2026-09-21T15:00:00Z');
      expect(parts.first['resource_id'], 'e');
    },
  );
  test('deadline stays a point and is never drawn as an occupied block', () {
    expect(
      calendarGridEntries([
        {
          'id': 'deadline:i',
          'resource_type': 'deadline',
          'due_at': '2026-09-21T10:00:00Z',
        },
      ], DateTime(2026, 9, 21)),
      isEmpty,
    );
  });
  test(
    'cached records survive network failure and remain owner scoped',
    () async {
      final api = SemesterApi()..session = account('one');
      final cache = MemoryStore();
      var fail = false;
      api.dio.httpClientAdapter = ControlledTransport(
        (r) async => fail
            ? body({'message': '暂时无法连接'}, 503)
            : body({
                'semester_id': 's',
                'revision': 1,
                'entries': [
                  {'id': 'event:e', 'title': '组会'},
                ],
                'undated': [],
              }),
      );
      final repo = CalendarRepository(api, cache);
      await repo.load('s', DateTime(2026, 9, 21));
      expect(repo.entries.single['title'], '组会');
      fail = true;
      await repo.load('s', DateTime(2026, 9, 21));
      expect(repo.offline, true);
      expect(repo.entries.single['title'], '组会');
      api.session = account('two');
      api.generation++;
      await repo.load('s', DateTime(2026, 9, 21));
      expect(repo.entries, isEmpty);
      repo.dispose();
    },
  );
  test('response for an old week cannot replace the newest week', () async {
    final api = SemesterApi()..session = account('one');
    final old = Completer<void>();
    api.dio.httpClientAdapter = ControlledTransport((r) async {
      final first = r.path.contains('2026-09-21');
      if (first) await old.future;
      return body({
        'semester_id': 's',
        'revision': 1,
        'entries': [
          {'id': first ? 'old' : 'new'},
        ],
        'undated': [],
      });
    });
    final repo = CalendarRepository(api, MemoryStore());
    final waiting = repo.load('s', DateTime(2026, 9, 21));
    await Future<void>.delayed(Duration.zero);
    await repo.load('s', DateTime(2026, 9, 28));
    old.complete();
    await waiting;
    expect(repo.entries.single['id'], 'new');
    repo.dispose();
  });
}
