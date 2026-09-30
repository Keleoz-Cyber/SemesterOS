import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/items/items_view.dart';
import 'planning_flow_test.dart' show PlanningFixture, bind;
import 'ui_polish_test.dart' show capture, loadPreviewFonts, mount;

void main() {
  setUpAll(loadPreviewFonts);

  testWidgets('seven tasks remain scannable without expanded risk cards', (
    tester,
  ) async {
    final fixture = PlanningFixture();
    await bind(tester, fixture);
    fixture.c.items = [
      for (var index = 0; index < 7; index++)
        {
          ...fixture.item,
          'id': index == 0 ? 'a' : 'task-$index',
          'title': index == 0 ? 'Java实验报告' : '第$index项待办任务',
        },
    ];
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ItemsView(
            controller: fixture.c,
            onCreate: () {},
            onOpen: (_) {},
          ),
        ),
      ),
      width: 390,
      height: 844,
    );
    final first = find.byKey(const ValueKey('plan-task-a'));
    final second = find.byKey(const ValueKey('plan-task-task-1'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    await tester.ensureVisible(first);
    await capture(tester, 'task-list-seven-compact');
    expect(tester.getSize(first).height, lessThan(180));
    expect(tester.getSize(second).height, lessThan(130));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    fixture.c.dispose();
  });
}
