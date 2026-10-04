import 'dart:convert';

abstract interface class NotificationPort {
  Future<bool> permission({bool request = false});
  Future<Map<int, Map<String, dynamic>>> pending();
  Future<Set<int>> activeIds();
  Future<void> cancel(int id);
  Future<void> cancelAll();
  Future<void> schedule(int id, Map<String, dynamic> data);
}

/// Opens the OS notification screen without waiting for cloud reconciliation.
abstract interface class NotificationSettingsPort {
  Future<void> openNotificationSettings();
}

/// Optional capability so non-Android ports and existing test doubles remain
/// useful. Reconciliation compares this with the mode stored in OS payloads.
abstract interface class PreciseNotificationPort {
  Future<bool> precisePermission({bool request = false});
}

String reminderFingerprint(
  String owner,
  Map<String, dynamic> rule,
) => jsonEncode([
  owner,
  rule['item_id'],
  rule['id'],
  rule['version'],
  rule['item_version'],
  DateTime.parse(rule['trigger_at']).toUtc().toIso8601String(),
  rule['title'],
  rule['purpose'],
  // Preserve the legacy form only for genuinely legacy feeds; enriched
  // resources invalidate old time/place/action text when their contents change.
  if (rule.containsKey('resource_type')) ...[
    rule['resource_type'],
    rule['resource_id'],
    rule['semester_id'],
    DateTime.tryParse('${rule['start_at']}')?.toUtc().toIso8601String(),
    rule['place'],
    rule['can_complete'],
    rule['time_meaning'],
  ],
]);

