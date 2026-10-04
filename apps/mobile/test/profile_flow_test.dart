import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/profile/profile_controller.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'controller_test.dart' show MemoryStore;

Map<String, dynamic> profileData({
  int version = 0,
  String school = '',
  String role = '',
  bool completed = false,
}) => {
  'version': version,
  'school': school,
  'college': '',
  'major': '',
  'class_name': '',
  'education_level': null,
  'entry_year': null,
  'class_role': role,
  'onboarding_completed': completed,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'incomplete profile offers the guide once in the current session',
    () async {
      final api = SemesterApi()..session = account('a');
      api.dio.httpClientAdapter = ControlledTransport(
        (_) async => body(profileData()),
      );
      final controller = ProfileController(api, MemoryStore());
      await controller.bind('a');
      expect(controller.needsOnboarding, true);
      expect(controller.claimGuide(), true);
      expect(controller.claimGuide(), false);
      await controller.reload();
      expect(controller.needsOnboarding, false);
      controller.dispose();
      api.dio.close();
    },
  );

  test(
    'saving accepts empty identity fields and an arbitrary class role',
    () async {
      final api = SemesterApi()..session = account('a');
      final requests = <Map<String, dynamic>>[];
      api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.method == 'PUT') {
          requests.add(Map<String, dynamic>.from(r.data));
          return body({...r.data, 'version': 1});
        }
        return body(profileData());
      });
      final store = MemoryStore();
      final controller = ProfileController(api, store);
      await controller.bind('a');
      final result = await controller.save(
        const UserProfile(classRole: ' 临时活动联络人 / 宿舍负责人 '),
      );
      expect(result, ProfileSaveResult.saved);
      expect(requests.single['expected_version'], 0);
      expect(requests.single['class_role'], '临时活动联络人 / 宿舍负责人');
      expect(requests.single['entry_year'], isNull);
      expect(requests.single['education_level'], isNull);
      expect(requests.single['onboarding_completed'], true);
      expect(requests.single, isNot(contains('name')));
      expect(controller.profile.version, 1);
      expect(controller.needsOnboarding, false);
      expect(store.data['profile:a']?['draft'], isNull);
      controller.dispose();
      api.dio.close();
    },
  );

  test('skip stores completion without clearing the known identity', () async {
    final api = SemesterApi()..session = account('a');
    Map<String, dynamic>? submitted;
    api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.method == 'PUT') {
        submitted = Map<String, dynamic>.from(r.data);
        return body({...r.data, 'version': 3});
      }
      return body(profileData(version: 2, school: '测试大学'));
    });
    final controller = ProfileController(api, MemoryStore());
    await controller.bind('a');
    await controller.skip();
    expect(submitted?['school'], '测试大学');
    expect(submitted?['expected_version'], 2);
    expect(submitted?['onboarding_completed'], true);
    expect(controller.profile.onboardingCompleted, true);
    expect(controller.needsOnboarding, false);
    controller.dispose();
    api.dio.close();
  });

  test(
    'conflict reloads latest saved context and preserves the local draft',
    () async {
      final api = SemesterApi()..session = account('a');
      var reads = 0, writes = 0;
      api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.method == 'PUT') {
          writes++;
          return body({'message': '资料已修改'}, 409);
        }
        reads++;
        return body(profileData(version: reads, school: '远端$reads'));
      });
      final controller = ProfileController(api, MemoryStore());
      await controller.bind('a');
      final result = await controller.save(
        const UserProfile(version: 1, school: '当前填写'),
      );
      expect(result, ProfileSaveResult.conflict);
      expect(controller.profile.school, '远端2');
      expect(controller.profile.version, 2);
      expect(controller.draft?.school, '当前填写');
      expect(controller.conflict, true);
      expect(writes, 1);
      controller.dispose();
      api.dio.close();
    },
  );

  test(
    'offline cache and skip marker are owner scoped and survive restart',
    () async {
      final api = SemesterApi()..session = account('a');
      final store = MemoryStore();
      api.dio.httpClientAdapter = ControlledTransport(
        (_) async => body(profileData(version: 4, school: '已保存学校')),
      );
      final first = ProfileController(api, store);
      await first.bind('a');
      first.dispose();
      api.dio.httpClientAdapter = ControlledTransport((r) async {
        throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: r,
        );
      });
      final offline = ProfileController(api, store);
      await offline.bind('a');
      expect(offline.profile.school, '已保存学校');
      expect(offline.offline, true);
      await offline.skip();
      offline.dispose();
      final restarted = ProfileController(api, store);
      await restarted.bind('a');
      expect(restarted.needsOnboarding, false);
      expect(restarted.profile.school, '已保存学校');
      await restarted.bind(null);
      expect(restarted.profile.school, '');
      expect(store.data.containsKey('profile:a'), false);
      api.session = account('b');
      api.generation++;
      await restarted.bind('b');
      expect(restarted.profile.school, '');
      expect(restarted.needsOnboarding, true);
      restarted.dispose();
      api.dio.close();
    },
  );

  test(
    'late save from account A cannot fill account B or recreate A cache',
    () async {
      final api = SemesterApi()..session = account('a');
      final pending = Completer<ResponseBody>(), started = Completer<void>();
      api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.method == 'PUT') {
          started.complete();
          return pending.future;
        }
        return body(profileData(school: '${api.session?['user']['id']}学校'));
      });
      final store = MemoryStore();
      final controller = ProfileController(api, store);
      await controller.bind('a');
      final saving = controller.save(const UserProfile(school: 'A修改'));
      await started.future;
      await api.forget();
      await controller.bind(null);
      await api.saveSession(account('b'));
      await controller.bind('b');
      pending.complete(body(profileData(version: 1, school: 'A修改')));
      expect(await saving, ProfileSaveResult.stale);
      expect(controller.profile.school, 'b学校');
      expect(controller.draft, isNull);
      expect(store.data.containsKey('profile:a'), false);
      expect(store.data['profile:b']?['profile']['school'], 'b学校');
      controller.dispose();
      api.dio.close();
    },
  );

  test(
    'late GET from account A cannot restore A identity after switching',
    () async {
      final api = SemesterApi()..session = account('a');
      final pending = Completer<ResponseBody>(), started = Completer<void>();
      api.dio.httpClientAdapter = ControlledTransport((r) async {
        if ('${r.headers['Authorization']}'.contains('access-a')) {
          started.complete();
          return pending.future;
        }
        return body(profileData(school: 'B学校'));
      });
      final store = MemoryStore();
      final controller = ProfileController(api, store);
      final old = controller.bind('a');
      await started.future;
      await api.saveSession(account('b'));
      await controller.bind('b');
      pending.complete(body(profileData(school: 'A学校')));
      await old;
      expect(controller.profile.school, 'B学校');
      expect(store.data.containsKey('profile:a'), false);
      controller.dispose();
      api.dio.close();
    },
  );

  test(
    'failed save keeps a recoverable draft without claiming cloud success',
    () async {
      final api = SemesterApi()..session = account('a');
      final store = MemoryStore();
      api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.method == 'PUT') return body({}, 503);
        return body(profileData(version: 2, school: '云端学校'));
      });
      final first = ProfileController(api, store);
      await first.bind('a');
      expect(
        await first.save(
          const UserProfile(version: 2, school: '未保存学校', classRole: ''),
        ),
        ProfileSaveResult.unavailable,
      );
      expect(first.profile.school, '云端学校');
      expect(first.profile.onboardingCompleted, false);
      first.dispose();
      final reopened = ProfileController(api, store);
      await reopened.bind('a');
      expect(reopened.draft?.school, '未保存学校');
      expect(reopened.draft?.classRole, '');
      expect(reopened.profile.school, '云端学校');
      reopened.dispose();
      api.dio.close();
    },
  );
}
