import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/items/item_widgets.dart';
import 'package:semester_os/features/items/reminder_editor.dart';
import 'package:semester_os/features/planning/risk_widgets.dart';
import 'package:semester_os/ui/app_selection.dart';
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);

  for (final scale in [1.0, 1.6]) {
    testWidgets('unified task cards preserve sparse content at $scale', (
      tester,
    ) async {
      var opened = 0;
      await mount(
        tester,
        Scaffold(
          appBar: AppBar(title: const Text('任务')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ItemCard(
                item: const {
                  'title': '准备社团招新海报',
                  'kind': 'task',
                  'lifecycle': 'active',
                  'certainty': 'formal',
                  'time': {'precision': 'unknown'},
                },
                onTap: () => opened++,
              ),
              ItemCard(
                item: const {
                  'title': '完成实验报告与误差分析，整理原始测量记录',
                  'kind': 'assignment',
                  'course_title': '大学物理实验',
                  'lifecycle': 'active',
                  'certainty': 'tentative',
                  'remaining_minutes': 90,
                  'priority': 'high',
                  'time': {
                    'precision': 'exact',
                    'at': '2099-10-02T18:00:00+08:00',
                  },
                },
                onTap: () {},
                riskFooter: RiskBadge(
                  risk: const {
                    'level': 'medium',
                    'reason_codes': ['uncertain_fixed'],
                  },
                  onTap: () {},
                ),
              ),
              ItemCard(
                item: const {
                  'title': '线性代数期中考试',
                  'kind': 'exam',
                  'lifecycle': 'completed',
                  'certainty': 'formal',
                  'time': {'precision': 'date', 'date': '2099-10-04'},
                },
                onTap: () {},
              ),
            ],
          ),
        ),
        width: 375,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('耗时待补充'), findsNothing);
      expect(find.text('时间待确认'), findsNothing);
      await tester.tap(find.text('准备社团招新海报'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      await capture(tester, 'unified-task-cards-$scale');
      expect(tester.takeException(), isNull);
    });

    testWidgets('unified reminder mode changes without applying at $scale', (
      tester,
    ) async {
      await mount(
        tester,
        const Scaffold(
          body: SafeArea(child: ReminderEditor(kind: 'task')),
        ),
        width: 375,
        textScale: scale,
      );
      expect(find.byType(AppSegmentedControl<String>), findsOneWidget);
      await tester.tap(find.text('指定时刻'));
      await tester.pumpAndSettle();
      expect(find.text('选择提醒日期和时间（北京时间）'), findsOneWidget);
      expect(find.text('确认这条提醒'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'unified-reminder-$scale');
    });
  }
}
