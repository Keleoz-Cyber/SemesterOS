import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  setUpAll(loadPreviewFonts);
  for (final kind in ['candidate', 'joint-plan', 'failed-plan']) {
    testWidgets('backend feedback $kind is readable and truthful', (
      tester,
    ) async {
      final f = ScheduleFixture();
      final original = f.api.dio.httpClientAdapter as ControlledTransport;
      const failure = '按已保存的学习时段，最长连续空档为120分钟，放不下180分钟整段。更正和安排都未保存。';
      final run = <String, dynamic>{
        'id': 'r',
        'status': kind == 'joint-plan' ? 'needs_confirmation' : 'completed',
        'text': kind == 'candidate' ? '晚上有十分钟空闲吗？' : '更正剩余量并安排时间',
        'answer': kind == 'failed-plan' ? '错误的已保存说法' : '',
        'cards': [
          if (kind == 'candidate')
            {
              'kind': 'windows',
              'data': {
                'scope': 'calendar',
                'confirmed_count': 0,
                'needs_check_count': 1,
                'overview_answer': '有待核对时段，需确认彩排结束时间。',
                'windows': [
                  {
                    'start_at': '2026-10-07T22:00:00+08:00',
                    'end_at': '2026-10-08T00:00:00+08:00',
                    'needs_check': true,
                  },
                ],
              },
            },
          if (kind == 'failed-plan')
            {
              'kind': 'planning_result',
              'data': {
                'overview_answer': failure,
                'result': {'status': 'CHUNKING_LIMITED'},
              },
            },
        ],
        if (kind == 'joint-plan')
          'preview': {
            'kind': 'plan',
            'action': 'schedule',
            'token': 'token',
            'before': {
              'tasks': [
                {'id': 'task', 'title': '交材料'},
              ],
              'blocks': [],
            },
            'after': {
              'blocks': [
                {
                  'item_id': 'task',
                  'start_at': '2026-10-08T19:00:00+08:00',
                  'end_at': '2026-10-08T19:05:00+08:00',
                  'minutes': 5,
                },
              ],
              'remaining_updates': [
                {
                  'item_id': 'task',
                  'before_remaining_minutes': 10,
                  'remaining_minutes': 5,
                },
              ],
              'unarranged_minutes': 0,
            },
          },
      };
      f.api.dio.httpClientAdapter = ControlledTransport((request) async {
        if (request.path.endsWith('/agent/threads/t')) {
          return body({
            'runs': [run],
          });
        }
        return original.respond(request);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await mount(
        tester,
        AgentPage(controller: f.c, semester: {'id': 's'}, initialThreadId: 't'),
        width: 320,
        textScale: 1.4,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      if (kind == 'candidate') {
        expect(find.text('待核对时段'), findsOneWidget);
        expect(find.textContaining('需核对安排结束时间'), findsOneWidget);
      } else if (kind == 'joint-plan') {
        expect(find.text('交材料：预计剩余 10分钟 → 5分钟'), findsOneWidget);
        expect(find.byKey(const Key('agent-plan-confirm')), findsOneWidget);
      } else {
        expect(find.text('错误的已保存说法'), findsNothing);
        expect(find.textContaining('最长连续空档'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await capture(tester, 'backend-$kind');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });
  }
}
