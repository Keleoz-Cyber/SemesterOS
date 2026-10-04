import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/ui/motion.dart' show SuccessCheckmark;
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'assistant_redesign_test.dart' show settled;
import 'planning_flow_test.dart' show ioTap;
import 'ui_polish_test.dart' show mount;

void main() {
  testWidgets(
    'confirming a course suspension renders the saved receipt and can request undo',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var confirmations = 0, undos = 0;
      var saved = false;
      final pending = <String, dynamic>{
        'id': 'r',
        'thread_id': 't',
        'text': '10月1日至7日全部停课',
        'status': 'needs_confirmation',
        'cards': [],
        'preview': {
          'kind': 'course_change',
          'action': 'suspend',
          'token': 'course-token',
          'semester_id': 's',
          'title': '国庆停课',
          'change_id': 'ch',
          'before': [
            for (var i = 0; i < 2; i++)
              {
                'id': 'c$i',
                'title': '课程${i + 1}',
                'start_at': '2026-10-0${i + 1}T08:30:00+08:00',
                'end_at': '2026-10-0${i + 1}T10:05:00+08:00',
              },
          ],
          'after': [],
          'impact': {'new_fixed_conflicts': []},
        },
      };
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/agent/threads/t')) {
          return body({
            'runs': [
              {
                ...pending,
                if (saved) 'status': 'applied',
                if (saved) 'undo_available': true,
              },
            ],
          });
        }
        if (r.path.endsWith('/agent/runs/r/decision')) {
          confirmations++;
          saved = true;
          return body({
            ...pending,
            'status': 'applied',
            'undo_available': true,
            'receipt': {
              'change_id': 'ch',
              'semester_id': 's',
              'revision': 1,
              'impact': {},
            },
          });
        }
        if (r.path.endsWith('/agent/runs/r/request-undo')) {
          undos++;
          return body({
            'id': 'u',
            'thread_id': 't',
            'text': '撤销这次操作',
            'status': 'needs_confirmation',
            'preview': {
              'kind': 'undo',
              'action': 'undo',
              'token': 'undo-token',
              'summary': [
                {'title': '国庆停课', 'detail': '恢复这两次课'},
              ],
            },
            'cards': [],
          });
        }
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await mount(
        tester,
        AgentPage(controller: f.c, semester: {'id': 's'}, initialThreadId: 't'),
      );
      await settled(tester);
      await tester.ensureVisible(find.text('确认停课'));
      await ioTap(tester, find.text('确认停课'));
      await settled(tester);
      expect(tester.takeException(), isNull);
      expect(confirmations, 1);
      expect(find.text('已停课 2 次'), findsOneWidget);
      expect(find.byType(SuccessCheckmark), findsOneWidget);
      await tester.ensureVisible(find.text('撤销'));
      await ioTap(tester, find.text('撤销'));
      await settled(tester);
      expect(undos, 1);
      expect(find.text('确认撤销'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await mount(
        tester,
        AgentPage(controller: f.c, semester: {'id': 's'}, initialThreadId: 't'),
      );
      await settled(tester);
      expect(find.text('已停课 2 次'), findsOneWidget);
      expect(find.byType(SuccessCheckmark), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
}
