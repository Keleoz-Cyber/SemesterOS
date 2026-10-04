import 'dart:async';
import 'package:dio/dio.dart' show ResponseBody;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/agent/agent_controller.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/features/agent/agent_widgets.dart';
import 'package:semester_os/features/agent/workflow_cards.dart';
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'api_session_test.dart' show ControlledTransport, body;
import 'planning_flow_test.dart' show ioTap;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;
import 'inline_agent_flow_test.dart' show VoiceFixture;
import 'package:semester_os/features/media/drafts.dart';

Future<void> settled(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets('free windows expand and page without another model turn', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    var pages = 0;
    Map<String, dynamic> window(int hour) => {
      'start_at': '2026-10-02T${hour.toString().padLeft(2, '0')}:00:00+08:00',
      'end_at':
          '2026-10-02T${(hour + 1).toString().padLeft(2, '0')}:00:00+08:00',
    };
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/agent/threads/t')) {
        return body({
          'runs': [
            {
              'id': 'r',
              'text': '本周什么时候有空',
              'status': 'completed',
              'cards': [
                {
                  'card_id': 'windows',
                  'kind': 'windows',
                  'total_count': 8,
                  'has_more': true,
                  'next_offset': 5,
                  'data': {
                    'windows': [for (var i = 9; i < 14; i++) window(i)],
                  },
                },
              ],
            },
          ],
        });
      }
      if (r.path.endsWith('/agent/runs/r/cards/windows')) {
        pages++;
        expect(r.method, 'GET');
        expect(r.queryParameters['offset'], 5);
        return body({
          'card': {
            'card_id': 'windows',
            'kind': 'windows',
            'total_count': 8,
            'data': {
              'windows': [for (var i = 14; i < 17; i++) window(i)],
            },
          },
          'has_more': false,
          'next_offset': null,
        });
      }
      if (r.path.endsWith('/turns')) {
        fail('Viewing more does not ask the model again');
      }
      return old.respond(r);
    });
    await tester.runAsync(() => f.c.bind('s'));
    await mount(
      tester,
      AgentPage(controller: f.c, semester: {'id': 's'}, initialThreadId: 't'),
    );
    await settled(tester);
    await ioTap(tester, find.text('再显示2项'));
    await tester.ensureVisible(find.text('查看更多'));
    await ioTap(tester, find.text('查看更多'));
    await settled(tester);
    expect(pages, 1);
    expect(find.textContaining('16:00'), findsWidgets);
    expect(find.text('查看更多'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
  testWidgets(
    'cancel editing after history switch restores that conversation draft',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/agent/history')) {
          return body({
            'threads': [
              {'id': 'b', 'title': '对话B'},
              {'id': 'a', 'title': '对话A'},
            ],
            'has_more': false,
          });
        }
        if (r.path.contains('/agent/threads/')) {
          final id = r.path.split('/').last;
          return body({
            'runs': [
              {
                'id': 'r$id',
                'thread_id': id,
                'text': '问题$id',
                'status': 'completed',
                'cards': [],
              },
            ],
          });
        }
        return old.respond(r);
      });
      await tester.runAsync(() async {
        await f.c.bind('s');
        final drafts = CaptureDrafts(f.c.cache, 'preview', () => true);
        await drafts.save('assistant:s', {'text': 'A未发送的草稿'});
        await drafts.save('assistant:s:thread:b', {'text': 'B未发送的草稿'});
      });
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
                    semester: {'id': 's'},
                    initialThreadId: 'a',
                  ),
                ),
              ),
              child: const Text('打开助手'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开助手'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
      }
      await settled(tester);
      await ioTap(tester, find.byTooltip('编辑并重发'));
      await ioTap(tester, find.byTooltip('最近对话'));
      await settled(tester);
      await ioTap(tester, find.text('对话B'));
      await settled(tester);
      await ioTap(tester, find.byTooltip('编辑并重发'));
      await ioTap(tester, find.byTooltip('取消编辑'));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'B未发送的草稿',
      );
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  test(
    'lazy cards read the same query and ignore a response after changing conversation',
    () async {
      final f = ScheduleFixture();
      f.c.semesterId = 's';
      final wait = Completer<ResponseBody>();
      var reads = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        expect(r.method, 'GET');
        reads++;
        expect(r.path, '/api/v1/agent/runs/r/cards/card');
        expect(r.queryParameters['offset'], 5);
        return wait.future;
      });
      final c = AgentController(f.c, 's');
      await c.open(fresh: true);
      final card = {
        'card_id': 'card',
        'kind': 'records',
        'has_more': true,
        'next_offset': 5,
        'data': {
          'records': [
            {'id': 'a', 'title': '组会'},
          ],
        },
      };
      c.runs = [
        {
          'id': 'r',
          'cards': [card],
        },
      ];
      final loading = c.loadCard('r', card);
      await Future<void>.delayed(Duration.zero);
      await c.open(fresh: true);
      wait.complete(
        body({
          'card': {
            ...card,
            'data': {
              'records': [
                {'id': 'b'},
              ],
            },
          },
          'has_more': false,
        }),
      );
      await loading;
      expect(c.runs, isEmpty);
      expect(reads, 1);
      c.dispose();
      f.c.dispose();
    },
  );
  test(
    'editing a question forks once without undoing saved business data',
    () async {
      final f = ScheduleFixture();
      f.c.semesterId = 's';
      final calls = <String>[];
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        calls.add(r.path);
        if (r.path.endsWith('/revise')) {
          return body({
            'id': 'new',
            'thread_id': 'fork',
            'status': 'completed',
            'text': r.data['text'],
          });
        }
        return body({
          'runs': [
            {'id': 'new', 'thread_id': 'fork', 'status': 'completed'},
          ],
        });
      });
      final c = AgentController(f.c, 's');
      await c.open(fresh: true);
      expect(
        await c.revise({'id': 'old', 'status': 'applied'}, '明天组会改为线上'),
        isTrue,
      );
      expect(c.threadId, 'fork');
      expect(calls.where((p) => p.contains('/undo')), isEmpty);
      expect(calls.where((p) => p.endsWith('/revise')).length, 1);
      c.dispose();
      f.c.dispose();
    },
  );
  testWidgets(
    'cold entry has no history request, keyboard and voice share one composer',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var history = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/agent/')) {
          history++;
          return body({'threads': [], 'has_more': false});
        }
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await mount(
        tester,
        AgentPage(
          controller: f.c,
          semester: {'id': 's', 'name': '第一学期'},
          voiceInput: VoiceFixture('unused'),
        ),
      );
      await settled(tester);
      expect(history, 0);
      await capture(tester, 'assistant-empty');
      await tester.enterText(
        find.byKey(const Key('agent-input')),
        '明天下午四点开组会，地点等通知',
      );
      await tester.tap(find.byTooltip('切换语音输入'));
      await tester.pumpAndSettle();
      expect(find.text('按住说话'), findsOneWidget);
      expect(find.text('语音记录'), findsNothing); // no separate recording screen
      await capture(tester, 'assistant-inline-voice');
      await tester.tap(find.byTooltip('切换键盘输入'));
      await tester.pumpAndSettle();
      expect(find.text('明天下午四点开组会，地点等通知'), findsOneWidget);
      await ioTap(tester, find.byTooltip('最近对话'));
      await settled(tester);
      expect(history, 1);
      expect(find.text('还没有历史对话'), findsOneWidget);
      await capture(tester, 'assistant-history-empty');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  for (final size in [
    (375.0, 812.0, 1.0),
    (320.0, 740.0, 1.6),
    (740.0, 390.0, 1.0),
  ]) {
    testWidgets('notice preview stays sparse and usable at $size', (
      tester,
    ) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/agent/threads/t')) {
          return body({
            'runs': [
              {
                'id': 'r',
                'status': 'needs_confirmation',
                'text': '班级通知：方便的时候把报名表发给负责人，不用急。',
                'answer': '整理为**提交报名表**，没有指定截止时间。',
                'cards': [],
                'preview': {
                  'kind': 'item',
                  'action': 'create',
                  'token': 'token',
                  'provided_fields': ['title', 'details', 'time'],
                  'after': {
                    'title': '提交报名表',
                    'kind': 'task',
                    'certainty': 'formal',
                    'priority': 'normal',
                    'start_policy': 'unconfirmed',
                    'time': {'precision': 'unknown', 'expression': '方便的时候'},
                    'details': {
                      'recipient': '班级负责人',
                      'materials': ['报名表'],
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
        AgentPage(controller: f.c, semester: {'id': 's'}, initialThreadId: 't'),
        width: size.$1,
        height: size.$2,
        textScale: size.$3,
      );
      await settled(tester);
      expect(find.text('时间待确认'), findsNothing);
      expect(find.text('暂无'), findsNothing);
      expect(find.text('普通'), findsNothing);
      expect(find.text('更多信息'), findsNothing);
      await tester.ensureVisible(find.text('确认添加'));
      await tester.pumpAndSettle();
      expect(find.text('确认添加').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'assistant-notice-${size.$1}-${size.$3}');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });
  }
  testWidgets(
    'assistant setup and saved actions keep readable narrow layouts',
    (tester) async {
      final f = ScheduleFixture();
      for (final size in [(375.0, 1.0), (320.0, 1.6)]) {
        await mount(
          tester,
          Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                ScheduleSetupCard(
                  controller: f.c,
                  data: {
                    'tasks': [
                      {
                        'id': 'a',
                        'title': '完成计算机网络课程设计与实验报告',
                        'remaining_minutes': 120,
                      },
                      {'id': 'b', 'title': '复习概率论', 'remaining_minutes': 40},
                    ],
                    'availability': {
                      'needs_confirmation': true,
                      'candidate': {
                        'weekly': [
                          {'weekday': 1, 'start': '19:00', 'end': '21:00'},
                          {'weekday': 3, 'start': '19:00', 'end': '21:00'},
                        ],
                      },
                    },
                  },
                  onReady: () async {},
                ),
                AssistantSavedAction(
                  text: '已保存 2 项安排，可继续修改',
                  onOpen: () {},
                  onUndo: () {},
                ),
              ],
            ),
          ),
          width: size.$1,
          textScale: size.$2,
        );
        expect(tester.takeException(), isNull);
        await capture(tester, 'assistant-workflow-${size.$1}-${size.$2}');
        await tester.ensureVisible(find.text('撤销'));
        await tester.pumpAndSettle();
        expect(find.text('撤销').hitTestable(), findsOneWidget);
        await capture(tester, 'assistant-saved-${size.$1}-${size.$2}');
        await tester.pumpWidget(const SizedBox());
      }
      f.c.dispose();
    },
  );
}
