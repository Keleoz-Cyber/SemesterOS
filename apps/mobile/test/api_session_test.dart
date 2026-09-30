import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/core/api.dart';

class ControlledTransport implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) respond;
  ControlledTransport(this.respond);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => respond(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody body(dynamic value, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(value),
  status,
  headers: {
    'content-type': ['application/json'],
  },
);
Map<String, dynamic> account(String id) => {
  'user': {'id': id, 'username': id},
  'access_token': 'access-$id',
  'refresh_token': 'refresh-$id',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('cloud base URL preserves the HTTPS deployment path', () async {
    final api = SemesterApi(baseUrl: 'https://keleoz.com/semesteros')
      ..session = account('preview');
    api.dio.httpClientAdapter = ControlledTransport((r) async {
      expect(
        r.uri.toString(),
        'https://keleoz.com/semesteros/api/v1/semesters',
      );
      return body([]);
    });
    expect(await api.request('GET', '/semesters'), isEmpty);
    api.dio.close();
  });
  test(
    'user errors preserve recovery instructions without raw exception details',
    () {
      expect(userError(ApiFailure('登录已过期，请重新登录')), '登录已过期，请重新登录');
      expect(userError(Exception('请选择提醒时间')), '请选择提醒时间');
      expect(userError(const FormatException('请填写正确的日期')), '请填写正确的日期');
      final hidden = userError(StateError('private plugin diagnostics'));
      expect(hidden, isNot(contains('StateError')));
      expect(hidden, isNot(contains('private')));
      expect(userError(ApiFailure('Internal Server Error')), hidden);
      expect(hidden, contains('重试'));
    },
  );
  test(
    'HTTP failure and connection failure give different recovery messages',
    () async {
      final api = SemesterApi()..session = account('preview');
      api.dio.httpClientAdapter = ControlledTransport(
        (r) async => body('upstream error', 500),
      );
      await expectLater(
        api.request('GET', '/items'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            contains('服务暂时不可用'),
          ),
        ),
      );
      api.dio.httpClientAdapter = ControlledTransport(
        (r) async => throw DioException(
          requestOptions: r,
          type: DioExceptionType.connectionError,
        ),
      );
      await expectLater(
        api.request('GET', '/items'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            contains('检查网络'),
          ),
        ),
      );
      api.dio.close();
    },
  );
  test(
    'calendar mismatch keeps its code for an actionable settings link',
    () async {
      final api = SemesterApi()..session = account('preview');
      api.dio.httpClientAdapter = ControlledTransport(
        (_) async => body({
          'code': 'CALENDAR_MISMATCH',
          'message': '课表使用第11节，请补上该节时间',
        }, 422),
      );
      await expectLater(
        api.request('POST', '/imports', data: {}),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.code, 'code', 'CALENDAR_MISMATCH')
              .having((e) => e.message, 'message', contains('第11节')),
        ),
      );
      api.dio.close();
    },
  );
  test(
    'a delayed response from account A cannot be used by account B',
    () async {
      final api = SemesterApi();
      final pending = Completer<ResponseBody>();
      final started = Completer<void>();
      api.dio.httpClientAdapter = ControlledTransport((_) {
        started.complete();
        return pending.future;
      });
      await api.saveSession(account('a'));
      final request = api.request('GET', '/semesters');
      await started.future;
      await api.forget();
      await api.saveSession(account('b'));
      final assertion = expectLater(request, throwsA(isA<ApiFailure>()));
      pending.complete(
        body([
          {'user_id': 'a'},
        ]),
      );
      await assertion;
      expect(api.session!['user']['id'], 'b');
    },
  );
  test(
    'temporary refresh failure does not declare credentials invalid',
    () async {
      final api = SemesterApi();
      api.dio.httpClientAdapter = ControlledTransport(
        (r) async => r.path.endsWith('/refresh')
            ? body({'message': 'temporary'}, 503)
            : body({}, 401),
      );
      await api.saveSession(account('a'));
      await expectLater(
        api.request('GET', '/me'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.unauthorized,
            'unauthorized',
            false,
          ),
        ),
      );
      expect(api.session!['user']['id'], 'a');
    },
  );
  test('late token refresh cannot resurrect a logged out account', () async {
    final api = SemesterApi();
    final pending = Completer<ResponseBody>(), started = Completer<void>();
    api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/refresh')) {
        started.complete();
        return pending.future;
      }
      return body({}, 401);
    });
    await api.saveSession(account('a'));
    final request = api.request('GET', '/me');
    await started.future;
    await api.forget();
    await api.saveSession(account('b'));
    final assertion = expectLater(request, throwsA(isA<ApiFailure>()));
    pending.complete(body(account('a')));
    await assertion;
    expect(api.session!['user']['id'], 'b');
  });
}
