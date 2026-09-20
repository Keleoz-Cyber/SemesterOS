import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/items/reminder_sync.dart';

class FakeNotifications implements NotificationPort {
  final scheduled = <int, Map<String, dynamic>>{};
  bool allowed = true;
  Completer<void>? gate;
  @override
  Future<bool> permission({bool request = false}) async => allowed;
  @override
  Future<void> cancelAll() async {
    scheduled.clear();
  }

  @override
  Future<void> schedule(int id, Map<String, dynamic> data) async {
    await gate?.future;
    scheduled[id] = data;
  }
}

Map<String, dynamic> rule(String id, {String state = 'scheduled'}) => {
  'id': id,
  'item_id': 'task',
  'version': 1,
  'item_version': 1,
  'title': '合成提醒',
  'schedule_state': state,
  'trigger_at': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 2))
      .toIso8601String(),
};

void main() {
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
