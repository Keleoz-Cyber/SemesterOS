import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../core/api.dart';
import '../items/items_controller.dart';
import 'drafts.dart';

/// Media attachment state for the existing conversation composer. Recognition
/// only offers text; the caller owns edits and the explicit send action.
class InlineCaptureController extends ChangeNotifier {
  InlineCaptureController({
    required this.controller,
    required this.semesterId,
    this.onTranscript,
    Duration pollInterval = const Duration(seconds: 2),
  }) : _generation = controller.api.generation,
       // Keep the public pollInterval injection name while storing it privately.
       // ignore: prefer_initializing_formals
       _pollInterval = pollInterval,
       _owner = controller.owner {
    _drafts = CaptureDrafts(controller.cache, _owner ?? '', () => same);
    controller.addListener(_accountChanged);
    _ensurePolling();
  }

  final ItemsController controller;
  final String semesterId;
  final ValueChanged<String>? onTranscript;
  final int _generation;
  final Duration _pollInterval;
  final String? _owner;
  late final CaptureDrafts _drafts;
  Timer? _poll;
  bool _disposed = false, _working = false, _checking = false;
  int _operation = 0, _contextEpoch = 0;
  int? _checkingOperation;
  String _key = _newKey(), _kind = 'audio', _phase = 'idle';
  String _referenceAt = DateTime.now().toUtc().toIso8601String();
  String? _local, _error, _reported, _confirmedText, _confirmedReference;
  String? _scope;
  dynamic _confirmedVersion;
  Map<String, dynamic>? _pendingConfirmation;
  Map<String, dynamic>? _source;

