import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../core/api.dart';
import '../items/items_controller.dart';

List<Map<String, dynamic>> rows(dynamic value) => value is List
    ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
    : [];

class AgentController extends ChangeNotifier {
  final ItemsController items;
  final String semesterId;
  late final int generation = items.api.generation;
  List<Map<String, dynamic>> runs = [], threads = [];
  String? threadId, error;
  bool busy = false, loading = true, _closed = false;
  int _epoch = 0;
  Timer? _poll;
  String? _pendingText, _pendingId;
  final Set<String> _syncedReceipts = {};
  Future<void>? _receiptSync;
  AgentController(this.items, this.semesterId);
  bool get active =>
      !_closed &&
      items.api.generation == generation &&
      items.semesterId == semesterId;
  bool get processing =>
      runs.any((r) => r['status'] == 'queued' || r['status'] == 'running');
  Map<String, dynamic>? get activeSource {
    if (runs.isEmpty ||
        {'applied', 'cancelled'}.contains(runs.last['status'])) {
      return null;
    }
    final value = runs.last['source'];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  void emit() {
    if (active) notifyListeners();
  }

  void check(int stamp) {
    if (!active || stamp != _epoch) {
      throw ApiFailure('账号或对话已切换，请重新打开', staleSession: true);
    }
  }

  Future<dynamic> request(String method, String path, {dynamic data}) =>
      items.api.request(method, path, data: data);
  Future<void> open({String? id, bool fresh = false}) async {
    final stamp = ++_epoch;
    _poll?.cancel();
    loading = true;
    error = null;
    emit();
    try {
      final all = await request(
        'GET',
        '/agent/threads?semester_id=$semesterId',
      );
      check(stamp);
      threads = rows(all);
      threadId = fresh
          ? null
          : id ?? (threads.isEmpty ? null : threads.first['id'] as String);
      runs = [];
      if (threadId != null) {
        final value = await request('GET', '/agent/threads/$threadId');
        check(stamp);
        runs = rows(value['runs']);
        await reconcileReceipts(stamp);
      }
      _pendingId = _pendingText = null;
    } catch (e) {
      if (active && stamp == _epoch) error = userError(e);
    } finally {
      if (active && stamp == _epoch) {
        loading = false;
        emit();
        schedulePoll();
      }
    }
  }

  void schedulePoll() {
    _poll?.cancel();
    if (active && processing) _poll = Timer(const Duration(seconds: 2), poll);
  }

  Future<void> poll() async {
    final stamp = _epoch;
    final pending = runs
        .where((r) => r['status'] == 'queued' || r['status'] == 'running')
        .toList();
    try {
      for (final row in pending) {
        final value = Map<String, dynamic>.from(
          await request('GET', '/agent/runs/${row['id']}'),
        );
        check(stamp);
        replace(value);
      }
      error = null;
      await reconcileReceipts(stamp);
    } catch (e) {
      if (active && stamp == _epoch) error = userError(e);
    } finally {
      if (active && stamp == _epoch) {
        emit();
        schedulePoll();
      }
    }
  }

  void replace(Map<String, dynamic> value) {
    final index = runs.indexWhere((r) => r['id'] == value['id']);
    if (index < 0) {
      runs = [...runs, value];
    } else {
      final old = runs[index];
      if ((value['sequence'] as int? ?? 0) < (old['sequence'] as int? ?? 0)) {
        return;
      }
      if (old['status'] == 'applied' && value['status'] != 'applied') return;
      runs = [...runs]..[index] = value;
    }
  }

  Future<bool> send(
    String text, {
    Map<String, dynamic>? source,
    List<String> selectedRecordIds = const [],
    bool detachSource = false,
  }) async {
    if (busy || processing || !active || text.trim().isEmpty) return false;
    final stamp = _epoch;
    busy = true;
    error = null;
    emit();
    try {
      if (threadId == null) {
        final t = await request(
          'POST',
          '/agent/threads',
          data: {'semester_id': semesterId},
        );
        check(stamp);
        threadId = t['id'];
      }
      final signature =
          '$text\u0000${source?['id'] ?? ''}:${source?['version'] ?? ''}:${selectedRecordIds.join(',')}:$detachSource';
      if (_pendingText != signature || _pendingId == null) {
        _pendingText = signature;
        _pendingId = List.generate(
          16,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
      }
      final value = Map<String, dynamic>.from(
        await request(
          'POST',
          '/agent/threads/$threadId/turns',
          data: {
            'text': text,
            'request_id': _pendingId,
            if (source != null) 'source_id': source['id'],
            if (source != null) 'source_version': source['version'],
            if (selectedRecordIds.isNotEmpty)
              'selected_record_ids': selectedRecordIds,
            if (detachSource) 'detach_source': true,
          },
        ),
      );
      check(stamp);
      runs = [
        for (final row in runs)
          if (row['status'] == 'needs_confirmation')
            {...row, 'status': 'superseded'}
          else
            row,
      ];
      replace(value);
      _pendingText = _pendingId = null;
      return true;
    } catch (e) {
      if (active && stamp == _epoch) error = userError(e);
      return false;
    } finally {
      if (active && stamp == _epoch) {
        busy = false;
        emit();
        schedulePoll();
      }
    }
  }

  Future<void> decide(Map<String, dynamic> run, bool confirm) async {
    if (busy || !active) return;
    final stamp = _epoch;
    busy = true;
    error = null;
    emit();
    try {
      final value = Map<String, dynamic>.from(
        await request(
          'POST',
          '/agent/runs/${run['id']}/decision',
          data: {
            'decision': confirm ? 'confirm' : 'reject',
            'token': run['preview']['token'],
          },
        ),
      );
      check(stamp);
      replace(value);
      emit();
      await reconcileReceipts(stamp);
    } catch (e) {
      if (active && stamp == _epoch) error = userError(e);
    } finally {
      if (active && stamp == _epoch) {
        busy = false;
        emit();
      }
    }
  }

  Future<void> stop(Map<String, dynamic> run) async {
    final stamp = _epoch;
    try {
      final value = Map<String, dynamic>.from(
        await request('POST', '/agent/runs/${run['id']}/cancel'),
      );
      check(stamp);
      replace(value);
      emit();
      schedulePoll();
    } catch (e) {
      if (active && stamp == _epoch) {
        error = userError(e);
        emit();
      }
    }
  }

  Future<void> reconcileReceipts(int stamp) async {
    if (_receiptSync != null) await _receiptSync;
    check(stamp);
    final unsynced = runs
        .where(
          (r) =>
              r['status'] == 'applied' &&
              r['receipt'] is Map &&
              !_syncedReceipts.contains(r['id']),
        )
        .toList();
    if (unsynced.isEmpty) return;
    final work = () async {
      try {
        final receipts =
            unsynced
                .map((r) => Map<String, dynamic>.from(r['receipt']))
                .toList()
              ..sort(
                (a, b) =>
                    (b['revision'] as int).compareTo(a['revision'] as int),
              );
        final latest = receipts.first;
        items.observeRevision(semesterId, latest['revision'] as int);
        items.invalidateRisk();
        await items.onRealityChanged?.call(latest);
        check(stamp);
        // Reminder-only changes may leave the semester revision unchanged.
        // Always reconcile the reminder feed as well as the calendar revision.
        await items.refresh();
        check(stamp);
        if (items.offline) throw ApiFailure('暂时无法同步');
        _syncedReceipts.addAll(unsynced.map((r) => r['id'] as String));
      } catch (_) {
        check(stamp);
        throw ApiFailure('修改已保存，本机安排和提醒尚未同步，请刷新。');
      }
    }();
    _receiptSync = work;
    try {
      await work;
    } finally {
      if (identical(_receiptSync, work)) _receiptSync = null;
    }
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    _poll?.cancel();
    super.dispose();
  }
}
