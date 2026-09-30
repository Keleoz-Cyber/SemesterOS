import 'package:forui/forui.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/planning/availability_page.dart';
import 'package:semester_os/features/planning/schedule_page.dart';
import 'package:semester_os/features/planning/proposal_page.dart';
import 'package:semester_os/features/planning/progress_page.dart';
import 'package:semester_os/features/planning/plan_list.dart';
import 'package:semester_os/features/planning/plan_change_confirmation.dart';
import 'package:semester_os/features/planning/risk_widgets.dart';
import 'package:semester_os/features/tags/tag_management_page.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'planning_flow_test.dart' show PlanningFixture, bind, ioTap;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'tag_management_test.dart' show tagRows, tagPreview;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

// Real production pages and their existing API fixtures. No display-only mocks.
Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, Widget page, double scale) async {
  await mount(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => page),
          ),
          child: const Text('打开页面'),
        ),
      ),
    ),
    width: 390,
    textScale: scale,
  );
  await ioTap(tester, find.text('打开页面'));
  await _settleIo(tester);
}

Future<void> _to(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _bottom(WidgetTester tester, {Finder? within}) async {
  final scroll = within == null
      ? find.byType(Scrollable).first
      : find.descendant(of: within, matching: find.byType(Scrollable)).first;
  // A lazy ListView can revise its estimated extent after laying out the tail.
  for (var i = 0; i < 12; i++) {
    final position = tester.state<ScrollableState>(scroll).position;
    final target = position.maxScrollExtent;
    position.jumpTo(target);
    await tester.pumpAndSettle();
    if ((position.maxScrollExtent - position.pixels).abs() < 1) break;
  }
}

Future<void> _shot(WidgetTester tester, String page, String scale) async {
  expect(tester.takeException(), isNull);
  await capture(tester, 'inner-planning-$page-$scale');
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);

  for (final scale in [1.0, 1.6]) {
    final size = scale == 1 ? 'normal' : 'large';

    testWidgets('inner availability weekly and confirmation $size', (
      tester,
    ) async {
      final f = PlanningFixture();
      f.preferences = {
        'configured': true,
        'version': 1,
        'weekly': [
          for (var day = 1; day <= 7; day++)
            {'weekday': day, 'start': '19:00', 'end': '21:00'},
          {'weekday': 3, 'start': '13:30', 'end': '15:00'},
        ],
        'exclusions': [
          {
            'start_at': '2099-09-23T19:00:00+08:00',
            'end_at': '2099-09-23T20:30:00+08:00',
            'label': '实验室安全培训与新学期设备使用说明',
          },
          {
            'start_at': '2099-09-24T19:00:00+08:00',
            'end_at': '2099-09-24T21:00:00+08:00',
            'label': '社团活动',
          },
        ],
      };
      await bind(tester, f);
      await _open(tester, AvailabilityPage(controller: f.c), scale);
      await _shot(tester, 'availability-top', size);
      await _bottom(tester);
      await _shot(tester, 'availability-save', size);
      await _to(tester, find.text('核对并保存学习时间'));
      await ioTap(tester, find.text('核对并保存学习时间'));
      expect(f.puts, 0);
      expect(find.text('确认保存学习时间'), findsOneWidget);
      await _bottom(tester, within: find.byType(AppDialog));
      await _shot(tester, 'availability-confirm', size);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });

    testWidgets('inner schedule task selection and optional controls $size', (
      tester,
    ) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      f.c.items = [
        {...f.item, 'title': '计算机网络课程报告：实验结果与分析'},
        {
          ...f.item,
          'id': 't2',
          'title': '毕业设计开题报告与相关工作整理',
          'remaining_minutes': 180,
        },
        {
          ...f.item,
          'id': 't3',
          'title': '英语阅读笔记',
          'remaining_minutes': null,
          'start_policy': 'unconfirmed',
        },
      ];
      await _open(tester, SchedulePage(controller: f.c), scale);
      await _shot(tester, 'schedule-top', size);
      await _to(tester, find.text('开始时间与分段设置'));
      await tester.tap(find.text('开始时间与分段设置'));
      await tester.pumpAndSettle();
      await _to(tester, find.text('每次想学习多久'));
      await _shot(tester, 'schedule-options', size);
      await _bottom(tester);
      expect(find.text('生成计划方案'), findsOneWidget);
      await _shot(tester, 'schedule-generate', size);
      expect(f.generated, 0);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });

    testWidgets('inner partial proposal timeline and consent $size', (
      tester,
    ) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      final proposal = f.proposal(partial: true);
      await _open(
        tester,
        ProposalPage(controller: f.c, proposal: proposal),
        scale,
      );
      await _shot(tester, 'proposal-top', size);
      await _to(tester, find.text('新增安排（2段）'));
      await _shot(tester, 'proposal-timeline', size);
      await _bottom(tester);
      final save = find.widgetWithText(FButton, '保存已安排部分（仍有45分钟未安排）');
      expect(tester.widget<FButton>(save).onPress, isNull);
      await _shot(tester, 'proposal-confirm-disabled', size);
      await _to(tester, find.byType(AppCheckRow));
      await tester.tap(find.byType(AppCheckRow));
      await tester.pumpAndSettle();
      await _bottom(tester);
      expect(tester.widget<FButton>(save).onPress, isNotNull);
      expect(f.applied, 0);
      await _shot(tester, 'proposal-confirm-ready', size);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });

    testWidgets('inner progress separates remaining and actual $size', (
      tester,
    ) async {
      final f = PlanningFixture();
      f.item = {...f.item, 'title': '数据结构实验报告：复杂度分析与测试结果'};
      await bind(tester, f);
      await _open(tester, ProgressPage(controller: f.c, item: f.item), scale);
      await _shot(tester, 'progress-top', size);
      await _to(tester, find.byKey(const Key('progress-remaining')));
      await tester.enterText(find.byKey(const Key('progress-remaining')), '90');
      await _to(tester, find.byKey(const Key('progress-actual')));
      await tester.enterText(find.byKey(const Key('progress-actual')), '60');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _bottom(tester);
      await _shot(tester, 'progress-save', size);
      await _to(tester, find.text('确认本次进度'));
      await ioTap(tester, find.text('确认本次进度'));
      expect(f.progressSaves, 0);
      expect(find.text('确认更新进度'), findsOneWidget);
      await _shot(tester, 'progress-confirm', size);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });

    testWidgets('inner plan list future history and locked cancellation $size', (
      tester,
    ) async {
      final f = ScheduleFixture();
      f.blocks = [
        ...List<Map<String, dynamic>>.from(f.proposal()['blocks']).indexed.map(
          (row) => {
            ...row.$2,
            'id': 'b${row.$1}',
            'version': 1,
            'locked': row.$1 == 0,
            'status': 'active',
          },
        ),
        {
          'id': 'past',
          'item_id': 't',
          'title': '已结束的文献整理计划',
          'start_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 1, hours: 1))
              .toIso8601String(),
          'end_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 1))
              .toIso8601String(),
          'minutes': 60,
          'version': 1,
          'locked': false,
          'status': 'active',
        },
      ];
      final previous = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((request) async {
        if (request.path.endsWith('/plans')) {
          return body({
            'semester_id': 's',
            'revision': f.revision,
            'blocks': f.blocks,
            'invalid_blocks': [],
            'latest_proposal': f.proposal(),
            'latest_applied': f.proposal(),
          });
        }
        return previous.respond(request);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await _open(tester, PlanListPage(controller: f.c), scale);
      await _shot(tester, 'records-top', size);
      await _to(tester, find.text('解锁').first);
      await _shot(tester, 'records-lock-controls', size);
      await _bottom(tester);
      expect(find.text('时间已过，尚未据此确认工作完成'), findsOneWidget);
      await _shot(tester, 'records-history', size);
      // Return to the first record through its lazy list, then show the real dialog.
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(0);
      await tester.pumpAndSettle();
      await _to(tester, find.text('取消此段').first);
      await tester.tap(find.text('取消此段').first);
      await tester.pumpAndSettle();
      expect(find.text('确认解锁并取消'), findsOneWidget);
      await _shot(tester, 'records-cancel-confirm', size);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });

    testWidgets('inner tag management rename and merge impact $size', (
      tester,
    ) async {
      final f = ScheduleFixture();
      final previous = f.api.dio.httpClientAdapter as ControlledTransport;
      var applies = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((request) async {
        if (request.path.endsWith('/tags')) {
          return body({'owner_id': 'preview', 'tags': tagRows});
        }
        if (request.path.endsWith('/tags/preview')) {
          return body({
            ...tagPreview(),
            'operation': request.data['operation'],
            if (request.data['operation'] == 'rename')
              'target': {...tagRows[0], 'name': request.data['name']},
          });
        }
        if (request.path.endsWith('/apply')) applies++;
        return previous.respond(request);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await _open(tester, TagManagementPage(controller: f.c), scale);
      await _shot(tester, 'tags-list', size);
      await _to(tester, find.text('重命名').first);
      await tester.tap(find.text('重命名').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(AppFormField), '学术论文阅读与笔记');
      await ioTap(tester, find.text('查看影响'));
      await _settleIo(tester);
      await _to(tester, find.text('确认重命名'));
      await _shot(tester, 'tags-rename-impact', size);
      await tester.tap(find.text('取消预览'));
      await tester.pumpAndSettle();
      await _to(tester, find.text('合并到').first);
      await tester.tap(find.text('合并到').first);
      await tester.pumpAndSettle();
      await ioTap(tester, find.text('科研').last);
      await _settleIo(tester);
      await _to(tester, find.text('确认合并'));
      await _shot(tester, 'tags-merge-impact', size);
      expect(applies, 0);
      await _bottom(tester);
      await _shot(tester, 'tags-bottom', size);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });

    testWidgets('inner risk details capacity and shared deficit $size', (
      tester,
    ) async {
      final f = PlanningFixture();
      f.item = {...f.item, 'title': '课程报告与文献阅读的共同截止窗口'};
      await bind(tester, f);
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showRiskDetails(context, f.c, f.item),
              child: const Text('查看余量依据'),
            ),
          ),
        ),
        textScale: scale,
      );
      await tester.tap(find.text('查看余量依据'));
      await tester.pumpAndSettle();
      await _shot(tester, 'risk-top', size);
      await _to(tester, find.text('可用时间如何扣除'));
      await _shot(tester, 'risk-capacity', size);
      await _bottom(tester);
      expect(find.text('刷新分析'), findsOneWidget);
      await _shot(tester, 'risk-bottom', size);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });

    testWidgets('inner plan change requires explicit unlock consent $size', (
      tester,
    ) async {
      final blocks = [
        for (var i = 0; i < 4; i++)
          {
            'id': 'locked-$i',
            'start_at': '2099-09-${21 + i}T19:00:00+08:00',
            'minutes': 60,
            'future_minutes': 60,
            'locked': i == 0,
          },
      ];
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => confirmPlanChange(
                context,
                title: '确认任务已经完成',
                message: '剩余工作已更新为0分钟。以下未来计划将取消，实际投入记录保留。',
                confirmLabel: '确认完成并停止提醒',
                blocks: blocks,
                cancelAll: true,
                remaining: 0,
              ),
              child: const Text('核对受影响计划'),
            ),
          ),
        ),
        textScale: scale,
      );
      await tester.tap(find.text('核对受影响计划'));
      await tester.pumpAndSettle();
      await _shot(tester, 'plan-change-top', size);
      final confirm = find.widgetWithText(AppButton, '确认完成并停止提醒');
      expect(tester.widget<AppButton>(confirm).onPressed, isNull);
      await _bottom(tester, within: find.byType(AppDialog));
      await _shot(tester, 'plan-change-confirm-disabled', size);
      await _to(tester, find.text('我确认解锁并取消所选锁定计划'));
      await tester.tap(find.text('我确认解锁并取消所选锁定计划'));
      await tester.pumpAndSettle();
      expect(tester.widget<AppButton>(confirm).onPressed, isNotNull);
      await _shot(tester, 'plan-change-confirm-ready', size);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
