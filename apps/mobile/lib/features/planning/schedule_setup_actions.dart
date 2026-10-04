import '../../core/api.dart';
import '../items/items_controller.dart';

Future<void> confirmScheduleSetup(
  ItemsController c,
  Map<String, dynamic> setup,
  List<Map<String, dynamic>> chosen,
  Map<String, int> minutes, {
  List<Map<String, dynamic>>? weekly,
}) async {
  final owner = c.owner, sid = c.semesterId, generation = c.api.generation;
  void check() {
    if (owner != c.owner ||
        sid != c.semesterId ||
        generation != c.api.generation) {
      throw ApiFailure('账号或学期已切换，请重新打开');
    }
  }

  check();
  final hours = Map<String, dynamic>.from(setup['availability'] ?? {});
  if (hours['needs_confirmation'] == true) {
    await c.saveAvailability({
      'expected_revision': setup['revision'],
      'expected_version':
          hours['current']?['version'] ?? setup['settings_version'],
      'weekly': weekly ?? hours['candidate']?['weekly'] ?? [],
      'exclusions': hours['candidate']?['exclusions'] ?? [],
    });
    check();
    setup['availability']['needs_confirmation'] = false;
  }
  for (final t in chosen) {
    check();
    final id = '${t['id']}', n = minutes[id];
    if (n == null || n < 1) throw ApiFailure('请填写预计分钟数');
    if (t['remaining_minutes'] == n) continue;
    final item = await c.get(id);
    check();
    if (t['version'] != null && item['version'] != t['version']) {
      throw ApiFailure('“${t['title']}”已有修改，请重新核对');
    }
    final result = await c.save({
      for (final key in [
        'semester_id',
        'kind',
        'title',
        'course_id',
        'time',
        'certainty',
        'start_policy',
        'earliest_start_at',
        'reserve_time',
        'splittable',
        'priority',
        'location',
        'notes',
        'source_text',
        'details',
        'candidate_id',
        'source_id',
        'category_id',
      ])
        if (item.containsKey(key)) key: item[key],
      'tags': (item['tags'] as List? ?? [])
          .map((v) => v is Map ? v['name'] : v)
          .whereType<String>()
          .toList(),
      'remaining_minutes': n,
      'expected_version': item['version'],
      'change_reason': '确认预计用时',
    }, id: id);
    check();
    t['remaining_minutes'] = n;
    t['version'] = result['version'];
  }
}
