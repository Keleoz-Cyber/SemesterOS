// Real Android UI, real storage, real backend and real model. Never production.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:semester_os/features/import/preview.dart';
import 'package:semester_os/features/items/item_form.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'package:semester_os/ui/clock_controls.dart';

void main() {
  const releaseOnly = bool.fromEnvironment('QA_RELEASE_ONLY');
  const resumeUsername = String.fromEnvironment('QA_RESUME_USERNAME');
  const resumeAt = String.fromEnvironment(
    'QA_RESUME_AT',
    defaultValue: 'manual',
  );
  const resumeEventRun = String.fromEnvironment('QA_RESUME_EVENT_RUN');
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'complete Android record and course workflows',
    (tester) async {
      const base = String.fromEnvironment('API_BASE_URL');
      const port = int.fromEnvironment('QA_BACKEND_PORT', defaultValue: 8874);
      expect(base, 'http://10.0.2.2:$port');
      final api = SemesterApi(baseUrl: base);
      await api.forget();
      final username = resumeUsername.isEmpty
          ? 'flow_${DateTime.now().millisecondsSinceEpoch}'
          : resumeUsername;
      if (resumeUsername.isNotEmpty) {
        expect(releaseOnly, isTrue);
        expect(RegExp(r'^flow_[0-9]+$').hasMatch(resumeUsername), isTrue);
        final session = Map<String, dynamic>.from(
          await api.request(
            'POST',
            '/auth/login',
            authenticated: false,
            data: {'username': username, 'password': 'mobile_flow_2026'},
          ),
        );
        await api.saveSession(session);
      }
      late String sid;
      final app = AppController(
        api,
        CalendarCache(),
        clearSchoolSession: () async {},
      );
      final evidence = <Map<String, dynamic>>[];
      binding.reportData = {'workflows': evidence};
      final originalFlutterError = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint('APP_FLOW_ORIGIN ${details.exceptionAsString()}');
        debugPrintStack(
          stackTrace: details.stack,
          label: 'APP_FLOW_ORIGIN_STACK',
        );
        for (final element
            in find.byType(AnimatedSize, skipOffstage: false).evaluate()) {
          final widget = element.widget as AnimatedSize;
          final render = element.findRenderObject();
          debugPrint(
            'APP_FLOW_SIZE $render key=${widget.key} duration=${widget.duration} creator=${render?.debugCreator}',
          );
        }
        originalFlutterError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalFlutterError);
      String stage = 'boot';
      Future<void> pump([int ms = 300]) async {
        await tester.pump(Duration(milliseconds: ms));
        final exception = tester.takeException();
        if (exception != null) fail('$stage: $exception');
      }

      Future<void> until(bool Function() condition, {int seconds = 30}) async {
        final expires = DateTime.now().add(Duration(seconds: seconds));
        while (!condition() && DateTime.now().isBefore(expires)) {
          await pump();
        }
        expect(
          condition(),
          isTrue,
          reason: '$stage: UI did not reach the expected state',
        );
        await pump();
      }

      Future<void> tap(Finder target) async {
        await pump(400);
        final visibleLists = find.byType(ListView).hitTestable();
        if (target.evaluate().isEmpty && visibleLists.evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            target,
            220,
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
        for (var attempt = 0; attempt < 5; attempt++) {
          await tester.ensureVisible(target.last);
          await pump(400);
          if (target.hitTestable().evaluate().isNotEmpty) break;
        }
        expect(
          target.hitTestable(),
          findsWidgets,
          reason: '$stage: control must be reachable before tapping',
        );
        await tester.tap(target.hitTestable().last);
        await pump(400);
      }

      Future<void> textTap(String text) => tap(find.text(text));
      Future<void> tabTap(String text) => tap(
        find.descendant(
          of: find.byType(FBottomNavigationBar),
          matching: find.text(text),
        ),
      );
      Finder field(String label) => find.byWidgetPredicate(
        (w) =>
            w is AppFormField && w.decoration.labelText == label ||
            w is AppField && w.decoration.labelText == label,
      );
      Future<void> enter(Finder target, String value) async {
        if (target.evaluate().isEmpty &&
            find.byType(ListView).evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            target,
            220,
            scrollable: find
                .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable),
                )
                .first,
            maxScrolls: 25,
          );
        }
        await until(() => target.evaluate().isNotEmpty);
        await tap(target);
        await tester.enterText(target.last, value);
        await pump();
      }

      Future<void> hideKeyboard() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await pump(500);
      }

      var captureReady = false;
      Future<void> shot(String name) async {
        if (!captureReady) {
          await binding.convertFlutterSurfaceToImage();
          captureReady = true;
        }
        await pump(500);
        await binding.takeScreenshot(name);
      }

      Future<void> passed(String name, [Map<String, dynamic>? details]) async {
        await shot(name);
        evidence.add({'case': name, 'passed': true, ...?details});
        debugPrint('APP_FLOW_PASS $name');
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWithValue(app)],
          child: const SemesterApp(),
        ),
      );
      final fixtures = <Map<String, dynamic>>[
        {
          'title': 'UI算法课',
          'weekday': 1,
          'weeks': List.generate(20, (i) => i + 1),
          'sections': [1, 2],
          'location': 'A301',
          'teacher': '示例教师',
        },
        {
          'title': 'UI物理课',
          'weekday': 4,
          'weeks': List.generate(20, (i) => i + 1),
          'sections': [3, 4],
          'location': 'B202',
          'teacher': '示例教师',
        },
      ];
      try {
        if (resumeUsername.isEmpty) {
          stage = 'register';
          await until(
            () => find.byKey(const Key('username')).evaluate().isNotEmpty,
          );
          await textTap('注册');
          await enter(find.byKey(const Key('username')), username);
          await enter(find.byKey(const Key('password')), 'mobile_flow_2026');
          await hideKeyboard();
          await tap(find.byKey(const Key('auth-submit')));
          await textTap('我已保存');
          await until(
            () =>
                app.loggedIn &&
                find.byKey(const Key('username')).evaluate().isEmpty,
          );
          if (find.byKey(const Key('profile-school')).evaluate().isEmpty) {
            await tap(find.byTooltip('账户'));
            await tap(find.byKey(const Key('account-profile')));
          }
          await until(
            () => find.byKey(const Key('profile-school')).evaluate().isNotEmpty,
          );
          await passed('register');
          stage = 'profile';
          await enter(find.byKey(const Key('profile-school')), '示例大学');
          await enter(find.byKey(const Key('profile-major')), '软件工程');
          await enter(find.byKey(const Key('profile-class')), '软件2401');
          await enter(find.byKey(const Key('profile-year')), '2024');
          await enter(find.byKey(const Key('profile-role')), '班长');
          await hideKeyboard();
          await tap(find.byKey(const Key('profile-save')));
          await until(
            () => find.byKey(const Key('profile-school')).evaluate().isEmpty,
          );
          await passed('profile-save');
          stage = 'create-semester';
          await textTap('创建学期');
          await enter(field('学期名称'), 'Android流程验证学期');
          await hideKeyboard();
          await tap(find.byKey(const Key('first-monday')));
          final displayed = tester
              .widget<DatePickerDialog>(find.byType(DatePickerDialog))
              .initialDate!;
          final months = (displayed.year - 2026) * 12 + displayed.month - 8;
          for (var i = 0; i < months; i++) {
            await tap(find.byTooltip('上个月'));
          }
          await tap(find.text('31').hitTestable());
          await textTap('确定');
          if (releaseOnly) {
            Future<void> changeMinute() async {
              final wheel = find.descendant(
                of: find.byKey(const ValueKey('range-clock-start')),
                matching: find.byKey(const Key('app-clock-minute-wheel')),
              );
              final extent = tester
                  .widget<ListWheelScrollView>(wheel)
                  .itemExtent;
              await tester.timedDrag(
                wheel,
                Offset(0, -extent),
                const Duration(milliseconds: 800),
              );
              await pump(600);
            }

            await tap(find.byKey(const ValueKey('period-1-start')));
            await changeMinute();
            await tap(find.byTooltip('取消选择'));
            expect(find.text('08:00'), findsOneWidget);
            await tap(find.byKey(const ValueKey('period-1-start')));
            await changeMinute();
            expect(
              tester
                  .widget<AppMinuteWheel>(
                    find.byKey(const ValueKey('range-clock-start')),
                  )
                  .value,
              481,
            );
            await tap(find.byKey(const Key('clock-range-confirm')));
            expect(find.text('08:01'), findsOneWidget);
          }
          await textTap('确认创建学期');
          await until(
            () =>
                app.semester != null && find.text('确认创建学期').evaluate().isEmpty,
          );
          sid = '${app.semester!['id']}';
          await passed('semester-create');

          stage = 'import-preview-save';

          // Parsed anonymous courses use the actual import confirmation screen.
          // School login/extraction are not exercised by this fixture.
          final homeContext = tester.element(find.byType(Scaffold).first);
          final imported = showImportPreview(
            homeContext,
            app,
            fixtures,
            'haut_webview',
            sourceTerm: '2026-2027/1',
          );
          await pump(1000);
          await textTap('确认保存课表');
          expect(await imported, isTrue);
          await pump();
          await passed('import-confirm');
          for (final tab in ['日程', '计划', '学期', '今日']) {
            stage = 'tab-$tab';
            await tabTap(tab);
            await pump(800);
          }
          await passed('main-tabs');
        } else {
          stage = 'resume-isolated-qa';
          await until(() => app.ready && app.loggedIn && app.semester != null);
          sid = '${app.semester!['id']}';
          // Fixture reset only: the previous failed run already saved this task.
          // Keep its history while returning the active list to the same state.
          final oldItems =
              (await api.request('GET', '/semesters/$sid/items'))['items']
                  as List;
          for (final item in oldItems.where(
            (r) =>
                resumeAt == 'manual' &&
                r['title'] == 'QA手工待办' &&
                r['lifecycle'] == 'active',
          )) {
            await api.request(
              'POST',
              '/items/${item['id']}/lifecycle',
              data: {
                'expected_version': item['version'],
                'lifecycle': 'cancelled',
              },
            );
          }
          await app.openSession(null, sid);
          for (final tab in ['日程', '计划', '学期', '今日']) {
            await tabTap(tab);
            await pump(800);
          }
          await passed('resume-isolated-qa', {
            'reused_checkpoints':
                'register/profile/semester/import/main-tabs from 20261004-182329-app-records',
            'fresh_registration': false,
          });
        }

        Future<void> openAssistant({bool fresh = false}) async {
          if (find.byType(AgentPage).evaluate().isEmpty) {
            await textTap('输入通知或日程问题');
            await until(
              () => find.byKey(const Key('agent-input')).evaluate().isNotEmpty,
            );
          }
          if (fresh) await tap(find.byTooltip('新对话'));
          await until(
            () =>
                find.byKey(const Key('agent-input')).evaluate().isNotEmpty &&
                tester
                    .widget<FTextField>(find.byKey(const Key('agent-input')))
                    .enabled,
          );
        }

        Future<void> closeAssistant() async {
          await tap(find.byTooltip('收起输入'));
          await until(() => find.byType(AgentPage).evaluate().isEmpty);
        }

        Future<Map<String, dynamic>> lastRun(String text) async {
          final untilAt = DateTime.now().add(const Duration(seconds: 100));
          while (DateTime.now().isBefore(untilAt)) {
            await pump(500);
            final history = await api.request(
              'GET',
              '/agent/history',
              queryParameters: {'semester_id': sid, 'limit': 1},
            );
            if ((history['threads'] as List).isEmpty) continue;
            final value = await api.request(
              'GET',
              '/agent/threads/${history['threads'][0]['id']}',
            );
            final runs = value['runs'] as List;
            if (runs.isNotEmpty &&
                runs.last['text'] == text &&
                !{'queued', 'running'}.contains(runs.last['status'])) {
              return Map<String, dynamic>.from(runs.last);
            }
          }
          fail('$stage: model request timed out');
        }

        Future<Map<String, dynamic>> askAndSave(
          String name,
          String text,
          String confirm, {
          bool fresh = false,
        }) async {
          stage = name;
          final revisionBefore = releaseOnly
              ? (await api.request('GET', '/semesters') as List).singleWhere(
                  (s) => s['id'] == sid,
                )['revision']
              : null;
          await openAssistant(fresh: fresh);
          await enter(find.byKey(const Key('agent-input')), text);
          final dynamic agentState = tester.state(find.byType(AgentPage));
          debugPrint(
            'APP_FLOW_SEND $name ready=${agentState.readyForDraft} loading=${agentState.c.loading} '
            'active=${agentState.c.active} draft=${agentState.input.text}',
          );
          await hideKeyboard();
          debugPrint(
            'APP_FLOW_SEND_AFTER_BLUR $name draft=${agentState.input.text} '
            'busy=${agentState.c.busy} media=${agentState.mediaWorking} sending=${agentState.sendingMedia}',
          );
          await until(
            () => tester
                .widgetList<AppIconButton>(find.byType(AppIconButton))
                .any((b) => b.tooltip == '发送' && b.onPressed != null),
          );
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: find.byKey(const Key('agent-input')),
                    matching: find.byType(EditableText),
                  ),
                )
                .controller
                .text,
            text,
            reason: 'Draft/input changed before sending',
          );
          await tap(find.byTooltip('发送'));
          final run = await lastRun(text);
          expect(
            run['status'],
            'needs_confirmation',
            reason: '$name: ${run['answer']} ${run['error']}',
          );
          if (releaseOnly) {
            expect(
              (await api.request('GET', '/semesters') as List).singleWhere(
                (s) => s['id'] == sid,
              )['revision'],
              revisionBefore,
              reason:
                  'A preview cannot commit business changes before confirmation',
            );
          }
          final confirmation = confirm == 'batch'
              ? '保存所选 ${(run['preview']['groups'] as List).length} 组'
              : confirm;
          await until(() => find.text(confirmation).evaluate().isNotEmpty);
          await shot('$name-preview');
          await textTap(confirmation);
          await until(() => find.text(confirmation).evaluate().isEmpty);
          final saved = Map<String, dynamic>.from(
            await api.request('GET', '/agent/runs/${run['id']}'),
          );
          expect(saved['status'], 'applied');
          await passed('$name-saved', {
            'run_id': run['id'],
            'preview_kind': run['preview']['kind'],
          });
          return saved;
        }

        Future<void> undoLast(String name) async {
          stage = name;
          await tap(find.text('撤销').last);
          await textTap('确认撤销');
          await until(() => find.text('确认撤销').evaluate().isEmpty);
          await passed(name);
        }

        Future<List<dynamic>> calendar(String from, String to) async {
          final result = await api.request(
            'GET',
            '/semesters/$sid/calendar',
            queryParameters: {'from_date': from, 'to_date': to},
          );
          return result['entries'] as List;
        }

        if (releaseOnly) {
          late Map<String, dynamic> task;
          late String eventId;
          expect(['manual', 'learning'], contains(resumeAt));
          if (resumeAt == 'manual') {
            stage = 'release-manual-task';
            GoRouter.of(
              tester.element(find.byType(Scaffold).first),
            ).push('/items/new?kind=task');
            await enter(find.byKey(const Key('item-title')), 'QA手工待办');
            await hideKeyboard();
            await textTap('安排学习时间');
            await enter(find.byKey(const Key('item-minutes')), '30');
            await tap(find.byKey(const Key('task-start-policy')));
            await textTap('从现在起可开始');
            await hideKeyboard();
            await textTap('保存');
            await until(() => find.byType(ItemFormPage).evaluate().isEmpty);
            final manualItems =
                (await api.request('GET', '/semesters/$sid/items'))['items']
                    as List;
            task = Map<String, dynamic>.from(
              manualItems.singleWhere(
                (r) => r['title'] == 'QA手工待办' && r['lifecycle'] == 'active',
              ),
            );
            expect(task['time']['precision'], 'unknown');
            expect(task['remaining_minutes'], 30);
            expect(task['start_policy'], 'now');
            await passed('release-manual-task-unknown-time');

            stage = 'release-notice-clipboard';
            const notice = '大家明天下午三点到我办公室开会@所有人';
            await Clipboard.setData(const ClipboardData(text: notice));
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tap(find.byKey(const Key('clipboard-import')));
            await until(() => find.byType(AgentPage).evaluate().isNotEmpty);
            final event = await askAndSave(
              'release-notice-confirm',
              notice,
              '确认添加',
            );
            expect(event['input_kind'], 'notice');
            eventId = '${event['receipt']['event']['id']}';
            final original = event['receipt']['event'];
            expect(original['time']['end_at'], isNull);
            await askAndSave(
              'release-notice-edit',
              '刚才会议地点改成6412，时间和其他内容不变。',
              '确认修改',
            );
            expect(
              (await api.request('GET', '/events/$eventId'))['location'],
              '6412',
            );
            await undoLast('release-notice-edit-undo');
            final restored = await api.request('GET', '/events/$eventId');
            expect(restored['location'], original['location']);
            expect(restored['time'], original['time']);
            await closeAssistant();
          } else {
            stage = 'resume-learning-window';
            final rows =
                (await api.request('GET', '/semesters/$sid/items'))['items']
                    as List;
            task = Map<String, dynamic>.from(
              rows.singleWhere(
                (r) => r['title'] == 'QA手工待办' && r['lifecycle'] == 'active',
              ),
            );
            expect(resumeEventRun, isNotEmpty);
            final saved = await api.request(
              'GET',
              '/agent/runs/$resumeEventRun',
            );
            expect(saved['status'], 'applied');
            expect(saved['preview']['kind'], 'event');
            expect(saved['receipt']['event']['semester_id'], sid);
            eventId = '${saved['receipt']['event']['id']}';
            expect(
              (await api.request('GET', '/events/$eventId'))['time']['end_at'],
              isNull,
            );
            await passed('resume-learning-window', {
              'reused_notice_checkpoints':
                  'confirmation/edit/undo from 20261004-184149-app-records',
              'new_notice_calls': 0,
            });
          }
          stage = 'release-learning-window';
          await tabTap('计划');
          await textTap('学习时间');
          await textTap('快速设置：每天19:00—21:00');
          await textTap('核对并保存学习时间');
          await textTap('确认保存学习时间');
          await until(() => find.text('可学习时间').evaluate().isEmpty);
          await passed('release-learning-window-save');
          final planned = await askAndSave(
            'release-plan-confirm',
            '帮我安排QA手工待办，剩余30分钟，从现在起按已保存的可学习时间安排。',
            '确认安排',
            fresh: true,
          );
          expect(planned['preview']['kind'], 'plan');
          final blocks =
              (await api.request('GET', '/semesters/$sid/plans'))['blocks']
                  as List;
          expect(blocks, isNotEmpty);
          expect(
            blocks.fold<int>(0, (sum, b) => sum + (b['minutes'] as int)),
            30,
          );
          await undoLast('release-plan-undo');
          expect(
            (await api.request('GET', '/semesters/$sid/plans'))['blocks'],
            isEmpty,
          );
          expect(
            (await api.request(
              'GET',
              '/items/${task['id']}',
            ))['remaining_minutes'],
            30,
          );
          await closeAssistant();

          stage = 'release-reminder';
          GoRouter.of(
            tester.element(find.byType(Scaffold).first),
          ).push('/items/${task['id']}');
          await textTap('添加提醒');
          await textTap('选择提醒日期和时间');
          final reminderAt = schoolNow().add(const Duration(days: 1));
          if (reminderAt.month != schoolNow().month) {
            await tap(find.byTooltip('下个月'));
          }
          await tap(find.text('${reminderAt.day}').hitTestable());
          await tap(find.byKey(const Key('date-time-confirm')));
          await textTap('确认这条提醒');
          await until(() => find.text('确认这条提醒').evaluate().isEmpty);
          final reminders =
              (await api.request('GET', '/items/${task['id']}'))['reminders']
                  as List;
          expect(reminders, hasLength(1));
          expect(reminders.single['mode'], 'absolute');
          expect(
            DateTime.parse(
              reminders.single['trigger_at'],
            ).isAfter(DateTime.now()),
            isTrue,
          );
          final dynamic appState = tester.state(find.byType(SemesterApp));
          var pending = await appState.notifications.plugin
              .pendingNotificationRequests();
          for (var attempt = 0; pending.isEmpty && attempt < 20; attempt++) {
            await pump();
            pending = await appState.notifications.plugin
                .pendingNotificationRequests();
          }
          expect(pending, isNotEmpty);
          await passed('release-reminder-system-pending');
          await tap(find.byTooltip('返回'));
          await tap(find.byTooltip('账户'));
          await textTap('退出登录');
          await until(
            () => find.byKey(const Key('username')).evaluate().isNotEmpty,
          );
          await enter(find.byKey(const Key('username')), username);
          await enter(find.byKey(const Key('password')), 'mobile_flow_2026');
          await hideKeyboard();
          await tap(find.byKey(const Key('auth-submit')));
          await until(
            () =>
                app.loggedIn &&
                app.semester != null &&
                find.byKey(const Key('username')).evaluate().isEmpty,
          );
          expect(
            (await api.request(
              'GET',
              '/items/${task['id']}',
            ))['time']['precision'],
            'unknown',
          );
          expect(
            (await api.request('GET', '/events/$eventId'))['time']['end_at'],
            isNull,
          );
          await passed('release-login-preserves-data');
          await passed('release-eight-step-workflow-finished');
          return;
        }

        if (!const bool.fromEnvironment('QA_MANAGEMENT_ONLY')) {
          await askAndSave(
            'course-suspend',
            '国庆节10月1日到7日都没课，按这个更正我的课表。',
            '确认停课',
            fresh: true,
          );
          expect(
            (await calendar(
              '2026-10-01',
              '2026-10-07',
            )).where((r) => r['resource_type'] == 'course'),
            isEmpty,
          );
          await until(() => find.text('已停课 2 次').evaluate().isNotEmpty);
          await closeAssistant();
          await openAssistant();
          await until(() => find.text('已停课 2 次').evaluate().isNotEmpty);
          await passed('course-saved-history-reopen');
          await undoLast('course-suspend-undo');
          expect(
            (await calendar(
              '2026-10-01',
              '2026-10-07',
            )).where((r) => r['resource_type'] == 'course').length,
            2,
          );
          await askAndSave(
            'course-move',
            '10月5日的UI算法课改到10月9日14点开始，时长不变，地点C303。',
            '确认修改',
            fresh: true,
          );
          expect(
            (await calendar(
              '2026-10-09',
              '2026-10-09',
            )).any((r) => r['title'] == 'UI算法课' && r['location'] == 'C303'),
            isTrue,
          );
          await undoLast('course-move-undo');

          final task = await askAndSave(
            'task-create',
            '帮我记：UI交报名表，没有截止时间。',
            '确认添加',
            fresh: true,
          );
          final taskId = '${task['receipt']['item']['id']}';
          stage = 'task-view';
          await tap(find.text('查看').last);
          await until(() => find.text('事项详情').evaluate().isNotEmpty);
          await passed('task-open-detail');
          await tap(find.byTooltip('返回'));
          await until(() => find.byType(AgentPage).evaluate().isNotEmpty);
          await askAndSave('task-edit', 'UI交报名表还需要30分钟完成。', '确认修改');
          expect(
            (await api.request('GET', '/items/$taskId'))['remaining_minutes'],
            30,
          );
          await askAndSave('task-reminder', '10月6日20点提醒我处理UI交报名表。', '确认修改');
          expect(
            (await api.request('GET', '/items/$taskId'))['reminders'] as List,
            isNotEmpty,
          );
          await askAndSave('task-complete', 'UI交报名表已经完成，标记完成。', '标记完成');
          expect(
            (await api.request('GET', '/items/$taskId'))['lifecycle'],
            'completed',
          );
          await undoLast('task-complete-undo');
          expect(
            (await api.request('GET', '/items/$taskId'))['lifecycle'],
            'active',
          );

          final event = await askAndSave(
            'event-create',
            '10月12日16点开UI组会，结束时间和地点都没确定。记录一下。',
            '确认添加',
            fresh: true,
          );
          final eventId = '${event['receipt']['event']['id']}';
          expect(event['receipt']['event']['time']['end_at'], isNull);
          await askAndSave('event-edit', 'UI组会地点补充为6412，其他不变。', '确认修改');
          expect(
            (await api.request('GET', '/events/$eventId'))['location'],
            '6412',
          );
          await askAndSave('event-reminder', 'UI组会提前30分钟提醒我。', '确认修改');
          expect(
            (await api.request('GET', '/events/$eventId'))['reminder_minutes'],
            contains(30),
          );
          await askAndSave('event-cancel', '取消UI组会。', '确认取消');
          expect(
            (await api.request('GET', '/events/$eventId'))['lifecycle'],
            'cancelled',
          );
          await undoLast('event-cancel-undo');
          expect(
            (await api.request('GET', '/events/$eventId'))['lifecycle'],
            'active',
          );

          final exam = await askAndSave(
            'exam-create',
            '12月1日9点到11点考UI期末考试，地点A101，帮我记录。',
            '确认添加',
            fresh: true,
          );
          final examId = '${exam['receipt']['item']['id']}';
          await askAndSave('exam-edit', 'UI期末考试改为12月3日，具体时刻还没确定。', '确认修改');
          expect(
            (await api.request('GET', '/items/$examId'))['time']['precision'],
            'date',
          );
          await askAndSave('exam-reference', 'UI期末考试仅作参考，不为我占用时间。', '确认修改');
          expect(
            (await api.request('GET', '/items/$examId'))['reserve_time'],
            isFalse,
          );
          await askAndSave('exam-complete', 'UI期末考试已经考完，标记完成。', '标记完成');
          expect(
            (await api.request('GET', '/items/$examId'))['lifecycle'],
            'completed',
          );
          await undoLast('exam-complete-undo');
          await askAndSave(
            'batch-create',
            '一次记录两件事：UI整理照片，没有截止时间；10月13日16点到17点开UI摄影讨论，地点B208。',
            'batch',
            fresh: true,
          );
          await undoLast('batch-undo');
          await closeAssistant();

          // Learning time and personal scheduling through the normal controls.
          stage = 'availability-save';
          await textTap('计划');
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
          await passed('availability-save');
          await askAndSave(
            'task-start-policy',
            'UI交报名表从现在起可以开始安排。',
            '确认修改',
            fresh: true,
          );
          final planned = await askAndSave(
            'plan-create',
            '帮我安排UI交报名表这项任务，剩余30分钟，按我的可学习时间安排。',
            '确认安排',
          );
          expect(planned['preview']['kind'], 'plan');
          final planFeed = await api.request('GET', '/semesters/$sid/plans');
          expect(planFeed['blocks'] as List, isNotEmpty);
          await undoLast('plan-undo');
          expect(
            (await api.request('GET', '/semesters/$sid/plans'))['blocks']
                as List,
            isEmpty,
          );
          await closeAssistant();
        }
        // Reimport changes use the actual production preview and confirmation.
        stage = 'reimport';
        final revised = fixtures
            .map((r) => {...r, if (r['title'] == 'UI算法课') 'location': 'D404'})
            .toList();
        final reimport = showImportPreview(
          tester.element(find.byType(Scaffold).first),
          app,
          revised,
          'haut_webview',
          sourceTerm: '2026-2027/1',
        );
        await pump(1000);
        await textTap('我已核对，替换这些旧课次');
        await textTap('确认保存课表');
        expect(await reimport, isTrue);
        expect(
          (await calendar(
            '2026-10-05',
            '2026-10-05',
          )).any((r) => r['title'] == 'UI算法课' && r['location'] == 'D404'),
          isTrue,
        );
        await passed('reimport-replace');

        stage = 'course-edit';
        final courses =
            await api.request('GET', '/semesters/$sid/courses') as List;
        final courseId = courses.firstWhere((c) => c['title'] == 'UI算法课')['id'];
        GoRouter.of(
          tester.element(find.byType(Scaffold).first),
        ).push('/courses/$courseId');
        await until(() => find.text('编辑课程安排').evaluate().isNotEmpty);
        await textTap('编辑课程安排');
        await enter(field('上课地点（可留空）'), 'E505');
        await hideKeyboard();
        await textTap('保存课程');
        await textTap('确认保存');
        await until(() => find.text('保存课程').evaluate().isEmpty);
        expect(
          (await api.request(
            'GET',
            '/courses/$courseId',
          ))['course']['location'],
          'E505',
        );
        await passed('course-edit');
        stage = 'course-delete';
        await textTap('删除这门课程');
        await textTap('确认删除');
        await until(() => find.text('删除这门课程').evaluate().isEmpty);
        await until(() => find.text('课程事务').evaluate().isEmpty);
        expect(
          (await api.request('GET', '/semesters/$sid/courses') as List).any(
            (c) => c['id'] == courseId,
          ),
          isFalse,
        );
        await passed('course-delete');

        stage = 'semester-settings';
        await textTap('学期');
        await textTap('管理学期与课表');
        await textTap('修改校历与节次');
        await tap(find.byTooltip('添加一节'));
        await tap(find.byTooltip('减少一节'));
        await tester.drag(find.byType(ListView).last, const Offset(0, 1800));
        await pump(500);
        await enter(field('学期名称'), 'Android流程验证学期-已修改');
        await hideKeyboard();
        await textTap('保存学期设置');
        await until(() => find.text('保存学期设置').evaluate().isEmpty);
        expect(app.semester!['name'], 'Android流程验证学期-已修改');
        await passed('semester-edit-and-period-buttons');
        await tap(find.byTooltip('返回'));

        // Manual creation keeps an unset date unset.
        stage = 'manual-task-create';
        GoRouter.of(
          tester.element(find.byType(Scaffold).first),
        ).push('/items/new?kind=task');
        await until(
          () => find.byKey(const Key('item-title')).evaluate().isNotEmpty,
        );
        await enter(find.byKey(const Key('item-title')), 'UI手工待办');
        await hideKeyboard();
        await textTap('保存');
        await until(() => find.byType(ItemFormPage).evaluate().isEmpty);
        final manualItems =
            (await api.request('GET', '/semesters/$sid/items'))['items']
                as List;
        expect(
          manualItems.any(
            (r) =>
                r['title'] == 'UI手工待办' && r['time']['precision'] == 'unknown',
          ),
          isTrue,
        );
        await passed('manual-task-create');
        stage = 'query-only';
        await openAssistant(fresh: true);
        const question = '10月1日至7日有课吗？';
        await enter(find.byKey(const Key('agent-input')), question);
        await hideKeyboard();
        await tap(find.byTooltip('发送'));
        final queryRun = await lastRun(question);
        expect(queryRun['status'], 'completed');
        expect(queryRun['preview'], isNull);
        await passed('read-only-query');
        stage = 'reject-preview';
        const rejected = '记录UI不保存的任务，没有截止时间。';
        await enter(find.byKey(const Key('agent-input')), rejected);
        await hideKeyboard();
        await tap(find.byTooltip('发送'));
        final rejectRun = await lastRun(rejected);
        expect(rejectRun['status'], 'needs_confirmation');
        await textTap('暂不添加');
        expect(
          (await api.request(
            'GET',
            '/agent/runs/${rejectRun['id']}',
          ))['status'],
          'cancelled',
        );
        expect(
          ((await api.request('GET', '/semesters/$sid/items'))['items'] as List)
              .any((r) => '${r['title']}'.contains('UI不保存')),
          isFalse,
        );
        await passed('reject-preview-no-write');
        await closeAssistant();

        stage = 'semester-delete';
        await textTap('学期');
        await textTap('管理学期与课表');
        await textTap('删除当前学期');
        await textTap('确认删除');
        await until(() => app.semester == null);
        await until(() => app.notice == null);
        expect(await api.request('GET', '/semesters') as List, isEmpty);
        await passed('semester-delete-with-records');
        await passed('record-workflows-finished');
      } catch (error, stack) {
        evidence.add({'case': stage, 'passed': false, 'error': '$error'});
        debugPrint('APP_FLOW_FAIL $stage: $error\n$stack');
        try {
          await shot('failure');
        } catch (_) {}
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: releaseOnly ? 10 : 25)),
  );
}
