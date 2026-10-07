import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiFailure implements Exception {
  final String message;
  final String? code;
  final bool unauthorized;
  final bool staleSession;
  final int? statusCode;
  ApiFailure(
    this.message, {
    this.code,
    this.unauthorized = false,
    this.staleSession = false,
    this.statusCode,
  });
  @override
  String toString() => message;
}

/// Keep actionable messages, without exposing plugin errors or stack details.
String userError(Object error) {
  if (error is ApiFailure &&
      RegExp(r'[\u4e00-\u9fff]').hasMatch(error.message)) {
    return error.message;
  }
  if (error is FormatException &&
      RegExp(r'[\u4e00-\u9fff]').hasMatch(error.message)) {
    return error.message;
  }
  final text = error.toString();
  if (text.startsWith('Exception: ')) {
    final message = text.substring('Exception: '.length);
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(message)) return message;
  }
  return '暂时没能完成，请重试。如果仍有问题，可以返回后重新打开。';
}

bool _isTimeout(DioExceptionType type) =>
    type == DioExceptionType.connectionTimeout ||
    type == DioExceptionType.receiveTimeout ||
    type == DioExceptionType.sendTimeout;

ApiFailure _transportFailure(DioException error) {
  if (_isTimeout(error.type)) {
    return ApiFailure('等待时间有点长，请稍后重试。已保存的内容不受影响。', code: 'NETWORK_TIMEOUT');
  }
  final cause = error.error;
  if (error.type == DioExceptionType.badCertificate || cause is TlsException) {
    return ApiFailure(
      '无法建立安全连接，请检查设备日期时间与网络后重试。已保存的课表仍可查看。',
      code: 'NETWORK_TLS',
    );
  }
  // Inspect only the native failure category; never expose its host or details.
  if (cause is SocketException &&
      cause.message.toLowerCase().startsWith('failed host lookup')) {
    return ApiFailure(
      '无法解析服务地址，请检查网络或切换网络后重试。已保存的课表仍可查看。',
      code: 'NETWORK_DNS',
    );
  }
  if (error.type == DioExceptionType.connectionError ||
      cause is SocketException) {
    return ApiFailure(
      '暂时无法连接服务，请检查网络后重试。已保存的课表仍可查看。',
      code: 'NETWORK_CONNECTION',
    );
  }
  return ApiFailure('暂时连接不上，请检查网络后重试。已保存的课表仍可查看。', code: 'NETWORK_UNAVAILABLE');
}

class SemesterApi {
  final Dio dio;
  final FlutterSecureStorage storage;
  Map<String, dynamic>? session;
  Future<void>? _refreshing;
  Future<void> _storageWrites = Future.value();
  int generation = 0;
  SemesterApi({String? baseUrl, FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage(),
      dio = Dio(
        BaseOptions(
          baseUrl:
              baseUrl ??
              const String.fromEnvironment(
                'API_BASE_URL',
                defaultValue: kDebugMode
                    ? 'http://10.0.2.2:8871'
                    : 'https://semesteros.keleoz.com',
              ),
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

  Future<void> restore() async {
    final stamp = generation;
    final value = await storage.read(key: 'semesteros_session');
    if (stamp == generation && value != null) {
      session = Map<String, dynamic>.from(jsonDecode(value));
      generation++;
    }
  }

  void checkSession(int stamp) {
    if (stamp != generation) {
      throw ApiFailure('账户已切换，已忽略旧请求', staleSession: true);
    }
  }

  Future<void> saveSession(
    Map<String, dynamic> value, {
    bool replacement = true,
  }) async {
    if (replacement) {
      generation++;
      _refreshing = null;
    }
    session = Map.of(value)..remove('recovery_code');
    final stamp = generation;
    final encoded = jsonEncode(session);
    _storageWrites = _storageWrites.catchError((Object _) {}).then((_) async {
      if (stamp == generation) {
        await storage.write(key: 'semesteros_session', value: encoded);
      }
    });
    await _storageWrites;
    checkSession(stamp);
  }

  Future<void> forget() async {
    generation++;
    _refreshing = null;
    session = null;
    _storageWrites = _storageWrites
        .catchError((Object _) {})
        .then((_) => storage.delete(key: 'semesteros_session'));
    await _storageWrites;
  }

  Future<void> _refresh(int stamp) async {
    checkSession(stamp);
    try {
      final result = await dio.post(
        '/api/v1/auth/refresh',
        data: {'refresh_token': session?['refresh_token']},
      );
      checkSession(stamp);
      await saveSession({
        ...Map<String, dynamic>.from(result.data),
        'logout_token': session?['logout_token'],
      }, replacement: false);
    } on DioException catch (e) {
      checkSession(stamp);
      if (e.response?.statusCode == 401) {
        throw ApiFailure('登录已过期，请重新登录', unauthorized: true);
      }
      if (e.response == null) throw _transportFailure(e);
      throw ApiFailure('暂时无法验证登录状态，请稍后重试。本机课表仍可查看。');
    }
  }

  Future<dynamic> request(
    String method,
    String path, {
    dynamic data,
    bool authenticated = true,
    String? idempotencyKey,
    Duration? receiveTimeout,
    String? contentType,
    ResponseType? responseType,
    Map<String, dynamic>? queryParameters,
  }) async {
    final stamp = generation;
    final key =
        idempotencyKey ??
        List.generate(
          20,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    for (var attempt = 0; attempt < 2; attempt++) {
      if (authenticated) checkSession(stamp);
      try {
        final response = await dio.request(
          '/api/v1$path',
          data: data is FormData ? data.clone() : data,
          queryParameters: queryParameters,
          options: Options(
            method: method,
            receiveTimeout: receiveTimeout,
            contentType: contentType,
            responseType: responseType,
            headers: {
              if (authenticated)
                'Authorization': 'Bearer ${session?['access_token']}',
              if (method != 'GET') 'Idempotency-Key': key,
            },
          ),
        );
        if (authenticated) checkSession(stamp);
        return response.data;
      } on DioException catch (e) {
        if (authenticated) checkSession(stamp);
        if (e.response?.statusCode == 401 &&
            authenticated &&
            attempt == 0 &&
            session != null) {
          final refresh = _refreshing ??= _refresh(stamp);
          try {
            await refresh;
          } finally {
            if (identical(_refreshing, refresh)) _refreshing = null;
          }
          continue;
        }
        if (e.response == null) throw _transportFailure(e);
        final response = e.response?.data;
        throw ApiFailure(
          response is Map && response['message'] is String
              ? response['message'] as String
              : _isTimeout(e.type)
              ? '等待时间有点长，请稍后重试。已保存的内容不受影响。'
              : '服务暂时不可用，请稍后重试。已保存的内容不受影响。',
          unauthorized: e.response?.statusCode == 401 && authenticated,
          statusCode: e.response?.statusCode,
          code: response is Map && response['code'] is String
              ? response['code'] as String
              : null,
        );
      }
    }
    throw ApiFailure('请求未完成');
  }

  Future<void> revokeSession(Map<String, dynamic> captured) async {
    // This capability only revokes its original session; never refresh or restore it.
    try {
      await dio.post(
        '/api/v1/auth/logout',
        data: captured['logout_token'] == null
            ? null
            : {'logout_token': captured['logout_token']},
        options: Options(
          headers: captured['logout_token'] == null
              ? {'Authorization': 'Bearer ${captured['access_token']}'}
              : {},
        ),
      );
    } on DioException {
      /* Device logout is immediate; offline server revocation is not guaranteed. */
    }
  }
}
