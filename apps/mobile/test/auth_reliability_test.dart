import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/app/controller.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'controller_test.dart' show MemoryStore;

class FailingCredentialStorage extends FlutterSecureStorage {
  bool failDelete = true;
  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failDelete && key == 'semesteros_session') {
      throw StateError('storage unavailable');
    }
    await super.delete(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'lost refresh reply reuses its persisted operation after restart',
    () async {
      final first = SemesterApi();
      await first.saveSession(account('a'));
      String? operation;
      first.dio.httpClientAdapter = ControlledTransport((request) async {
        if (!request.path.endsWith('/refresh')) return body({}, 401);
        operation = request.headers['Idempotency-Key'] as String;
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
        );
      });
      await expectLater(
        first.request('GET', '/me'),
        throwsA(isA<ApiFailure>()),
      );
      expect(operation!.length, greaterThanOrEqualTo(20));
      final second = SemesterApi();
      await second.restore();
      var refreshes = 0;
      second.dio.httpClientAdapter = ControlledTransport((request) async {
        if (request.path.endsWith('/refresh')) {
          refreshes++;
          expect(request.headers['Idempotency-Key'], operation);
          expect(request.data['refresh_token'], 'refresh-a');
          return body({
            ...account('a'),
            'access_token': 'rotated-a',
            'refresh_token': 'rotated-refresh-a',
          });
        }
        return request.headers['Authorization'] == 'Bearer rotated-a'
            ? body({'ok': true})
            : body({}, 401);
      });
      expect(await second.request('GET', '/me'), {'ok': true});
      expect(refreshes, 1);
      expect(second.session!.containsKey('pending_refresh_id'), isFalse);
      first.dio.close();
      second.dio.close();
    },
  );

  test(
    'a delayed old-token 401 retries the new token without another refresh',
    () async {
      final api = SemesterApi();
      await api.saveSession(account('a'));
      final late = Completer<ResponseBody>();
      final sent = Completer<void>();
      var refreshes = 0;
      api.dio.httpClientAdapter = ControlledTransport((request) async {
        if (request.path.endsWith('/refresh')) {
          refreshes++;
          return body({...account('a'), 'access_token': 'new-access-a'});
        }
        if (request.path.endsWith('/late') &&
            request.headers['Authorization'] == 'Bearer access-a') {
          sent.complete();
          return late.future;
        }
        return request.headers['Authorization'] == 'Bearer new-access-a'
            ? body({'ok': true})
            : body({}, 401);
      });
      final delayed = api.request('GET', '/late');
      await sent.future;
      expect(await api.request('GET', '/first'), {'ok': true});
      late.complete(body({}, 401));
      expect(await delayed, {'ok': true});
      expect(refreshes, 1);
      api.dio.close();
    },
  );

  test(
    'credential deletion failure cannot restore old login after restart',
    () async {
      final storage = FailingCredentialStorage();
      final api = SemesterApi(storage: storage);
      await api.saveSession(account('a'));
      await expectLater(api.forget(), throwsA(isA<ApiFailure>()));
      expect(api.session, isNull);
      final restarted = SemesterApi(storage: storage);
      await expectLater(restarted.restore(), throwsA(isA<ApiFailure>()));
      expect(restarted.session, isNull);
      final controller = AppController(
        restarted,
        MemoryStore(),
        clearSchoolSession: () async {},
      );
      await controller.initialize();
      expect(controller.ready, isTrue);
      expect(controller.logoutCleanupFailed, isTrue);
      storage.failDelete = false;
      await controller.logout(remote: false);
      expect(controller.logoutCleanupFailed, isFalse);
      expect(await storage.read(key: 'semesteros_session'), isNull);
      expect(await storage.read(key: 'semesteros_logout_pending'), isNull);
      api.dio.close();
      restarted.dio.close();
    },
  );

  test(
    'logout continues cookie cache and notification cleanup and exposes retry',
    () async {
      final storage = FailingCredentialStorage();
      final api = SemesterApi(storage: storage);
      await api.saveSession(account('a'));
      final cache = MemoryStore();
      cache.data['a'] = {'private': 'cached'};
      var cookiesFail = true, notificationsCleared = false;
      final controller = AppController(
        api,
        cache,
        clearSchoolSession: () async {
          if (cookiesFail) throw StateError('cookie cleanup failed');
        },
      );
      controller.clearNotifications = () async {
        notificationsCleared = true;
      };
      await controller.logout(remote: false);
      expect(controller.ready, isTrue);
      expect(controller.loggedIn, isFalse);
      expect(cache.data.containsKey('a'), isFalse);
      expect(notificationsCleared, isTrue);
      expect(controller.logoutCleanupFailed, isTrue);
      expect(controller.notice, contains('登录信息未清除'));
      cookiesFail = false;
      storage.failDelete = false;
      await controller.logout(remote: false);
      expect(controller.logoutCleanupFailed, isFalse);
      expect(controller.notice, isNull);
      expect(await storage.read(key: 'semesteros_session'), isNull);
      controller.dispose();
    },
  );
}
