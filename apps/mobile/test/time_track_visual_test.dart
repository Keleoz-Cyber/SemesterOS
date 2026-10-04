import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/features/home/today_dashboard.dart';
import 'package:semester_os/features/calendar/time_track.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'calendar_flow_test.dart' show semester;
import 'controller_test.dart' show MemoryStore;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

final rows = <Map<String, dynamic>>[
  {
    'id': 'c1',
    'resource_id': 'c1',
    'resource_type': 'course',
    'title': '摄影测量学',
    'location': '莲7号教学楼315',
    'start_at': '2026-09-30T08:30:00+08:00',
    'end_at': '2026-09-30T10:05:00+08:00',
  },
  {
    'id': 'c2',
    'resource_id': 'c2',
    'resource_type': 'course',
    'title': '习近平新时代中国特色社会主义思想概论',
    'location': '莲4号教学楼312',
    'start_at': '2026-09-30T14:30:00+08:00',
    'end_at': '2026-09-30T16:05:00+08:00',
  },
];

void main() {
  setUpAll(loadPreviewFonts);
  for (final size in [
    (375.0, 812.0, 1.0),
    (320.0, 740.0, 1.6),
    (740.0, 390.0, 1.0),
  ]) {
    testWidgets('ended courses stay accessible without a clock at $size', (
      tester,
    ) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/day-brief?')) {
          return body({
            'semester_id': 's',
            'revision': 1,
            'date': '2026-09-30',
            'entries': rows,
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
            padding: const EdgeInsets.all(16),
            children: [
              TodayDashboard(
                app: app,
                items: f.c,
                onCalendar: () {},
                now: () => DateTime.utc(2026, 9, 30, 21, 37),
              ),
            ],
          ),
        ),
        width: size.$1,
        height: size.$2,
        textScale: size.$3,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      final ended = find.text('今天已结束 · 2项');
      await tester.ensureVisible(ended);
      await tester.pumpAndSettle();
      expect(ended.hitTestable(), findsOneWidget);
      for (final row in rows) {
        expect(find.text(row['title']), findsNothing);
      }
      expect(find.text('现在 21:37'), findsNothing);
      await tester.tap(ended);
      await tester.pumpAndSettle();
      for (final row in rows) {
        await tester.ensureVisible(find.text(row['title']));
        expect(find.text(row['title']).hitTestable(), findsOneWidget);
      }
      expect(find.text('现在 21:37'), findsNothing);
      expect(
        find.byKey(const ValueKey('time-track-current-gap')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('time-track-event-progress')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'time-track-ended-${size.$1}-${size.$3}');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
      app.dispose();
    });
  }
  testWidgets(
    'current gap is between the correct courses, rather than above them',
    (tester) async {
      await mount(
        tester,
        Scaffold(
          body: TimeTrack(
            rows: rows,
            date: DateTime.utc(2026, 9, 30),
            now: DateTime.utc(2026, 9, 30, 12),
            rowBuilder: (row, last, clock) =>
                SizedBox(height: 90, child: Text(row['title'])),
          ),
        ),
      );
      final clock = tester.getRect(find.text('现在 12:00'));
      expect(
        clock.top,
        greaterThan(tester.getRect(find.text(rows.first['title'])).bottom),
      );
      expect(
        clock.bottom,
        lessThan(tester.getRect(find.text(rows.last['title'])).top),
      );
      await capture(tester, 'time-track-between');
    },
  );
  testWidgets(
    'unknown end remains a point and an empty list has no floating clock',
    (tester) async {
      await mount(
        tester,
        Scaffold(
          body: TimeTrack(
            rows: [
              {...rows.first}..remove('end_at'),
            ],
            date: DateTime.utc(2026, 9, 30),
            now: DateTime.utc(2026, 9, 30, 9),
            rowBuilder: (row, last, clock) => Text(row['title']),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('time-track-event-progress')),
        findsNothing,
      );
      await mount(
        tester,
        Scaffold(
          body: TimeTrack(
            rows: const [],
            date: DateTime.utc(2026, 9, 30),
            now: DateTime.utc(2026, 9, 30, 9),
            rowBuilder: (row, last, clock) => Text(row['title']),
          ),
        ),
      );
      expect(find.text('现在 09:00'), findsNothing);
    },
  );
}
