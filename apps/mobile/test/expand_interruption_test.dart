import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/ui/motion.dart';

class ExpandHarness extends StatefulWidget {
  const ExpandHarness({super.key, required this.maintainState});
  final bool maintainState;
  @override
  State<ExpandHarness> createState() => ExpandHarnessState();
}

class ExpandHarnessState extends State<ExpandHarness> {
  bool visible = false;
  void show(bool value) => setState(() => visible = value);
  void refresh() => setState(() {});
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: AppExpandRegion(
        visible: visible,
        maintainState: widget.maintainState,
        child: const SizedBox(key: Key('expand-body'), height: 160, width: 200),
      ),
    ),
  );
}

AnimationController expandController(WidgetTester tester) =>
    (tester.widget<SizeTransition>(find.byType(SizeTransition)).sizeFactor
                as dynamic)
            .parent
        as AnimationController;

void main() {
  for (final retained in [false, true]) {
    testWidgets(
      'first-frame expansion reversal cancels old target with retention $retained',
      (tester) async {
        final key = GlobalKey<ExpandHarnessState>();
        await tester.pumpWidget(
          ExpandHarness(key: key, maintainState: retained),
        );
        key.currentState!.show(true);
        await tester.pump();
        final controller = expandController(tester);
        expect(controller.value, 0);
        key.currentState!.show(false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getSize(find.byType(AppExpandRegion)).height, 0);
        expect(controller.value, 0);
        expect(controller.isAnimating, isFalse);
        expect(
          find.byKey(const Key('expand-body')),
          retained ? findsOneWidget : findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('same visibility refresh keeps the current expansion timeline', (
    tester,
  ) async {
    final key = GlobalKey<ExpandHarnessState>();
    await tester.pumpWidget(ExpandHarness(key: key, maintainState: true));
    key.currentState!.show(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final controller = expandController(tester);
    final elapsed = controller.lastElapsedDuration!;
    key.currentState!.refresh();
    await tester.pump();
    expect(controller.lastElapsedDuration, greaterThanOrEqualTo(elapsed));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppExpandRegion)).height, 160);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ordinary collapse releases an unretained field after its exit', (
    tester,
  ) async {
    final key = GlobalKey<ExpandHarnessState>();
    await tester.pumpWidget(ExpandHarness(key: key, maintainState: false));
    key.currentState!.show(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expand-body')), findsOneWidget);
    key.currentState!.show(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('expand-body')), findsOneWidget);
    expect(
      tester.getSize(find.byType(AppExpandRegion)).height,
      inExclusiveRange(0, 160),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppExpandRegion)).height, 0);
    expect(find.byKey(const Key('expand-body')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
