// Real Android UI + real AI. This test refuses production endpoints.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/app/semester_app.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/core/cache.dart';
import 'package:semester_os/features/agent/agent_page.dart';

class SmokeCache implements CalendarStore {
  final values = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>?> read(String key) async => values[key];
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    values[key] = jsonDecode(jsonEncode(value));
  }

  @override
  Future<void> clear(String key) async {
    values.remove(key);
  }

  @override
  Future<void> close() async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'notice input, interpretation and save through the real Android app',
    (tester) async {
      const base = String.fromEnvironment('API_BASE_URL');
      expect(
        base,
        'http://10.0.2.2:8874',
        reason: 'Only an isolated localhost QA backend is allowed',
      );
      final api = SemesterApi(baseUrl: base);
      final username = 'notice_ui_${DateTime.now().millisecondsSinceEpoch}';
      const password = 'notice_qa_only_2026';
      final created = Map<String, dynamic>.from(
        await api.request(
          'POST',
          '/auth/register',
          authenticated: false,
          data: {'username': username, 'password': password},
        ),
      );
      await api.saveSession(created);
      final term = Map<String, dynamic>.from(
        await api.request(
          'POST',
          '/semesters',
          data: {
            'name': '通知验证学期',
            'first_monday': '2026-08-31',
            'total_weeks': 20,
            'periods': [
              {'number': 1, 'start': '08:00', 'end': '08:50'},
              {'number': 2, 'start': '09:00', 'end': '09:50'},
            ],
          },
        ),
      );
      await api.forget();
      final app = AppController(
        api,
        SmokeCache(),
        clearSchoolSession: () async {},
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWithValue(app)],
          child: const SemesterApp(),
        ),
      );
      Future<void> until(bool Function() condition, {int seconds = 20}) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!condition() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        if (!condition()) {
          debugPrint(
            'NOTICE_UI_STATE ready=${app.ready}, loggedIn=${app.loggedIn}; '
            '${tester.widgetList<Text>(find.byType(Text)).map((v) => v.data).whereType<String>().take(20).join(' | ')}',
          );
        }
        expect(
          condition(),
          isTrue,
          reason: 'UI state did not arrive within $seconds seconds',
        );
      }

      await until(
        () => find.byKey(const Key('username')).evaluate().isNotEmpty,
      );
      await tester.enterText(find.byKey(const Key('username')), username);
      await tester.enterText(find.byKey(const Key('password')), password);
      await tester.tap(find.byKey(const Key('auth-submit')));
      await until(
        () => find.byKey(const Key('profile-school')).evaluate().isNotEmpty,
      );
      await tester.enterText(find.byKey(const Key('profile-school')), '示例大学');
      await tester.enterText(find.byKey(const Key('profile-major')), '软件工程');
      await tester.enterText(find.byKey(const Key('profile-class')), '软件2401');
      await tester.ensureVisible(find.byKey(const Key('profile-year')));
      await tester.enterText(find.byKey(const Key('profile-year')), '2024');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.scrollUntilVisible(
        find.byKey(const Key('profile-save')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('profile-save')));
      await until(
        () => find.byKey(const Key('profile-school')).evaluate().isEmpty,
      );
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      final evidence = <Map<String, dynamic>>[];
      Future<void> screenshot(String name) async {
        await tester.pump(const Duration(milliseconds: 500));
        await binding.takeScreenshot(name);
      }

      Future<Map<String, dynamic>> notice(String name, String text) async {
        // Open the same public assistant route used by the app's input dock.
        final home = tester.element(find.byType(Scaffold).first);
        GoRouter.of(home).push('/assistant');
        await until(
          () => find.byKey(const Key('agent-input')).evaluate().isNotEmpty,
        );
        if (find.byTooltip('新对话').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('新对话'));
          await tester.pump(const Duration(milliseconds: 400));
        }
        await tester.enterText(find.byKey(const Key('agent-input')), text);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byTooltip('发送'));
        final timer = Stopwatch()..start();
        Map<String, dynamic>? run;
        final expires = DateTime.now().add(const Duration(seconds: 100));
        while (DateTime.now().isBefore(expires)) {
          await tester.pump(const Duration(milliseconds: 500));
          final history = await api.request(
            'GET',
            '/agent/history',
            queryParameters: {'semester_id': term['id'], 'limit': 1},
          );
          if ((history['threads'] as List).isNotEmpty) {
            final thread = await api.request(
              'GET',
              '/agent/threads/${history['threads'][0]['id']}',
            );
            final runs = thread['runs'] as List;
            if (runs.isNotEmpty && runs.last['text'] == text) {
              run = Map<String, dynamic>.from(runs.last);
              if (!{'queued', 'running'}.contains(run['status'])) break;
            }
          }
        }
        expect(run, isNotNull);
        expect(
          run!['status'],
          'needs_confirmation',
          reason: '$name: ${run['answer']} ${run['error']}',
        );
        await until(() => find.text('确认添加').evaluate().isNotEmpty);
        await tester.ensureVisible(find.text('确认添加'));
        await tester.pump(const Duration(milliseconds: 400));
        await screenshot('$name-preview');
        await tester.tap(find.text('确认添加'));
        await until(() => find.text('确认添加').evaluate().isEmpty);
        final applied = await api.request('GET', '/agent/runs/${run['id']}');
        expect(applied['status'], 'applied');
        await screenshot('$name-saved');
        evidence.add({
          'case': name,
          'elapsed_seconds': timer.elapsedMilliseconds / 1000,
          'result': applied,
        });
        binding.reportData!['notice_cases'] = evidence;
        debugPrint(
          'NOTICE_UI $name applied; ${timer.elapsedMilliseconds / 1000}s',
        );
        GoRouter.of(tester.element(find.byType(AgentPage))).pop();
        await tester.pump(const Duration(milliseconds: 500));
        return Map<String, dynamic>.from(applied);
      }

      final noDate = await notice(
        'no-deadline',
        '班委通知：麻烦大家把班级群昵称改为姓名，方便的时候改一下。帮我记成待办。',
      );
      final a = noDate['preview']['after'];
      expect(a['time']['precision'], 'unknown');
      expect(a['time']['at'], isNull);
      expect(a['certainty'], 'formal');
      final startOnly = await notice(
        'start-only',
        '老师通知：10月8日下午4点开班会，地点另行通知，结束时间没说。记录这个班会。',
      );
      final b = startOnly['preview']['after'];
      expect(b['time']['at'], isNotNull);
      expect(b['time']['end_at'], isNull);
      expect(b['location'], anyOf('', isNull));
      final materials = await notice(
        'materials',
        '班委通知：报名表电子版10月7日18点前发给班级负责人，纸质版10月9日上午9点至下午6点都可以交到办公室A201。先帮我记录交纸质报名表，电子版我已经交了。',
      );
      final c = materials['preview']['after'];
      expect(c['time']['meaning'], 'window');
      expect(c['time']['end_at'], isNotNull);
      expect(c['details']['materials'], isNotEmpty);
      expect(c['details']['recipient'], anyOf('', isNull));
      expect(c['notes'], anyOf('', isNull));
      final events = await api.request(
        'GET',
        '/semesters/${term['id']}/calendar',
        queryParameters: {'from_date': '2026-10-09', 'to_date': '2026-10-09'},
      );
      expect(
        (events['entries'] as List).where(
          (entry) =>
              entry['fixed'] == true && '${entry['title']}'.contains('报名表'),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
