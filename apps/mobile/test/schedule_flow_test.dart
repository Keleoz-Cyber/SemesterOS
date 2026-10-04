import 'package:forui/forui.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/items/items_controller.dart';
import 'package:semester_os/features/items/reminder_sync.dart';
import 'package:semester_os/features/planning/schedule_page.dart';
import 'package:semester_os/features/planning/proposal_page.dart';
import 'package:semester_os/features/planning/plan_list.dart';
import 'package:semester_os/features/planning/plan_change_confirmation.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'controller_test.dart' show MemoryStore;
import 'reminder_sync_test.dart' show FakeNotifications;
import 'planning_flow_test.dart' show ioTap, route;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

class ScheduleFixture {
  final api = SemesterApi()..session = account('preview');
  late final ItemsController c;
  final start = DateTime.now().toUtc().add(const Duration(days: 1));
  int revision = 1, generated = 0, applied = 0, locks = 0;
  Map<String, dynamic>? accepted;
  List<Map<String, dynamic>> blocks = [];
  late Map<String, dynamic> item = {
    'id': 't',
    'kind': 'task',
    'semester_id': 's',
    'title': '合成报告',
    'lifecycle': 'active',
    'version': 1,
    'remaining_minutes': 120,
    'start_policy': 'now',
    'certainty': 'formal',
    'time': {
      'precision': 'exact',
      'at': start.add(const Duration(hours: 4)).toIso8601String(),
    },
    'reminders': [],
  };
  Map<String, dynamic> proposal({bool partial = false}) {
    var offset = 0;
    final rows = <Map<String, dynamic>>[];
    for (final duration in partial ? [45, 30] : [45, 45, 30]) {
      rows.add({
        'item_id': 't',
        'title': '合成报告',
        'start_at': start.add(Duration(minutes: offset)).toIso8601String(),
        'end_at': start
            .add(Duration(minutes: offset + duration))
            .toIso8601String(),
        'minutes': duration,
      });
      offset += duration;
    }
    return {
      'id': 'p',
      'semester_id': 's',
      'version': 1,
      'base_revision': 1,
      'phase': 'ready',
      'status': partial ? 'FEASIBLE_PARTIAL' : 'FEASIBLE_COMPLETE',
      'window_start': start.toIso8601String(),
      'window_end': start.add(const Duration(days: 7)).toIso8601String(),
      'valid_until': start.toIso8601String(),
      'optimal': true,
      'can_apply': true,
      'unarranged_minutes': partial ? 45 : 0,
      'messages': ['已有计划保持原位，本轮只追加未覆盖部分'],
      'request': {
        'days': 7,
        'lead_minutes': 5,
        'chunk_minutes': 45,
        'allow_partial': partial,
        'tasks': [
          {'item_id': 't', 'target_minutes': null},
        ],
      },
      'tasks': [
        {
          'item_id': 't',
          'title': '合成报告',
          'target_minutes': 120,
          'existing_minutes': 0,
          'outside_minutes': 0,
          'new_minutes': partial ? 75 : 120,
          'unarranged_minutes': partial ? 45 : 0,
          'later_minutes': 0,
        },
      ],
      'blocks': rows,
    };
  }

