import 'package:flutter/foundation.dart';
import '../../core/cache.dart';

const homeModules = {
  'deadlines': '近期截止',
  'plans': '个人计划',
  'windows': '空档与建议',
  'exams': '近期考试',
};

class HomePreferences extends ChangeNotifier {
  final CalendarStore cache;
  final String owner, semester;
  final bool Function() valid;
  List<String> order = homeModules.keys.toList();
  Set<String> enabled = homeModules.keys.toSet();
  int _epoch = 0;
  bool _closed = false;
  Future<void> _writes = Future.value();
  HomePreferences(this.cache, this.owner, this.semester, this.valid);
  String get key => 'home-layout:$owner:$semester';
  Future<void> restore() async {
    final stamp = _epoch;
    final data = await cache.read(key);
    if (!valid() || _closed || stamp != _epoch || data == null) return;
    order = [
      ...(data['order'] is List
              ? (data['order'] as List).whereType<String>().where(
                  homeModules.containsKey,
                )
              : <String>[])
          .toSet(),
    ];
    order.addAll(homeModules.keys.where((id) => !order.contains(id)));
    if (data['enabled'] is List) {
      enabled = (data['enabled'] as List)
          .whereType<String>()
          .where(homeModules.containsKey)
          .toSet();
    }
    notifyListeners();
  }

  Future<void> change({List<String>? order, Set<String>? enabled}) async {
    if (!valid() || _closed) return;
    _epoch++;
    if (order != null) {
      this.order = order.where(homeModules.containsKey).toSet().toList();
      this.order.addAll(
        homeModules.keys.where((id) => !this.order.contains(id)),
      );
    }
    if (enabled != null) {
      this.enabled = enabled.where(homeModules.containsKey).toSet();
    }
    final data = {
      'order': [...this.order],
      'enabled': this.enabled.toList(),
    };
    notifyListeners();
    _writes = _writes.catchError((Object _) {}).then((_) async {
      if (valid()) await cache.write(key, data);
    });
    await _writes;
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
