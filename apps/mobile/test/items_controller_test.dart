import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/items/items_controller.dart';
import 'package:semester_os/features/items/reminder_sync.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'controller_test.dart' show MemoryStore;
import 'reminder_sync_test.dart' show FakeNotifications;

class BlockingNotifications extends FakeNotifications {
  Completer<void>? cancelGate;
  @override
  Future<void> cancelAll() async {
    await cancelGate?.future;
    await super.cancelAll();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'exam and review reminder receipts replace old alarms even if the following GET fails',
    () async {
      final api = SemesterApi()..session = account('a');
      final port = FakeNotifications();
      final oldTime = DateTime.now()
          .toUtc()
          .add(const Duration(days: 5))
          .toIso8601String();
      final newTime = DateTime.now()
          .toUtc()
          .add(const Duration(days: 3))
          .toIso8601String();
      Map<String, dynamic> item(String id, int version, String at) => {
        'id': id,
        'semester_id': 's',
        'version': version,
        'lifecycle': 'active',
        'reminders': [
          {
            'id': 'r$id',
            'item_id': id,
            'version': version,
            'item_version': version,
            'title': id,
            'enabled': true,
            'schedule_state': 'scheduled',
            'trigger_at': at,
          },
        ],
      };
      var fail = false;
      api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.method == 'POST') {
          fail = true;
          return body({
            'semester_id': 's',
            'revision': 2,
            'changed_items': [
              item('exam', 2, newTime),
              item('review', 2, newTime),
            ],
          });
        }
        if (fail) return body({'message': 'offline'}, 503);
        if (r.path.endsWith('/courses')) return body([]);
        if (r.path.endsWith('/reminders')) {
          return body({
            'owner_id': 'a',
            'reminders': [
              ...item('exam', 1, oldTime)['reminders'],
              ...item('review', 1, oldTime)['reminders'],
            ],
          });
        }
        return body({
          'revision': 1,
          'semester_id': 's',
          'items': [item('exam', 1, oldTime), item('review', 1, oldTime)],
        });
      });
      final c = ItemsController(api, MemoryStore(), ReminderSync(port));
      await c.bind('s');
      expect(port.scheduled.length, 2);
      await c.changeRequest(
        'POST',
        '/exams/exam/reschedule',
        data: {},
        apply: true,
      );
      expect(c.offline, isTrue);
      expect(port.scheduled.values.map((r) => r['trigger_at']).toSet(), {
        newTime,
      });
      expect(c.items.every((i) => i['version'] == 2), isTrue);
      c.dispose();
    },
  );
  test(
    'a pre-commit refresh cannot overwrite a committed completion receipt',
    () async {
      final api = SemesterApi()..session = account('a');
      final gate = Completer<void>();
      var hold = false;
      final original = {
        'id': 'item',
        'version': 1,
        'semester_id': 's',
        'lifecycle': 'active',
        'reminders': <Map<String, dynamic>>[],
      };
      api.dio.httpClientAdapter = ControlledTransport((r) async {
        final stale = hold;
        if (stale) await gate.future;
        if (r.path.endsWith('/courses')) return body([]);
        if (r.path.endsWith('/reminders')) {
          return body({'owner_id': 'a', 'reminders': []});
        }
        return body({
          'items': [original],
        });
      });
      final port = BlockingNotifications();
      final c = ItemsController(api, MemoryStore(), ReminderSync(port));
      await c.bind('s');
      hold = true;
      final reading = c.refresh();
      await Future<void>.delayed(Duration.zero);
      port.cancelGate = Completer<void>();
      final committed = c.acceptItem({
        ...original,
        'version': 2,
        'lifecycle': 'completed',
      });
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final state = c.items.single['lifecycle'];
      port.cancelGate!.complete();
      await Future.wait([reading, committed]);
      expect(state, 'completed');
      c.dispose();
    },
  );
  test(
    'offline items use the correct account cache and never substitute another semester',
    () async {
      final api = SemesterApi()..session = account('a');
      api.dio.httpClientAdapter = ControlledTransport(
        (_) async => body({'message': 'offline'}, 503),
      );
      final cache = MemoryStore();
      cache.data['items:a'] = {
        'semesters': {
          's': {
            'items': [
              {'id': 'saved', 'title': '缓存事项'},
            ],
            'courses': [],
          },
        },
      };
      final c = ItemsController(api, cache, ReminderSync(FakeNotifications()));
      await c.bind('s');
      expect(c.items.single['id'], 'saved');
      expect(c.offline, isTrue);
      await c.bind('other');
      expect(c.items, isEmpty);
      c.dispose();
    },
  );
  test(
    'late old-account item feed cannot replace the new-account view or schedule reminders',
    () async {
      final api = SemesterApi()..session = account('a');
      final gate = Completer<void>();
      api.dio.httpClientAdapter = ControlledTransport((r) async {
        final old = '${r.headers['Authorization']}'.contains('access-a');
        if (old) await gate.future;
        if (r.path.endsWith('/courses')) return body([]);
        if (r.path.endsWith('/reminders')) {
          return body({
            'owner_id': old ? 'a' : 'b',
            'reminders': [],
            'synced_at': '2026-09-20T00:00:00Z',
          });
        }
        return body({
          'items': [
            {'id': old ? 'old' : 'new'},
          ],
        });
      });
      final cache = MemoryStore();
      final c = ItemsController(api, cache, ReminderSync(FakeNotifications()));
      final old = c.bind('s');
      await Future<void>.delayed(Duration.zero);
      await api.forget();
      await api.saveSession(account('b'));
      await c.bind('s');
      gate.complete();
      await old;
      expect(c.items.single['id'], 'new');
      expect(cache.data['items:a'], isNull);
      c.dispose();
    },
  );
}