  ScheduleFixture() {
    c = ItemsController(api, MemoryStore(), ReminderSync(FakeNotifications()));
    api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/courses')) return body([]);
      if (r.path.endsWith('/reminders')) {
        return body({'owner_id': 'preview', 'reminders': []});
      }
      if (r.path.endsWith('/plans')) {
        return body({
          'semester_id': 's',
          'revision': revision,
          'blocks': blocks,
          'invalid_blocks': [],
        });
      }
      if (r.path.endsWith('/plan-proposals')) {
        generated++;
        return body(proposal(partial: r.data['allow_partial'] == true), 201);
      }
      if (r.path.endsWith('/accept')) {
        applied++;
        accepted = Map<String, dynamic>.from(r.data);
        revision++;
        blocks =
            List<Map<String, dynamic>>.from(
                  proposal(
                    partial: r.data['confirm_partial'] == true,
                  )['blocks'],
                ).indexed
                .map(
                  (r) => {
                    ...r.$2,
                    'id': 'b${r.$1}',
                    'version': 1,
                    'locked': false,
                    'status': 'active',
                  },
                )
                .toList();
        return body({
          'semester_id': 's',
          'revision': revision,
          'proposal_version': 2,
        });
      }
      if (r.path.endsWith('/lock')) {
        locks++;
        revision++;
        blocks[0] = {...blocks[0], 'locked': r.data['locked'], 'version': 2};
        return body({'semester_id': 's', 'revision': revision});
      }
      return body({
        'items': [item],
        'revision': revision,
      });
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  testWidgets(
    'a known newer semester revision immediately disables an open proposal',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      await route(
        tester,
        ProposalPage(controller: f.c, proposal: f.proposal()),
      );
      f.c.observeRevision('s', 2);
      await tester.pumpAndSettle();
      expect(find.text('你的安排已有变化，请重新生成计划。'), findsOneWidget);
      expect(find.text('确认保存计划'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets('generation remains a preview until explicitly accepted', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final previous = f.api.dio.httpClientAdapter as ControlledTransport;
    f.api.dio.httpClientAdapter = ControlledTransport((request) async {
      if (request.path.endsWith('/schedule/setup')) {
        return body({
          'revision': f.revision,
          'tasks': [
            {...f.item, 'can_schedule': true},
          ],
          'availability': {
            'needs_confirmation': false,
            'current': {'version': 1, 'weekly': [], 'exclusions': []},
          },
        });
      }
      if (request.path.endsWith('/plan-proposals')) {
        f.generated++;
        expect(request.data['tasks'], [
          {'item_id': 't'},
        ]);
        return body(f.proposal(), 201);
      }
      return previous.respond(request);
    });
    await tester.runAsync(() => f.c.bind('s'));
    await route(tester, SchedulePage(controller: f.c));
    await capture(tester, 'schedule-input');
    await tester.scrollUntilVisible(
      find.text('生成安排'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await ioTap(tester, find.text('生成安排'));
    expect(f.generated, 1);
    expect(f.applied, 0);
    expect(find.text('查看计划方案'), findsOneWidget);
    await capture(tester, 'schedule-proposal');
    await tester.scrollUntilVisible(
      find.text('确认保存计划'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await ioTap(tester, find.text('确认保存计划'));
    expect(f.applied, 1);
    expect(f.c.items.single['remaining_minutes'], 120);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
  testWidgets(
    'partial candidate requires a separate confirmation of the unarranged minutes',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      await route(
        tester,
        ProposalPage(controller: f.c, proposal: f.proposal(partial: true)),
      );
      final button = find.widgetWithText(FButton, '保存已安排部分');
      expect(tester.widget<FButton>(button).onPress, isNull);
      expect(f.applied, 0);
      await tester.scrollUntilVisible(
        find.byType(AppCheckRow),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byType(AppCheckRow));
      await tester.tap(find.byType(AppCheckRow));
      await tester.pumpAndSettle();
      await ioTap(tester, button);
      expect(f.accepted!['confirm_partial'], true);
      expect(f.accepted!['unarranged_minutes'], 45);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'locked future blocks require explicit unlock and cancellation consent',
    (tester) async {
      Map<String, dynamic>? result;
      final block = {
        'id': 'b',
        'start_at': '2099-09-21T09:00:00+08:00',
        'minutes': 60,
        'future_minutes': 60,
        'locked': true,
      };
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await confirmPlanChange(
                  context,
                  title: '完成核对',
                  message: '未来计划需要取消',
                  confirmLabel: '确认完成',
                  blocks: [block],
                  cancelAll: true,
                  remaining: 0,
                );
              },
              child: const Text('预览'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('预览'));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(AppButton, '确认完成');
      expect(tester.widget<AppButton>(button).onPressed, isNull);
      await tester.tap(find.text('取消所选固定安排'));
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(result!['confirm_locked_cancellation'], true);
      expect(result!['cancel_plan_ids'], ['b']);
    },
  );
  testWidgets(
    'locking changes only the lock state and large-text plan list remains usable',
    (tester) async {
      final f = ScheduleFixture();
      f.blocks = [
        ...List<Map<String, dynamic>>.from(f.proposal()['blocks']).indexed.map(
          (r) => {
            ...r.$2,
            'id': 'b${r.$1}',
            'locked': false,
            'status': 'active',
            'version': 1,
          },
        ),
      ];
      await tester.runAsync(() => f.c.bind('s'));
      final before = f.blocks[0]['start_at'];
      await mount(
        tester,
        PlanListPage(controller: f.c),
        width: 360,
        textScale: 2,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final firstBlock = find.byKey(const ValueKey('learning-plan-b0'));
      await tester.scrollUntilVisible(
        firstBlock,
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(firstBlock);
      await tester.pumpAndSettle();
      expect(find.text('锁定'), findsNothing);
      await tester.tap(firstBlock);
      await tester.pumpAndSettle();
      expect(find.text('查看任务'), findsOneWidget);
      await tester.runAsync(() => tester.tap(find.text('固定这段时间')));
      // The page init refresh starts in FakeAsync; interleave frames and I/O
      // when testing a second platform-queue mutation from the real async zone.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
      }
      await tester.pumpAndSettle();
      expect(f.locks, 1);
      expect(f.blocks[0]['start_at'], before);
      expect(f.blocks[0]['locked'], true);
      expect(tester.takeException(), isNull);
      await capture(tester, 'plans-large-text');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
}
