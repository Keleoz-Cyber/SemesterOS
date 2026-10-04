import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/planning/plan_list.dart';
import 'planning_flow_test.dart' show PlanningFixture, bind;
import 'ui_polish_test.dart' show capture, loadPreviewFonts, mount, previewFont;

void main() {
  setUpAll(loadPreviewFonts);

  testWidgets('three learning blocks fit as a readable mobile timeline', (
    tester,
  ) async {
    final f = PlanningFixture();
    await bind(tester, f);
    final start = DateTime.now().add(const Duration(days: 1));
    f.c.planFeed = {
      'semester_id': 's',
      'revision': f.c.itemsRevision,
      'blocks': [
        for (var index = 0; index < 3; index++)
          {
            'id': 'b$index',
            'item_id': 'a',
            'title': '第${index + 1}段学习任务',
            'start_at': start.add(Duration(hours: index)).toIso8601String(),
            'end_at': start
                .add(Duration(hours: index, minutes: 45))
                .toIso8601String(),
            'minutes': 45,
            'locked': index == 1,
          },
      ],
    };
    expect(f.c.hasCurrentPlans, isTrue);
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: PlanningEntry(controller: f.c),
        ),
      ),
    );
    expect(find.text('第1段学习任务'), findsOneWidget);
    expect(find.text('第2段学习任务'), findsOneWidget);
    expect(find.text('第3段学习任务'), findsOneWidget);
    for (final key in [
      'learning-plan-header',
      'learning-plan-b0',
      'learning-plan-b1',
      'learning-plan-b2',
      'learning-plan-action',
    ]) {
      expect(
        tester.getSize(find.byKey(ValueKey(key))).height,
        greaterThanOrEqualTo(48),
      );
    }
    await capture(tester, 'planning-entry-compact');
    // The bundled test font has different Chinese metrics from a device font.
    expect(
      tester.getSize(find.byType(PlanningEntry)).height,
      lessThan(previewFont ? 310 : 360),
    );
    expect(tester.takeException(), isNull);

    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: PlanningEntry(controller: f.c),
        ),
      ),
      width: 320,
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull);
    f.c.items.clear();
    f.c.planFeed!['blocks'] = [];
    await mount(tester, Scaffold(body: PlanningEntry(controller: f.c)));
    expect(find.text('任务还没有安排到具体时间'), findsNothing);
    expect(find.byKey(const ValueKey('learning-plan-action')), findsNothing);
    expect(find.text('全部安排'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
}
