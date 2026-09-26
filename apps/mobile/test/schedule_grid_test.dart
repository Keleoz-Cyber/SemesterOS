import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/calendar/schedule_grid.dart';
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

Map<String, dynamic> event(String id, String name, String start, String end) =>
    {
      'id': id,
      'resource_id': id,
      'resource_type': 'event',
      'title': name,
      'location': 'A101',
      'start_at': start,
      'end_at': end,
      'time_precision': 'exact',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  testWidgets(
    'mature calendar lays out overlaps separately and opens original event',
    (tester) async {
      Map<String, dynamic>? opened;
      final list = [
        event(
          'a',
          '程序设计课程',
          '2026-09-21T08:00:00+08:00',
          '2026-09-21T10:00:00+08:00',
        ),
        event(
          'b',
          '课程项目组会',
          '2026-09-21T08:30:00+08:00',
          '2026-09-21T09:30:00+08:00',
        ),
        event(
          'c',
          '材料提交说明会',
          '2026-09-21T09:00:00+08:00',
          '2026-09-21T10:00:00+08:00',
        ),
      ];
      await mount(
        tester,
        Scaffold(
          body: SizedBox(
            height: 600,
            child: ScheduleGrid(
              firstDay: DateTime(2026, 9, 21),
              entries: list,
              onOpen: (e) => opened = e,
            ),
          ),
        ),
        width: 800,
      );
      await tester.pumpAndSettle();
      expect(find.text('程序设计课程'), findsOneWidget);
      final a = tester.getRect(
        find.byKey(const ValueKey('schedule-tile-a/2026-09-21')),
      );
      final b = tester.getRect(
        find.byKey(const ValueKey('schedule-tile-b/2026-09-21')),
      );
      expect(a.overlaps(b), isFalse);
      await tester.tap(find.text('课程项目组会'));
      await tester.pump();
      expect(opened?['resource_id'], 'b');
      expect(opened?['start_at'], '2026-09-21T08:30:00+08:00');
      await capture(tester, 'calendar-component-overlap');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('cross-day and Sunday events survive projection and large text', (
    tester,
  ) async {
    final list = [
      event(
        'night',
        '跨日活动',
        '2026-09-26T23:00:00+08:00',
        '2026-09-27T01:00:00+08:00',
      ),
      event(
        'sun',
        '周日中文长标题课程安排',
        '2026-09-27T09:00:00+08:00',
        '2026-09-27T10:00:00+08:00',
      ),
    ];
    await mount(
      tester,
      Scaffold(
        body: SizedBox(
          height: 600,
          child: ScheduleGrid(
            firstDay: DateTime(2026, 9, 21),
            entries: list,
            onOpen: (_) {},
          ),
        ),
      ),
      width: 800,
      textScale: 1.5,
    );
    await tester.pumpAndSettle();
    expect(find.text('跨日活动'), findsNWidgets(2));
    expect(find.text('周日中文长标题课程安排'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
