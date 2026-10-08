import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/items/item_actions.dart';
import 'package:semester_os/ui/campus_theme.dart';

void main() {
  for (final accessibleNavigation in [false, true]) {
    testWidgets('completion undo feedback expires across rebuilds '
        '(accessibleNavigation=$accessibleNavigation)', (tester) async {
      late StateSetter rebuild;
      var undos = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: campusTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(accessibleNavigation: accessibleNavigation),
            child: child!,
          ),
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showItemCompletionFeedback(
                      context,
                      onUndo: () => undos++,
                    ),
                    child: const Text('标记完成'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('标记完成'));
      await tester.pumpAndSettle();
      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('撤销'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      rebuild(() {});
      await tester.pump();
      expect(find.text('已完成'), findsOneWidget);
      if (accessibleNavigation) {
        await tester.pump(const Duration(seconds: 4));
        expect(find.text('已完成'), findsOneWidget);
      }
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('已完成'), findsNothing);
      expect(find.text('撤销'), findsNothing);
      expect(undos, 0);
      rebuild(() {});
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('completion feedback keeps undo until it is dismissed', (
    tester,
  ) async {
    var undos = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () =>
                    showItemCompletionFeedback(context, onUndo: () => undos++),
                child: const Text('标记完成'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('标记完成'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(undos, 1);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
