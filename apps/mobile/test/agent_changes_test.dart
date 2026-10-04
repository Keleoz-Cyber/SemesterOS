import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/agent/agent_controller.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/features/agent/change_confirmation.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'planning_flow_test.dart' show ioTap;
import 'ui_polish_test.dart' show mount, loadPreviewFonts, capture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  testWidgets(
    'group selection and explicit conflict confirmation reach the decision together',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      final agent = AgentController(f.c, 's');
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      Map<String, dynamic>? decision;
      final run = <String, dynamic>{
        'id': 'r',
        'status': 'needs_confirmation',
        'preview': {
          'kind': 'batch',
          'token': 'token',
          'groups': [
            {
              'id': 'g1',
              'title': '公共组会',
              'operations': [
                {
                  'kind': 'event',
                  'action': 'create',
                  'after': {'title': '公共组会'},
                },
                {
                  'kind': 'event',
                  'action': 'create',
                  'after': {'title': '补充讨论'},
                },
              ],
            },
            {
              'id': 'g2',
              'title': '提交材料',
              'operations': [
                {
                  'kind': 'item',
                  'action': 'create',
                  'after': {'title': '提交材料'},
                },
              ],
            },
          ],
          'impact': {
            'fixed_conflicts': [
              {
                'titles': ['组会', '班会'],
                'start_at': '2026-10-01T09:00:00+08:00',
                'end_at': '2026-10-01T10:00:00+08:00',
              },
            ],
          },
        },
      };
      final subsetImpact = run['preview']['impact'];
      run['preview']['impact'] = <String, dynamic>{};
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/selection-preview')) {
          return body({'impact': subsetImpact});
        }
        if (r.path.endsWith('/decision')) {
          decision = Map<String, dynamic>.from(r.data);
          return body({
            ...run,
            'status': 'applied',
            'receipt': {'semester_id': 's', 'revision': 1},
          });
        }
        return old.respond(r);
      });
      await mount(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: ChangeConfirmation(
              run: run,
              controller: agent,
              details: (_) => const SizedBox(),
            ),
          ),
        ),
      );
      expect(find.text('有时间冲突'), findsNothing);
      await ioTap(tester, find.text('提交材料'));
      await tester.pumpAndSettle();
      expect(find.text('保存 2 项'), findsOneWidget);
      expect(find.text('有时间冲突'), findsOneWidget);
      await capture(tester, 'agent-selected-group-conflict');
      await tester.tap(find.text('保留这些重叠安排'));
      await tester.pumpAndSettle();
      await ioTap(tester, find.text('保存 2 项'));
      expect(decision?['selected_group_ids'], ['g1']);
      expect(decision?['confirm_fixed_conflicts'], true);
      await tester.pumpWidget(const SizedBox());
      agent.dispose();
      f.c.dispose();
    },
  );

  testWidgets(
    'course occurrence lists render before and after without a map cast crash',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      final run = <String, dynamic>{
        'id': 'r',
        'text': '老师通知调课',
        'status': 'needs_confirmation',
        'cards': [],
        'preview': {
          'kind': 'course_change',
          'action': 'move',
          'token': 'course-token',
          'title': '概率论',
          'before': [
            {
              'title': '概率论',
              'start_at': '2026-10-01T09:00:00+08:00',
              'end_at': '2026-10-01T10:00:00+08:00',
              'location': 'A201',
            },
          ],
          'after': [
            {
              'title': '概率论',
              'start_at': '2026-10-02T09:00:00+08:00',
              'end_at': '2026-10-02T10:00:00+08:00',
              'location': 'B302',
            },
          ],
          'impact': {},
        },
      };
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/agent/threads?')) {
          return body([
            {'id': 't', 'title': '调课'},
          ]);
        }
        if (r.path.endsWith('/agent/threads/t')) {
          return body({
            'runs': [run],
          });
        }
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await mount(
        tester,
        AgentPage(controller: f.c, semester: {'id': 's'}, initialThreadId: 't'),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.text('原安排'), findsOneWidget);
      expect(find.text('新安排'), findsOneWidget);
      expect(find.text('A201'), findsOneWidget);
      expect(find.text('B302'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'agent-course-change');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  test(
    'undo request reuses its key after transport failure and restores a preview',
    () async {
      final f = ScheduleFixture();
      await f.c.bind('s');
      final c = AgentController(f.c, 's');
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      final keys = <String>[];
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/request-undo')) {
          keys.add(r.data['request_id']);
          if (keys.length == 1) throw StateError('transport failed');
          return body({
            'id': 'undo',
            'status': 'needs_confirmation',
            'preview': {
              'kind': 'undo',
              'source_run_id': 'source',
              'token': 'token',
            },
          });
        }
        return old.respond(r);
      });
      await c.requestUndo({'id': 'source'});
      await c.requestUndo({'id': 'source'});
      expect(keys.toSet().length, 1);
      expect(c.runs.single['status'], 'needs_confirmation');
      c.replace({'id': 'source', 'status': 'applied', 'undo_available': true});
      c.replace({
        'id': 'undo',
        'status': 'applied',
        'preview': {'kind': 'undo', 'source_run_id': 'source'},
      });
      expect(
        c.runs.firstWhere((r) => r['id'] == 'source')['undo_available'],
        false,
      );
      c.dispose();
      f.c.dispose();
    },
  );
}
