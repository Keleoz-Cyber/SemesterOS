import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/features/calendar/calendar_panel.dart';
import 'package:semester_os/features/home/today_dashboard.dart';
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'calendar_flow_test.dart' show semester;
import 'controller_test.dart' show MemoryStore;
import 'api_session_test.dart' show ControlledTransport, body;
import 'ui_polish_test.dart' show mount;
import 'centers_flow_test.dart' show settleIo;

void main() {
  testWidgets('agenda sorts mixed timezone offsets by real time', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.contains('/calendar?')) {
        return body({
          'semester_id': 's',
          'revision': 1,
          'undated': [],
          'entries': [
            {
              'id': 'plan',
              'resource_type': 'plan',
              'resource_id': 'p',
              'title': '晚间计划',
              'start_at': '2026-09-23T09:00:00Z',
              'end_at': '2026-09-23T10:00:00Z',
              'time_precision': 'exact',
            },
            {
              'id': 'course',
              'resource_type': 'course',
              'resource_id': 'c',
              'title': '下午课程',
              'start_at': '2026-09-23T14:00:00+08:00',
              'end_at': '2026-09-23T15:00:00+08:00',
              'time_precision': 'exact',
            },
          ],
        });
      }
      return old.respond(r);
    });
    await tester.runAsync(() => f.c.bind('s'));
    final app =
        AppController(f.api, MemoryStore(), clearSchoolSession: () async {})
          ..semester = semester()
          ..week = 4;
    final key = GlobalKey<CalendarPanelState>();
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: CalendarPanel(key: key, app: app, items: f.c),
        ),
      ),
    );
    await settleIo(tester);
    key.currentState!.selectDay(DateTime.utc(2026, 9, 23));
    await tester.pumpAndSettle();
    expect(
      // AnimatedCrossFade keeps the hidden week projection mounted.
      tester.getTopLeft(find.text('下午课程').last).dy,
      lessThan(tester.getTopLeft(find.text('晚间计划').last).dy),
    );
    expect(find.text('17:00').last, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
    app.dispose();
  });

  testWidgets('failed agenda with no cache does not claim an empty day', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.contains('/calendar?')) {
        throw StateError('network unavailable');
      }
      return old.respond(r);
    });
    await tester.runAsync(() => f.c.bind('s'));
    final app =
        AppController(f.api, MemoryStore(), clearSchoolSession: () async {})
          ..semester = semester()
          ..week = 4;
    final key = GlobalKey<CalendarPanelState>();
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: CalendarPanel(key: key, app: app, items: f.c),
        ),
      ),
    );
    await settleIo(tester);
    key.currentState!.selectDay(DateTime.utc(2026, 9, 23));
    await tester.pumpAndSettle();
    expect(key.currentState!.repository.offline, isTrue);
    expect(find.text('这一天没有已记录的安排'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
    app.dispose();
  });

  testWidgets(
    'hidden and background today page cancels its clock and resumes once',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      final app = AppController(
        f.api,
        MemoryStore(),
        clearSchoolSession: () async {},
      )..semester = semester();
      final key = GlobalKey<TodayDashboardState>();
      final visible = ValueNotifier(true);
      await mount(
        tester,
        Scaffold(
          body: ValueListenableBuilder(
            valueListenable: visible,
            builder: (_, enabled, _) => TickerMode(
              enabled: enabled,
              child: SingleChildScrollView(
                child: TodayDashboard(
                  key: key,
                  app: app,
                  items: f.c,
                  onCalendar: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await settleIo(tester);
      expect(key.currentState!.clock?.isActive, isTrue);
      visible.value = false;
      await tester.pump();
      expect(key.currentState!.clock, isNull);
      visible.value = true;
      await settleIo(tester);
      expect(key.currentState!.clock?.isActive, isTrue);
      key.currentState!.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(key.currentState!.clock, isNull);
      key.currentState!.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settleIo(tester);
      expect(key.currentState!.clock?.isActive, isTrue);
      await tester.pumpWidget(const SizedBox());
      visible.dispose();
      f.c.dispose();
      app.dispose();
    },
  );
}
