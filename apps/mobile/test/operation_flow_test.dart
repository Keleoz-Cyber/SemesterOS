import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/operations/operation_page.dart';
import 'package:semester_os/features/media/drafts.dart';
import 'package:semester_os/features/planning/proposal_page.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'planning_flow_test.dart' show route;
import 'centers_flow_test.dart' show settleIo;
import 'ui_polish_test.dart' show capture, loadPreviewFonts;

Future<void> ioTap(WidgetTester t, Finder f) async {
  await t.runAsync(() => t.tap(f));
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 50));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
  }
}

Map<String, dynamic> operation(
  ScheduleFixture f, {
  String intent = 'update_task',
  String phase = 'ready',
}) => {
  'id': 'op',
  'version': 1,
  'semester_id': 's',
  'base_revision': 1,
  'phase': phase,
  'source_text': '合成报告还需60分钟',
  'reference_at': DateTime.now().toUtc().toIso8601String(),
  'suggestion': {
    'intent': intent,
    'task_patch': {'remaining_minutes': 60},
    'reminder_patch': {},
    'reminder_action': 'edit',
    'plan_mode': 'schedule',
    'questions': [],
  },
  'suggested_target_id': intent == 'request_plan' ? null : 't',
  'choices': [f.item],
  'selection': intent == 'request_plan' ? {} : {'target_item_id': 't'},
  if (phase == 'ready')
    'preview': {
      'intent': intent,
      'before': f.item,
      'after': {...f.item, 'remaining_minutes': 60},
      'task_patch': {'remaining_minutes': 60},
      'affected_blocks': [],
      if (intent == 'request_plan') ...{
        'tasks': [f.item],
        'planning_request': {
          'days': 7,
          'tasks': [
            {'item_id': 't'},
          ],
        },
      },
    },
};
Future<void> showButton(WidgetTester t, String label) async {
  await t.scrollUntilVisible(
    find.text(label),
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await t.drag(find.byType(Scrollable).first, const Offset(0, -140));
  await t.pump(const Duration(milliseconds: 300));
  await ioTap(t, find.text(label));
}

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets(
    'item detail does not restore another items implicit-target draft',
    (t) async {
      final f = ScheduleFixture();
      await t.runAsync(() => f.c.bind('s'));
      await t.runAsync(
        () => CaptureDrafts(
          f.c.cache,
          'preview',
          () => true,
        ).save('operation:s', {'text': '还需要两小时', 'context_item_id': 'other'}),
      );
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      Map<String, dynamic>? sent;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/operations')) return body([]);
        if (r.path.endsWith('/operations/parse')) {
          sent = Map<String, dynamic>.from(r.data);
          return body(operation(f), 201);
        }
        return old.respond(r);
      });
      await route(t, OperationPage(controller: f.c, contextItemId: 't'));
      await settleIo(t);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('operation-text')))
            .controller!
            .text,
        isEmpty,
      );
      await t.enterText(find.byKey(const Key('operation-text')), '还需要两小时');
      await showButton(t, '让AI整理修改');
      expect(sent!['context_item_id'], 't');
      await t.pumpWidget(const SizedBox());
      await settleIo(t);
      f.c.dispose();
    },
  );
  for (final plan in [false, true]) {
    testWidgets(
      plan
          ? 'planning operation still requires separate candidate acceptance'
          : 'task operation never applies before confirmation',
      (t) async {
        final f = ScheduleFixture();
        await t.runAsync(() => f.c.bind('s'));
        final old = f.api.dio.httpClientAdapter as ControlledTransport;
        var applied = 0;
        final p = operation(f, intent: plan ? 'request_plan' : 'update_task');
        f.api.dio.httpClientAdapter = ControlledTransport((r) async {
          if (r.path.endsWith('/operations')) return body([]);
          if (r.path.endsWith('/operations/parse')) return body(p, 201);
          if (r.path.endsWith('/operations/op/apply')) {
            applied++;
            return body({
              'operation_id': 'op',
              'operation_version': 2,
              'semester_id': 's',
              'revision': 1,
              'changed_items': [],
              if (plan)
                'planning_request': {
                  'days': 7,
                  'tasks': [
                    {'item_id': 't'},
                  ],
                },
            });
          }
          return old.respond(r);
        });
        await route(
          t,
          OperationPage(controller: f.c, initialText: p['source_text']),
        );
        await settleIo(t);
        expect(applied, 0);
        expect(f.generated, 0);
        expect(f.blocks, isEmpty);
        await t.scrollUntilVisible(
          find.text(plan ? '按这个范围生成计划' : '确认保存修改'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        if (!plan) await capture(t, 'operation-task-preview');
        await showButton(t, plan ? '按这个范围生成计划' : '确认保存修改');
        expect(applied, 1);
        if (plan) {
          expect(find.byType(ProposalPage), findsOneWidget);
          expect(f.generated, 1);
          expect(f.applied, 0);
          expect(f.blocks, isEmpty);
        } else {
          expect(find.text('修改已保存'), findsOneWidget);
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await settleIo(t);
        f.c.dispose();
      },
    );
  }
  testWidgets('reminder editor metadata is separate from strict rule payload', (
    t,
  ) async {
    final f = ScheduleFixture();
    f.item['reminders'] = [
      {
        'id': 'rule',
        'version': 3,
        'mode': 'relative',
        'lead_minutes': 1440,
        'purpose': 'item',
        'enabled': true,
        'trigger_at': f.start.toIso8601String(),
      },
    ];
    await t.runAsync(() => f.c.bind('s'));
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    Map<String, dynamic>? sent;
    final p = operation(
      f,
      intent: 'update_reminder',
      phase: 'needs_clarification',
    );
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/operations')) return body([]);
      if (r.path.endsWith('/operations/parse')) return body(p, 201);
      if (r.path.endsWith('/items/t')) return body(f.item);
      if (r.path.endsWith('/resolve')) {
        sent = Map<String, dynamic>.from(r.data);
        return body(p);
      }
      return old.respond(r);
    });
    await route(
      t,
      OperationPage(controller: f.c, initialText: p['source_text']),
    );
    await settleIo(t);
    await showButton(t, '设置提醒时间');
    await ioTap(t, find.text('2小时前'));
    await ioTap(t, find.text('确认这条提醒'));
    await settleIo(t);
    await showButton(t, '查看修改前后');
    expect(sent, isNotNull);
    expect(sent!['expected_item_version'], 1);
    expect(sent!['expected_reminder_version'], 3);
    expect(sent!['reminder']['lead_minutes'], 120);
    expect(sent!['reminder'].containsKey('expected_version'), isFalse);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await settleIo(t);
    f.c.dispose();
  });
  testWidgets(
    'restored media draft preserves original source version and confirmation gate',
    (t) async {
      final f = ScheduleFixture();
      await t.runAsync(() => f.c.bind('s'));
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      Map<String, dynamic>? sent;
      await t.runAsync(
        () => CaptureDrafts(f.c.cache, 'preview', () => true)
            .save('operation:s', {
              'text': '合成报告还需60分钟',
              'reference_at': '2026-09-20T00:00:00Z',
              'source_id': 'src',
              'source_version': 2,
            }),
      );
      final p = operation(f, phase: 'needs_clarification')
        ..['source'] = {'id': 'src', 'version': 2, 'kind': 'image'};
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/operations')) return body([]);
        if (r.path.endsWith('/sources/src')) {
          return body({'id': 'src', 'version': 3});
        }
        if (r.path.endsWith('/operations/parse')) {
          sent = Map<String, dynamic>.from(r.data);
          return body(p, 201);
        }
        if (r.path.endsWith('/items/t')) return body(f.item);
        return old.respond(r);
      });
      await route(t, OperationPage(controller: f.c));
      await settleIo(t);
      await showButton(t, '让AI整理修改');
      expect(sent!['source_id'], 'src');
      expect(sent!['source_version'], 2);
      expect(find.text('确认保存修改'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await settleIo(t);
      f.c.dispose();
    },
  );
}
