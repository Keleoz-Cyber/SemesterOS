import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/features/calendar/calendar_panel.dart';
import 'package:semester_os/features/calendar/schedule_grid.dart';

import 'api_session_test.dart' show ControlledTransport, body;
import 'calendar_flow_test.dart' show semester;
import 'centers_flow_test.dart' show settleIo;
import 'controller_test.dart' show MemoryStore;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount;

Map<String, dynamic> sundayEvent(String id, String title, String at) => {
  'id': id,
  'resource_id': id,
  'resource_type': 'event',
  'title': title,
  'start_at': '2026-09-27T$at+08:00',
  'end_at': '2026-09-27T${int.parse(at.substring(0, 2)) + 1}:00:00+08:00',
  'time_precision': 'exact',
};

void main() {
  testWidgets('phone week shows full Sunday agenda and day mode at 320dp', (
    tester,
  ) async {
    final fixture = ScheduleFixture();
    final previous = fixture.api.dio.httpClientAdapter as ControlledTransport;
    fixture.api.dio.httpClientAdapter = ControlledTransport((request) async {
      if (request.path.contains('/calendar?')) {
        return body({
          'semester_id': 's',
          'revision': 1,
          'entries': [
            sundayEvent('a', '项目讨论', '17:00:00'),
            sundayEvent('b', 'Java实验报告', '19:00:00'),
            sundayEvent('c', '社团报名与材料确认', '19:15:00'),
            sundayEvent('d', '整理调研材料', '20:00:00'),
            {
              'id': 'due',
              'resource_id': 'due',
              'resource_type': 'deadline',
              'title': '提交开题报告',
              'due_at': '2026-09-27T20:30:00+08:00',
              'time_precision': 'exact',
            },
          ],
          'undated': [],
        });
      }
      return previous.respond(request);
    });
    await tester.runAsync(() => fixture.c.bind('s'));
    final app =
        AppController(
            fixture.api,
            MemoryStore(),
            clearSchoolSession: () async {},
          )
          ..semester = semester()
          ..week = 4;
    final panel = GlobalKey<CalendarPanelState>();
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: CalendarPanel(key: panel, app: app, items: fixture.c),
        ),
      ),
      width: 320,
      textScale: 1.5,
    );
    await settleIo(tester);
    final weekAgenda = find.byKey(const ValueKey('calendar-week-agenda'));
    expect(weekAgenda, findsOneWidget);
    expect(find.byType(ScheduleGrid), findsNothing);
    for (final title in ['项目讨论', 'Java实验报告', '社团报名与材料确认', '整理调研材料', '提交开题报告']) {
      expect(
        find.descendant(of: weekAgenda, matching: find.text(title)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: weekAgenda, matching: find.text('17:00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: weekAgenda, matching: find.text('19:15')),
      findsWidgets, // The live clock may also read 19:15 during the test.
    );
    expect(
      find.descendant(of: weekAgenda, matching: find.text('5项')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    panel.currentState!.selectDay(DateTime.utc(2026, 9, 27));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周').first);
    await tester.pumpAndSettle();
    final sunday = find.byKey(const ValueKey('calendar-day-2026-09-27'));
    expect(sunday.hitTestable(), findsOneWidget);
    expect(tester.getRect(sunday).right, lessThanOrEqualTo(320));

    final fade = find.byType(AnimatedCrossFade).first;
    await tester.tap(find.text('日').first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedCrossFade>(fade).crossFadeState,
      CrossFadeState.showSecond,
    );
    final day = tester
        .state<CalendarPanelState>(find.byType(CalendarPanel))
        .selectedDay!;
    expect(
      find.text('${day.month}月${day.day}日 · 周${'一二三四五六日'[day.weekday - 1]}'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-day-2026-09-27')),
      findsOneWidget,
    );
    await tester.tap(find.text('周').first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedCrossFade>(fade).crossFadeState,
      CrossFadeState.showFirst,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    fixture.c.dispose();
    app.dispose();
  });
}
