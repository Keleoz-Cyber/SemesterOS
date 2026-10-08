import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/ui/v2/widgets/glass_dock.dart';
import 'package:semester_os/ui/app_navigation.dart';
import 'package:semester_os/ui/campus_theme.dart';

void main() {
  testWidgets(
    'glass navigation preserves tab selection and Android touch targets',
    (tester) async {
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
      expect(find.byType(GlassDock), findsOneWidget);
      expect(find.byType(InkResponse), findsNWidgets(4));
      await tester.tap(find.text('日程'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(changes, [1]);
      await tester.tap(find.text('日程'));
      await tester.pumpAndSettle();
      expect(changes, [1]);
      for (final element in find.byType(InkResponse).evaluate()) {
        expect(
          tester.getSize(find.byWidget(element.widget)).height,
          greaterThanOrEqualTo(48),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}
