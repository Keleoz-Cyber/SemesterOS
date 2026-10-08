import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/calendar/calendar_panel.dart';
import 'package:semester_os/features/calendar/calendar_repository.dart';
import 'package:semester_os/features/calendar/schedule_grid.dart';
import 'package:semester_os/features/centers/semester_centers.dart';
import 'package:semester_os/features/home/day_brief_controller.dart';
import 'package:semester_os/features/home/home_preferences.dart';
import 'package:semester_os/features/home/next_schedule_card.dart';
import 'package:semester_os/features/home/today_dashboard.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'calendar_flow_test.dart' show semester;
import 'centers_flow_test.dart' show hub;
import 'controller_test.dart' show MemoryStore;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount, loadPreviewFonts;

Map<String, dynamic> attendanceCourse(
  String id,
  String title, {
  String? status,
  bool exempt = false,
  int hour = 8,
  String date = '2026-09-21',
}) => {
  'id': id,
  'resource_id': 'source-$id',
  'resource_type': 'course',
  'title': title,
  'start_at': '${date}T${hour.toString().padLeft(2, '0')}:00:00+08:00',
  'end_at': '${date}T${(hour + 1).toString().padLeft(2, '0')}:00:00+08:00',
  'time_precision': 'exact',
  'attendance_status': ?status,
  if (exempt) 'attendance_exempt': true,
};

List<Map<String, dynamic>> attendanceRows({bool onlyLeave = false}) => [
  attendanceCourse('leave', '请假原课', status: 'leave'),
  if (!onlyLeave) ...[
    attendanceCourse('planned', '计划请假课', status: 'plan_leave'),
    attendanceCourse('active', '正常课程', hour: 10),
    attendanceCourse('exempt', '免听课程', exempt: true, hour: 12),
  ],
];

ScheduleFixture attendanceFixture(
  List<Map<String, dynamic>> rows, {
  List<Map<String, dynamic>> tomorrow = const [],
}) {
  final fixture = ScheduleFixture();
  final old = fixture.api.dio.httpClientAdapter as ControlledTransport;
  fixture.api.dio.httpClientAdapter = ControlledTransport((request) async {
    if (request.path.contains('/calendar?')) {
      return body({
        'semester_id': 's',
        'revision': 1,
        'from_date': '2026-09-21',
        'to_date': '2026-09-27',
        'entries': rows,
        'undated': [],
      });
    }
    if (request.path.contains('/day-brief?')) {
      return body({
        'semester_id': 's',
        'revision': 1,
        'date': '2026-09-21',
        'valid_until': '2099-01-01T00:00:00Z',
        'entries': rows,
        'next_day': {'entries': tomorrow},
        'undated': [],
        'suggestions': [],
        'available_windows': [],
        'needs_availability': true,
      });
    }
    return old.respond(request);
  });
  return fixture;
}

