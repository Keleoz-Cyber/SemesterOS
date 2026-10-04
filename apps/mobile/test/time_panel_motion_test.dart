import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/ui/app_navigation.dart';
import 'package:semester_os/ui/campus_theme.dart';
import 'package:semester_os/ui/motion.dart';

void main() {
  testWidgets('tab motion keeps the page state and honors reduced motion', (
    tester,
  ) async {
    var active = true, reduce = false;
    var direction = AxisDirection.right;
    late StateSetter update;
    final draft = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
              child: TabEntrance(
                active: active,
                animateOnMount: false,
                direction: direction,
                child: Material(child: TextField(controller: draft)),
              ),
            );
          },
        ),
      ),
    );
    final motion = find.descendant(
      of: find.byType(TabEntrance),
      matching: find.byType(SlideTransition),
    );
    expect(tester.widget<SlideTransition>(motion).position.value, Offset.zero);
    await tester.enterText(find.byType(TextField), '未发送的通知');
    final editor = tester.state(find.byType(EditableText));
    update(() => active = false);
    await tester.pump();
    update(() => active = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tester.widget<SlideTransition>(motion).position.value.dx,
      greaterThan(0),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SlideTransition>(motion).position.value.dx,
      closeTo(0, .01),
    );
    expect(tester.state(find.byType(EditableText)), same(editor));
    expect(draft.text, '未发送的通知');

    update(() => active = false);
    await tester.pump();
    update(() {
      active = true;
      direction = AxisDirection.left;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tester.widget<SlideTransition>(motion).position.value.dx,
      lessThan(0),
    );
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(editor));
    expect(draft.text, '未发送的通知');
    FocusManager.instance.primaryFocus?.unfocus();

    update(() {
      active = false;
      reduce = true;
    });
    await tester.pump();
    update(() => active = true);
    await tester.pump();
    expect(tester.widget<SlideTransition>(motion).position.value, Offset.zero);
    expect(
      AppMotion.page(tester.element(find.byType(TabEntrance))),
      Duration.zero,
    );
    final fade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(TabEntrance),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 1);
    expect(fade.opacity.status, AnimationStatus.completed);
    // EditableText can briefly animate its caret after losing focus. Settle
    // that independent feedback before checking for any continuing tickers.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    draft.dispose();
  });

  testWidgets('compact navigation keeps Android targets at large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: Scaffold(
              bottomNavigationBar: AppNavigation(
                selected: 0,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}
