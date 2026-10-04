import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/features/agent/agent_motion.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

Future<void> io(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 90)),
  );
  await tester.pump();
}

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets(
    'a real poll reveals the complete reply once and old history stays static',
    (tester) async {
      final f = ScheduleFixture();
      final previous = f.api.dio.httpClientAdapter as ControlledTransport;
      var phase = 0;
      Map<String, dynamic> run() => {
        'id': 'r',
        'thread_id': 't',
        'sequence': phase + 1,
        'text': '明天下午四点开组会，地点6412',
        'status': phase < 2 ? 'running' : 'needs_confirmation',
        'stage': phase == 0 ? '正在理解通知' : '正在核对时间',
        'answer': phase < 2 ? '' : '**组会**已整理，核对后添加。',
        'cards': [],
        if (phase == 2)
          'preview': {
            'kind': 'item',
            'action': 'create',
            'token': 'p',
            'provided_fields': ['title', 'time', 'location'],
            'after': {
              'title': '组会',
              'kind': 'event',
              'certainty': 'formal',
              'time': {'at': '2026-10-04T16:00:00+08:00', 'meaning': 'start'},
              'location': '6412',
            },
          },
      };
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/agent/threads/t')) {
          return body({
            'runs': [run()],
          });
        }
        if (r.path.endsWith('/agent/runs/r')) return body(run());
        if (r.path.endsWith('/agent/history')) {
          return body({
            'threads': [
              {
                'id': 't',
                'title': '继续这段对话',
                'updated_at': '2026-10-03T10:00:00+08:00',
              },
            ],
            'has_more': false,
          });
        }
        return previous.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AgentPage(
                    controller: f.c,
                    semester: {'id': 's', 'name': '第一学期'},
                    initialThreadId: 't',
                  ),
                ),
              ),
              child: const Text('打开对话'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开对话'));
      await io(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await capture(tester, '01-understanding');
      phase = 1;
      await tester.pump(const Duration(seconds: 2));
      await io(tester);
      await capture(tester, '02-stage-transition');
      phase = 2;
      await tester.pump(const Duration(seconds: 2));
      await io(tester);
      expect(find.text('确认添加'), findsOneWidget);
      // No fake streamed substring: the entire returned reply and preview exist
      // in the first frame that accepts the server's completed snapshot.
      final response = find
          .descendant(
            of: find.byKey(const ValueKey('agent-response-r')),
            matching: find.byType(FadeTransition),
          )
          .first;
      expect(
        tester.widget<FadeTransition>(response).opacity.value,
        lessThan(1),
      );
      await capture(tester, '03-response-start');
      await tester.pump(const Duration(milliseconds: 70));
      await capture(tester, '04-response-mid');
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.widget<FadeTransition>(response).opacity.value, 1);
      await capture(tester, '05-response-ready');
      await tester.tap(find.byTooltip('最近对话'));
      await io(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('继续这段对话'));
      await io(tester);
      await io(tester);
      await io(tester);
      await tester.pumpAndSettle();
      expect(tester.widget<FadeTransition>(response).opacity.value, 1);
      expect(tester.takeException(), isNull);
      await capture(tester, '06-history-static');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'arrival preserves geometry and finishes offstage or with reduced motion',
    (tester) async {
      late StateSetter update;
      var revision = 'old', offstage = false, reduced = false;
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, set) {
            update = set;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: TickerMode(
                enabled: !offstage,
                child: Scaffold(
                  body: SizedBox(
                    width: 300,
                    height: 160,
                    key: const Key('natural-size'),
                    child: AssistantArrival(
                      revision: revision,
                      child: SelectableText('完整回复 $revision'),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      final before = tester.getRect(find.byKey(const Key('natural-size')));
      update(() => revision = 'new');
      await tester.pump();
      expect(find.text('完整回复 new'), findsOneWidget);
      final fade = find.byType(FadeTransition).last;
      expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(1));
      expect(tester.getRect(find.byKey(const Key('natural-size'))), before);
      update(() => offstage = true);
      await tester.pump();
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      update(() {
        offstage = false;
        reduced = true;
        revision = 'reduced';
      });
      await tester.pump();
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      update(() {
        reduced = false;
        revision = 'background';
      });
      await tester.pump();
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