Future<void> settleAttendanceIo(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);

  test('schedule projection hides leave without removing source records', () {
    final source = attendanceRows();
    final api = SemesterApi();
    final repository = CalendarRepository(api, MemoryStore())
      ..data = {'entries': source, 'undated': source};
    final brief = DayBriefController(api, MemoryStore())
      ..data = {'entries': source};
    for (final projection in [
      calendarScheduleEntries(source),
      repository.entries,
      repository.undated,
      brief.entries,
    ]) {
      expect(projection.map((row) => row['id']), [
        'planned',
        'active',
        'exempt',
      ]);
    }
    expect(source.length, 4);
    expect(source.first['title'], '请假原课');
    expect(repository.data?['entries'], same(source));
    expect(brief.data?['entries'], same(source));
    expect(calendarDisplayEntry(source.first)['title'], '已请假 · 请假原课');
    expect(calendarReservesTime(source[1]), isTrue);
    expect(calendarReservesTime(source[3]), isFalse);
    expect(
      calendarGridEntries(
        source,
        DateTime.utc(2026, 9, 21),
      ).map((row) => row['resource_id']),
      ['source-planned', 'source-active'],
    );
    repository.dispose();
    brief.dispose();
  });

  test('raw course fallback preserves explicitly linked events and exams', () {
    final rawCourse = {
      'course_id': 'source-course',
      'weekday': 1,
      'weeks': [1, 2],
      'sections': [1, 2],
      'attendance_status': 'leave',
    };
    final source = <Map<String, dynamic>>[
      {...rawCourse, 'id': 'raw-leave'},
      {
        'id': 'kind-leave',
        'reality_kind': 'course',
        'attendance_status': 'leave',
      },
      {...rawCourse, 'id': 'raw-planned', 'attendance_status': 'plan_leave'},
      {
        ...rawCourse,
        'id': 'raw-exempt',
        'attendance_status': 'attend',
        'attendance_exempt': true,
      },
      {...rawCourse, 'id': 'linked-event', 'resource_type': 'event'},
      {...rawCourse, 'id': 'linked-exam', 'resource_type': 'exam'},
      {...rawCourse, 'id': 'raw-activity', 'reality_kind': 'activity'},
      {
        'id': 'linked-task',
        'course_id': 'source-course',
        'attendance_status': 'leave',
      },
    ];
    expect(calendarScheduleEntries(source).map((row) => row['id']), [
      'raw-planned',
      'raw-exempt',
      'linked-event',
      'linked-exam',
      'raw-activity',
      'linked-task',
    ]);
    expect(source, hasLength(8));
    expect(source.first['attendance_status'], 'leave');
  });

  testWidgets('week grid omits leave points and phantom overlap counts', (
    tester,
  ) async {
    await mount(
      tester,
      Scaffold(
        body: SizedBox(
          height: 550,
          child: ScheduleGrid(
            firstDay: DateTime.utc(2026, 9, 21),
            entries: attendanceRows(),
            onOpen: (_) {},
            now: () => DateTime.utc(2026, 9, 21, 7),
          ),
        ),
      ),
    );
    expect(find.textContaining('请假原课'), findsNothing);
    expect(
      find.byKey(const ValueKey('schedule-start-leave/2026-09-21')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('schedule-tile-planned/2026-09-21')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-tile-active/2026-09-21')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-start-exempt/2026-09-21')),
      findsOneWidget,
    );
    expect(find.text('2项重叠'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('excused occurrence keeps the course attendance restore entry', (
    tester,
  ) async {
    final fixture = attendanceFixture(attendanceRows(onlyLeave: true));
    await tester.runAsync(() => fixture.c.bind('s'));
    final old = fixture.api.dio.httpClientAdapter as ControlledTransport;
    var writes = 0;
    fixture.api.dio.httpClientAdapter = ControlledTransport((request) async {
      if (request.method != 'GET') writes++;
      if (request.path.endsWith('/hub')) {
        return body({
          ...hub(fixture),
          'occurrences': attendanceRows(onlyLeave: true),
        });
      }
      return old.respond(request);
    });
    await mount(
      tester,
      CourseHubPage(
        controller: fixture.c,
        courseId: 'c',
        occurrenceId: 'leave',
      ),
    );
    await settleAttendanceIo(tester);
    expect(find.text('已请假 · 原课程保留'), findsOneWidget);
    expect(find.text('本学期上课安排（1次）'), findsOneWidget);
    await tester.ensureVisible(find.text('本次听课'));
    await tester.tap(find.text('本次听课'));
    await tester.pumpAndSettle();
    expect(find.text('正常上课'), findsOneWidget);
    expect(find.text('撤销本次请假或请假打算'), findsOneWidget);
    expect(writes, 0);
    Navigator.of(tester.element(find.text('正常上课'))).pop();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    fixture.c.dispose();
  });

  for (final onlyLeave in [false, true]) {
    testWidgets(
      'calendar list and day use ${onlyLeave ? 'empty state' : 'remaining count'} after leave',
      (tester) async {
        final source = attendanceRows(onlyLeave: onlyLeave);
        final fixture = attendanceFixture(source);
        await tester.runAsync(() => fixture.c.bind('s'));
        // Courses remain in the catalog even when all current occurrences
        // are excused; that is distinct from never having imported courses.
        fixture.c.courses = [
          {'id': 'source-leave', 'title': '请假原课'},
        ];
        final app =
            AppController(
                fixture.api,
                MemoryStore(),
                clearSchoolSession: () async {},
              )
              ..semester = semester()
              ..week = 4;
        final key = GlobalKey<CalendarPanelState>();
        await mount(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              child: CalendarPanel(
                key: key,
                app: app,
                items: fixture.c,
                now: () => DateTime.utc(2026, 9, 21, 7),
              ),
            ),
          ),
        );
        await settleAttendanceIo(tester);
        final panel = key.currentState!;
        expect(panel.repository.data?['entries'], hasLength(source.length));
        await panel.chooseView('list');
        await tester.pumpAndSettle();
        final agenda = find.byKey(const ValueKey('calendar-week-agenda'));
        expect(agenda, findsOneWidget);
        expect(find.textContaining('请假原课'), findsNothing);
        expect(find.text('还没有课程'), findsNothing);
        expect(
          find.descendant(
            of: agenda,
            matching: find.text(onlyLeave ? '0项' : '3项'),
          ),
          findsOneWidget,
        );
        if (onlyLeave) {
          expect(find.text('暂无安排'), findsOneWidget);
        } else {
          expect(find.text('待请假 · 计划请假课'), findsOneWidget);
          expect(find.text('正常课程'), findsOneWidget);
          expect(find.textContaining('免听课程'), findsOneWidget);
        }
        panel.selectDay(DateTime.utc(2026, 9, 21));
        await tester.pumpAndSettle();
        expect(find.textContaining('请假原课'), findsNothing);
        if (onlyLeave) {
          expect(find.text('这一天没有已记录的安排'), findsOneWidget);
        } else {
          expect(find.text('待请假 · 计划请假课'), findsOneWidget);
          expect(find.text('正常课程'), findsOneWidget);
          expect(find.textContaining('免听课程'), findsOneWidget);
        }
        expect(fixture.c.courses.single['id'], 'source-leave');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        fixture.c.dispose();
        app.dispose();
      },
    );

    testWidgets(
      'today modes and next course use ${onlyLeave ? 'empty state' : 'remaining courses'} after leave',
      (tester) async {
        final fixture = attendanceFixture(
          attendanceRows(onlyLeave: onlyLeave),
          tomorrow: [
            attendanceCourse(
              'tomorrow-leave',
              '次日请假原课',
              status: 'leave',
              date: '2026-09-22',
            ),
          ],
        );
        await tester.runAsync(() => fixture.c.bind('s'));
        fixture.c.items = [];
        final app = AppController(
          fixture.api,
          MemoryStore(),
          clearSchoolSession: () async {},
        )..semester = semester();
        var now = DateTime.utc(2026, 9, 21, 7);
        await mount(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              child: TodayDashboard(
                app: app,
                items: fixture.c,
                onCalendar: () {},
                now: () => now,
              ),
            ),
          ),
        );
        await settleAttendanceIo(tester);
        final dashboard = tester.state<TodayDashboardState>(
          find.byType(TodayDashboard),
        );
        for (final mode in [TodayViewMode.overview, TodayViewMode.schedule]) {
          await tester.runAsync(
            () => dashboard.preferences.change(todayView: mode),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('请假原课'), findsNothing);
          if (onlyLeave) {
            expect(find.byType(NextScheduleCard), findsNothing);
            expect(find.text('今天没有安排'), findsOneWidget);
            expect(find.textContaining('今天已结束'), findsNothing);
          } else {
            expect(find.text('今天没有安排'), findsNothing);
            expect(
              tester
                  .widget<NextScheduleCard>(find.byType(NextScheduleCard))
                  .row['id'],
              'planned',
            );
            expect(find.text('正常课程'), findsOneWidget);
            expect(find.textContaining('免听课程'), findsOneWidget);
          }
        }
        // Evening next-day preview must not revive an excused occurrence.
        now = DateTime.utc(2026, 9, 21, 18);
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpAndSettle();
        expect(find.textContaining('次日请假原课'), findsNothing);
        expect(find.byType(NextScheduleCard), findsNothing);
        expect(dashboard.brief.data?['entries'], hasLength(onlyLeave ? 1 : 4));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        fixture.c.dispose();
        app.dispose();
      },
    );
  }
}
