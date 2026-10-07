import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/features/home/today_dashboard.dart';
import 'package:semester_os/features/calendar/time_track.dart';
import 'package:semester_os/features/home/home_preferences.dart';
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'calendar_flow_test.dart' show semester;
import 'controller_test.dart' show MemoryStore;
import 'api_session_test.dart' show ControlledTransport, body;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  for (final populated in [false, true]) {
    testWidgets(
      'Today overview and stored views keep the date anchor for ${populated ? 'urgent and next-day content' : 'empty views'}',
      (tester) async {
        final f = ScheduleFixture();
        final old = f.api.dio.httpClientAdapter as ControlledTransport;
        f.api.dio.httpClientAdapter = ControlledTransport((r) async {
          if (r.path.contains('/day-brief?')) {
            return body({
              'semester_id': 's',
              'revision': 1,
              'date': '2026-09-21',
              'valid_until': '2099-01-01T00:00:00Z',
              'entries': [
                if (populated)
                  {
                    'id': 'course',
                    'resource_id': 'course',
                    'resource_type': 'course',
                    'title': '晚间课程',
                    'start_at': '2026-09-21T18:00:00+08:00',
                    'end_at': '2026-09-21T19:00:00+08:00',
                    'time_precision': 'exact',
                  },
              ],
              'next_day': {
                'entries': [
                  if (populated)
                    {
                      'id': 'tomorrow',
                      'resource_type': 'course',
                      'title': '次日课程',
                      'start_at': '2026-09-22T08:00:00+08:00',
                      'end_at': '2026-09-22T09:00:00+08:00',
                    },
                ],
              },
              'undated': [],
              'suggestions': [],
              'available_windows': [],
              'needs_availability': true,
            });
          }
          return old.respond(r);
        });
        await tester.runAsync(() => f.c.bind('s'));
        f.c.items = [
          if (populated)
            {
              ...f.item,
              'title': '课后报告',
              'priority': 'high',
              'time': {
                'precision': 'exact',
                'meaning': 'deadline',
                'at': '2026-09-23T20:00:00+08:00',
              },
            },
        ];
        final app = AppController(
          f.api,
          MemoryStore(),
          clearSchoolSession: () async {},
        )..semester = semester();
        var calendarOpens = 0, taskOpens = 0;
        await mount(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: TodayDashboard(
                app: app,
                items: f.c,
                onCalendar: () => calendarOpens++,
                onAllTasks: () => taskOpens++,
                now: () => DateTime.utc(2026, 9, 21, 17, 30),
              ),
            ),
          ),
          width: populated ? 320 : 390,
          textScale: populated ? 1.7 : 1,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
        final dashboard = tester.state<TodayDashboardState>(
          find.byType(TodayDashboard),
        );
        final dateHeader = tester.getRect(find.byTooltip('调整首页内容'));
        expect(find.byKey(const Key('today-events-action')), findsOneWidget);
        expect(find.byKey(const Key('today-tasks-action')), findsOneWidget);
        if (populated) {
          expect(find.text('课后报告'), findsOneWidget);
          expect(find.text('晚间课程'), findsOneWidget);
          expect(
            tester.getTopLeft(find.text('次日课程')).dy,
            greaterThan(tester.getTopLeft(find.text('课后报告')).dy),
          );
        }
        if (!populated) await capture(tester, 'today-empty-agenda');
        if (!populated) {
          await tester.tap(find.byTooltip('调整首页内容'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('日程与待办'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('仅待办'));
          await tester.pumpAndSettle();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 80)),
          );
          expect(dashboard.preferences.todayView, TodayViewMode.tasks);
          await tester.tap(find.text('完成').hitTestable());
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('today-events-action')), findsNothing);
        }
        if (populated) expect(find.text('次日课程'), findsOneWidget);
        for (final mode in [
          TodayViewMode.tasks,
          TodayViewMode.schedule,
          TodayViewMode.tasks,
        ]) {
          await tester.runAsync(
            () => dashboard.preferences.change(todayView: mode),
          );
          await tester.pump(const Duration(milliseconds: 55));
          expect(
            tester.getRect(find.byTooltip('调整首页内容')).top,
            closeTo(dateHeader.top, .001),
          );
        }
        await tester.pumpAndSettle();
        if (!populated) await capture(tester, 'today-empty-tasks');
        expect(find.text('次日课程'), findsNothing);
        expect(find.text(populated ? '课后报告' : '暂无待办事项'), findsOneWidget);
        await tester.tap(find.byKey(const Key('today-secondary-action')));
        await tester.pumpAndSettle();
        expect(taskOpens, 1);
        expect(calendarOpens, 0);
        await tester.runAsync(
          () => dashboard.preferences.change(todayView: TodayViewMode.schedule),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('today-secondary-action')));
        await tester.pumpAndSettle();
        expect(calendarOpens, 1);
        expect(
          tester.getRect(find.byTooltip('调整首页内容')).top,
          closeTo(dateHeader.top, .001),
        );
        if (populated) expect(find.text('次日课程'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        f.c.dispose();
        app.dispose();
      },
    );
  }
  testWidgets(
    'deleting the selected semester stops the old dashboard listener and clock',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var briefReads = 0;
      var weekReads = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/calendar?')) weekReads++;
        if (r.path.contains('/day-brief?')) {
          briefReads++;
          return body({
            'semester_id': 's',
            'revision': 1,
            'date': '2026-09-21',
            'valid_until': '2099-01-01T00:00:00Z',
            'entries': [],
            'undated': [],
            'suggestions': [],
            'available_windows': [],
            'needs_availability': true,
          });
        }
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      final app = AppController(
        f.api,
        MemoryStore(),
        clearSchoolSession: () async {},
      )..semester = semester();
      await mount(
        tester,
        TodayDashboard(
          app: app,
          items: f.c,
          onCalendar: () {},
          now: () => DateTime.utc(2026, 9, 21, 7),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(weekReads, 0);
      final dashboard = tester.state<TodayDashboardState>(
        find.byType(TodayDashboard),
      );
      await dashboard.preferences.change(
        enabled: {...dashboard.preferences.enabled, 'week_heatmap'},
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(weekReads, 1);
      await dashboard.preferences.change(
        enabled: {'deadlines', 'plans', 'windows', 'exams'},
      );
      await tester.runAsync(dashboard.reload);
      expect(weekReads, 1);
      final before = briefReads;
      app.semester = null;
      f.c.changed();
      await tester.runAsync(() => f.c.bind(null));
      await tester.pump();
      await tester.pump(const Duration(minutes: 1));
      expect(tester.takeException(), isNull);
      expect(briefReads, before);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
      app.dispose();
    },
  );
  testWidgets('today puts three courses above fold and offers module editing', (
    tester,
  ) async {
    final f = ScheduleFixture();
    var current = DateTime.utc(2026, 9, 21, 7);
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.contains('/day-brief?')) {
        return body({
          'semester_id': 's',
          'revision': 1,
          'date': '2026-09-21',
          'valid_until': '2099-01-01T00:00:00Z',
          'entries': [
            for (var i = 0; i < 3; i++)
              {
                'id': 'c$i',
                'resource_id': 'c$i',
                'resource_type': 'course',
                'title': ['概率论', '程序设计', '大学英语'][i],
                'location': 'A${i + 1}01',
                'start_at': '2026-09-21T${['08', '10', '14'][i]}:00:00+08:00',
                'end_at': '2026-09-21T${['09', '11', '15'][i]}:50:00+08:00',
                'time_precision': 'exact',
              },
          ],
          'undated': [],
          'suggestions': [],
          'available_windows': [],
          'needs_availability': true,
        });
      }
      return old.respond(r);
    });
    await tester.runAsync(() => f.c.bind('s'));
    final app = AppController(
      f.api,
      MemoryStore(),
      clearSchoolSession: () async {},
    )..semester = semester();
    await mount(
      tester,
      Scaffold(
        appBar: AppBar(title: const Text('品牌')),
        bottomNavigationBar: const SizedBox(height: 134),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TodayDashboard(
              app: app,
              items: f.c,
              onCalendar: () {},
              now: () => current,
            ),
          ],
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(find.text('大学英语'), findsOneWidget);
    expect(tester.getRect(find.text('大学英语')).bottom, lessThan(710));
    expect(find.byTooltip('调整首页内容'), findsOneWidget);
    await capture(tester, 'today-course-first');
    final dashboard = tester.state<TodayDashboardState>(
      find.byType(TodayDashboard),
    );
    await tester.runAsync(
      () => dashboard.preferences.change(todayView: TodayViewMode.schedule),
    );
    await tester.pumpAndSettle();
    current = DateTime.utc(2026, 9, 21, 8, 55);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    final active = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('time-track-event-progress')),
    );
    expect(active.value, closeTo(.5, .001));
    expect(find.text('现在 08:55'), findsOneWidget);
    await capture(tester, 'today-current-active');
    current = DateTime.utc(2026, 9, 21, 9, 55);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    final gap =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byKey(const ValueKey('time-track-current-gap')),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as TimeTrackMarkerPainter;
    expect(gap.fraction, closeTo(.5, .001));
    expect(find.text('现在 09:55'), findsOneWidget);
    await capture(tester, 'today-current-gap');
    f.c.items = [
      {
        ...f.item,
        'id': 'exam',
        'kind': 'exam',
        'title': '本周暂定考试',
        'certainty': 'tentative',
        'time': {'precision': 'week', 'week': 4},
      },
      {
        ...f.item,
        'id': 'range',
        'title': '本周待定汇报',
        'time': {
          'precision': 'range',
          'date': '2026-09-20',
          'end_date': '2026-09-24',
        },
      },
    ];
    f.c.changed();
    await tester.pumpAndSettle();
    expect(find.text('本周暂定考试'), findsOneWidget);
    expect(find.text('本周待定汇报'), findsOneWidget);
    expect(find.text('截止日期已过'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
    app.dispose();
  });
}
