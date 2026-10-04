import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/items/reminder_sync.dart';

class FakeNotifications implements NotificationPort {
  final scheduled = <int, Map<String, dynamic>>{};
  bool allowed = true;
  Completer<void>? gate;
  Completer<void>? permissionGate;
  Completer<void>? pendingGate;
  Completer<void>? activeGate;
  Object? pendingFailure;
  int scheduleCalls = 0;
  final active = <int>{};
  final cancelled = <int>[];
  @override
  Future<Map<int, Map<String, dynamic>>> pending() async {
    await pendingGate?.future;
    if (pendingFailure != null) throw pendingFailure!;
    return {
      for (final entry in scheduled.entries) entry.key: {...entry.value},
    };
  }

  @override
  Future<Set<int>> activeIds() async {
    await activeGate?.future;
    return {...active};
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
    active.remove(id);
  }

  @override
  Future<bool> permission({bool request = false}) async {
    await permissionGate?.future;
    return allowed;
  }

  @override
  Future<void> cancelAll() async {
    scheduled.clear();
    active.clear();
  }

  @override
  Future<void> schedule(int id, Map<String, dynamic> data) async {
    await gate?.future;
    scheduleCalls++;
    scheduled[id] = data;
  }
}

class PreciseNotifications extends FakeNotifications
    implements PreciseNotificationPort {
  bool precise = true;
  @override
  Future<bool> precisePermission({bool request = false}) async => precise;
  @override
  Future<void> schedule(int id, Map<String, dynamic> data) async {
    await super.schedule(id, {...data, 'precise': precise});
  }
}

Map<String, dynamic> rule(
  String id, {
  String state = 'scheduled',
  DateTime? at,
}) => {
  'id': id,
  'item_id': 'task',
  'version': 1,
  'item_version': 1,
  'title': '合成提醒',
  'schedule_state': state,
  'trigger_at': (at ?? DateTime.now().toUtc().add(const Duration(hours: 2)))
      .toIso8601String(),
};

