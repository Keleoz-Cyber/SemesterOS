import 'dart:ui' show SemanticsAction, Tristate;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/ui/v2/motion/spring_segmented.dart';
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
      expect(find.byType(SpringSegmented<String>), findsOneWidget);
      expect(
        tester
            .widget<SpringSegmented<String>>(
              find.byType(SpringSegmented<String>),
            )
            .selected,
        'week',
      );
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      final tabs = tester.widget<SpringSegmented<String>>(
        find.byType(SpringSegmented<String>),
      );
      expect(tabs.segments, hasLength(2));
      for (final target in tabs.segments) {
        // Measure the whole spring control's hit cell, not its text glyphs.
        final hitArea = find.ancestor(
          of: find.text(target.$2),
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
              child: StatefulBuilder(
                builder: (context, update) => SizedBox(
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
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final tabs = tester.widget<SpringSegmented<String>>(
        find.byType(SpringSegmented<String>),
      );
      expect(tabs.segments, hasLength(4));
      await tester.ensureVisible(find.text('自选日期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自选日期'));
      await tester.pumpAndSettle();
      expect(selected, 'custom');
      expect(
        tester
            .widget<SpringSegmented<String>>(
              find.byType(SpringSegmented<String>),
            )
            .selected,
        'custom',
      );
      // Reduced motion puts the actual indicator in its final slot immediately.
      expect(
        tester.getCenter(find.byKey(const Key('spring-selection-surface'))).dx,
        closeTo(tester.getCenter(find.text('自选日期')).dx, 1),
      );
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
    expect(
      tester
          .widget<SpringSegmented<bool>>(find.byType(SpringSegmented<bool>))
          .selected,
      false,
    );
  });
}
