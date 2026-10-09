import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/ui/v2/motion/pressable.dart';
import 'package:semester_os/ui/v2/motion/spring_segmented.dart';

class MotionHarness extends StatefulWidget {
  const MotionHarness({super.key, this.pressable = false});
  final bool pressable;
  @override
  State<MotionHarness> createState() => MotionHarnessState();
}

class MotionHarnessState extends State<MotionHarness> {
  bool active = true;
  int selected = 0;
  void refresh() => setState(() {});
  void select(int value) => setState(() => selected = value);
  void hide() => setState(() => active = false);
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: TickerMode(
          enabled: active,
          child: SizedBox(
            width: 300,
            child: widget.pressable
                ? Pressable(
                    onPressed: () {},
                    child: const SizedBox(height: 56, child: Text('动作')),
                  )
                : SpringSegmented<int>(
                    selected: selected,
                    segments: const [(0, '待处理'), (1, '已完成'), (2, '已取消')],
                    onChanged: select,
                  ),
          ),
        ),
      ),
    ),
  );
}

AnimationController controllerFor(WidgetTester tester, Finder owner) {
  final builders = tester
      .widgetList<AnimatedBuilder>(
        find.descendant(of: owner, matching: find.byType(AnimatedBuilder)),
      )
      .map((widget) => widget.animation)
      .whereType<AnimationController>()
      .toList();
  if (builders.isNotEmpty) return builders.first;
  return tester
          .widget<ScaleTransition>(
            find
                .descendant(of: owner, matching: find.byType(ScaleTransition))
                .first,
          )
          .scale
      as AnimationController;
}

void main() {
  testWidgets('parent refresh does not restart an unchanged segment target', (
    tester,
  ) async {
    final key = GlobalKey<MotionHarnessState>();
    await tester.pumpWidget(MotionHarness(key: key));
    key.currentState!.select(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final controller = controllerFor(tester, find.byType(SpringSegmented<int>));
    final elapsed = controller.lastElapsedDuration!;
    expect(elapsed, greaterThan(Duration.zero));
    key.currentState!.refresh();
    await tester.pump();
    expect(controller.lastElapsedDuration, greaterThanOrEqualTo(elapsed));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hidden segment updates settle without starting a muted spring', (
    tester,
  ) async {
    final key = GlobalKey<MotionHarnessState>();
    await tester.pumpWidget(MotionHarness(key: key));
    key.currentState!.hide();
    await tester.pump();
    key.currentState!.select(1);
    await tester.pump();
    final controller = controllerFor(tester, find.byType(SpringSegmented<int>));
    expect(controller.value, 1);
    expect(controller.isAnimating, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('covered pressed control returns to its neutral visible state', (
    tester,
  ) async {
    final key = GlobalKey<MotionHarnessState>();
    await tester.pumpWidget(MotionHarness(key: key, pressable: true));
    final button = find.byType(Pressable);
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 45));
    final controller = controllerFor(tester, button);
    expect(controller.value, lessThan(1));
    key.currentState!.hide();
    await tester.pump();
    expect(controller.value, 1);
    expect(controller.isAnimating, isFalse);
    await gesture.up();
    await tester.pumpWidget(const SizedBox());
  });
}
