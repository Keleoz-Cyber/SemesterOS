import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/features/home/today_dashboard.dart';
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'calendar_flow_test.dart' show semester;
import 'controller_test.dart' show MemoryStore;
import 'api_session_test.dart' show ControlledTransport, body;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  testWidgets('today puts three courses above fold and offers module editing', (
    tester,
  ) async {
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
              now: () => DateTime.utc(2026, 9, 21, 7),
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
