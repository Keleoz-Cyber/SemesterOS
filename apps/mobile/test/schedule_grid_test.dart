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
    'an optional reference stays clickable without an occupied block',
    (tester) async {
      Map<String, dynamic>? opened;
      final row = {
        ...event(
          'reference',
          '可选讲座',
          '2026-09-21T09:00:00+08:00',
          '2026-09-21T10:00:00+08:00',
        ),
        'reserve_time': false,
        'details': {'participation_status': 'optional'},
      };
      await mount(
        tester,
        Scaffold(
          body: SizedBox(
            height: 500,
            child: ScheduleGrid(
              firstDay: DateTime.utc(2026, 9, 21),
              entries: [row],
              onOpen: (r) => opened = r,
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('schedule-start-reference/2026-09-21')),
        findsOneWidget,
      );
      expect(find.text('可选'), findsOneWidget);
      await tester.tap(find.text('可选'));
      await tester.pump();
      expect(opened?['reserve_time'], isFalse);
      expect(opened?['end_at'], '2026-09-21T10:00:00+08:00');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'current time follows minute position and stops while hidden or backgrounded',
    (tester) async {
      var now = DateTime.utc(2026, 9, 21, 9, 30), reads = 0;
      final visible = ValueNotifier(true);
      await mount(
        tester,
        Scaffold(
          body: ValueListenableBuilder(
            valueListenable: visible,
            builder: (_, show, _) => SizedBox(
              height: 500,
              child: ScheduleGrid(
                firstDay: DateTime.utc(2026, 9, 21),
                entries: const [],
                onOpen: (_) {},
                visible: show,
                now: () {
                  reads++;
                  return now;
                },
              ),
            ),
          ),
        ),
      );
      double top() {
        final marker = tester.widget<Positioned>(
          find.byKey(const ValueKey('schedule-current-time')),
        );
        return marker.top! + marker.height! / 2;
      }

      expect(top(), closeTo(85.5, .01));
      now = DateTime.utc(2026, 9, 21, 9, 31);
      await tester.pump(const Duration(seconds: 58));
      expect(top(), closeTo(85.5, .01));
      await tester.pump(const Duration(seconds: 2));
      expect(top(), closeTo(86.45, .01));
      visible.value = false;
      await tester.pump();
      final hiddenReads = reads;
      await tester.pump(const Duration(minutes: 2));
      expect(reads, hiddenReads);
      visible.value = true;
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final pausedReads = reads;
      await tester.pump(const Duration(minutes: 2));
      expect(reads, pausedReads);
      now = DateTime.utc(2026, 9, 28, 9, 31);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byKey(const ValueKey('schedule-current-time')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      visible.dispose();
    },
  );
  for (final screen in [
    ('phone', 375.0, 844.0, 1.0),
    ('large', 320.0, 844.0, 1.6),
    ('landscape', 740.0, 390.0, 1.0),
  ]) {
    testWidgets(
      'seven-column grid supports ${screen.$1} with short and point markers',
      (tester) async {
        final rows = [
          {
            ...event(
              'mon',
              '高等数学',
              '2026-09-21T08:00:00+08:00',
              '2026-09-21T10:00:00+08:00',
            ),
            'resource_type': 'course',
          },
          {
            ...event(
              'point',
              '班会',
              '2026-09-22T09:00:00+08:00',
              '2026-09-22T10:00:00+08:00',
            ),
            'end_at': null,
          },
          event(
            'short',
            '取材料',
            '2026-09-23T08:15:00+08:00',
            '2026-09-23T08:25:00+08:00',
          ),
          {
            ...event(
              'thu',
              '大学英语',
              '2026-09-24T09:00:00+08:00',
              '2026-09-24T10:00:00+08:00',
            ),
            'resource_type': 'course',
          },
          event(
            'sun',
            '项目组会',
            '2026-09-27T09:00:00+08:00',
            '2026-09-27T10:00:00+08:00',
          ),
        ];
        await mount(
          tester,
          Scaffold(
            body: ScheduleGrid(
              firstDay: DateTime.utc(2026, 9, 21),
              entries: rows,
              onOpen: (_) {},
              now: () => DateTime.utc(2026, 9, 21, 9, 30),
            ),
          ),
          width: screen.$2,
          height: screen.$3,
          textScale: screen.$4,
        );
        expect(find.text('周日'), findsOneWidget);
        expect(find.text('班会'), findsOneWidget);
        expect(find.text('开始'), findsNothing);
        expect(
          find.byKey(const ValueKey('schedule-start-point/2026-09-22')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('schedule-tile-short/2026-09-23')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await capture(tester, 'calendar-grid-${screen.$1}');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'a start-only event is a clickable point without invented end time',
    (tester) async {
      Map<String, dynamic>? opened;
      final row = {
        ...event(
          'point',
          '通知会议',
          '2026-09-21T10:10:00+08:00',
          '2026-09-21T11:10:00+08:00',
        ),
        'end_at': null,
      };
      await mount(
        tester,
        Scaffold(
          body: SizedBox(
            height: 550,
            child: ScheduleGrid(
              firstDay: DateTime.utc(2026, 9, 21),
              entries: [row],
              onOpen: (value) => opened = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('schedule-start-point/2026-09-21')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('schedule-start-point/2026-09-21')),
      );
      await tester.pump();
      expect(opened?['resource_id'], 'point');
      expect(opened?['end_at'], isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'hidden calendar suspends its minute clock and restores its scroll',
    (tester) async {
      final visible = ValueNotifier(true);
      await mount(
        tester,
        Scaffold(
          body: ValueListenableBuilder(
            valueListenable: visible,
            builder: (_, show, _) => SizedBox(
              height: 400,
              child: ScheduleGrid(
                firstDay: DateTime.utc(2026, 9, 21),
                entries: const [],
                onOpen: (_) {},
                visible: show,
              ),
            ),
          ),
        ),
      );
      final view = find.byType(ScheduleGrid);
      Finder vertical() => find
          .descendant(
            of: view,
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      tester.state<ScrollableState>(vertical()).position.jumpTo(170);
      await tester.pump();
      visible.value = false;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-grid-scroll')), findsNothing);
      await tester.pump(const Duration(minutes: 2));
      visible.value = true;
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(vertical()).position.pixels,
        closeTo(170, 1),
      );
      await tester.pumpWidget(const SizedBox());
      visible.dispose();
    },
  );
  testWidgets(
    'phone week fits viewport and overlapping entries open day context',
    (tester) async {
      DateTime? opened;
      final list = [
        event(
          'a',
          '课程甲',
          '2026-09-21T08:00:00+08:00',
          '2026-09-21T10:00:00+08:00',
        ),
        event(
          'b',
          '课程乙',
          '2026-09-21T08:30:00+08:00',
          '2026-09-21T09:30:00+08:00',
        ),
      ];
      await mount(
        tester,
        Scaffold(
          body: SizedBox(
            height: 550,
            child: ScheduleGrid(
              firstDay: DateTime(2026, 9, 21),
              entries: list,
              onOpen: (_) {},
              onDay: (d) => opened = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('周日')).right, lessThanOrEqualTo(390));
      expect(find.text('2项重叠'), findsOneWidget);
      await tester.tap(find.text('2项重叠'));
      await tester.pumpAndSettle();
      expect(find.text('2项时间重叠'), findsOneWidget);
      expect(find.text('课程甲'), findsOneWidget);
      expect(find.text('课程乙'), findsOneWidget);
      await tester.tap(find.text('查看这一天'));
      await tester.pumpAndSettle();
      expect(opened?.day, 21);
      await tester.pumpWidget(const SizedBox());
    },
  );
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
