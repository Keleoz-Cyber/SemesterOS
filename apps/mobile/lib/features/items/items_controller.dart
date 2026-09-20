import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/api.dart';
import '../../core/cache.dart';
import 'reminder_sync.dart';
import '../planning/risk_state.dart';

class ItemsController extends ChangeNotifier {
  final SemesterApi api;
  final CalendarStore cache;
  final ReminderSync reminders;
  ItemsController(this.api, this.cache, this.reminders);
  List<Map<String, dynamic>> items = [];
  List<Map<String, dynamic>> courses = [], reminderFeed = [];
  bool offline = false;
  bool busy = false;
  String? notice, notificationStatus, syncedAt;
  String? _owner, semesterId;
  int _epoch = 0, _request = 0, _boundGeneration = -1;
  bool _disposed = false;
  Map<String, dynamic> _saved = {};
  VoidCallback? onUnauthorized;
  Future<void> Function(Map<String, dynamic>)? onRealityChanged;
  Map<String, dynamic>? analysis;
  int? itemsRevision;
  int? _observedRevision;
  int _riskRequest = 0;
  bool riskBusy = false;
  String? riskNotice;
  Map<String, dynamic>? planFeed;
  String? planNotice;
  int _planRequest = 0;
  bool get hasCurrentPlans =>
      !offline &&
      planFeed != null &&
      semesterId != null &&
      itemsRevision != null &&
      planFeed?['semester_id'] == semesterId &&
      planFeed?['revision'] == itemsRevision;
  bool revisionIsStale(String? sid, int revision) =>
      sid != semesterId ||
      (_observedRevision != null && _observedRevision! > revision) ||
      (itemsRevision != null && itemsRevision! > revision);

  bool get hasCurrentRisk =>
      !offline &&
      (_observedRevision == null ||
          (itemsRevision != null && itemsRevision! >= _observedRevision!)) &&
      riskSnapshotUsable(analysis, semesterId, itemsRevision, DateTime.now());
  Map<String, dynamic>? riskFor(Map<String, dynamic> item) {
    if (!hasCurrentRisk || item['lifecycle'] != 'active') return null;
    return rows(analysis?['items'])
        .where(
          (r) =>
              r['item_id'] == item['id'] &&
              r['item_version'] == item['version'],
        )
        .firstOrNull;
  }

  void invalidateRisk() {
    analysis = null;
    _riskRequest++;
    riskBusy = false;
    planFeed = null;
    _planRequest++;
  }

  bool observeRevision(String sid, int revision) {
    if (sid != semesterId) return false;
    if (_observedRevision == null || revision > _observedRevision!) {
      _observedRevision = revision;
    }
    if (itemsRevision != null && itemsRevision! < _observedRevision!) {
      invalidateRisk();
      riskNotice = '课表或安排已变化，正在更新余量';
      changed();
      return true;
    }
    return false;
  }

  String? get owner => api.session?['user']?['id'] as String?;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  bool valid(int epoch, int generation) =>
      !_disposed &&
      epoch == _epoch &&
      generation == api.generation &&
      owner == _owner;
  List<Map<String, dynamic>> rows(dynamic value) =>
      List<Map<String, dynamic>>.from(value ?? []);

  Future<void> bind(String? selected) async {
    if (_owner == owner &&
        semesterId == selected &&
        _boundGeneration == api.generation) {
      return;
    }
    final previous = _owner;
    _epoch++;
    invalidateRisk();
    itemsRevision = null;
    _observedRevision = null;
    riskNotice = null;
    _owner = owner;
    semesterId = selected;
    _boundGeneration = api.generation;
    items = [];
    courses = [];
    reminderFeed = [];
    _saved = {};
    notice = null;
    notificationStatus = null;
    syncedAt = null;
    busy = false;
    offline = false;
    final epoch = _epoch, generation = api.generation;
    changed();
    if (previous != _owner || _owner == null) {
      try {
        await reminders.clear();
      } catch (_) {
        notificationStatus = '旧系统提醒清理失败，请重新打开App重试';
      }
      if (previous != null && previous != _owner) {
        await cache.clear('items:$previous');
      }
    }
    if (!valid(epoch, generation) || _owner == null || selected == null) return;
    final saved = await cache.read('items:$_owner');
    if (!valid(epoch, generation)) return;
    _saved = Map<String, dynamic>.from(saved?['semesters'] ?? {});
    final selectedCache = _saved[selected];
    items = rows(selectedCache?['items']);
    courses = rows(selectedCache?['courses']);
    reminderFeed = rows(saved?['reminders']);
    syncedAt = saved?['synced_at'];
    changed();
    await refresh();
  }

