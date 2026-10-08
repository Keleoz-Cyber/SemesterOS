import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/calendar/calendar_week_pager.dart';
import 'package:semester_os/features/calendar/schedule_grid.dart';
import 'package:semester_os/ui/campus_theme.dart';

void main() {
  testWidgets('weekly grid highlights the real date, never next week weekday', (
    tester,
  ) async {
    final first = ValueNotifier(DateTime.utc(2026, 10, 5));
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(),
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: first,
            builder: (_, day, _) => ScheduleGrid(
              firstDay: day,
              selectedDay: day.add(const Duration(days: 3)),
              now: () => DateTime.utc(2026, 10, 8, 10, 0),
              entries: const [],
              refreshClock: false,
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    );
    Material header(String date) => tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(ValueKey('calendar-day-$date')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(header('2026-10-08').color, CampusColors.blueSoft);
    expect(find.text('今天'), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-current-time')), findsOneWidget);
    first.value = DateTime.utc(2026, 10, 12);
    await tester.pump();
    expect(header('2026-10-15').color, Colors.transparent);
    expect(find.text('今天'), findsNothing);
    expect(find.byKey(const ValueKey('schedule-current-time')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    first.dispose();
  });

  testWidgets('week drag moves adjacent pages together with no opacity layer', (
    tester,
  ) async {
    var week = 2;
    late StateSetter update;
    final changes = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              body: CalendarWeekPager(
                week: week,
                totalWeeks: 8,
                onChanged: (value) {
                  changes.add(value);
                  setState(() => week = value);
                },
                pageBuilder: (_, value) => ColoredBox(
                  key: ValueKey('week-$value'),
                  color: Colors.white,
                  child: Center(child: Text('第$value周')),
                ),
              ),
            );
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(700, 300));
    await gesture.moveBy(const Offset(-320, 0));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('week-2'))).dx,
      lessThan(0),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('week-3'))).dx,
      greaterThan(0),
    );
    expect(
      find.descendant(
        of: find.byType(CalendarWeekPager),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    await gesture.moveBy(const Offset(-200, 0));
    await tester.pump();
    expect(
      changes,
      isEmpty,
      reason: 'dragging does not request intermediate weeks',
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(week, 3);
    expect(changes, [3]);
    changes.clear();
    update(() => week = 7);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('week-7')).hitTestable(), findsOneWidget);
    expect(
      changes,
      isEmpty,
      reason: 'programmatic jump must not select intermediate weeks',
    );
    update(() => week = 6);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    update(() => week = 7);
    await tester.pump();
    await tester.pumpAndSettle();
    final pager = tester.widget<PageView>(
      find.byKey(const ValueKey('calendar-week-pages')),
    );
    expect(pager.controller!.page, 6);
    expect(find.byKey(const ValueKey('week-7')).hitTestable(), findsOneWidget);
    expect(
      changes,
      isEmpty,
      reason: 'a fast reversal keeps the latest requested week',
    );
    // The arrow starts moving off week 7 without crossing a page midpoint.
    // The user cancels it by dragging back to week 7. PageView need not emit
    // onPageChanged here, but the settled page still has to update the parent.
    update(() => week = 6);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final reverseDrag = await tester.startGesture(const Offset(700, 300));
    await reverseDrag.moveBy(const Offset(-240, 0));
    await reverseDrag.up();
    await tester.pumpAndSettle();
    expect(week, 7);
    expect(pager.controller!.page, 6);
    expect(changes, [7]);
  });

  testWidgets(
    'reducing motion during a week transition goes straight to final week',
    (tester) async {
      var week = 1, reduced = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: Scaffold(
                  body: CalendarWeekPager(
                    week: week,
                    totalWeeks: 8,
                    onChanged: (value) => setState(() => week = value),
                    pageBuilder: (_, value) => Center(child: Text('第$value周')),
                  ),
                ),
              );
            },
          ),
        ),
      );
      update(() => week = 6);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      update(() => reduced = true);
      await tester.pump();
      await tester.pump();
      final pager = tester.widget<PageView>(
        find.byKey(const ValueKey('calendar-week-pages')),
      );
      expect(pager.controller!.page, 5);
      expect(find.text('第6周').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
