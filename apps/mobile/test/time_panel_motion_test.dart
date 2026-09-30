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
                direction: 1,
                child: Material(child: TextField(controller: draft)),
              ),
            );
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '未发送的通知');
    final editor = tester.state(find.byType(EditableText));
    update(() => active = false);
    await tester.pump();
    update(() => active = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final motion = find.byKey(const ValueKey('tab-entrance-transform'));
    expect(
      tester.widget<Transform>(motion).transform.storage[12],
      greaterThan(0),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Transform>(motion).transform.storage[12],
      closeTo(0, .01),
    );
    expect(tester.state(find.byType(EditableText)), same(editor));
    expect(draft.text, '未发送的通知');

    update(() {
      active = false;
      reduce = true;
    });
    await tester.pump();
    update(() => active = true);
    await tester.pump();
    expect(tester.widget<Transform>(motion).transform.storage[12], 0);
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
