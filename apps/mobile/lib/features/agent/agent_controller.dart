import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/api.dart';
import '../../ui/assistant_scope.dart' show AssistantBrowsingContext;
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
  bool historyLoading = false, earlierLoading = false;
  bool hasMoreThreads = false, hasMoreRuns = false;
  String? threadCursor, runCursor;
  final Set<String> loadingCards = {};
  int _epoch = 0;
  int get contextVersion => _epoch;
  Timer? _poll;
  String? _pendingText, _pendingId;
  final Set<String> _syncedReceipts = {};
  Future<void>? _receiptSync;
  Map<String, dynamic>? mediaRun;
  AgentController(this.items, this.semesterId);
  bool get active =>
      !_closed &&
      items.api.generation == generation &&
      items.semesterId == semesterId;
  bool get processing =>
      mediaProcessing ||
      runs.any(
        (r) => {'queued', 'running', 'recognizing'}.contains(r['status']),
      );
  bool get mediaProcessing =>
      mediaRun != null &&
      mediaRun!['run'] == null &&
      {
        'queued',
        'running',
        'uploaded',
        'recognized',
      }.contains(mediaRun!['status']);
  String? get mediaStatus => mediaRun?['status'] as String?;
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

  Future<dynamic> request(
    String method,
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
  }) => items.api.request(method, path, data: data, queryParameters: query);
  Future<void> open({String? id, bool fresh = false}) async {
    final stamp = ++_epoch;
    _poll?.cancel();
    historyLoading = earlierLoading = false;
    loading = true;
    error = null;
    mediaRun = null;
    emit();
    if (fresh) {
      mediaRun = null;
      threadId = null;
      runs = [];
      hasMoreRuns = false;
      runCursor = null;
      _pendingId = _pendingText = null;
      loading = false;
      emit();
      return;
    }
    try {
      if (id == null) {
        final all = await request(
          'GET',
          '/agent/threads?semester_id=$semesterId',
        );
        check(stamp);
        threads = rows(all);
      }
      threadId = id ?? (threads.isEmpty ? null : threads.first['id'] as String);
      runs = [];
      if (threadId != null) {
        final value = await request(
          'GET',
          '/agent/threads/$threadId',
          query: {'limit': 20},
        );
        check(stamp);
        if (value['semester_id'] != null &&
            value['semester_id'] != semesterId) {
          threadId = null;
          throw ApiFailure('这段对话属于其他学期，请先切换学期');
        }
        runs = rows(value['runs']);
        hasMoreRuns = value['has_more'] == true;
        runCursor = value['next_cursor'] as String?;
        await reconcileReceipts(stamp);
      }
      final recent = runs.lastOrNull;
      if (recent?['media_run_id'] is String &&
          {'recognizing', 'failed', 'cancelled'}.contains(recent?['status'])) {
        final value = Map<String, dynamic>.from(
          await request('GET', '/agent/media-runs/${recent!['media_run_id']}'),
        );
        check(stamp);
        _acceptMediaRun(value);
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

  Future<void> loadHistory({bool reset = false}) async {
    if (historyLoading || !active || (!reset && !hasMoreThreads)) return;
    final stamp = _epoch;
    historyLoading = true;
    error = null;
    emit();
    try {
      final value = await request(
        'GET',
        '/agent/history',
        query: {
          'semester_id': semesterId,
          'limit': 20,
          if (!reset && threadCursor != null) 'before_thread_id': threadCursor,
        },
      );
      check(stamp);
      final page = rows(value['threads']);
      threads = reset
          ? page
          : [
              ...threads,
              ...page.where((r) => !threads.any((old) => old['id'] == r['id'])),
            ];
      hasMoreThreads = value['has_more'] == true;
      threadCursor = value['next_cursor'] as String?;
    } catch (e) {
      if (active && stamp == _epoch) error = userError(e);
    } finally {
      if (active && stamp == _epoch) {
        historyLoading = false;
        emit();
      }
    }
  }

  Future<void> loadEarlier() async {
    if (earlierLoading || !active || !hasMoreRuns || threadId == null) return;
    final stamp = _epoch;
    final target = threadId;
    earlierLoading = true;
    error = null;
    emit();
    try {
      final value = await request(
        'GET',
        '/agent/threads/$target',
        query: {'limit': 20, if (runCursor != null) 'before_run_id': runCursor},
      );
      check(stamp);
      final page = rows(value['runs']);
      runs = [
        ...page.where((r) => !runs.any((old) => old['id'] == r['id'])),
        ...runs,
      ];
      hasMoreRuns = value['has_more'] == true;
      runCursor = value['next_cursor'] as String?;
    } catch (e) {
      if (active && stamp == _epoch) error = userError(e);
    } finally {
      if (active && stamp == _epoch) {
        earlierLoading = false;
        emit();
      }
    }
  }

  Future<void> loadCard(String runId, Map<String, dynamic> card) async {
    final cardId = card['card_id'] as String?;
    final key = '$runId:$cardId';
    if (!active ||
        cardId == null ||
        loadingCards.contains(key) ||
        card['has_more'] != true) {
      return;
    }
    final stamp = _epoch;
    loadingCards.add(key);
    error = null;
    emit();
    try {
      final value = await request(
        'GET',
        '/agent/runs/$runId/cards/$cardId',
        query: {'offset': card['next_offset'] ?? 5, 'limit': 20},
      );
      check(stamp);
      final next = Map<String, dynamic>.from(value['card']);
      final oldData = Map<String, dynamic>.from(card['data'] ?? {});
      final nextData = Map<String, dynamic>.from(next['data'] ?? {});
      for (final field in [
        'entries',
        'undated',
        'records',
        'occurrences',
        'windows',
        'actions',
        'tasks',
        'blocks',
      ]) {
        if (!oldData.containsKey(field) && !nextData.containsKey(field)) {
          continue;
        }
        final before = rows(oldData[field]);
        String identity(Map<String, dynamic> row) => row['id'] != null
            ? '${row['resource_type']}:${row['id']}:${row['start_at']}'
            : jsonEncode(row);
        final seen = before.map(identity).toSet();
        nextData[field] = [
          ...before,
          ...rows(nextData[field]).where((row) => seen.add(identity(row))),
        ];
      }
      final merged = {
        ...card,
        ...next,
        'data': {...oldData, ...nextData},
        'has_more': value['has_more'] == true,
        'next_offset': value['next_offset'],
      };
      runs = runs
          .map(
            (run) => run['id'] != runId
                ? run
                : <String, dynamic>{
                    ...run,
                    'cards': rows(run['cards'])
                        .map((old) => old['card_id'] == cardId ? merged : old)
                        .toList(),
                  },
          )
          .toList();
    } catch (e) {
      if (active && stamp == _epoch) error = userError(e);
    } finally {
      loadingCards.remove(key);
      if (active && stamp == _epoch) emit();
    }
  }

  Future<bool> revise(
    Map<String, dynamic> run,
    String text, {
    String inputKind = 'message',
    Map<String, dynamic>? source,
    bool detachSource = false,
    AssistantBrowsingContext? browsingContext,
  }) async {
    if (busy || processing || !active || text.trim().isEmpty) return false;
    final stamp = ++_epoch;
    _poll?.cancel();
    busy = true;
    error = null;
    emit();
    try {
      final signature =
          'revise:${run['id']}:$text:${source?['id']}:${source?['version']}:$detachSource:$inputKind:${jsonEncode(browsingContext?.toJson())}';
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
          '/agent/runs/${run['id']}/revise',
          data: {
            'text': text.trim(),
            'request_id': _pendingId,
            'input_kind': inputKind,
            if (browsingContext != null)
              'browsing_context': browsingContext.toJson(),
            if (source != null) 'source_id': source['id'],
            if (source != null) 'source_version': source['version'],
            if (detachSource) 'detach_source': true,
          },
        ),
      );
      check(stamp);
      threadId = value['thread_id'] as String;
      runs = [value];
      hasMoreRuns = false;
      runCursor = null;
      emit();
      try {
        final page = await request(
          'GET',
          '/agent/threads/$threadId',
          query: {'limit': 20},
        );
        check(stamp);
        runs = rows(page['runs']);
        replace(value);
        hasMoreRuns = page['has_more'] == true;
        runCursor = page['next_cursor'] as String?;
      } catch (e) {
        check(stamp);
        error = userError(e);
      }
      _pendingId = _pendingText = null;
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

  void schedulePoll() {
    _poll?.cancel();
    if (active && processing) _poll = Timer(const Duration(seconds: 2), poll);
  }

  Future<void> poll() async {
    final stamp = _epoch;
    final pending = runs
        .where(
          (r) => {'queued', 'running', 'recognizing'}.contains(r['status']),
        )
        .toList();
    try {
      if (mediaProcessing) {
        final value = Map<String, dynamic>.from(
          await request('GET', '/agent/media-runs/${mediaRun!['id']}'),
        );
        check(stamp);
        _acceptMediaRun(value);
      }
      for (final row in pending) {
        final value = Map<String, dynamic>.from(
          await request('GET', '/agent/runs/${row['id']}'),
        );
        check(stamp);
        replace(value);
      }
      if (mediaRun?['status'] != 'failed') error = null;
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

  void _acceptMediaRun(Map<String, dynamic> value) {
    mediaRun = value;
    final thread = value['thread'];
    if (thread is Map && thread['id'] is String) threadId = thread['id'];
    final run = value['run'];
    if (run is Map) {
      final row = Map<String, dynamic>.from(run);
      threadId = row['thread_id'] as String? ?? threadId;
      runs = [
        for (final old in runs)
          if (old['status'] == 'needs_confirmation')
            {...old, 'status': 'superseded'}
          else
            old,
      ];
      replace(row);
      error = null;
    } else if (value['status'] == 'failed') {
      error = '图片识别未完成，请重新选择图片或粘贴通知文字。';
    } else {
      final source = value['source'];
      final metadata = source is Map ? source['recognition'] : null;
      final runId = metadata is Map ? metadata['agent_run_id'] : null;
      final existing = runs.where((row) => row['id'] == runId).firstOrNull;
      if (existing != null) {
        replace({
          ...existing,
          'status': 'recognizing',
          'stage': value['stage'],
          'progress': value['progress'] ?? [],
          'error': null,
        });
      }
    }
  }

  Future<void> cancelMedia() async {
    if (busy || !active || mediaRun == null) return;
    final stamp = _epoch, id = mediaRun!['id'];
    busy = true;
    error = null;
    emit();
    try {
      final value = Map<String, dynamic>.from(
        await request('POST', '/agent/media-runs/$id/cancel'),
      );
      check(stamp);
      _acceptMediaRun(value);
    } catch (e) {
      if (active && stamp == _epoch) error = userError(e);
    } finally {
      if (active && stamp == _epoch) {
        busy = false;
        emit();
        schedulePoll();
      }
    }
  }

  Future<void> refreshMedia() async {
    if (busy || !active || mediaRun == null) return;
    final stamp = _epoch, id = mediaRun!['id'];
    busy = true;
    error = null;
    emit();
    try {
      final value = Map<String, dynamic>.from(
        await request('GET', '/agent/media-runs/$id'),
      );
      check(stamp);
      _acceptMediaRun(value);
    } catch (e) {
      if (active && stamp == _epoch) error = userError(e);
    } finally {
      if (active && stamp == _epoch) {
        busy = false;
        emit();
        schedulePoll();
      }
    }
  }

  Future<bool> retryMedia({
    AssistantBrowsingContext? browsingContext,
    bool useCurrentContext = false,
  }) async {
    if (busy || !active || mediaRun == null || processing) return false;
    final stamp = _epoch, id = mediaRun!['id'];
    final source = mediaRun!['source'];
    if (source is! Map) return false;
    busy = true;
    error = null;
    emit();
    try {
      final value = Map<String, dynamic>.from(
        await request(
          'POST',
          '/agent/media-runs/$id/retry',
          data: {
            'expected_version': source['version'],
            if (useCurrentContext)
              'browsing_context': browsingContext?.toJson(),
          },
        ),
      );
      check(stamp);
      _acceptMediaRun(value);
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

  /// Called only by the composer's explicit send. All pages form one notice.
  Future<bool> sendImages(
    List<String> paths, {
    String instruction = '',
    String? clientRequestId,
    AssistantBrowsingContext? browsingContext,
  }) async {
    if (busy || processing || !active || paths.isEmpty) return false;
    final stamp = _epoch;
    busy = true;
    error = null;
    emit();
    try {
      final signature =
          'images:${paths.join('\u0000')}:$instruction:${jsonEncode(browsingContext?.toJson())}';
      if (_pendingText != signature || _pendingId == null) {
        _pendingText = signature;
        _pendingId =
            clientRequestId ??
            List.generate(
              16,
              (_) => Random.secure()
                  .nextInt(256)
                  .toRadixString(16)
                  .padLeft(2, '0'),
            ).join();
      }
      final files = <MapEntry<String, MultipartFile>>[];
      for (final path in paths) {
        files.add(MapEntry('files', await MultipartFile.fromFile(path)));
        check(stamp);
      }
      final payload = FormData();
      payload.fields.addAll([
        MapEntry('semester_id', semesterId),
        const MapEntry('kind', 'image'),
        MapEntry('client_request_id', _pendingId!),
        if (threadId != null) MapEntry('thread_id', threadId!),
        if (instruction.trim().isNotEmpty)
          MapEntry('instruction', instruction.trim()),
        if (browsingContext != null)
          MapEntry('browsing_context', jsonEncode(browsingContext.toJson())),
      ]);
      payload.files.addAll(files);
      final value = Map<String, dynamic>.from(
        await items.api.request(
          'POST',
          '/agent/media-runs',
          data: payload,
          receiveTimeout: const Duration(seconds: 60),
          idempotencyKey: _pendingId,
        ),
      );
      check(stamp);
      _acceptMediaRun(value);
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

  void replace(Map<String, dynamic> value) {
    if (value['status'] == 'applied' && value['preview']?['kind'] == 'undo') {
      final sourceId = value['preview']['source_run_id'];
      runs = [
        for (final row in runs)
          if (row['id'] == sourceId)
            {...row, 'undo_available': false, 'undone_by': value['id']}
          else
            row,
      ];
    }
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
    String inputKind = 'message',
    Map<String, dynamic>? source,
    List<String> selectedRecordIds = const [],
    List<String> contextRecordIds = const [],
    bool detachSource = false,
    AssistantBrowsingContext? browsingContext,
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
          '$text\u0000${source?['id'] ?? ''}:${source?['version'] ?? ''}:${selectedRecordIds.join(',')}:${contextRecordIds.join(',')}:$detachSource:$inputKind:${jsonEncode(browsingContext?.toJson())}';
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
            'input_kind': inputKind,
            if (browsingContext != null)
              'browsing_context': browsingContext.toJson(),
            if (source != null) 'source_id': source['id'],
            if (source != null) 'source_version': source['version'],
            if (selectedRecordIds.isNotEmpty)
              'selected_record_ids': selectedRecordIds,
            if (contextRecordIds.isNotEmpty)
              'context_record_ids': contextRecordIds,
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

  Future<void> decide(
    Map<String, dynamic> run,
    bool confirm, {
    List<String>? selectedGroupIds,
    bool confirmFixedConflicts = false,
  }) async {
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
            'selected_group_ids': ?selectedGroupIds,
            if (confirmFixedConflicts) 'confirm_fixed_conflicts': true,
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

  final Map<String, String> _undoRequests = {};
  Future<Map<String, dynamic>> selectionPreview(
    Map<String, dynamic> run,
    List<String> ids,
  ) async {
    if (!active) throw ApiFailure('账号或学期已切换，请重新打开');
    final stamp = _epoch;
    final value = Map<String, dynamic>.from(
      await request(
        'POST',
        '/agent/runs/${run['id']}/selection-preview',
        data: {'token': run['preview']['token'], 'selected_group_ids': ids},
      ),
    );
    check(stamp);
    return Map<String, dynamic>.from(value['impact']);
  }

  Future<void> requestUndo(Map<String, dynamic> run) async {
    if (busy || processing || !active) return;
    final stamp = _epoch;
    busy = true;
    error = null;
    emit();
    final key = _undoRequests.putIfAbsent(
      run['id'],
      () => List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
    );
    try {
      final value = Map<String, dynamic>.from(
        await request(
          'POST',
          '/agent/runs/${run['id']}/request-undo',
          data: {'request_id': key},
        ),
      );
      check(stamp);
      runs = [
        for (final r in runs)
          if (r['status'] == 'needs_confirmation')
            {...r, 'status': 'superseded'}
          else
            r,
      ];
      replace(value);
      _undoRequests.remove(run['id']);
    } catch (e) {
      if (active && stamp == _epoch) error = userError(e);
    } finally {
      if (active && stamp == _epoch) {
        busy = false;
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
              r['context_only'] != true &&
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
