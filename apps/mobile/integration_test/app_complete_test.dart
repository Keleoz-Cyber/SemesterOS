// Opt-in local Android acceptance. Never connects to the production account/API.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/app/semester_app.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/core/cache.dart';
import 'package:semester_os/core/device_surfaces.dart';
import 'package:semester_os/features/timetable/shell_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'search, native live activity and feedback use the real local app',
    (tester) async {
      const base = String.fromEnvironment('API_BASE_URL');
      expect(base, 'http://10.0.2.2:8871');
      final api = SemesterApi(baseUrl: base);
      await api.forget();
      final username = 'complete_${DateTime.now().millisecondsSinceEpoch}';
      final session = Map<String, dynamic>.from(
        await api.request(
          'POST',
          '/auth/register',
          authenticated: false,
          data: {'username': username, 'password': 'local-surface-check-4812'},
        ),
      );
      await api.saveSession(session);
      final today = schoolNow(),
          first = schoolNow().subtract(Duration(days: schoolNow().weekday - 1));
      String date(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final semester = await api.request(
        'POST',
        '/semesters',
        data: {
          'name': '完善验收（合成数据）',
          'first_monday': date(first),
          'total_weeks': 20,
          'periods': [
            {'number': 1, 'start': '08:30', 'end': '09:15'},
            {'number': 2, 'start': '09:20', 'end': '10:05'},
          ],
        },
      );
      final at = DateTime.now().toUtc().add(const Duration(minutes: 8));
      await api.request(
        'POST',
        '/events',
        data: {
          'semester_id': semester['id'],
          'expected_revision': 0,
          'title': '实验小组讨论',
          'location': '6108',
          'source_text': '实验小组讨论，带上报告，地点6108',
          'certainty': 'formal',
          'time': {
            'precision': 'exact',
            'at': at.toIso8601String(),
            'end_at': at.add(const Duration(minutes: 35)).toIso8601String(),
          },
          'reminder_minutes': [5],
        },
      );
      final app = AppController(
        api,
        CalendarCache(),
        clearSchoolSession: () async {},
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWithValue(app)],
          child: const SemesterApp(),
        ),
      );
      Future<void> until(bool Function() ready, {int seconds = 35}) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!ready() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(ready(), isTrue);
        expect(tester.takeException(), isNull);
      }

      await until(
        () =>
            app.ready &&
            app.semester != null &&
            find.byType(ShellPage).evaluate().isNotEmpty,
      );
      final router = GoRouter.of(tester.element(find.byType(ShellPage)));
      router.push('/search');
      await until(() => find.text('搜索安排').evaluate().isNotEmpty);
      await tester.enterText(find.byType(TextField).first, '6108');
      await until(() => find.text('实验小组讨论').evaluate().isNotEmpty);
      await tester.tap(find.text('实验小组讨论').first);
      await until(() => find.text('日程详情').evaluate().isNotEmpty);
      await until(() => find.textContaining('6108').evaluate().isNotEmpty);
      router.go('/device-surfaces');
      await until(() => find.text('桌面卡片与实时提醒').evaluate().isNotEmpty);
      await until(() => find.text('跟踪').evaluate().isNotEmpty);
      await tester.tap(find.text('跟踪').first);
      await until(() => find.text('跟踪中').evaluate().isNotEmpty);
      final status = await DeviceSurfaces.status();
      expect(status['sdk'], greaterThanOrEqualTo(36));
      expect(status['tracked'], isNotEmpty);
      await DeviceSurfaces.action('test');
      router.go('/feedback');
      await until(() => find.text('反馈问题').evaluate().isNotEmpty);
      await tester.enterText(find.byType(TextField).first, '合成验收：搜索、跟踪均已操作');
      await tester.tap(find.text('提交反馈'));
      await until(() => find.text('反馈已提交').evaluate().isNotEmpty);
      router.go('/data');
      await until(() => find.text('导出个人数据').evaluate().isNotEmpty);
      expect(find.text('删除账号'), findsOneWidget);
      if (const bool.fromEnvironment('QA_DATA_EXPORT')) {
        await tester.tap(find.text('导出个人数据'));
        await until(
          () => find.text('数据已导出到你选择的位置').evaluate().isNotEmpty,
          seconds: 60,
        );
      }
      router.go('/device-surfaces');
      await tester.pump(const Duration(seconds: 1));
      // Leaves a real platform widget chooser for the host-side launcher check.
      await DeviceSurfaces.action('pinWidget');
      if (const bool.fromEnvironment('QA_HOLD_SURFACES')) {
        await Future<void>.delayed(const Duration(seconds: 45));
      }
      await DeviceSurfaces.action('stop');
      expect((await DeviceSurfaces.status())['tracked'], isEmpty);
      // The test account is synthetic. Exercise the real password+confirmation UI.
      router.go('/data');
      await until(() => find.text('删除账号').evaluate().isNotEmpty);
      await tester.tap(find.text('删除账号'));
      await until(() => find.text('删除账号和全部数据').evaluate().isNotEmpty);
      await tester.enterText(
        find.byType(TextField).at(0),
        'local-surface-check-4812',
      );
      await tester.enterText(find.byType(TextField).at(1), '删除我的账号');
      await tester.tap(find.text('删除账号').last);
      await until(() => !app.loggedIn && app.ready);
      final cleared = await DeviceSurfaces.status();
      expect(cleared['tracked'], isEmpty);
      expect(cleared['entries'], isEmpty);
      debugPrint('COMPLETE_DEVICE_PASS ${date(today)}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
