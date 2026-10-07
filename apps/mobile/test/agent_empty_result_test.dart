import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  setUpAll(loadPreviewFonts);
  for (final detail in [false, true]) {
    testWidgets(
      'free query ${detail ? 'preserves requested detail' : 'shows one verified overview'}',
      (tester) async {
        final f = ScheduleFixture();
        final prior = f.api.dio.httpClientAdapter as ControlledTransport;
        const original = '这是模型可能输出的完整列表。';
        const overview = '已查到周四、周五有一小时空档。';
        f.api.dio.httpClientAdapter = ControlledTransport((r) async {
          if (r.path.endsWith('/agent/threads/t')) {
            return body({
              'runs': [
                {
                  'id': 'r',
                  'status': 'completed',
                  'text': '这周哪天有一小时空闲？',
                  'answer': original,
                  'cards': [
                    {
                      'kind': 'windows',
                      'data': {
                        'scope': 'calendar',
                        'answer_style': detail ? 'detail' : 'summary',
                        'overview_answer': overview,
                        'windows': [
                          {
                            'start_at': '2026-10-08T08:00:00+08:00',
                            'end_at': '2026-10-08T09:00:00+08:00',
                          },
                        ],
                      },
                    },
                  ],
                },
              ],
            });
          }
          return prior.respond(r);
        });
        await tester.runAsync(() => f.c.bind('s'));
        await mount(
          tester,
          AgentPage(
            controller: f.c,
            semester: {'id': 's'},
            initialThreadId: 't',
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
        expect(find.text(original), detail ? findsOneWidget : findsNothing);
        expect(find.text(overview), detail ? findsNothing : findsOneWidget);
        if (!detail) {
          await tester.tap(find.text('更多说明'));
          await tester.pumpAndSettle();
          expect(find.text(original), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        f.c.dispose();
      },
    );
  }
  testWidgets(
    'completed empty queries avoid duplicate cards but preserve facts and diagnostics',
    (tester) async {
      for (final mode in [
        'empty',
        'windows',
        'records',
        'occurrences',
        'nonempty',
        'no-answer',
        'warning',
        'stale',
        'error',
        'paging',
      ]) {
        final f = ScheduleFixture();
        final previous = f.api.dio.httpClientAdapter as ControlledTransport;
        final card = {
          'card_id': 'q',
          'kind': mode == 'windows'
              ? 'windows'
              : mode == 'records'
              ? 'records'
              : mode == 'occurrences'
              ? 'course_occurrences'
              : 'calendar',
          'total_count': mode == 'nonempty' || mode == 'paging' ? 1 : 0,
          'has_more': mode == 'paging',
          'data': {
            'from_date': '2026-10-04',
            'to_date': '2026-10-04',
            'entries': mode == 'nonempty'
                ? [
                    {
                      'id': 'e',
                      'resource_type': 'event',
                      'title': '组会',
                      'date': '2026-10-04',
                    },
                  ]
                : [],
            'undated': [],
            'records': [],
            'occurrences': [],
            'windows': [],
            'fixed_conflicts': [],
            'categories': [
              {'id': 'study', 'name': '学习'},
            ],
            if (mode == 'warning') 'warnings': ['资料尚未同步'],
            if (mode == 'stale') 'stale': true,
            if (mode == 'error') 'error': '查询未完整返回',
          },
        };
        f.api.dio.httpClientAdapter = ControlledTransport((request) async {
          if (request.path.endsWith('/agent/threads/t')) {
            return body({
              'runs': [
                {
                  'id': 'r',
                  'status': 'completed',
                  'text': '明天有什么安排？',
                  'answer': mode == 'no-answer' ? '' : '明天没有安排。',
                  'cards': [card],
                },
              ],
            });
          }
          return previous.respond(request);
        });
        await tester.runAsync(() => f.c.bind('s'));
        await mount(
          tester,
          AgentPage(
            controller: f.c,
            semester: {'id': 's'},
            initialThreadId: 't',
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
        final cleanEmpty = {
          'empty',
          'records',
          'occurrences',
          'windows',
        }.contains(mode);
        if (mode == 'windows') expect(find.text('可用时段'), findsNothing);
        if (mode != 'no-answer') expect(find.text('明天没有安排。'), findsOneWidget);
        expect(find.text('相关安排'), cleanEmpty ? findsNothing : findsOneWidget);
        expect(
          find.text('没有查到匹配的安排'),
          cleanEmpty || mode == 'nonempty' || mode == 'paging'
              ? findsNothing
              : findsOneWidget,
        );
        if (!cleanEmpty) {
          expect(
            find.text('10月4日'),
            mode == 'nonempty' ? findsNWidgets(2) : findsOneWidget,
          );
          expect(find.text('10月4日 — 10月4日'), findsNothing);
        }
        if (mode == 'nonempty') expect(find.text('组会'), findsOneWidget);
        if (mode == 'paging') expect(find.text('查看更多 · 共1项'), findsOneWidget);
        if (mode == 'empty' || mode == 'nonempty') {
          await capture(tester, 'empty-result-$mode');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        f.c.dispose();
      }
    },
  );
}
