import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:semester_os/features/timetable/course_widgets.dart';
import 'package:semester_os/ui/app_navigation.dart';
import 'package:semester_os/ui/campus_theme.dart';

void main() {
  testWidgets('main navigation uses Forui items and preserves tab selection', (
    tester,
  ) async {
    var selected = 0;
    final changes = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(),
        home: StatefulBuilder(
          builder: (context, update) => Scaffold(
            bottomNavigationBar: AppNavigation(
              selected: selected,
              onSelected: (value) => update(() {
                selected = value;
                changes.add(value);
              }),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(FBottomNavigationBar), findsOneWidget);
    expect(find.byType(FBottomNavigationBarItem), findsNWidgets(4));
    await tester.tap(find.text('日程'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(changes, [1]);
    await tester.tap(find.text('日程'));
    await tester.pumpAndSettle();
    expect(changes, [1]);
    for (final element in find.byType(FBottomNavigationBarItem).evaluate()) {
      expect(
        tester.getSize(find.byWidget(element.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('course row wraps long names and omits absent location', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: CourseCard(
                  event: {
                    'title': '计算机系统设计与综合实践课程',
                    'start_at': '2026-09-21T01:00:00Z',
                    'end_at': '2026-09-21T02:40:00Z',
                  },
                  now: DateTime.utc(2026, 9, 21),
                  onTap: () => opened++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('地点待补充'), findsNothing);
    expect(find.text('null'), findsNothing);
    await tester.tap(find.text('计算机系统设计与综合实践课程'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });
}