  Future<void> refresh() async {
    if (_owner == null || semesterId == null || owner != _owner) return;
    final epoch = _epoch, generation = api.generation, request = ++_request;
    final sid = semesterId!;
    invalidateRisk();
    busy = true;
    changed();
    try {
      final result = await Future.wait([
        api.request('GET', '/semesters/$sid/items'),
        api.request('GET', '/semesters/$sid/courses'),
        api.request('GET', '/reminders'),
      ]);
      if (!valid(epoch, generation) || request != _request) return;
      if (result[2]['owner_id'] != _owner) throw ApiFailure('提醒清单账号不一致');
      items = rows(result[0]['items']);
      itemsRevision = result[0]['revision'];
      courses = rows(result[1]);
      reminderFeed = rows(result[2]['reminders']);
      syncedAt = result[2]['synced_at'];
      _saved[sid] = {'items': items, 'courses': courses};
      offline = false;
      notice = null;
      await cache.write('items:$_owner', {
        'semesters': _saved,
        'reminders': reminderFeed,
        'synced_at': syncedAt,
      });
      if (!valid(epoch, generation)) return;
      await syncNotifications();
      if (valid(epoch, generation) && request == _request) await refreshPlans();
      if (valid(epoch, generation) && request == _request) {
        await refreshRisk(reloadOnMismatch: false);
      }
    } on ApiFailure catch (e) {
      if (!valid(epoch, generation) || request != _request) return;
      if (e.unauthorized) {
        onUnauthorized?.call();
        return;
      }
      offline = true;
      invalidateRisk();
      riskNotice = '离线时不显示旧余量，联网后重新计算';
      notice = '事项同步未完成，正在显示本机记录；联网后可保存修改。';
      if (reminderFeed.isNotEmpty) await syncNotifications();
    } catch (_) {
      if (valid(epoch, generation)) notice = '本机事项或提醒同步未完成，请重试';
    } finally {
      if (valid(epoch, generation) && request == _request) {
        busy = false;
        changed();
      }
    }
  }

  Future<void> syncNotifications({bool requestPermission = false}) async {
    if (_owner == null || owner != _owner) return;
    final epoch = _epoch, generation = api.generation;
    try {
      if (requestPermission) await reminders.port.permission(request: true);
      if (!valid(epoch, generation)) return;
      final state = await reminders.replace(_owner!, reminderFeed);
      if (valid(epoch, generation)) notificationStatus = state;
    } catch (_) {
      if (valid(epoch, generation)) {
        notificationStatus = '系统提醒同步未完成，请重试；云端规则已保留';
      }
    }
    if (valid(epoch, generation)) changed();
  }

  Future<Map<String, dynamic>> save(
    Map<String, dynamic> data, {
    String? id,
    String? idempotencyKey,
  }) async {
    final generation = api.generation;
    final result = Map<String, dynamic>.from(
      await api.request(
        id == null ? 'POST' : 'PATCH',
        id == null ? '/items' : '/items/$id',
        data: data,
        idempotencyKey: idempotencyKey,
      ),
    );
    api.checkSession(generation);
    await acceptItem(result);
    await refresh();
    api.checkSession(generation);
    return result;
  }

  Future<Map<String, dynamic>> get(String id) async =>
      Map<String, dynamic>.from(await api.request('GET', '/items/$id'));
  Future<void> acceptItem(Map<String, dynamic> item) => acceptItems([item]);

