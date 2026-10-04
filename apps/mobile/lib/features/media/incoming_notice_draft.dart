import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/cache.dart';

const noticeInputChannel = MethodChannel('cn.semesteros/incoming_notice');

/// A system share is an editable input. Receiving it never creates a run.
class IncomingNoticeDraft {
  final String id, text;
  final List<String> imagePaths;
  final String? warning;
  const IncomingNoticeDraft({
    required this.id,
    this.text = '',
    this.imagePaths = const [],
    this.warning,
  });

  bool get isEmpty =>
      text.trim().isEmpty && imagePaths.isEmpty && (warning?.isEmpty ?? true);
  factory IncomingNoticeDraft.fromJson(Map<String, dynamic> value) =>
      IncomingNoticeDraft(
        id: '${value['id']}',
        text: value['text'] as String? ?? '',
        imagePaths: (value['image_paths'] as List? ?? [])
            .whereType<String>()
            .toList(growable: false),
        warning: value['warning'] as String?,
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'image_paths': imagePaths,
    if (warning != null) 'warning': warning,
  };
}

/// Persists shares while authentication and semester setup are in progress.
/// Native acknowledgement happens only after the local copy is durable.
class IncomingNoticeController extends ChangeNotifier {
  IncomingNoticeController(this.cache, {MethodChannel? channel})
    : channel = channel ?? noticeInputChannel;
  final CalendarStore cache;
  final MethodChannel channel;
  static const _cacheKey = 'device:incoming-notice-drafts';
  final List<IncomingNoticeDraft> _pending = [];
  Future<void> _operations = Future.value();
  bool _disposed = false, ready = false;
  IncomingNoticeDraft? get next => _pending.firstOrNull;
  int get count => _pending.length;

  Future<void> initialize() async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'incomingDraft' && call.arguments is Map) {
        await add(
          IncomingNoticeDraft.fromJson(
            Map<String, dynamic>.from(call.arguments),
          ),
        );
      }
    });
    try {
      final saved = await cache.read(_cacheKey);
      if (_disposed) return;
      for (final value in (saved?['drafts'] as List? ?? []).whereType<Map>()) {
        final draft = IncomingNoticeDraft.fromJson(
          Map<String, dynamic>.from(value),
        );
        if (!draft.isEmpty && !_pending.any((old) => old.id == draft.id)) {
          _pending.add(draft);
        }
      }
      final native = await channel.invokeListMethod<dynamic>(
        'getPendingDrafts',
      );
      for (final value in (native ?? []).whereType<Map>()) {
        await add(
          IncomingNoticeDraft.fromJson(Map<String, dynamic>.from(value)),
        );
      }
    } on MissingPluginException {
      // Shares are Android-native; other platforms can still retain local input.
    } catch (_) {
      // Keep native input unacknowledged if local storage cannot retain it.
    } finally {
      if (!_disposed) {
        ready = true;
        notifyListeners();
      }
    }
  }

  Future<void> _queue(Future<void> Function() action) {
    final work = _operations.catchError((Object _) {}).then((_) async {
      if (!_disposed) await action();
    });
    _operations = work;
    return work;
  }

  Future<void> add(IncomingNoticeDraft draft) => _queue(() async {
    if (draft.isEmpty) return;
    if (!_pending.any((old) => old.id == draft.id)) _pending.add(draft);
    await _save();
    try {
      await channel.invokeMethod<void>('acknowledgeDraft', {'id': draft.id});
    } on MissingPluginException {
      // Dart callers do not require a native acknowledgement.
    }
    if (!_disposed) notifyListeners();
  });

  /// Called after the composer has adopted and persisted the editable draft.
  Future<void> accepted(String id) => _queue(() async {
    _pending.removeWhere((draft) => draft.id == id);
    await _save();
    if (!_disposed) notifyListeners();
  });

  Future<void> _save() => cache.write(_cacheKey, {
    'drafts': _pending.map((draft) => draft.toJson()).toList(),
  });

  @override
  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}

/// Delete only native-owned share copies after upload or explicit removal.
Future<void> releaseNoticeImages(Iterable<String> paths) async {
  if (paths.isEmpty) return;
  try {
    if (Platform.isAndroid) {
      final root = Directory(
        '${(await getApplicationSupportDirectory()).path}/notice-drafts',
      );
      if (await root.exists()) {
        final owned = await root.resolveSymbolicLinks();
        for (final path in paths) {
          final file = File(path);
          if (await file.exists() &&
              await file.parent.resolveSymbolicLinks() == owned &&
              file.uri.pathSegments.last.startsWith('draft_')) {
            await file.delete();
          }
        }
      }
    }
  } on FileSystemException {
    /* Cleanup cannot invalidate an upload. */
  }
  try {
    await noticeInputChannel.invokeMethod<void>('releaseImages', {
      'paths': paths.toList(),
    });
  } on MissingPluginException {
    // Image-picker files remain owned by that plugin.
  } on PlatformException {
    // Cleanup cannot invalidate a successfully uploaded notice.
  }
}

/// Picker cache files are copied into app storage before a draft is acknowledged.
Future<List<String>> retainNoticeImages(Iterable<String> paths) async {
  if (!Platform.isAndroid) return paths.toList();
  final root = Directory(
    '${(await getApplicationSupportDirectory()).path}/notice-drafts',
  );
  await root.create(recursive: true);
  final result = <String>[];
  for (final path in paths) {
    final file = File(path);
    if (await file.parent.resolveSymbolicLinks() ==
        await root.resolveSymbolicLinks()) {
      result.add(path);
      continue;
    }
    final name = file.uri.pathSegments.last;
    final ext =
        RegExp(r'\.[A-Za-z0-9]{1,8}$').firstMatch(name)?.group(0) ?? '.png';
    final target =
        '${root.path}/draft_${DateTime.now().microsecondsSinceEpoch}_${result.length}$ext';
    await file.copy(target);
    result.add(target);
  }
  return result;
}
