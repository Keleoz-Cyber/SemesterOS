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
        'cards': [],
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
            'runs': [run],
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
