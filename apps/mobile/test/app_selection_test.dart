import 'dart:ui' show SemanticsAction, Tristate;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:semester_os/ui/app_selection.dart';
import 'package:semester_os/ui/forui_theme.dart';

void main() {
  testWidgets('single selection moves without checkmarks and exposes state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var value = 'day';
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => ShiriForuiTheme(child: child!),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AppSegmentedControl<String>(
                  value: value,
                  options: const {'day': '日', 'week': '周'},
                  onChanged: (next) => setState(() => value = next),
                );
              },
            ),
          ),
        ),
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(RegExp(r'^周(?:\n|,|，|$)')))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(RegExp(r'^日(?:\n|,|，|$)')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      await tester.tap(find.text('周'));
      await tester.pumpAndSettle();
      expect(value, 'week');
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(RegExp(r'^周(?:\n|,|，|$)')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(RegExp(r'^日(?:\n|,|，|$)')))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      expect(find.byType(FTabs), findsOneWidget);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      final tabs = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabs.tabs, hasLength(2));
      for (final target in tabs.tabs) {
        // Forui supplies each label; TabBar expands the surrounding InkWell
        // into the full interactive cell. Measure that hit area, not the text.
        final hitArea = find.ancestor(
          of: find.byWidget(target),
          matching: find.byType(InkWell),
        );
        expect(hitArea, findsOneWidget);
        expect(tester.widget<InkWell>(hitArea).onTap, isNotNull);
        final size = tester.getSize(hitArea);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }

    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'large text remains reachable in a narrow track with reduced motion',
    (tester) async {
      var selected = 'week';
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => ShiriForuiTheme(child: child!),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2.5),
                disableAnimations: true,
              ),
              child: StatefulBuilder(builder: (context, update) => SizedBox(
                width: 280,
                child: AppSegmentedControl<String>(
                  value: selected,
                  options: const {
                    'week': '本周',
                    'month': '近4周',
                    'term': '本学期',
                    'custom': '自选日期',
                  },
                  onChanged: (value) => update(() => selected = value),
                ),
              )),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final tabs = tester.widget<FTabs>(find.byType(FTabs));
      // Forui's lifted control has no public concrete class, but its motion
      // is passed directly to the underlying TabController.
      expect(tabs.control, isNot(isA<FTabManagedControl>()));
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.animationDuration, Duration.zero);
      await tester.ensureVisible(find.text('自选日期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自选日期'));
      await tester.pumpAndSettle();
      expect(selected, 'custom');
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled options cannot change selection', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => ShiriForuiTheme(child: child!),
        home: Scaffold(
          body: AppSegmentedControl<bool>(
            value: false,
            options: const {false: '日程', true: '周视图'},
            disabledValues: const {true},
            onChanged: (_) => calls++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
  });
}
