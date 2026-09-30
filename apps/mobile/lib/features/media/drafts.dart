import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../core/cache.dart';

class CaptureDrafts {
  final CalendarStore cache;
  final String owner;
  final bool Function() valid;
  CaptureDrafts(this.cache, this.owner, this.valid);
  // Serialize read-modify-write operations for the actual store, without
  // coupling independent stores (or their event loops) through a global Future.
  static final _queues = Expando<Future<void>>();
  Future<void> get _writes => _queues[cache] ?? Future.value();
  set _writes(Future<void> value) => _queues[cache] = value;
  Future<Map<String, dynamic>?> read(String key) async {
    await _writes.catchError((_) {});
    if (!valid()) return null;
    final saved = await cache.read('capture:$owner');
    if (!valid() || saved?[key] == null) return null;
    return Map<String, dynamic>.from(saved![key]);
  }

  Future<void> save(
    String key,
    Map<String, dynamic>? value, {
    String? pointerKey,
    bool activatePointer = false,
  }) {
    _writes = _writes.catchError((_) {}).then((_) async {
      if (!valid()) return;
      final data = await cache.read('capture:$owner') ?? {};
      if (!valid()) return;
      if (value == null) {
        data.remove(key);
      } else {
        data[key] = value;
      }
      // A context draft and its recovery pointer must become visible together.
      if (pointerKey != null) {
        if (activatePointer && value != null) {
          data[pointerKey] = {'key': key};
        } else if (data[pointerKey]?['key'] == key) {
          data.remove(pointerKey);
        }
      }
      await cache.write('capture:$owner', data);
    });
    return _writes;
  }

  static Future<Directory> folder(String owner) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(owner)) {
      throw const FormatException('无效账号标识');
    }
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/capture/$owner');
  }

  static Future<void> clearUser(CalendarStore cache, String owner) {
    final operation = (_queues[cache] ?? Future<void>.value())
        .catchError((_) {})
        .then((_) async {
          await cache.clear('capture:$owner');
          final dir = await folder(owner);
          if (await dir.exists()) await dir.delete(recursive: true);
        });
    _queues[cache] = operation;
    return operation;
  }

  static Future<void> clearSemester(
    CalendarStore cache,
    String owner,
    String semesterId,
  ) {
    bool belongs(String key) =>
        [
          'text:$semesterId',
          'assistant:$semesterId',
          'assistant-context:$semesterId:',
          'assistant-context-latest:$semesterId',
          'inline:$semesterId',
          'media:$semesterId',
          'operation:$semesterId',
        ].any(
          (prefix) => prefix.endsWith(':')
              ? key.startsWith(prefix)
              : key == prefix || key.startsWith('$prefix:'),
        );
    final operation = (_queues[cache] ?? Future<void>.value())
        .catchError((_) {})
        .then((_) async {
          final data = await cache.read('capture:$owner') ?? {};
          final files = <String>[];
          for (final key in data.keys.where(belongs).toList()) {
            final value = data.remove(key);
            if (value is Map && value['local'] is String) {
              files.add(value['local'] as String);
            }
          }
          await cache.write('capture:$owner', data);
          if (files.isEmpty) return;
          final directory = await folder(owner);
          if (!await directory.exists()) return;
          final base = await directory.resolveSymbolicLinks();
          for (final path in files) {
            try {
              final file = File(path);
              if (!await file.exists()) continue;
              final resolved = await file.resolveSymbolicLinks();
              if (resolved.startsWith('$base${Platform.pathSeparator}')) {
                await file.delete();
              }
            } on FileSystemException {
              // A vanished temporary attachment cannot be reopened later.
            }
          }
        });
    _queues[cache] = operation;
    return operation;
  }
}
