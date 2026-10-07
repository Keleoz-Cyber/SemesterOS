import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/features/agent/agent_controller.dart';
import 'package:semester_os/ui/assistant_scope.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount, loadPreviewFonts, capture;
import 'planning_flow_test.dart' show ioTap;

Future<void> ready(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 90)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadPreviewFonts);
  final context = AssistantBrowsingContext(
    startDate: DateTime(2026, 10, 9),
    endDate: DateTime(2026, 10, 9),
  );
  for (final remove in [false, true]) {
    testWidgets(
      'visible page context is ${remove ? 'removable' : 'sent with this turn'}',
      (tester) async {
        final f = ScheduleFixture();
        final previous = f.api.dio.httpClientAdapter as ControlledTransport;
        Map<String, dynamic>? sent;
        f.api.dio.httpClientAdapter = ControlledTransport((r) async {
          if (r.path.endsWith('/agent/threads') && r.method == 'POST') {
            return body({'id': 't'});
          }
          if (r.path.endsWith('/turns')) {
            sent = Map<String, dynamic>.from(r.data);
            return body({
              'id': 'r',
              'thread_id': 't',
              'status': 'completed',
              'text': sent!['text'],
              'cards': [],
              'browsing_context': sent!['browsing_context'],
            });
          }
          return previous.respond(r);
        });
        await tester.runAsync(() => f.c.bind('s'));
        await mount(
          tester,
          AgentPage(
            controller: f.c,
            semester: {'id': 's'},
            initialText: '这天有什么课？',
            browsingContext: context,
          ),
          width: 320,
          textScale: 1.4,
        );
        await ready(tester);
        expect(find.text('浏览：${context.label}'), findsOneWidget);
        await capture(
          tester,
          'agent-context-${remove ? 'remove' : 'keep'}-before',
        );
        if (remove) {
          await tester.tap(find.byTooltip('移除浏览日期'));
          await tester.pumpAndSettle();
          expect(find.text('浏览：${context.label}'), findsNothing);
        }
        await ioTap(tester, find.byTooltip('发送'));
        expect(sent?['text'], '这天有什么课？');
        expect(sent?['browsing_context'], remove ? isNull : context.toJson());
        await capture(
          tester,
          'agent-context-${remove ? 'remove' : 'keep'}-sent',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        f.c.dispose();
      },
    );
  }
  test(
    'editing a notice keeps input kind and uses only explicit page context',
    () async {
      final f = ScheduleFixture();
      final previous = f.api.dio.httpClientAdapter as ControlledTransport;
      Map<String, dynamic>? sent;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/revise')) {
          sent = Map<String, dynamic>.from(r.data);
          return body({
            'id': 'edited',
            'thread_id': 'branch',
            'status': 'completed',
            'cards': [],
          });
        }
        if (r.path.endsWith('/agent/threads/branch')) return body({'runs': []});
        return previous.respond(r);
      });
      await f.c.bind('s');
      final c = AgentController(f.c, 's');
      expect(
        await c.revise(
          {'id': 'old'},
          '通知原文',
          inputKind: 'notice',
          browsingContext: context,
        ),
        isTrue,
      );
      expect(sent?['input_kind'], 'notice');
      expect(sent?['browsing_context'], context.toJson());
      expect(
        await c.revise({'id': 'old'}, '修改后的通知', inputKind: 'notice'),
        isTrue,
      );
      expect(sent?.containsKey('browsing_context'), isFalse);
      c.dispose();
      f.c.dispose();
    },
  );
}
