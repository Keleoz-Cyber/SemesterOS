import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/items/item_detail.dart';
import 'package:semester_os/features/items/item_widgets.dart';
import 'package:semester_os/features/items/reminder_editor.dart';
import 'package:semester_os/features/planning/risk_widgets.dart';
import 'package:semester_os/features/planning/progress_page.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'calendar_flow_test.dart' show semester;
import 'inner_items_visual_test.dart' show fixture, itemRecord, settle;
import 'ui_polish_test.dart' show mount, loadPreviewFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);

  test('incomplete evidence never presents positive slack as a safe plan', () {
    expect(
      riskSummary({
        'level': 'unknown',
        'task_slack_minutes': 30,
        'reason_codes': ['other_tasks_incomplete'],
      }),
      '其他任务还需补充信息，整体负荷尚不能确定',
    );
    expect(
      riskSummary({
        'level': 'unknown',
        'task_slack_minutes': 30,
        'window_gap_minutes': 60,
      }),
      '同期任务至少还缺 1小时',
    );
    expect(
      riskSummary({'level': 'high', 'task_slack_minutes': -45}),
      '截止前还缺 45分钟',
    );
  });

  testWidgets('secondary actions stay reachable without a button bank', (
    tester,
  ) async {
    final f = await fixture(tester);
    await mount(
      tester,
      ItemDetailPage(controller: f.c, semester: semester(), id: 't'),
      textScale: 1.6,
    );
    await settle(tester);
    expect(find.text('标记完成'), findsOneWidget);
    expect(find.text('取消事项'), findsNothing);
    expect(find.text('修改历史'), findsNothing);
    expect(find.byTooltip('编辑事项'), findsOneWidget);
    final deadline = displayInstant(itemRecord()['time']['at']);
    expect(find.text(deadline), findsOneWidget);
    expect(find.text('$deadline 截止'), findsNothing);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改历史'));
    await settle(tester);
    expect(find.text('根据实验课通知补充地点'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });

  testWidgets('progress and reminder rows open their real flows', (
    tester,
  ) async {
    final f = await fixture(tester);
    await mount(
      tester,
      ItemDetailPage(controller: f.c, semester: semester(), id: 't'),
    );
    await settle(tester);
    final progress = find.text(
      '还需 ${minutesLabel(itemRecord()['remaining_minutes'])}',
    );
    await tester.ensureVisible(progress);
    await tester.pumpAndSettle();
    await tester.tap(progress);
    await tester.pumpAndSettle();
    expect(find.byType(ProgressPage), findsOneWidget);
    Navigator.of(tester.element(find.byType(ProgressPage))).pop();
    await settle(tester);
    await tester.ensureVisible(find.text('提醒 · 2条'));
    await tester.tap(find.text('提醒 · 2条'));
    await tester.pumpAndSettle();
    expect(find.text('提前1天'), findsOneWidget);
    expect(find.text('指定时刻 · 核实通知'), findsOneWidget);
    expect(find.byTooltip('系统通知设置'), findsOneWidget);
    expect(find.text('添加提醒'), findsOneWidget);
    await tester.tap(find.text('提前1天'));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderEditor), findsOneWidget);
    expect(find.text('修改提醒'), findsOneWidget);
    final editor = tester.widget<ReminderEditor>(find.byType(ReminderEditor));
    expect(editor.initial?['id'], 'r1');
    expect(editor.initial?['mode'], 'relative');
    expect(editor.initial?['lead_minutes'], 1440);
    expect(editor.initial?['purpose'], 'item');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });

  testWidgets('cancel remains behind explicit confirmation', (tester) async {
    final f = await fixture(tester);
    var writes = 0;
    final original = f.api.dio.httpClientAdapter as ControlledTransport;
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/lifecycle/preview')) {
        return body({'base_revision': 1, 'affected_blocks': []});
      }
      if (r.path.endsWith('/lifecycle')) writes++;
      return original.respond(r);
    });
    await mount(
      tester,
      ItemDetailPage(controller: f.c, semester: semester(), id: 't'),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消事项'));
    await settle(tester);
    expect(find.text('确认取消事项'), findsOneWidget);
    expect(writes, 0);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('标记完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
}