  String get draftKey =>
      'inline:$semesterId${_scope == null ? '' : ':$_scope'}';
  bool get same =>
      !_disposed &&
      _owner != null &&
      _generation == controller.api.generation &&
      _owner == controller.owner &&
      semesterId == controller.semesterId;
  bool get busy => same && (_working || _recognizing);
  bool get hasPending => same && (_source != null || _local != null);
  Map<String, dynamic>? get source =>
      _source == null ? null : Map.unmodifiable(_source!);
  String? get error => _error;
  String get kind => _kind;
  String get referenceAt => _referenceAt;
  String? get local => _local;
  String? get localPath => _local;
  String get phase => _phase;
  bool get _recognizing => ['queued', 'running'].contains(_source?['status']);
  bool _valid(int stamp) => same && stamp == _operation;
  static String _newKey() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  static bool _sameReference(String? a, String b) {
    if (a == b) return true;
    final first = a == null ? null : DateTime.tryParse(a);
    final second = DateTime.tryParse(b);
    return first != null && second != null && first.isAtSameMomentAs(second);
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _ensurePolling() {
    if (_poll?.isActive != true) {
      _poll = Timer.periodic(_pollInterval, (_) => unawaited(checkJob()));
    }
  }

  /// Retires this composer's context locally; shared source files stay intact.
  Future<void> retireContext({String? scope}) {
    if (_disposed) return Future<void>.value();
    if (_scope == null && scope != null) _scope = scope;
    final key = draftKey;
    _operation++;
    _contextEpoch++;
    _poll?.cancel();
    _poll = null;
    _checking = false;
    _checkingOperation = null;
    _reset();
    _changed();
    final actor = _owner;
    if (actor == null) return Future<void>.value();
    // A queued cleanup must finish after page disposal, while remaining scoped
    // to the original account/generation/semester. No server cancellation or
    // file release is performed here.
    return CaptureDrafts(
      controller.cache,
      actor,
      () =>
          _generation == controller.api.generation &&
          actor == controller.owner &&
          semesterId == controller.semesterId,
    ).save(key, null);
  }

  void _accountChanged() {
    if (same || _disposed) return;
    _operation++;
    _poll?.cancel();
    _reset();
    _changed();
  }

  void _reset() {
    _source = null;
    _local = null;
    _error = null;
    _phase = 'idle';
    _working = false;
    _reported = null;
    _confirmedText = null;
    _confirmedReference = null;
    _confirmedVersion = null;
    _pendingConfirmation = null;
    _key = _newKey();
  }

  Future<void> _save() {
    final context = _contextEpoch;
    return _drafts.save(draftKey, {
      'kind': _kind,
      'local': _local,
      'key': _key,
      'source': _source,
      'reference_at': _referenceAt,
      'phase': _phase,
      'confirmed_text': _confirmedText,
      'confirmed_reference': _confirmedReference,
      'confirmed_version': _confirmedVersion,
      'pending_confirmation': _pendingConfirmation,
    }, when: () => context == _contextEpoch);
  }

  void _accept(Map<String, dynamic> value, {bool transcript = true}) {
    if (value['semester_id'] != null && value['semester_id'] != semesterId) {
      throw ApiFailure('来源不属于当前学期，请重新选择');
    }
    _source = value;
    _referenceAt = value['reference_at'] as String? ?? _referenceAt;
    _kind = value['kind'] as String? ?? _kind;
    _phase = value['status'] as String? ?? 'uploaded';
    _error = _phase == 'failed'
        ? switch (value['error_code']) {
            'EMPTY_TRANSCRIPT' || 'NO_USABLE_TEXT' =>
              _kind == 'audio'
                  ? '没有识别到语音，请重新录音或直接输入。'
                  : '没有识别到文字，请重新选择图片或直接输入。',
            'MODEL_OR_FILE_MISSING' => '识别服务或来源文件暂不可用，请稍后重试，或直接输入。',
            _ => '识别未完成，可以重试或直接输入。',
          }
        : null;
    if (transcript && _phase == 'recognized') {
      final text = (value['text'] as String? ?? '').trim();
      final token = '${value['id']}:${value['version']}';
      if (text.isNotEmpty && _reported != token) {
        _reported = token;
        onTranscript?.call(text);
      }
    }
  }

  Future<void> restore({String? scope}) async {
    if (!same || _working || hasPending) return;
    _ensurePolling();
    if (scope != null) _scope = scope;
    final stamp = ++_operation;
    _working = true;
    _changed();
    try {
      final draft = await _drafts.read(draftKey);
      if (!_valid(stamp) || draft == null) return;
      _local = draft['local'] as String?;
      _kind = draft['kind'] as String? ?? _kind;
      _key = draft['key'] as String? ?? _key;
      _referenceAt = draft['reference_at'] as String? ?? _referenceAt;
      _confirmedText = draft['confirmed_text'] as String?;
      _confirmedReference = draft['confirmed_reference'] as String?;
      _confirmedVersion = draft['confirmed_version'];
      _pendingConfirmation = draft['pending_confirmation'] == null
          ? null
          : Map<String, dynamic>.from(draft['pending_confirmation']);
      if (draft['source'] != null) {
        _accept(Map<String, dynamic>.from(draft['source']), transcript: false);
        if (_confirmedVersion == _source!['version'] &&
            _confirmedText == _source!['text'] &&
            _sameReference(_confirmedReference, _referenceAt)) {
          _reported = '${_source!['id']}:${_source!['version']}';
        }
      } else if (_local != null) {
        _phase = 'failed';
        _error = '来源还未上传，可重试继续。';
      }
    } catch (e) {
      if (_valid(stamp)) _error = userError(e);
    } finally {
      if (_valid(stamp)) {
        _working = false;
        _changed();
      }
    }
    if (_valid(stamp) && _source != null) await checkJob(force: true);
  }

  /// Copies the caller-owned temporary file before this future completes.
  Future<void> capture(String path, String kind) async {
    if (!same || busy) return;
    _ensurePolling();
    final previousLocal = _local;
    final stamp = ++_operation;
    _working = true;
    _error = null;
    _phase = 'adopting';
    _changed();
    try {
      if (!['audio', 'image'].contains(kind)) {
        throw const FormatException('不支持的来源类型');
      }
      final file = File(path);
      if (await file.length() > (kind == 'image' ? 10 : 20) * 1024 * 1024) {
        throw Exception(kind == 'image' ? '图片超过10MB，请先裁剪' : '录音超过20MB，请缩短');
      }
      if (!_valid(stamp)) return;
      final folder = await CaptureDrafts.folder(_owner!);
      if (!_valid(stamp)) return;
      await folder.create(recursive: true);
      if (!_valid(stamp)) return;
      final saved = await file.copy(
        '${folder.path}/${_newKey()}.${kind == 'audio' ? 'wav' : 'image'}',
      );
      if (!_valid(stamp)) {
        if (await saved.exists()) await saved.delete();
        return;
      }
      _reset();
      _working = true;
      _local = saved.path;
      _kind = kind;
      _referenceAt = DateTime.now().toUtc().toIso8601String();
      _phase = 'uploading';
      await _save();
      if (_valid(stamp)) {
        await CaptureDrafts.releaseFile(_owner, previousLocal);
        if (_valid(stamp)) await _uploadAndRecognize(stamp);
      }
    } catch (e) {
      if (_valid(stamp)) {
        _error = userError(e);
        _phase = 'failed';
      }
    } finally {
      if (_valid(stamp)) {
        _working = false;
        _changed();
      }
    }
    if (_valid(stamp) && _error != null && _source != null) {
      await checkJob(force: true);
    }
  }

  Future<void> _uploadAndRecognize(int stamp) async {
    if (_source == null) {
      final data = await File(_local!).readAsBytes();
      if (!_valid(stamp)) return;
      final value = await controller.api.request(
        'POST',
        '/semesters/$semesterId/sources?kind=$_kind',
        data: data,
        contentType: 'application/octet-stream',
        idempotencyKey: _key,
        receiveTimeout: const Duration(seconds: 60),
      );
      if (!_valid(stamp)) return;
      _accept(Map<String, dynamic>.from(value), transcript: false);
      await _save();
    }
    if (!_valid(stamp) || _recognizing || _source?['status'] == 'recognized') {
      return;
    }
    final value = await controller.api.request(
      'POST',
      '/sources/${_source!['id']}/recognize',
      data: {'expected_version': _source!['version']},
    );
    if (!_valid(stamp)) return;
    _accept(Map<String, dynamic>.from(value));
    await _save();
  }

  Future<void> retry() async {
    if (!same || _working || !hasPending) return;
    // An interrupted recognition request may already have reached the server.
    if (_source != null) await checkJob(force: true);
    if (!same ||
        _working ||
        _recognizing ||
        _source?['status'] == 'recognized') {
      return;
    }
    final stamp = ++_operation;
    _working = true;
    _error = null;
    _phase = _source == null ? 'uploading' : 'queued';
    _changed();
    try {
      await _uploadAndRecognize(stamp);
    } catch (e) {
      if (_valid(stamp)) {
        _error = userError(e);
        _phase = 'failed';
      }
    } finally {
      if (_valid(stamp)) {
        _working = false;
        _changed();
      }
    }
    if (_valid(stamp) && _error != null && _source != null) {
      await checkJob(force: true);
    }
  }

  Future<void> checkJob({bool force = false}) async {
    if (!same ||
        _source == null ||
        _working ||
        _checking ||
        (!force && !_recognizing)) {
      return;
    }
    final stamp = _operation, id = _source!['id'];
    _checking = true;
    _checkingOperation = stamp;
    try {
      final value = await controller.api.request('GET', '/sources/$id');
      if (!_valid(stamp) || _source?['id'] != id) return;
      _accept(
        Map<String, dynamic>.from(value),
        transcript: _pendingConfirmation == null,
      );
      await _save();
      if (_valid(stamp)) _changed();
    } catch (e) {
      if (_valid(stamp)) {
        _error = '暂时无法获取识别状态，网络恢复后会继续检查';
        _changed();
      }
    } finally {
      if (_checkingOperation == stamp) {
        _checking = false;
        _checkingOperation = null;
      }
    }
  }

  Future<void> cancel() async {
    if (!same) return;
    final stamp = ++_operation;
    _working = true;
    _changed();
    try {
      if (_source != null) {
        final value = await controller.api.request(
          'POST',
          '/sources/${_source!['id']}/cancel',
          data: {'expected_version': _source!['version']},
        );
        if (!_valid(stamp)) return;
        _accept(Map<String, dynamic>.from(value), transcript: false);
        await _save();
      } else {
        final local = _local;
        await _drafts.save(draftKey, null);
        if (!_valid(stamp)) return;
        _reset();
        _changed();
        await CaptureDrafts.releaseFile(_owner!, local);
      }
    } catch (e) {
      if (_valid(stamp)) _error = userError(e);
    } finally {
      if (_valid(stamp)) {
        _working = false;
        _changed();
      }
    }
  }

  /// Marks reviewed text only at the caller's explicit send action. Repeated
  /// sends after transport failure reuse the same source version.
  Future<Map<String, dynamic>?> confirmText(
    String text, {
    String? referenceAt,
  }) async {
    if (!same || _working || _recognizing || _source == null) return null;
    final reference = referenceAt ?? _referenceAt;
    if (_confirmedText == text &&
        _sameReference(_confirmedReference, reference) &&
        _confirmedVersion == _source!['version']) {
      return Map.of(_source!);
    }
    final stamp = ++_operation, id = _source!['id'];
    _working = true;
    _error = null;
    _changed();
    try {
      if (_pendingConfirmation != null) {
        final matched = await _reconcileConfirmation(stamp);
        if (!_valid(stamp)) return null;
        if (matched &&
            _confirmedText == text &&
            _sameReference(_confirmedReference, reference)) {
          return Map.of(_source!);
        }
        // A conflicting write is surfaced before another explicit send attempt.
        if (_error != null) return null;
      }
      _pendingConfirmation = {
        'text': text,
        'reference_at': reference,
        'version': _source!['version'],
      };
      await _save();
      if (!_valid(stamp)) return null;
      final value = await controller.api.request(
        'PATCH',
        '/sources/$id',
        data: {
          'expected_version': _source!['version'],
          'text': text,
          'reference_at': reference,
        },
      );
      if (!_valid(stamp) || _source?['id'] != id) return null;
      _accept(Map<String, dynamic>.from(value), transcript: false);
      _confirmedText = text;
      _confirmedReference = _referenceAt;
      _confirmedVersion = _source!['version'];
      _reported = '${_source!['id']}:${_source!['version']}';
      _pendingConfirmation = null;
      await _save();
      return _valid(stamp) ? Map.of(_source!) : null;
    } catch (e) {
      if (!_valid(stamp)) return null;
      _error = userError(e);
      if (_pendingConfirmation != null) {
        try {
          if (await _reconcileConfirmation(stamp) && _valid(stamp)) {
            return Map.of(_source!);
          }
        } catch (_) {
          // Retain the pending attempt; the next send refreshes before PATCH.
        }
      }
      return null;
    } finally {
      if (_valid(stamp)) {
        _working = false;
        _changed();
      }
    }
  }

  Future<bool> _reconcileConfirmation(int stamp) async {
    final attempt = _pendingConfirmation!;
    final id = _source!['id'];
    final value = Map<String, dynamic>.from(
      await controller.api.request('GET', '/sources/$id'),
    );
    if (!_valid(stamp) || _source?['id'] != id) return false;
    final failure = _error;
    _accept(value, transcript: false);
    // Equal recognition text at the original version is not proof of a saved
    // review. Require the expected version transition and exact reviewed text.
    final saved =
        attempt['version'] is int &&
        value['version'] == (attempt['version'] as int) + 1 &&
        value['text'] == attempt['text'] &&
        _sameReference(
          value['reference_at'] as String?,
          attempt['reference_at'],
        ) &&
        !_recognizing;
    _pendingConfirmation = null;
    if (saved) {
      _confirmedText = attempt['text'];
      _confirmedReference = _referenceAt;
      _confirmedVersion = value['version'];
      _reported = '$id:${value['version']}';
      _error = null;
    } else {
      _error = value['version'] != attempt['version']
          ? '来源已变化，请核对文字后再次发送。'
          : failure ?? '文字尚未保存，请再次发送重试。';
    }
    await _save();
    return saved;
  }

  /// Drops the composer attachment after successful send; the saved source stays.
  Future<void> detach() async {
    if (!same) return;
    final stamp = ++_operation;
    final local = _local;
    _working = true;
    _changed();
    try {
      await _drafts.save(draftKey, null);
      if (!_valid(stamp)) return;
      _reset();
      _changed();
      await CaptureDrafts.releaseFile(_owner!, local);
    } catch (e) {
      if (_valid(stamp)) _error = userError(e);
    } finally {
      if (_valid(stamp)) {
        _working = false;
        _changed();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _operation++;
    _poll?.cancel();
    controller.removeListener(_accountChanged);
    super.dispose();
  }
}