  Future<void> acceptItems(List<Map<String, dynamic>> committed) async {
    _request++;
    invalidateRisk();
    final epoch = _epoch, generation = api.generation;
    if (_owner == null || owner != _owner) return;
    var accepted = false;
    for (final item in committed) {
      if (item['semester_id'] == semesterId) {
        final existing = items.where((r) => r['id'] == item['id']).firstOrNull;
        if (existing != null &&
            (existing['version'] as int) > (item['version'] as int)) {
          continue;
        }
        items = [item, ...items.where((r) => r['id'] != item['id'])];
        _saved[semesterId!] = {'items': items, 'courses': courses};
      }
      reminderFeed = [
        ...reminderFeed.where((r) => r['item_id'] != item['id']),
        if (item['lifecycle'] == 'active')
          ...rows(item['reminders']).where((r) => r['enabled'] == true),
      ];
      accepted = true;
    }
    if (!accepted) return;
    changed();
    // Correct local alarms from the committed receipt even if the next GET fails.
    await syncNotifications();
    if (!valid(epoch, generation)) return;
    await cache.write('items:$_owner', {
      'semesters': _saved,
      'reminders': reminderFeed,
      'synced_at': syncedAt,
    });
  }

  Future<void> lifecycle(
    Map<String, dynamic> item,
    String state, {
    Map<String, dynamic> confirmation = const {},
  }) async {
    final result = Map<String, dynamic>.from(
      await api.request(
        'POST',
        '/items/${item['id']}/lifecycle',
        data: {
          'expected_version': item['version'],
          'lifecycle': state,
          ...confirmation,
        },
      ),
    );
    await acceptItem(result);
    await refresh();
  }

  Future<void> saveReminder(
    Map<String, dynamic> item,
    Map<String, dynamic> data, {
    String? id,
  }) async {
    final result = Map<String, dynamic>.from(
      await api.request(
        id == null ? 'POST' : 'PATCH',
        id == null ? '/items/${item['id']}/reminders' : '/reminders/$id',
        data: {...data, 'expected_item_version': item['version']},
      ),
    );
    await acceptItem({
      ...item,
      'reminders': [
        ...rows(item['reminders']).where((r) => r['id'] != result['id']),
        result,
      ],
    });
    await refresh();
  }

