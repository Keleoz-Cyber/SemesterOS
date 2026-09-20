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

  Future<void> save(String key, Map<String, dynamic>? value) {
    _writes = _writes.catchError((_) {}).then((_) async {
      if (!valid()) return;
      final data = await cache.read('capture:$owner') ?? {};
      if (!valid()) return;
      if (value == null) {
        data.remove(key);
      } else {
        data[key] = value;
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
}
