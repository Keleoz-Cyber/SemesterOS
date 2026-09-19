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
