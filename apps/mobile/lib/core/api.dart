import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiFailure implements Exception {
  final String message;
  final bool unauthorized;
  final bool staleSession;
  ApiFailure(
    this.message, {
    this.unauthorized = false,
    this.staleSession = false,
  });
  @override
  String toString() => message;
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
                defaultValue: 'http://10.0.2.2:8871',
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
      throw ApiFailure('暂时无法刷新登录，请稍后重试；本机课表仍保留');
    }
  }

  Future<dynamic> request(
    String method,
    String path, {
    dynamic data,
    bool authenticated = true,
    String? idempotencyKey,
    Duration? receiveTimeout,
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
          data: data,
          options: Options(
            method: method,
            receiveTimeout: receiveTimeout,
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
        final response = e.response?.data;
        throw ApiFailure(
          response is Map
              ? '${response['message'] ?? '操作未完成，请重试'}'
              : '无法连接服务，请检查网络；已保存课表仍可查看',
          unauthorized: e.response?.statusCode == 401 && authenticated,
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