class ReminderSync {
  final NotificationPort port;
  final DateTime Function() now;
  ReminderSync(this.port, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  Future<void> _queue = Future.value();
  int _generation = 0;
  int _cleanupGeneration = 0;
  String? _cleanupOwner;
  String? _owner;
  final Map<int, String> _known = {};

  Future<String> replace(String owner, List<Map<String, dynamic>> rules) {
    _owner = owner;
    // A refresh for this owner must not supersede its cold-start cleanup.
    // A direct foreign-owner replacement must not inherit the old cleanup.
    if (_cleanupOwner != null && _cleanupOwner != owner) {
      _cleanupGeneration++;
      _cleanupOwner = null;
    }
    final generation = ++_generation;
    final desired = <String, Map<String, dynamic>>{};
    for (final rule in rules) {
      if (rule['enabled'] == false ||
          !{'scheduled', 'expired'}.contains(rule['schedule_state'])) {
        continue;
      }
      final trigger = DateTime.tryParse('${rule['trigger_at']}');
      if (trigger == null) continue;
      final fingerprint = reminderFingerprint(owner, rule);
      desired[fingerprint] = {
        ...rule,
        'owner_id': owner,
        'fingerprint': fingerprint,
      };
    }
    final operation = _queue.then((_) async {
      if (generation != _generation) return '提醒清单已更新';
      final pending = await port.pending();
      if (generation != _generation) return '提醒清单已更新';
      for (final entry in pending.entries) {
        if (entry.value['fingerprint'] is String) {
          _known[entry.key] = entry.value['fingerprint'];
        }
      }
      final active = await port.activeIds();
      if (generation != _generation) return '提醒清单已更新';
      for (final id in active.where(
        (id) => _known.containsKey(id) && !desired.containsKey(_known[id]),
      )) {
        await port.cancel(id);
        _known.remove(id);
        if (generation != _generation) return '提醒清单已更新';
      }
      final matching = <String, int>{};
      for (final entry in pending.entries) {
        final fingerprint = entry.value['fingerprint'];
        if (entry.value['owner_id'] == owner &&
            fingerprint is String &&
            desired.containsKey(fingerprint)) {
          matching.putIfAbsent(fingerprint, () => entry.key);
        }
      }
      final current = now();
      DateTime trigger(String key) {
        final saved = pending[matching[key]];
        final snooze = saved?['snoozed'] == true
            ? DateTime.tryParse('${saved?['snooze_until']}')
            : null;
        return snooze ?? DateTime.parse(desired[key]!['trigger_at']);
      }

      final overdue =
          matching.keys.where((key) => !trigger(key).isAfter(current)).toList()
            ..sort((a, b) => trigger(a).compareTo(trigger(b)));
      final future =
          desired.keys
              .where(
                (key) =>
                    trigger(key).isAfter(current) &&
                    (desired[key]!['schedule_state'] == 'scheduled' ||
                        matching.containsKey(key)),
              )
              .toList()
            ..sort((a, b) => trigger(a).compareTo(trigger(b)));
      final selected = [...overdue, ...future].take(450).toList();
      // Reserve every retained ID before allocating new ones; collisions must
      // never replace another rule's OS-pending alarm.
      final identifiers = {
        for (final key in selected)
          if (matching.containsKey(key)) matching[key]!,
      };
      for (final id in pending.keys.where((id) => !identifiers.contains(id))) {
        if (generation != _generation) return '提醒清单已更新';
        await port.cancel(id);
        _known.remove(id);
      }
      if (generation != _generation) return '提醒清单已更新';
      if (!await port.permission()) return '提醒已保存，请开启系统通知';
      final exact = port is PreciseNotificationPort
          ? await (port as PreciseNotificationPort).precisePermission()
          : null;
      for (final key in selected) {
        if (generation != _generation) return '提醒清单已更新';
        if (!trigger(key).isAfter(now())) continue;
        final retained = matching[key];
        if (retained != null) {
          final saved = pending[retained]!;
          if (exact == null || saved['precise'] == exact) continue;
          // On Android a revoked exact-alarm permission cancels alarms but the
          // plugin can still retain their records. Re-arm with the allowed
          // mode on resume/startup, including a user's snoozed trigger.
          await port.cancel(retained);
          if (generation != _generation) return '提醒清单已更新';
          await port.schedule(retained, {
            ...desired[key]!,
            if (saved['snoozed'] == true) ...{
              'snoozed': true,
              'snooze_until': saved['snooze_until'],
              'trigger_at': saved['snooze_until'],
            },
          });
          continue;
        }
        var id = key.codeUnits.fold<int>(
          2166136261,
          (n, c) => ((n ^ c) * 16777619) & 0x7fffffff,
        );
        while (!identifiers.add(id)) {
          id = (id + 1) & 0x7fffffff;
        }
        await port.schedule(id, desired[key]!);
        _known[id] = key;
      }
      return overdue.length + future.length > 450
          ? '已安排最近450条系统提醒，其余仍在App内显示'
          : exact == true
          ? '已设置准时提醒'
          : '已设置系统提醒；未开启准时提醒权限，系统可能延迟';
    });
    // The caller receives failures; the serialization tail must never leave
    // a second, unobserved rejected Future while waiting for the next refresh.
    _queue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  // Cold start cannot cancelAll: an inexact alarm may be due but not delivered.
  // Active notifications have no payload, so clear only IDs absent from the
  // pending snapshot, then remove pending alarms belonging to other accounts.
  Future<void> initializeOwner(String owner) {
    _owner = owner;
    _generation++;
    final cleanupGeneration = ++_cleanupGeneration;
    _cleanupOwner = owner;
    final operation = _queue.then((_) async {
      if (cleanupGeneration != _cleanupGeneration) return;
      final pending = await port.pending();
      if (cleanupGeneration != _cleanupGeneration) return;
      final active = await port.activeIds();
      for (final id in {
        ...active.where((id) => !pending.containsKey(id)),
        ...pending.entries
            .where((entry) => entry.value['owner_id'] != owner)
            .map((entry) => entry.key),
      }) {
        if (cleanupGeneration != _cleanupGeneration) return;
        await port.cancel(id);
      }
    });
    _queue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> clear() {
    _owner = null;
    _generation++;
    _cleanupGeneration++;
    _cleanupOwner = null;
    _known.clear();
    final operation = _queue.then((_) => port.cancelAll());
    _queue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<bool> snooze(String owner, int id, Map<String, dynamic> source) {
    final generation = _generation;
    final operation = _queue.then((_) async {
      if (owner != _owner || generation != _generation) return false;
      if (!await port.permission()) return false;
      if (owner != _owner || generation != _generation) return false;
      final until = now()
          .toUtc()
          .add(const Duration(minutes: 10))
          .toIso8601String();
      await port.cancel(id);
      if (owner != _owner || generation != _generation) return false;
      await port.schedule(id, {
        ...source,
        'owner_id': owner,
        'trigger_at': until,
        'snoozed': true,
        'snooze_until': until,
      });
      return true;
    });
    _queue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }
}
