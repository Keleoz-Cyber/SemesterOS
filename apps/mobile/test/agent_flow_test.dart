import 'package:semester_os/ui/app_controls.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/features/agent/agent_controller.dart';
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'api_session_test.dart' show ControlledTransport, body;
import 'planning_flow_test.dart' show ioTap;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  testWidgets('record selection respects removal of the current media source', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    Map<String, dynamic>? sent;
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.contains('/agent/threads?')) {
        return body([
          {'id': 't', 'title': '选择组会'},
        ]);
      }
      if (r.path.endsWith('/agent/threads/t')) {
        return body({
          'runs': [
            {
              'id': 'r',
              'status': 'completed',
              'text': '改组会',
              'answer': '请选出要修改的记录',
              'source': {
                'id': 'media',
                'version': 1,
                'kind': 'image',
                'text': '原通知',
              },
              'ambiguous_ids': ['e'],
              'cards': [
                {
                  'kind': 'records',
                  'data': {
                    'records': [
                      {
                        'id': 'e',
                        'resource_type': 'event',
                        'title': '组会',
                        'date': '2026-10-01',
                      },
                    ],
                  },
                },
              ],
            },
          ],
        });
      }
      if (r.path.endsWith('/turns')) {
        sent = Map<String, dynamic>.from(r.data);
        return body({
          'id': 'new',
          'status': 'completed',
          'text': '已选择',
          'cards': [],
        });
      }
      return old.respond(r);
    });
    await tester.runAsync(() => f.c.bind('s'));
    await mount(
      tester,
      AgentPage(controller: f.c, semester: {'id': 's', 'name': '学期'}),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除本次附件'));
    await tester.pump();
    await ioTap(tester, find.text('选这条'));
    expect(sent?['detach_source'], isTrue);
    expect(sent?.containsKey('source_id'), isFalse);
    expect(sent?['selected_record_ids'], ['e']);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
  testWidgets(
    'partial plan requires acknowledging unfinished work before confirm',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var confirmations = 0;
      final run = <String, dynamic>{
        'id': 'r',
        'status': 'needs_confirmation',
        'text': '先安排能完成的部分',
        'cards': [],
        'preview': {
          'kind': 'plan',
          'action': 'schedule',
          'token': 'bound',
          'before': {
            'tasks': [
              {'id': 't', 'title': 'Java报告'},
            ],
            'blocks': [],
          },
          'after': {
            'unarranged_minutes': 30,
            'blocks': [
              {
                'item_id': 't',
                'start_at': '2026-10-01T09:00:00+08:00',
                'end_at': '2026-10-01T10:00:00+08:00',
                'minutes': 60,
              },
            ],
          },
        },
      };
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/agent/threads?')) {
          return body([
            {'id': 't', 'title': '安排'},
          ]);
        }
        if (r.path.endsWith('/agent/threads/t')) {
          return body({
            'runs': [run],
          });
        }
        if (r.path.endsWith('/decision')) {
          confirmations++;
          return body({
            ...run,
            'status': 'applied',
            'receipt': {'semester_id': 's', 'revision': 1},
          });
        }
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await mount(
        tester,
        AgentPage(controller: f.c, semester: {'id': 's', 'name': '学期'}),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('30分钟没有排入日程'), findsOneWidget);
      await capture(tester, 'agent-plan-preview');
      expect(
        tester
            .widget<AppButton>(find.byKey(const Key('agent-plan-confirm')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('先保存能安排的部分'));
      await tester.tap(find.text('先保存能安排的部分'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppButton>(find.byKey(const Key('agent-plan-confirm')))
            .onPressed,
        isNotNull,
      );
      await ioTap(tester, find.byKey(const Key('agent-plan-confirm')));
      expect(confirmations, 1);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  test(
    'restoring saved receipt refreshes reminders after lost confirmation response',
    () async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var reminderReads = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/agent/threads?')) {
          return body([
            {'id': 't', 'title': '提醒'},
          ]);
        }
        if (r.path.endsWith('/agent/threads/t')) {
          return body({
            'runs': [
              {
                'id': 'r',
                'text': '修改提醒',
                'status': 'applied',
                'sequence': 3,
                'receipt': {'semester_id': 's', 'revision': 1},
              },
            ],
          });
        }
        if (r.path.endsWith('/reminders')) reminderReads++;
        return old.respond(r);
      });
      await f.c.bind('s');
      reminderReads = 0;
      final c = AgentController(f.c, 's');
      try {
        await c.open();
        expect(c.runs.single['status'], 'applied');
        expect(reminderReads, greaterThan(0));
      } finally {
        c.dispose();
        f.c.dispose();
      }
    },
  );
  test('late polling response cannot replace completed result', () async {
    final f = ScheduleFixture();
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    final slow = Completer<dynamic>(), fast = Completer<dynamic>();
    var reads = 0;
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.contains('/agent/threads?')) {
        return body([
          {'id': 't', 'title': '查询'},
        ]);
      }
      if (r.path.endsWith('/agent/threads/t')) {
        return body({
          'runs': [
            {'id': 'r', 'text': '查询', 'status': 'running', 'sequence': 1},
          ],
        });
      }
      if (r.path.endsWith('/agent/runs/r')) {
        reads++;
        return await (reads == 1 ? slow.future : fast.future);
      }
      return old.respond(r);
    });
    await f.c.bind('s');
    final c = AgentController(f.c, 's');
    try {
      await c.open();
      final first = c.poll();
      final second = c.poll();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      fast.complete(
        body({
          'id': 'r',
          'text': '查询',
          'status': 'completed',
          'sequence': 3,
          'answer': '已查到',
        }),
      );
      await second;
      slow.complete(
        body({'id': 'r', 'text': '查询', 'status': 'running', 'sequence': 2}),
      );
      await first;
      expect(c.runs.single['status'], 'completed');
      expect(c.runs.single['answer'], '已查到');
    } finally {
      c.dispose();
      f.c.dispose();
    }
  });
  testWidgets('preview displays changed end date and certainty', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.contains('/agent/threads?')) {
        return body([
          {'id': 't', 'title': '活动'},
        ]);
      }
      if (r.path.endsWith('/agent/threads/t')) {
        return body({
          'id': 't',
          'runs': [
            {
              'id': 'r',
              'text': '活动延长到5号，暂定',
              'status': 'needs_confirmation',
              'cards': [],
              'preview': {
                'kind': 'event',
                'action': 'update',
                'token': 'token',
                'before': {
                  'title': '校园活动',
                  'certainty': 'formal',
                  'time': {
                    'precision': 'range',
                    'date': '2026-10-01',
                    'end_date': '2026-10-03',
                  },
                },
                'after': {
                  'title': '校园活动',
                  'certainty': 'tentative',
                  'time': {
                    'precision': 'range',
                    'date': '2026-10-01',
                    'end_date': '2026-10-05',
                  },
                },
              },
            },
          ],
        });
      }
      return old.respond(r);
    });
    await tester.runAsync(() => f.c.bind('s'));
    await mount(
      tester,
      AgentPage(controller: f.c, semester: {'id': 's', 'name': '测试学期'}),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-10-03'), findsOneWidget);
    expect(find.textContaining('2026-10-05'), findsOneWidget);
    expect(find.text('暂定'), findsOneWidget);
    expect(find.text('已确定'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
  testWidgets(
    'assistant restores pending preview and confirms only on explicit tap',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var applied = 0;
      final run = <String, dynamic>{
        'id': 'run',
        'text': '组会改到6302',
        'status': 'needs_confirmation',
        'answer': '请核对这次修改，确认后保存。',
        'cards': [
          {
            'kind': 'calendar',
            'data': {
              'from_date': '2026-09-28',
              'to_date': '2026-10-04',
              'entries': [
                for (var i = 0; i < 21; i++)
                  {
                    'title': '参考课程$i',
                    'resource_type': 'course',
                    'resource_id': 'c$i',
                    'start_at': '2026-09-30T08:00:00+08:00',
                    'end_at': '2026-09-30T09:00:00+08:00',
                  },
              ],
            },
          },
        ],
        'preview': {
          'kind': 'event',
          'action': 'update',
          'token': 'bound-token',
          'before': {'title': '课题组组会', 'location': '6412'},
          'after': {
            'title': '课题组组会',
            'location': '6302',
            'time': {
              'precision': 'exact',
              'at': '2026-09-30T09:00:00Z',
              'end_at': '2026-09-30T10:00:00Z',
            },
          },
        },
      };
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/agent/threads?')) {
          return body([
            {'id': 'thread', 'title': '组会安排'},
          ]);
        }
        if (r.path.endsWith('/agent/threads/thread')) {
          return body({
            'id': 'thread',
            'runs': [
              {
                'id': 'earlier',
                'text': '之前的问题',
                'status': 'completed',
                'answer': '历史答复' * 80,
                'cards': [],
              },
              run,
            ],
          });
        }
        if (r.path.endsWith('/decision')) {
          expect(r.data, {'decision': 'confirm', 'token': 'bound-token'});
          applied++;
          return body({
            ...run,
            'status': 'applied',
            'answer': '已保存。',
            'receipt': {'semester_id': 's', 'revision': 2},
          });
        }
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await mount(
        tester,
        AgentPage(controller: f.c, semester: {'id': 's', 'name': '测试学期'}),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.text('课题组组会'), findsWidgets);
      expect(find.textContaining('6412'), findsWidgets);
      expect(find.textContaining('6302'), findsWidgets);
      expect(applied, 0);
      expect(find.text('历史消息 · 1'), findsOneWidget);
      expect(find.text('历史答复' * 80), findsNothing);
      expect(find.text('参考课程0'), findsNothing);
      expect(find.text('确认修改').hitTestable(), findsOneWidget);
      await capture(tester, 'agent-change-preview');
      await tester.ensureVisible(find.text('确认修改'));
      await ioTap(tester, find.text('确认修改'));
      expect(applied, 1);
      expect(find.text('已保存'), findsOneWidget);
      expect(find.text('确认修改'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
}
