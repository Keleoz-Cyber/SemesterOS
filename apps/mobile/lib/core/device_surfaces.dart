import 'dart:convert';
import 'package:flutter/services.dart';
import 'api.dart';

/// Native surfaces use a small, owner-scoped snapshot; no credentials leave Dart.
abstract final class DeviceSurfaces {
  static const channel = MethodChannel('cn.semesteros/device_surfaces');
  static Future<Map<String, dynamic>> status() async =>
      Map<String, dynamic>.from(await channel.invokeMethod('status') ?? {});
  static Future<void> sync(Map<String, dynamic> snapshot) async {
    try {
      await channel.invokeMethod('sync', jsonEncode(snapshot));
    } on MissingPluginException {
      /* Native surfaces are Android-only. */
    }
  }

  static Future<void> clear() => sync({});
  static Future<void> action(String name, [Map<String, dynamic>? data]) async {
    try {
      await channel.invokeMethod(name, data);
    } on PlatformException catch (e) {
      throw ApiFailure(
        e.message != null && RegExp(r'[\u4e00-\u9fff]').hasMatch(e.message!)
            ? e.message!
            : '系统暂未完成操作，请重试',
      );
    }
  }

  static Future<bool> export(Map<String, dynamic> data) async =>
      await channel.invokeMethod<bool>(
        'export',
        const JsonEncoder.withIndent('  ').convert(data),
      ) ??
      false;
}
