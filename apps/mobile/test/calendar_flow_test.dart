import 'package:semester_os/ui/app_controls.dart';
import 'package:forui/forui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/features/calendar/calendar_panel.dart';
import 'package:semester_os/features/calendar/event_form.dart';
import 'package:semester_os/features/calendar/event_overview.dart';
import 'package:semester_os/features/timetable/shell_page.dart';
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'api_session_test.dart' show ControlledTransport, body;
import 'controller_test.dart' show MemoryStore;
import 'planning_flow_test.dart' show ioTap;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

Map<String, dynamic> semester() => {
  'id': 's',
  'name': '测试学期',
  'first_monday': '2026-08-31',
  'total_weeks': 20,
  'revision': 1,
  'periods': [
    {'number': 1, 'start': '08:00', 'end': '08:50'},
    {'number': 10, 'start': '20:00', 'end': '20:50'},
  ],
};

class ClockedCalendarApp extends AppController {
  int currentWeek = 4;
  ClockedCalendarApp(super.api, super.cache)
    : super(clearSchoolSession: () async {});
  @override
  int weekNow(Map<String, dynamic> semester) => currentWeek;
}

void main() {
  testWidgets(
    'start-only event shows its clock and keeps classification secondary',
    (tester) async {
      await mount(
        tester,
        Scaffold(
          body: ListView(
            children: [
              EventOverview(
                category: '校园事务',
                row: {
                  'title': '座谈会（同学）',
                  'certainty': 'formal',
                  'reserve_time': true,
                  'location': '6108',
                  'time': {
                    'precision': 'exact_start',
                    'at': '2026-09-29T14:00:00+08:00',
                  },
                  'tags': [
                    {'name': '座谈会'},
                    {'name': '线下'},
                  ],
                },
              ),
            ],
          ),
        ),
      );
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('9月29日 · 周二'), findsOneWidget);
      expect(find.text('6108'), findsOneWidget);
      expect(find.text('开始'), findsNothing);
      expect(find.text('结束'), findsNothing);
      expect(find.text('校园事务 · 线下'), findsOneWidget);
      expect(find.text('座谈会'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  testWidgets(
    'returning to calendar reloads changed personal plans even if course revision is unchanged',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var revision = 1, reads = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/calendar?')) {
          reads++;
          return body({
            'semester_id': 's',
            'revision': revision,
            'entries': [],
            'undated': [],
          });
        }
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      final app =
          AppController(f.api, MemoryStore(), clearSchoolSession: () async {})
            ..semester = semester()
            ..week = 4;
      final enabled = ValueNotifier(true);
      await mount(
        tester,
        Scaffold(
          body: ValueListenableBuilder(
            valueListenable: enabled,
            builder: (_, active, _) => TickerMode(
              enabled: active,
              child: SingleChildScrollView(
                child: CalendarPanel(app: app, items: f.c),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(reads, 1);
      enabled.value = false;
      await tester.pump();
      f.c.itemsRevision = ++revision;
      f.c.changed();
      await tester.pump();
      expect(reads, 1);
      enabled.value = true;
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(app.semester!['revision'], 1);
      await tester.pumpWidget(const SizedBox());
      enabled.dispose();
      f.c.dispose();
      app.dispose();
    },
  );
  testWidgets(
    'tab return preserves calendar filter without refetching the same week',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var reads = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/calendar?')) {
          reads++;
          return body({
            'semester_id': 's',
            'revision': 1,
            'entries': [],
            'undated': [],
          });
        }
        return old.respond(r);
      });
      final app =
          AppController(f.api, MemoryStore(), clearSchoolSession: () async {})
            ..semester = semester()
            ..week = 4
            ..ready = true;
      await tester.runAsync(() => f.c.bind('s'));
      await mount(tester, ShellPage(controller: app, items: f.c));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      await ioTap(tester, find.text('日程').last);
      await ioTap(tester, find.byTooltip('筛选日程'));
      await capture(tester, 'calendar-filter-sheet');
      await ioTap(tester, find.text('活动').last);
      final before = reads;
      await ioTap(tester, find.text('今日').last);
      await ioTap(tester, find.text('日程').last);
      expect(find.text('仅看活动'), findsOneWidget);
      expect(reads, before);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
      app.dispose();
    },
  );
  testWidgets(
    'calendar includes fixed events with courses and separates date-only deadlines',
    (tester) async {
      final fixture = ScheduleFixture();
      final existing = fixture.api.dio.httpClientAdapter as ControlledTransport;
      fixture.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/calendar?')) {
          return body({
            'semester_id': 's',
            'revision': 1,
            'entries': [
              {
                'id': 'c',
                'resource_id': 'c',
                'resource_type': 'course',
                'title': '概率论',
                'start_at': '2026-09-23T06:00:00Z',
                'end_at': '2026-09-23T07:50:00Z',
                'location': 'A203',
                'time_precision': 'exact',
              },
              {
                'id': 'event:e',
                'resource_id': 'e',
                'resource_type': 'event',
                'title': '课题组组会',
                'start_at': '2026-09-23T09:00:00Z',
                'end_at': '2026-09-23T10:00:00Z',
                'location': '6412',
                'time_precision': 'exact',
              },
              {
                'id': 'deadline:i',
                'resource_id': 'i',
                'resource_type': 'deadline',
                'title': '提交材料',
                'date': '2026-09-25',
                'location': '',
                'time_precision': 'date',
              },
            ],
            'undated': [],
          });
        }
        return existing.respond(r);
      });
      final app =
          AppController(
              fixture.api,
              MemoryStore(),
              clearSchoolSession: () async {},
            )
            ..semester = semester()
            ..week = 4;
      await tester.runAsync(() => fixture.c.bind('s'));
      await mount(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: CalendarPanel(app: app, items: fixture.c),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('日程列表'));
      await tester.pumpAndSettle();
      expect(find.text('课题组组会'), findsOneWidget);
      expect(find.text('提交材料'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calendar-day-2026-09-23')));
      await tester.pumpAndSettle();
      expect(find.text('概率论').hitTestable(), findsOneWidget);
      expect(find.textContaining('17:00').hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calendar-day-2026-09-25')));
      await tester.pumpAndSettle();
      expect(find.text('9月25日 · 周五').hitTestable(), findsOneWidget);
      expect(find.text('概率论').hitTestable(), findsNothing);
      await capture(tester, 'calendar-events-list');
      await tester.pumpWidget(const SizedBox());
      fixture.c.dispose();
      app.dispose();
    },
  );

  testWidgets(
    'event form preserves unknown time and sends one confirmed payload',
    (tester) async {
      final fixture = ScheduleFixture();
      final existing = fixture.api.dio.httpClientAdapter as ControlledTransport;
      Map<String, dynamic>? submitted;
      fixture.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/semesters')) return body([semester()]);
        if (r.path.endsWith('/events') && r.method == 'POST') {
          submitted = Map<String, dynamic>.from(r.data);
          fixture.revision++;
          return body({
            'semester_id': 's',
            'revision': fixture.revision,
            'event': {'id': 'e'},
            'affected_plan_ids': [],
          }, 201);
        }
        return existing.respond(r);
      });
      await tester.runAsync(() => fixture.c.bind('s'));
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EventFormPage(
                    controller: fixture.c,
                    semester: semester(),
                  ),
                ),
              ),
              child: const Text('新建'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('新建'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(AppFormField).first, '课题组组会');
      await tester.ensureVisible(find.text('时间方式'));
      await tester.tap(find.text('时间方式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('暂不填写时间'));
      await tester.pumpAndSettle();
      await capture(tester, 'event-form');
      await tester.ensureVisible(find.widgetWithText(FButton, '添加日程'));
      await ioTap(tester, find.widgetWithText(FButton, '添加日程'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(submitted?['title'], '课题组组会');
      expect(submitted?['time'], {
        'precision': 'unknown',
        'meaning': 'unspecified',
        'expression': '',
      });
      expect(submitted?['expected_revision'], 1);
      expect(
        find.text('新建'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      await tester.pumpWidget(const SizedBox());
      fixture.c.dispose();
    },
  );
  testWidgets('today refresh follows the current week after rollover', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final previous = f.api.dio.httpClientAdapter as ControlledTransport;
    final requests = <String>[];
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.contains('/calendar?')) {
        requests.add(r.path);
        return body({
          'semester_id': 's',
          'revision': 1,
          'entries': [],
          'undated': [],
        });
      }
      return previous.respond(r);
    });
    final app = ClockedCalendarApp(f.api, MemoryStore())..semester = semester();
    final key = GlobalKey<CalendarPanelState>();
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: CalendarPanel(key: key, app: app, items: f.c, todayOnly: true),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(requests.last, contains('from_date=2026-09-21'));
    app.currentWeek = 5;
    await tester.runAsync(() => key.currentState!.reload());
    await tester.pumpAndSettle();
    expect(requests.last, contains('from_date=2026-09-28'));
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
    app.dispose();
  });
  testWidgets('422 keeps event fields editable and allows a corrected save', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final previous = f.api.dio.httpClientAdapter as ControlledTransport;
    final sent = <Map<String, dynamic>>[];
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/semesters')) return body([semester()]);
      if (r.path.endsWith('/events') && r.method == 'POST') {
        sent.add(Map<String, dynamic>.from(r.data));
        if (sent.length == 1) return body({'message': '请核对标签格式'}, 422);
        f.revision++;
        return body({
          'semester_id': 's',
          'revision': f.revision,
          'event': {'id': 'e'},
          'affected_plan_ids': [],
        }, 201);
      }
      return previous.respond(r);
    });
    await tester.runAsync(() => f.c.bind('s'));
    await mount(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    EventFormPage(controller: f.c, semester: semester()),
              ),
            ),
            child: const Text('新建'),
          ),
        ),
      ),
    );
    await ioTap(tester, find.text('新建'));
    await tester.enterText(find.byType(AppFormField).first, '原名称');
    await tester.ensureVisible(find.widgetWithText(FButton, '添加日程'));
    await ioTap(tester, find.widgetWithText(FButton, '添加日程'));
    expect(find.text('请核对标签格式'), findsOneWidget);
    expect(find.text('重试保存'), findsNothing);
    await tester.ensureVisible(find.byType(AppFormField).first);
    await tester.enterText(find.byType(AppFormField).first, '更正名称');
    await tester.ensureVisible(find.widgetWithText(FButton, '添加日程'));
    await ioTap(tester, find.widgetWithText(FButton, '添加日程'));
    expect(sent.last['title'], '更正名称');
    expect(find.text('新建'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
}
