import 'package:flutter/foundation.dart';
import '../../core/cache.dart';

const homeModules = {
  'deadlines': '近期截止',
  'plans': '个人计划',
  'windows': '安排建议',
  'exams': '近期考试',
  'week_heatmap': '本周忙闲',
  'semester_progress': '学期进度',
  'time_stats': '时间统计',
  'breathing_exercise': '呼吸练习',
};

enum TodayViewMode { schedule, tasks }

const defaultHomeModules = {'deadlines', 'plans', 'windows', 'exams'};

/// With no explicit choice, dated arrangements select the agenda. A day with
/// only tasks opens the task list, including tasks whose time is still unknown.
TodayViewMode defaultTodayViewMode({required int events, required int tasks}) =>
    events > 0 || tasks == 0 ? TodayViewMode.schedule : TodayViewMode.tasks;

class HomePreferences extends ChangeNotifier {
  final CalendarStore cache;
  final String owner, semester;
  final bool Function() valid;
  List<String> order = homeModules.keys.toList();
  Set<String> enabled = {...defaultHomeModules};
  TodayViewMode? todayView;
  List<String> taskOrder = [];
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
    todayView = switch (data['today_view']) {
      'schedule' => TodayViewMode.schedule,
      'tasks' => TodayViewMode.tasks,
      _ => null,
    };
    taskOrder = data['task_order'] is List
        ? (data['task_order'] as List).whereType<String>().toSet().toList()
        : [];
    notifyListeners();
  }

  Future<void> change({
    List<String>? order,
    Set<String>? enabled,
    TodayViewMode? todayView,
    List<String>? taskOrder,
  }) async {
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
    if (todayView != null) this.todayView = todayView;
    if (taskOrder != null) this.taskOrder = taskOrder.toSet().toList();
    final data = {
      'order': [...this.order],
      'enabled': this.enabled.toList(),
      if (this.todayView != null) 'today_view': this.todayView!.name,
      'task_order': [...this.taskOrder],
    };
    notifyListeners();
    _writes = _writes.catchError((Object _) {}).then((_) async {
      if (valid() && !_closed) await cache.write(key, data);
    });
    await _writes;
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