  Future<Map<String, dynamic>> parse(String text, String referenceAt) async =>
      Map<String, dynamic>.from(
        await api.request(
          'POST',
          '/capture/text',
          data: {
            'semester_id': semesterId,
            'text': text,
            'reference_at': referenceAt,
          },
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

  Future<void> refreshRisk({bool reloadOnMismatch = true}) async {
    if (owner == null ||
        _owner != owner ||
        semesterId == null ||
        offline ||
        itemsRevision == null) {
      return;
    }
    final epoch = _epoch,
        generation = api.generation,
        request = ++_riskRequest,
        inputs = _request;
    riskBusy = true;
    changed();
    try {
      final result = Map<String, dynamic>.from(
        await api.request('GET', '/semesters/$semesterId/risk'),
      );
      if (!valid(epoch, generation) ||
          request != _riskRequest ||
          inputs != _request) {
        return;
      }
      if (result['revision'] != itemsRevision ||
          (_observedRevision != null &&
              (result['revision'] as int) < _observedRevision!)) {
        analysis = null;
        riskNotice = '安排已变化，请刷新后重新分析';
        if (reloadOnMismatch && !busy) await refresh();
        return;
      }
      analysis = result;
      riskNotice = null;
    } catch (_) {
      if (valid(epoch, generation) && request == _riskRequest) {
        analysis = null;
        riskNotice = '余量分析未完成，可重试；事项与提醒仍可使用';
      }
    } finally {
      if (valid(epoch, generation) && request == _riskRequest) {
        riskBusy = false;
        changed();
      }
    }
  }

  Future<Map<String, dynamic>> getAvailability() async =>
      Map<String, dynamic>.from(
        await api.request('GET', '/semesters/$semesterId/availability'),
      );
  Future<Map<String, dynamic>> previewAvailability(
    Map<String, dynamic> data,
  ) async => Map<String, dynamic>.from(
    await api.request(
      'POST',
      '/semesters/$semesterId/availability/preview',
      data: data,
    ),
  );
  Future<void> saveAvailability(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await api.request(
      'PUT',
      '/semesters/$semesterId/availability',
      data: data,
      idempotencyKey: idempotencyKey,
    );
    invalidateRisk();
    changed();
    await refresh();
  }

  Future<Map<String, dynamic>> previewProgress(
    String id,
    Map<String, dynamic> data,
  ) async => Map<String, dynamic>.from(
    await api.request('POST', '/items/$id/progress/preview', data: data),
  );
  Future<void> saveProgress(
    String id,
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final item = Map<String, dynamic>.from(
      await api.request(
        'POST',
        '/items/$id/progress',
        data: data,
        idempotencyKey: idempotencyKey,
      ),
    );
    await acceptItem(item);
    await refresh();
  }

  Future<Map<String, dynamic>> previewLifecycle(
    Map<String, dynamic> item,
    String state,
  ) async => Map<String, dynamic>.from(
    await api.request(
      'POST',
      '/items/${item['id']}/lifecycle/preview',
      data: {'expected_version': item['version'], 'lifecycle': state},
    ),
  );
  Future<void> refreshPlans() async {
    if (owner == null || owner != _owner || semesterId == null) return;
    final epoch = _epoch, generation = api.generation, request = ++_planRequest;
    try {
      final result = Map<String, dynamic>.from(
        await api.request('GET', '/semesters/$semesterId/plans'),
      );
      if (!valid(epoch, generation) || request != _planRequest) return;
      planFeed = result;
      planNotice = result['revision'] == itemsRevision ? null : '计划已变化，请刷新';
    } catch (_) {
      if (valid(epoch, generation) && request == _planRequest) {
        planFeed = null;
        planNotice = '个人计划同步未完成，请重试';
      }
    }
    if (valid(epoch, generation) && request == _planRequest) changed();
  }

  Future<Map<String, dynamic>> generateSchedule(
    Map<String, dynamic> data,
  ) async {
    final sid = semesterId;
    final result = Map<String, dynamic>.from(
      await api.request(
        'POST',
        '/semesters/$sid/${data['mode'] == 'replan' ? 'replan-proposals' : 'plan-proposals'}',
        data: data,
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    if (sid != semesterId) throw ApiFailure('学期已切换，请重新打开候选');
    return result;
  }

  Future<Map<String, dynamic>> changeRequest(
    String method,
    String path, {
    Map<String, dynamic>? data,
    bool apply = false,
  }) async {
    final sid = semesterId;
    final generation = api.generation;
    final result = Map<String, dynamic>.from(
      await api.request(
        method,
        path,
        data: data,
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    if (sid != semesterId) throw ApiFailure('学期已切换，请重新打开');
    if (apply) {
      api.checkSession(generation);
      observeRevision(result['semester_id'], result['revision']);
      final receipts = rows(result['changed_items']);
      if (receipts.isNotEmpty) await acceptItems(receipts);
      api.checkSession(generation);
      invalidateRisk();
      changed();
      await onRealityChanged?.call(result);
      await refresh();
    }
    return result;
  }

  Future<Map<String, dynamic>> acceptSchedule(
    Map<String, dynamic> p,
    bool partial,
  ) async {
    final result = Map<String, dynamic>.from(
      await api.request(
        'POST',
        '/plan-proposals/${p['id']}/accept',
        data: {
          'expected_version': p['version'],
          'expected_revision': p['base_revision'],
          'confirm_partial': partial,
          'unarranged_minutes': p['unarranged_minutes'] ?? 0,
        },
      ),
    );
    observeRevision(result['semester_id'], result['revision']);
    invalidateRisk();
    changed();
    await refresh();
    return result;
  }

  Future<void> undoSchedule(Map<String, dynamic> p, int revision) async {
    final result = Map<String, dynamic>.from(
      await api.request(
        'POST',
        '/plan-proposals/${p['id']}/undo',
        data: {'expected_version': p['version'], 'expected_revision': revision},
      ),
    );
    observeRevision(result['semester_id'], result['revision']);
    invalidateRisk();
    changed();
    await refresh();
  }

  Future<void> changePlanBlock(
    Map<String, dynamic> b, {
    bool? locked,
    bool cancel = false,
    bool confirmLocked = false,
  }) async {
    final result = Map<String, dynamic>.from(
      await api.request(
        cancel ? 'POST' : 'PATCH',
        '/plan-blocks/${b['id']}/${cancel ? 'cancel' : 'lock'}',
        data: {
          'expected_version': b['version'],
          if (cancel) 'confirm_locked': confirmLocked else 'locked': locked,
        },
      ),
    );
    observeRevision(result['semester_id'], result['revision']);
    invalidateRisk();
    changed();
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}
