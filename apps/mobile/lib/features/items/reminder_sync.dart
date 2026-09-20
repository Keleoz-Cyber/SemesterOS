abstract interface class NotificationPort {
  Future<bool> permission({bool request = false});
  Future<void> cancelAll();
  Future<void> schedule(int id, Map<String, dynamic> data);
}

class ReminderSync {
  final NotificationPort port;
  ReminderSync(this.port);
  Future<void> _queue = Future.value();
  int _generation = 0;

  Future<String> replace(String owner, List<Map<String, dynamic>> rules) {
    final generation = ++_generation;
    final ready =
        rules
            .where(
              (r) =>
                  r['schedule_state'] == 'scheduled' &&
                  r['trigger_at'] != null &&
                  DateTime.parse(r['trigger_at']).isAfter(DateTime.now()),
            )
            .toList()
          ..sort(
            (a, b) => '${a['trigger_at']}'.compareTo('${b['trigger_at']}'),
          );
    final operation = _queue.catchError((Object _) {}).then((_) async {
      if (generation != _generation) return '提醒清单已更新';
      await port.cancelAll();
      if (!await port.permission()) return '系统通知未开启，提醒规则已保留';
      final identifiers = <int>{};
      for (final rule in ready.take(450)) {
        if (generation != _generation) return '提醒清单已更新';
        final key =
            '$owner/${rule['item_id']}/${rule['id']}/${rule['version']}/${rule['item_version']}';
        var id = key.codeUnits.fold<int>(
          2166136261,
          (n, c) => ((n ^ c) * 16777619) & 0x7fffffff,
        );
        while (!identifiers.add(id)) {
          id = (id + 1) & 0x7fffffff;
        }
        await port.schedule(id, {...rule, 'owner_id': owner});
      }
      return ready.length > 450
          ? '已安排最近450条系统提醒，其余仍在App内显示'
          : '系统提醒已同步（普通定时，可能延迟）';
    });
    _queue = operation.then<void>((_) {});
    return operation;
  }

  Future<void> clear() {
    _generation++;
    _queue = _queue.catchError((Object _) {}).then((_) => port.cancelAll());
    return _queue;
  }
}
