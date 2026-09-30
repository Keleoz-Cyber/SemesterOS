import 'dart:convert';

abstract interface class NotificationPort {
  Future<bool> permission({bool request = false});
  Future<Map<int, Map<String, dynamic>>> pending();
  Future<Set<int>> activeIds();
  Future<void> cancel(int id);
  Future<void> cancelAll();
  Future<void> schedule(int id, Map<String, dynamic> data);
}

class ReminderSync {
  final NotificationPort port;
  final DateTime Function() now;
  ReminderSync(this.port, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  Future<void> _queue = Future.value();
  int _generation = 0;
  int _cleanupGeneration = 0;
  String? _cleanupOwner;

  Future<String> replace(String owner, List<Map<String, dynamic>> rules) {
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
      final fingerprint = jsonEncode([
        owner,
        rule['item_id'],
        rule['id'],
        rule['version'],
        rule['item_version'],
        trigger.toUtc().toIso8601String(),
        rule['title'],
        rule['purpose'],
      ]);
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
      DateTime trigger(String key) =>
          DateTime.parse(desired[key]!['trigger_at']);
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
      }
      if (generation != _generation) return '提醒清单已更新';
      if (!await port.permission()) return '提醒已保存，请开启系统通知';
      for (final key in selected) {
        if (generation != _generation) return '提醒清单已更新';
        if (matching.containsKey(key) || !trigger(key).isAfter(now())) continue;
        var id = key.codeUnits.fold<int>(
          2166136261,
          (n, c) => ((n ^ c) * 16777619) & 0x7fffffff,
        );
        while (!identifiers.add(id)) {
          id = (id + 1) & 0x7fffffff;
        }
        await port.schedule(id, desired[key]!);
      }
      return overdue.length + future.length > 450
          ? '已安排最近450条系统提醒，其余仍在App内显示'
          : '已设置系统提醒，可能受手机省电设置影响而延迟';
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
    _generation++;
    _cleanupGeneration++;
    _cleanupOwner = null;
    final operation = _queue.then((_) => port.cancelAll());
    _queue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }
}
