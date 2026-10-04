import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/calendar/calendar_repository.dart';
import 'package:semester_os/features/home/day_brief_controller.dart';
import 'package:semester_os/features/calendar/time_track.dart';
import 'controller_test.dart' show MemoryStore;
import 'package:semester_os/features/calendar/calendar_panel.dart';
import 'package:semester_os/features/home/today_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:semester_os/app/controller.dart';
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'api_session_test.dart' show ControlledTransport, body;
import 'calendar_flow_test.dart' show semester;
import 'ui_polish_test.dart' show mount;

void main() {
  testWidgets(
    'today displays the paper window once without an empty next card or deadline warning',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      final time = {
        'precision': 'exact',
        'meaning': 'window',
        'at': '2026-10-09T09:00:00+08:00',
        'end_at': '2026-10-09T18:00:00+08:00',
      };
      f.item = {
        ...f.item,
        'title': '交纸质报名表',
        'remaining_minutes': null,
        'time': time,
        'anchor_at': null,
      };
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/day-brief?')) {
          return body({
            'semester_id': 's',
            'revision': 1,
            'date': '2026-10-09',
            'entries': [
              {
                'id': 'deadline:t',
                'resource_id': 't',
                'resource_type': 'deadline',
                'title': '交纸质报名表',
                'date': '2026-10-09',
                'time': time,
                'fixed': false,
              },
            ],
            'suggestions': [],
            'undated': [],
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
          body: ListView(
            children: [
              TodayDashboard(
                app: app,
                items: f.c,
                onCalendar: () {},
                now: () => DateTime.utc(2026, 10, 9, 10),
              ),
            ],
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.text('交纸质报名表'), findsOneWidget);
      expect(find.text('暂无后续安排'), findsNothing);
      expect(find.text('今日截止'), findsNothing);
      expect(find.text('截止日期已过'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
      app.dispose();
    },
  );
  test(
    'known task start stays visible without becoming a deadline or interval',
    () {
      final row = <String, dynamic>{
        'id': 'start-task',
        'resource_type': 'task',
        'time': {
          'precision': 'exact',
          'meaning': 'start',
          'at': '2026-10-09T09:00:00+08:00',
        },
      };
      final display = calendarDisplayEntry(row);
      expect(display['start_at'], '2026-10-09T09:00:00+08:00');
      expect(display['end_at'], isNull);
      expect(calendarTimeLabel(row), '10/9 09:00');
      expect(
        CalendarPanelState().onDay(row, DateTime.utc(2026, 10, 9)),
        isTrue,
      );
      expect(
        TodayDashboardState().deadline({'kind': 'task', 'time': row['time']}),
        isNull,
      );
    },
  );
  test(
    'required paper window does not become a reference or urgent deadline',
    () {
      final row = <String, dynamic>{
        'reserve_time': true,
        'time': {
          'precision': 'exact',
          'meaning': 'window',
          'at': '2026-10-09T09:00:00+08:00',
          'end_at': '2026-10-09T18:00:00+08:00',
        },
      };
      expect(calendarReservesTime(row), isFalse);
      expect(calendarParticipationLabel(row), '');
      expect(calendarTimeLabel(row), contains('办理窗口'));
      expect(
        TodayDashboardState().deadline({'kind': 'task', 'time': row['time']}),
        isNull,
      );
    },
  );
  test('optional reference events never occupy a known interval', () {
    final row = <String, dynamic>{
      'id': 'reference',
      'reserve_time': false,
      'details': {'participation_status': 'optional'},
      'start_at': '2026-09-21T09:00:00+08:00',
      'end_at': '2026-09-21T10:00:00+08:00',
    };
    expect(calendarGridEntries([row], DateTime.utc(2026, 9, 21)), isEmpty);
    expect(calendarParticipationLabel(row), '可选');
    final current = trackPosition(
      [row],
      DateTime.utc(2026, 9, 21),
      DateTime.utc(2026, 9, 21, 9, 30),
    )!;
    expect(current.inOccurrence, isFalse);
  });
  testWidgets('minute clock aligns its first tick and cancels further work', (
    tester,
  ) async {
    var current = DateTime.utc(2026, 9, 21, 9, 30, 45), ticks = 0;
    final clock = MinuteClock(() => ticks++, now: () => current);
    await tester.pump(const Duration(seconds: 14));
    expect(ticks, 0);
    current = DateTime.utc(2026, 9, 21, 9, 31);
    await tester.pump(const Duration(seconds: 1));
    expect(ticks, 1);
    await tester.pump(const Duration(seconds: 59));
    expect(ticks, 1);
    clock.cancel();
    await tester.pump(const Duration(minutes: 2));
    expect(ticks, 1);
  });
  test(
    'nested notice windows retain their facts without calendar occupancy',
    () {
      final row = <String, dynamic>{
        'id': 'window',
        'start_at': '2026-09-21T08:00:00+08:00',
        'end_at': '2026-09-21T16:00:00+08:00',
        'time': {
          'precision': 'exact',
          'meaning': 'window',
          'at': '2026-09-21T08:00:00+08:00',
          'end_at': '2026-09-21T16:00:00+08:00',
        },
      };
      expect(calendarGridEntries([row], DateTime.utc(2026, 9, 21)), isEmpty);
      expect(calendarTimeLabel(row), '办理窗口：9/21 08:00—9/21 16:00');
      expect(
        calendarTimeLabel({
          'time': {'precision': 'unknown', 'expression': '等学院后续通知'},
        }),
        '等学院后续通知',
      );
    },
  );
  test(
    'explicit early arrival extends only a known interval and preserves meeting start',
    () {
      final row = <String, dynamic>{
        'id': 'meeting',
        'start_at': '2026-09-21T15:00:00+08:00',
        'end_at': '2026-09-21T16:00:00+08:00',
        'arrival_at': '2026-09-21T14:30:00+08:00',
        'occupancy_start_at': '2026-09-21T14:30:00+08:00',
      };
      final parts = calendarGridEntries([row], DateTime.utc(2026, 9, 21));
      expect(
        DateTime.parse(
          parts.single['end_at'],
        ).difference(DateTime.parse(parts.single['start_at'])).inMinutes,
        90,
      );
      expect(row['start_at'], '2026-09-21T15:00:00+08:00');
      expect(calendarArrivalLabel(row), '14:30到场');
      final current = trackPosition(
        [row],
        DateTime.utc(2026, 9, 21),
        DateTime.utc(2026, 9, 21, 14, 45),
      )!;
      expect(current.inOccurrence, isTrue);
      expect(current.fraction, closeTo(1 / 6, .001));
      expect(
        calendarGridEntries([
          {...row, 'end_at': null},
        ], DateTime.utc(2026, 9, 21)),
        isEmpty,
      );
    },
  );
  final rows = [
    {
      'start_at': '2026-09-21T08:00:00+08:00',
      'end_at': '2026-09-21T09:00:00+08:00',
    },
    {
      'start_at': '2026-09-21T10:00:00+08:00',
      'end_at': '2026-09-21T11:00:00+08:00',
    },
  ];
  test(
    'clock position interpolates an active occurrence and the actual gap',
    () {
      final active = trackPosition(
        rows,
        DateTime.utc(2026, 9, 21),
        DateTime.utc(2026, 9, 21, 8, 30),
      )!;
      expect(active.inOccurrence, isTrue);
      expect(active.index, 0);
      expect(active.fraction, closeTo(.5, .001));
      final gap = trackPosition(
        rows,
        DateTime.utc(2026, 9, 21),
        DateTime.utc(2026, 9, 21, 9, 30),
      )!;
      expect(gap.inOccurrence, isFalse);
      expect(gap.index, 1);
      expect(gap.fraction, closeTo(.5, .001));
      expect(
        trackPosition(
          rows,
          DateTime.utc(2026, 9, 22),
          DateTime.utc(2026, 9, 21, 8, 30),
        ),
        isNull,
      );
    },
  );
  test('a start-only point cannot be treated as currently occupying time', () {
    final point = trackPosition(
      [
        {'start_at': '2026-09-21T08:00:00+08:00'},
        rows.last,
      ],
      DateTime.utc(2026, 9, 21),
      DateTime.utc(2026, 9, 21, 9),
    )!;
    expect(point.inOccurrence, isFalse);
    expect(point.index, 1);
    expect(point.fraction, closeTo(.5, .001));
  });
  test('optional clocks show existing facts without missing-field labels', () {
    expect(
      calendarTimeLabel({'start_at': '2026-09-21T10:10:00+08:00'}),
      '9/21 10:10',
    );
    expect(calendarTimeLabel({'date': '2026-09-21'}), '9月21日');
    expect(calendarTimeLabel({}), isEmpty);
    expect(
      calendarTimeLabel({'time_precision': 'unknown', 'expression': '等学院后续通知'}),
      '等学院后续通知',
    );
  });
  test('generic missing-time suggestions do not gate unrelated schedules', () {
    final brief = DayBriefController(SemesterApi(), MemoryStore())
      ..data = {
        'suggestions': [
          {'kind': 'missing_time', 'title': '有安排的起止时间还没确定'},
          {'kind': 'plan_conflict', 'title': '个人计划与课程重叠'},
        ],
      };
    expect(brief.suggestions.map((r) => r['kind']), ['plan_conflict']);
    brief.dispose();
  });
}
