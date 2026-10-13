import '../../core/api.dart';
import '../../core/cache.dart';

/// Only records an attempt. Recovery queries the server and never repeats writes.
class DecisionJournal {
  final CalendarStore cache;
  final String owner;
  final bool Function() valid;
  Future<void> _queue = Future.value();
  DecisionJournal(this.cache, this.owner, this.valid);
  String get key => 'agent-decisions:$owner';

  Future<List<Map<String, dynamic>>> read() async {
    await _queue.catchError((Object _) {});
    final saved = await cache.read(key);
    if (!valid()) throw ApiFailure('账号已切换', staleSession: true);
    return (saved?['attempts'] as List? ?? [])
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
  }

  Future<void> update(String id, Map<String, dynamic>? value) {
    final work = _queue.catchError((Object _) {}).then((_) async {
      if (!valid()) throw ApiFailure('账号已切换', staleSession: true);
      final saved = await cache.read(key);
      if (!valid()) throw ApiFailure('账号已切换', staleSession: true);
      final attempts = (saved?['attempts'] as List? ?? [])
          .whereType<Map>()
          .where((r) => r['id'] != id)
          .toList();
      if (value != null) attempts.add({...value, 'id': id});
      await cache.write(key, {'attempts': attempts});
    });
    _queue = work;
    return work;
  }
}
