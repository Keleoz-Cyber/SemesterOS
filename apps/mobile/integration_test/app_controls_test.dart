// Native controls against disposable local accounts. API writes below only
// seed fixtures; every action named in the evidence is performed in the App.
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/app/semester_app.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/core/cache.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/features/media/hold_voice_button.dart';
import 'package:semester_os/ui/app_controls.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'native account, semester, task and voice controls',
    (tester) async {
      const base = String.fromEnvironment('API_BASE_URL');
      const port = int.fromEnvironment('QA_BACKEND_PORT', defaultValue: 8874);
      expect(base, 'http://10.0.2.2:$port');
      final api = SemesterApi(baseUrl: base);
      await api.forget();
      final username = 'controls_${DateTime.now().millisecondsSinceEpoch}';
      const password = 'native_controls_2026';
      final session = Map<String, dynamic>.from(
        await api.request(
          'POST',
          '/auth/register',
          authenticated: false,
          data: {'username': username, 'password': password},
        ),
      );
      await api.saveSession(session);
      await api.request(
        'PUT',
        '/me/profile',
        data: {
          'expected_version': 0,
          'school': '示例大学',
          'onboarding_completed': true,
        },
      );
      final terms = <Map<String, dynamic>>[];
      for (final name in ['控制验证学期A', '控制验证学期B']) {
        terms.add(
          Map<String, dynamic>.from(
            await api.request(
              'POST',
              '/semesters',
              data: {
                'name': name,
                'first_monday': '2026-08-31',
                'total_weeks': 20,
                'periods': [
                  {'number': 1, 'start': '08:30', 'end': '10:05'},
                ],
              },
            ),
          ),
        );
      }
      final sid = '${terms.first['id']}';
      final task = await api.request(
        'POST',
        '/items',
        data: {
          'semester_id': sid,
          'kind': 'task',
          'title': 'UI控制任务',
          'remaining_minutes': 60,
          'start_policy': 'now',
        },
      );
      final id = '${task['id']}';
      final exam = await api.request(
        'POST',
        '/items',
        data: {
          'semester_id': sid,
          'kind': 'exam',
          'title': 'UI控制考试',
          'certainty': 'formal',
          'time': {'precision': 'date', 'date': '2026-12-01'},
          'location': 'B101',
          'reserve_time': false,
        },
      );
      final examId = '${exam['id']}';
      final app = AppController(
        api,
        CalendarCache(),
        clearSchoolSession: () async {},
      );
      final evidence = <Map<String, dynamic>>[];
      binding.reportData = {'workflows': evidence};
      var stage = 'boot', captureReady = false;
      Future<void> pump([int ms = 300]) async {
        await tester.pump(Duration(milliseconds: ms));
        final e = tester.takeException();
        if (e != null) fail('$stage: $e');
      }

      Future<void> until(bool Function() condition, {int seconds = 30}) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!condition() && DateTime.now().isBefore(end)) {
          await pump();
        }
        expect(condition(), isTrue, reason: '$stage: UI state timeout');
        await pump();
      }

      Future<void> reveal(Finder target) async {
        await pump(400);
        final visibleLists = find.byType(ListView).hitTestable();
        if (target.evaluate().isEmpty && visibleLists.evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            target,
            200,
            scrollable: find
                .descendant(
                  of: visibleLists.last,
                  matching: find.byType(Scrollable),
                )
                .first,
            maxScrolls: 25,
          );
        }
        await until(() => target.evaluate().isNotEmpty);
        await tester.ensureVisible(target.last);
        await pump(400);
      }

      Future<void> tap(Finder f) async {
        await reveal(f);
        await tester.tap(f.last);
        await pump(400);
      }

      Future<void> textTap(String s) => tap(find.text(s));
      Future<void> enter(Finder f, String s) async {
        await reveal(f);
        await tester.tap(f.last);
        await pump(400);
        await tester.enterText(f.last, s);
        await pump();
      }

      Future<void> hideKeyboard() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await pump(500);
      }

      Future<void> shot(String name) async {
        if (!captureReady) {
          await binding.convertFlutterSurfaceToImage();
          captureReady = true;
        }
        await pump(500);
        await binding.takeScreenshot(name);
      }

      Future<void> passed(String name) async {
        await shot(name);
        evidence.add({'case': name, 'passed': true});
        debugPrint('APP_FLOW_PASS $name');
      }

      Future<void> push(String path) async {
        GoRouter.of(tester.element(find.byType(Scaffold).first)).push(path);
        await pump(800);
      }

      Future<void> openAssistant() async {
        await textTap('输入通知或日程问题');
        await until(
          () =>
              find.byKey(const Key('agent-input')).evaluate().isNotEmpty &&
              tester
                  .widget<FTextField>(find.byKey(const Key('agent-input')))
                  .enabled,
        );
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWithValue(app)],
          child: const SemesterApp(),
        ),
      );
      try {
        await until(() => app.ready && app.semester != null);
        stage = 'switch-semester';
        await textTap('学期');
        await textTap('管理学期与课表');
        await textTap('控制验证学期A');
        await until(
          () =>
              app.semester?['id'] == sid &&
              find.text('管理学期与课表').evaluate().length == 1,
        );
        await passed('semester-switch-a');
        await textTap('管理学期与课表');
        await textTap('控制验证学期B');
        await until(() => app.semester?['id'] == terms.last['id']);
        await passed('semester-switch-b');
        await textTap('管理学期与课表');
        await textTap('控制验证学期A');
        await until(() => app.semester?['id'] == sid);

        stage = 'manual-course-create';
        await push('/manual');
        await enter(find.byKey(const Key('course-title')), 'UI手工课程');
        await enter(
          find.byWidgetPredicate(
            (w) => w is AppField && w.decoration.labelText == '周次',
          ),
          '1-20',
        );
        await enter(
          find.byWidgetPredicate(
            (w) => w is AppField && w.decoration.labelText == '节次',
          ),
          '1',
        );
        await hideKeyboard();
        await textTap('核对课程信息');
        await textTap('确认保存课表');
        await until(() => find.text('手工添加课程').evaluate().isEmpty);
        expect(
          (await api.request('GET', '/semesters/$sid/courses') as List).any(
            (c) => c['title'] == 'UI手工课程',
          ),
          isTrue,
        );
        await passed('course-manual-create');

        stage = 'progress';
        await push('/items/$id');
        await textTap('添加提醒');
        await textTap('选择提醒日期和时间（北京时间）');
        final reminderAt = schoolNow().add(const Duration(days: 2));
        if (reminderAt.month != schoolNow().month) {
          await tap(find.byTooltip('下个月'));
        }
        await tap(find.text('${reminderAt.day}').hitTestable());
        await textTap('确定');
        await textTap('确定');
        await textTap('确认这条提醒');
        await until(() => find.text('提醒 · 1条').evaluate().isNotEmpty);
        expect(
          (await api.request('GET', '/items/$id'))['reminders'],
          hasLength(1),
        );
        await passed('task-reminder-without-date');
        await textTap('更新进度');
        await enter(find.byKey(const Key('progress-remaining')), '40');
        await enter(find.byKey(const Key('progress-actual')), '20');
        await hideKeyboard();
        await textTap('确认本次进度');
        await textTap('确认更新进度');
        await until(() => find.text('更新任务进度').evaluate().isEmpty);
        expect(
          (await api.request('GET', '/items/$id'))['remaining_minutes'],
          40,
        );
        expect(
          (await api.request('GET', '/items/$id/progress') as List)
              .last['actual_minutes'],
          20,
        );
        await passed('task-progress-update');
        await tap(find.byTooltip('编辑事项'));
        await enter(find.byKey(const Key('item-title')), 'UI控制任务-改名');
        await hideKeyboard();
        await textTap('保存修改');
        await until(() => find.text('保存修改').evaluate().isEmpty);
        expect((await api.request('GET', '/items/$id'))['title'], 'UI控制任务-改名');
        await passed('task-manual-edit');
        await textTap('标记完成');
        await textTap('确认');
        await until(() => find.text('恢复事项').evaluate().isNotEmpty);
        expect(
          (await api.request('GET', '/items/$id'))['lifecycle'],
          'completed',
        );
        await passed('task-manual-complete');
        await textTap('恢复事项');
        await textTap('确认');
        await until(() => find.text('标记完成').evaluate().isNotEmpty);
        expect((await api.request('GET', '/items/$id'))['lifecycle'], 'active');
        await passed('task-manual-restore');
        await tap(find.byTooltip('更多操作'));
        await textTap('取消事项');
        await textTap('确认');
        await until(() => find.text('恢复事项').evaluate().isNotEmpty);
        expect(
          (await api.request('GET', '/items/$id'))['lifecycle'],
          'cancelled',
        );
        await passed('task-manual-cancel');
        await textTap('恢复事项');
        await textTap('确认');
        await until(() => find.text('标记完成').evaluate().isNotEmpty);
        await textTap('更新进度');
        await enter(find.byKey(const Key('progress-remaining')), '40');
        await hideKeyboard();
        await textTap('确认本次进度');
        await textTap('确认更新进度');
        await until(() => find.text('更新任务进度').evaluate().isEmpty);
        await tap(find.byTooltip('返回'));

        stage = 'plan-controls';
        await textTap('任务');
        await until(
          () =>
              find.text('设置可学习时间').evaluate().isNotEmpty ||
              find.text('学习时间设置').evaluate().isNotEmpty,
        );
        await textTap(
          find.text('设置可学习时间').evaluate().isNotEmpty ? '设置可学习时间' : '学习时间设置',
        );
        await textTap('快速设置：每天19:00—21:00');
        await textTap('核对并保存学习时间');
        await textTap('确认保存学习时间');
        await until(() => find.text('可学习时间').evaluate().isEmpty);
        await openAssistant();
        const request = '帮我安排UI控制任务-改名这项任务，剩余40分钟，未来7天内按我的可学习时间安排。';
        await enter(find.byKey(const Key('agent-input')), request);
        await hideKeyboard();
        await tap(find.byTooltip('发送'));
        Map<String, dynamic>? run;
        final deadline = DateTime.now().add(const Duration(seconds: 100));
        while (DateTime.now().isBefore(deadline)) {
          await pump(500);
          final history = await api.request(
            'GET',
            '/agent/history',
            queryParameters: {'semester_id': sid, 'limit': 1},
          );
          if ((history['threads'] as List).isEmpty) continue;
          final thread = await api.request(
            'GET',
            '/agent/threads/${history['threads'][0]['id']}',
          );
          final runs = thread['runs'] as List;
          if (runs.isNotEmpty &&
              !{'queued', 'running'}.contains(runs.last['status'])) {
            run = Map<String, dynamic>.from(runs.last);
            break;
          }
        }
        expect(
          run?['status'],
          'needs_confirmation',
          reason: '${run?['answer']} ${run?['error']}',
        );
        await until(() => find.text('确认安排').evaluate().isNotEmpty);
        await textTap('确认安排');
        await until(() => find.text('确认安排').evaluate().isEmpty);
        await tap(find.byTooltip('收起输入'));
        await until(() => find.byType(AgentPage).evaluate().isEmpty);
        await textTap('安排记录');
        await textTap('锁定');
        await until(() => find.text('解锁').evaluate().isNotEmpty);
        final locked =
            (await api.request('GET', '/semesters/$sid/plans'))['blocks']
                as List;
        expect(locked.single['locked'], isTrue);
        await passed('plan-native-lock');
        await textTap('取消此段');
        await textTap('确认解锁并取消');
        await until(() => find.text('取消此段').evaluate().isEmpty);
        expect(
          (await api.request('GET', '/semesters/$sid/plans'))['blocks'] as List,
          isEmpty,
        );
        expect(
          (await api.request('GET', '/items/$id'))['remaining_minutes'],
          40,
        );
        await passed('plan-native-unlock-cancel');
        await tap(find.byTooltip('返回'));

        stage = 'exam-native-controls';
        await push('/exams/$examId');
        await textTap('添加复习任务');
        await enter(find.byKey(const Key('review-minutes')), '60');
        await hideKeyboard();
        await textTap('创建复习任务');
        await until(() => find.text('复习目标').evaluate().isEmpty);
        final examReviews =
            (await api.request('GET', '/semesters/$sid/items'))['items']
                as List;
        expect(
          examReviews.any(
            (r) =>
                r['review_exam_id'] == examId &&
                r['remaining_minutes'] == 60 &&
                r['time']['precision'] == 'unknown',
          ),
          isTrue,
        );
        await passed('exam-native-review-create');
        await textTap('调整考试安排');
        await enter(
          find.byWidgetPredicate(
            (w) => w is AppField && w.decoration.labelText == '新地点',
          ),
          'B202',
        );
        await hideKeyboard();
        await textTap('查看改期影响');
        await textTap('确认考试新安排');
        await until(() => find.text('核对考试新安排').evaluate().isEmpty);
        final changedExam = await api.request('GET', '/items/$examId');
        expect(changedExam['location'], 'B202');
        expect(changedExam['time']['precision'], 'date');
        expect(changedExam['reserve_time'], isFalse);
        await until(() => find.text('仅作参考').evaluate().isNotEmpty);
        await passed('exam-native-location-change');
        await tap(find.byTooltip('返回'));

        stage = 'voice-controls';
        await openAssistant();
        await tap(find.byTooltip('切换语音输入'));
        await until(() => find.text('按住说话').evaluate().isNotEmpty);
        await passed('voice-inline-toggle');
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(HoldVoiceButton)),
        );
        await until(() => find.textContaining('松开完成').evaluate().isNotEmpty);
        await gesture.moveBy(const Offset(0, -90));
        await pump(500);
        expect(find.text('松开取消'), findsOneWidget);
        await gesture.up();
        await until(() => find.text('按住说话').evaluate().isNotEmpty);
        final dynamic agentState = tester.state(find.byType(AgentPage));
        expect(agentState.currentSource, isNull);
        await passed('voice-native-record-cancel');
        await tap(find.byTooltip('切换键盘输入'));
        await until(
          () => find.byKey(const Key('agent-input')).evaluate().isNotEmpty,
        );
        await passed('voice-back-to-keyboard');
        await tap(find.byTooltip('收起输入'));
        await until(() => find.byType(AgentPage).evaluate().isEmpty);

        stage = 'profile';
        await tap(find.byTooltip('账户'));
        await tap(find.byKey(const Key('account-profile')));
        await enter(find.byKey(const Key('profile-class')), '验证2401');
        await hideKeyboard();
        await tap(find.byKey(const Key('profile-save')));
        await until(
          () => find.byKey(const Key('profile-school')).evaluate().isEmpty,
        );
        expect(
          (await api.request('GET', '/me/profile'))['class_name'],
          '验证2401',
        );
        await passed('profile-manual-edit');
        stage = 'logout';
        await tap(find.byTooltip('账户'));
        await textTap('退出登录');
        await until(
          () => find.byKey(const Key('username')).evaluate().isNotEmpty,
        );
        expect(app.loggedIn, isFalse);
        await passed('account-logout');
        stage = 'recover-account';
        await textTap('使用恢复码找回密码');
        await enter(find.byKey(const Key('username')), username);
        await enter(
          find.byWidgetPredicate(
            (w) => w is AppFormField && w.decoration.labelText == '账户恢复码',
          ),
          '${session['recovery_code']}',
        );
        const newPassword = 'native_recovered_2026';
        await enter(find.byKey(const Key('password')), newPassword);
        await hideKeyboard();
        await tap(find.byKey(const Key('auth-submit')));
        await textTap('我已保存');
        await until(() => find.text('密码已更新，请登录').evaluate().isNotEmpty);
        await passed('account-recovery');
        stage = 'login';
        await enter(find.byKey(const Key('username')), username);
        await enter(find.byKey(const Key('password')), newPassword);
        await hideKeyboard();
        await tap(find.byKey(const Key('auth-submit')));
        await until(
          () =>
              app.loggedIn &&
              app.semester != null &&
              find.byKey(const Key('username')).evaluate().isEmpty,
        );
        expect((await api.request('GET', '/items/$id'))['title'], 'UI控制任务-改名');
        expect(
          (await api.request('GET', '/me/profile'))['class_name'],
          '验证2401',
        );
        await passed('account-login-cloud-data');
        stage = 'insights';
        await push('/insights');
        await until(() => find.text('本周').evaluate().isNotEmpty);
        await textTap('近4周');
        await pump(2000);
        await passed('insights-range-switch');
        await tap(find.byTooltip('返回'));
        await passed('controls-workflows-finished');
      } catch (error, stack) {
        evidence.add({'case': stage, 'passed': false, 'error': '$error'});
        debugPrint('APP_FLOW_FAIL $stage: $error\n$stack');
        await shot('failure');
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
