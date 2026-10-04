import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
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
}