void main() {
  final start = DateTime.utc(2026, 9, 27);
  test(
    'permission changes re-arm future reminders in the permitted mode',
    () async {
      final port = PreciseNotifications();
      final sync = ReminderSync(port, now: () => start);
      final reminder = rule('one', at: start.add(const Duration(hours: 1)));
      await sync.replace('a', [reminder]);
      final id = port.scheduled.keys.single;
      port.precise = false;
      await sync.replace('a', [reminder]);
      expect(port.scheduled[id]!['precise'], isFalse);
      port.precise = true;
      await sync.replace('a', [reminder]);
      expect(port.scheduled[id]!['precise'], isTrue);
      expect(port.scheduleCalls, 3);
    },
  );
  test(
    'snooze survives refresh and permission downgrade but source edits cancel it',
    () async {
      var now = start;
      final port = PreciseNotifications();
      final sync = ReminderSync(port, now: () => now);
      final reminder = rule('one', at: start.add(const Duration(seconds: 1)));
      await sync.replace('a', [reminder]);
      final id = port.scheduled.keys.single;
      final source = {...port.scheduled[id]!};
      now = start.add(const Duration(seconds: 2));
      expect(await sync.snooze('a', id, source), isTrue);
      final until = port.scheduled[id]!['trigger_at'];
      port.precise = false;
      await sync.replace('a', [
        {...reminder, 'schedule_state': 'expired'},
      ]);
      expect(port.scheduled[id]!['trigger_at'], until);
      expect(port.scheduled[id]!['precise'], isFalse);
      await sync.replace('a', [
        {...reminder, 'schedule_state': 'expired', 'version': 2},
      ]);
      expect(port.scheduled, isEmpty);
    },
  );
  test(
    'logout invalidates a queued snooze without recreating old alarms',
    () async {
      final port = FakeNotifications();
      final sync = ReminderSync(port, now: () => start);
      await sync.replace('a', [
        rule('one', at: start.add(const Duration(hours: 1))),
      ]);
      final id = port.scheduled.keys.single;
      port.permissionGate = Completer<void>();
      final snooze = sync.snooze('a', id, port.scheduled[id]!);
      await Future<void>.delayed(Duration.zero);
      final logout = sync.clear();
      port.permissionGate!.complete();
      expect(await snooze, isFalse);
      await logout;
      expect(port.scheduled, isEmpty);
    },
  );
  test(
    'completed source removes its delivered notification in the same session',
    () async {
      final port = FakeNotifications();
      final sync = ReminderSync(port, now: () => start);
      await sync.replace('a', [
        rule('one', at: start.add(const Duration(hours: 1))),
      ]);
      final id = port.scheduled.keys.single;
      port.scheduled.clear();
      port.active.add(id);
      await sync.replace('a', []);
      expect(port.active, isEmpty);
    },
  );
  for (final phase in ['pending', 'active']) {
    test(
      'same-owner replacement during $phase snapshot keeps cold-start cleanup',
      () async {
        final gate = Completer<void>();
        final port = FakeNotifications()..active.add(17);
        if (phase == 'pending') {
          port.pendingGate = gate;
        } else {
          port.activeGate = gate;
        }
        final sync = ReminderSync(port, now: () => start);
        final initialize = sync.initializeOwner('a');
        await Future<void>.delayed(Duration.zero);
        final replacing = sync.replace('a', []);
        gate.complete();
        await Future.wait([initialize, replacing]);
        expect(port.active, isEmpty);
        expect(port.cancelled, [17]);
      },
    );
  }
  for (final transition in ['initialize', 'replace', 'clear']) {
    test(
      '$transition invalidates old-owner initialization while a snapshot waits',
      () async {
        final port = FakeNotifications();
        final due = rule('one', at: start.add(const Duration(seconds: 1)));
        await ReminderSync(port, now: () => start).replace('b', [due]);
        final retainedId = port.scheduled.keys.single;
        port.activeGate = Completer<void>();
        final sync = ReminderSync(
          port,
          now: () => start.add(const Duration(seconds: 2)),
        );
        final old = sync.initializeOwner('a');
        await Future<void>.delayed(Duration.zero);
        final Future<dynamic> next;
        if (transition == 'initialize') {
          next = sync.initializeOwner('b');
        } else if (transition == 'replace') {
          next = sync.replace('b', [
            {...due, 'schedule_state': 'expired'},
          ]);
        } else {
          next = sync.clear();
        }
        port.activeGate!.complete();
        await Future.wait([old, next]);
        expect(port.cancelled, isEmpty);
        expect(
          port.scheduled.keys,
          transition == 'clear' ? isEmpty : [retainedId],
        );
      },
    );
  }
  test(
    'failed pending snapshot reaches caller without an uncaught queue error and retry succeeds',
    () async {
      final uncaught = <Object>[];
      await runZonedGuarded<Future<void>>(() async {
        final failure = StateError('pending snapshot unavailable');
        final port = FakeNotifications()..pendingFailure = failure;
        final sync = ReminderSync(port, now: () => start);
        final rules = [rule('one', at: start.add(const Duration(hours: 1)))];
        await expectLater(sync.replace('a', rules), throwsA(same(failure)));
        // Give an unobserved rejected queue tail a full event turn to surface.
        await Future<void>.delayed(Duration.zero);
        port.pendingFailure = null;
        await sync.replace('a', rules);
        expect(port.scheduled, hasLength(1));
      }, (error, stack) => uncaught.add(error));
      expect(uncaught, isEmpty);
    },
  );
  test(
    'new alarm allocation reserves a retained ID even when hashes collide',
    () async {
      final port = FakeNotifications();
      final sync = ReminderSync(port, now: () => start);
      final fresh = rule('fresh', at: start.add(const Duration(minutes: 1)));
      final retained = rule(
        'retained',
        at: start.add(const Duration(minutes: 2)),
      );
      await sync.replace('a', [fresh]);
      final collisionId = port.scheduled.keys.single;
      await sync.replace('a', [retained]);
      final retainedData = port.scheduled.values.single;
      port.scheduled
        ..clear()
        ..[collisionId] = retainedData;
      await ReminderSync(
        port,
        now: () => start,
      ).replace('a', [fresh, retained]);
      expect(port.scheduled[collisionId]!['id'], 'retained');
      expect(port.scheduled, hasLength(2));
      expect(port.scheduleCalls, 3);
    },
  );
  test('omitting an overdue pending rule cancels it without replay', () async {
    var now = start;
    final port = FakeNotifications();
    final sync = ReminderSync(port, now: () => now);
    await sync.replace('a', [
      rule('one', at: start.add(const Duration(seconds: 1))),
    ]);
    now = start.add(const Duration(seconds: 2));
    await sync.replace('a', []);
    expect(port.scheduled, isEmpty);
    expect(port.cancelled, hasLength(1));
    expect(port.scheduleCalls, 1);
  });
  test(
    'clock crossing the deadline preserves pending but never creates missed alarms',
    () async {
      var now = start;
      final port = FakeNotifications();
      final due = rule('one', at: start.add(const Duration(seconds: 1)));
      await ReminderSync(port, now: () => now).replace('a', [due]);
      final originalId = port.scheduled.keys.single;
      now = start.add(const Duration(seconds: 2));
      await ReminderSync(port, now: () => now).replace('a', [
        {...due, 'schedule_state': 'expired'},
        rule('never-scheduled', state: 'expired', at: start),
        rule('stale-scheduled', at: start),
      ]);
      expect(port.scheduled.keys, [originalId]);
      expect(port.scheduleCalls, 1);
    },
  );
  for (final change in <String, Map<String, dynamic>>{
    'rule version': {'version': 2},
    'item version': {'item_version': 2},
    'trigger': {
      'trigger_at': start
          .subtract(const Duration(seconds: 1))
          .toIso8601String(),
    },
    'title': {'title': 'renamed'},
    'purpose': {'purpose': 'start_review'},
    'rule id': {'id': 'other'},
    'item id': {'item_id': 'other'},
    'disabled': {'enabled': false},
    'cancelled': {'schedule_state': 'cancelled'},
  }.entries) {
    test(
      'overdue pending alarm is cancelled after ${change.key} changes',
      () async {
        var now = start;
        final port = FakeNotifications();
        final due = rule('one', at: start.add(const Duration(seconds: 1)));
        final sync = ReminderSync(port, now: () => now);
        await sync.replace('a', [due]);
        now = start.add(const Duration(seconds: 2));
        await sync.replace('a', [
          {...due, 'schedule_state': 'expired', ...change.value},
        ]);
        expect(port.scheduled, isEmpty);
        expect(port.cancelled, hasLength(1));
        expect(port.scheduleCalls, 1);
      },
    );
  }
  test('canonical UTC timestamps retain the same pending alarm', () async {
    final port = FakeNotifications();
    final due = rule('one', at: start.add(const Duration(hours: 1)));
    final sync = ReminderSync(port, now: () => start);
    await sync.replace('a', [due]);
    await sync.replace('a', [
      {...due, 'trigger_at': '2026-09-27T09:00:00+08:00'},
    ]);
    expect(port.scheduleCalls, 1);
    expect(port.cancelled, isEmpty);
  });
  test('owner transition cancels the old overdue alarm', () async {
    var now = start;
    final port = FakeNotifications();
    final due = rule('one', at: start.add(const Duration(seconds: 1)));
    final sync = ReminderSync(port, now: () => now);
    await sync.replace('a', [due]);
    now = start.add(const Duration(seconds: 2));
    await sync.replace('b', [
      {...due, 'schedule_state': 'expired'},
    ]);
    expect(port.scheduled, isEmpty);
  });
  test(
    'legacy payloads are cancelled and only future rules are recreated',
    () async {
      final port = FakeNotifications();
      port.scheduled.addAll({
        1: {'owner_id': 'a', 'item_id': 'task'},
        2: {'owner_id': 'a', 'item_id': 'task'},
      });
      await ReminderSync(port, now: () => start).replace('a', [
        rule('past', state: 'expired', at: start),
        rule('future', at: start.add(const Duration(hours: 1))),
      ]);
      expect(port.cancelled, containsAll([1, 2]));
      expect(port.scheduled.values.single['id'], 'future');
      expect(port.scheduleCalls, 1);
    },
  );
  test(
    'permission wait crossing deadline never schedules in the past',
    () async {
      var now = start;
      final port = FakeNotifications()..permissionGate = Completer<void>();
      final syncing = ReminderSync(
        port,
        now: () => now,
      ).replace('a', [rule('one', at: start.add(const Duration(seconds: 1)))]);
      await Future<void>.delayed(Duration.zero);
      now = start.add(const Duration(seconds: 2));
      port.permissionGate!.complete();
      await syncing;
      expect(port.scheduleCalls, 0);
    },
  );
  test(
    'queued refresh crossing deadline never creates a missed alarm',
    () async {
      var now = start;
      final port = FakeNotifications()..gate = Completer<void>();
      final sync = ReminderSync(port, now: () => now);
      final first = sync.replace('a', [
        rule('held', at: start.add(const Duration(hours: 1))),
      ]);
      await Future<void>.delayed(Duration.zero);
      final second = sync.replace('a', [
        rule('missed', at: start.add(const Duration(seconds: 1))),
      ]);
      now = start.add(const Duration(seconds: 2));
      port.gate!.complete();
      await Future.wait([first, second]);
      expect(port.scheduleCalls, 1);
      expect(port.scheduled, isEmpty);
    },
  );
  test('retained overdue alarms count toward the nearest 450 cap', () async {
    var now = start;
    final port = FakeNotifications();
    final sync = ReminderSync(port, now: () => now);
    final due = rule('overdue', at: start.add(const Duration(seconds: 1)));
    await sync.replace('a', [due]);
    final retainedId = port.scheduled.keys.single;
    now = start.add(const Duration(seconds: 2));
    final result = await sync.replace('a', [
      {...due, 'schedule_state': 'expired'},
      for (var i = 450; i > 0; i--)
        rule('future-$i', at: start.add(Duration(minutes: i))),
    ]);
    expect(port.scheduled, hasLength(450));
    expect(port.scheduled.containsKey(retainedId), isTrue);
    expect(port.scheduled.values.any((r) => r['id'] == 'future-450'), isFalse);
    expect(port.scheduled.values.any((r) => r['id'] == 'future-449'), isTrue);
    expect(port.scheduleCalls, 450);
    expect(result, contains('最近450条'));
  });
  test(
    'unchanged overdue OS pending alarm survives a new sync instance',
    () async {
      final port = FakeNotifications();
      final overdue = {
        ...rule('one', state: 'expired'),
        'trigger_at': '2026-01-01T00:00:00Z',
      };
      port.scheduled[17] = {
        ...overdue,
        'owner_id': 'a',
        'fingerprint': jsonEncode([
          'a',
          'task',
          'one',
          1,
          1,
          '2026-01-01T00:00:00.000Z',
          '合成提醒',
          null,
        ]),
      };
      await ReminderSync(port).replace('a', [overdue]);
      expect(port.scheduled.keys, [17]);
      expect(port.scheduleCalls, 0);
    },
  );
  test(
    'reconciliation removes cancelled rules and never catches up expired notifications',
    () async {
      final port = FakeNotifications();
      final sync = ReminderSync(port);
      await sync.replace('a', [rule('one'), rule('past', state: 'expired')]);
      expect(port.scheduled.length, 1);
      await sync.replace('a', []);
      expect(port.scheduled, isEmpty);
    },
  );
  test(
    'logout queued during scheduling leaves no old-owner notifications',
    () async {
      final port = FakeNotifications()..gate = Completer<void>();
      final sync = ReminderSync(port);
      final pending = sync.replace('a', [rule('one')]);
      await Future<void>.delayed(Duration.zero);
      final logout = sync.clear();
      port.gate!.complete();
      await Future.wait([pending, logout]);
      expect(port.scheduled, isEmpty);
    },
  );
  test(
    'denied permission keeps notification state distinct from saved rules',
    () async {
      final port = FakeNotifications()..allowed = false;
      final sync = ReminderSync(port);
      final result = await sync.replace('a', [rule('one')]);
      expect(result, '提醒已保存，请开启系统通知');
      expect(port.scheduled, isEmpty);
    },
  );
}
