import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/agent/agent_controller.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/features/agent/conversation_session.dart';
import 'package:semester_os/features/media/drafts.dart';
import 'package:semester_os/features/media/inline_capture_controller.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'controller_test.dart' show MemoryStore;
import 'planning_flow_test.dart' show ioTap;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount, loadPreviewFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);

  testWidgets(
    'history deletion disappears after confirmation without recovery',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var deleted = false, deleteRequests = 0;
      final thread = {'id': 'history-t', 'title': '合成对话'};
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/agent/history')) {
          expect(r.queryParameters.containsKey('deleted'), isFalse);
          return body({
            'threads': deleted ? [] : [thread],
            'has_more': false,
          });
        }
        if (r.path.endsWith('/agent/threads/history-t')) {
          if (r.method == 'DELETE') {
            deleteRequests++;
            deleted = true;
            return body({...thread, 'deleted_at': '2026-10-08T06:00:00Z'});
          }
          return body({
            'semester_id': 's',
            'runs': [
              {
                'id': 'history-r',
                'status': 'completed',
                'text': '合成旧消息',
                'answer': '合成旧回答',
                'cards': [],
              },
            ],
          });
        }
        expect(r.path.endsWith('/restore'), isFalse);
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await mount(
        tester,
        AgentPage(
          controller: f.c,
          semester: const {'id': 's'},
          initialThreadId: 'history-t',
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      await ioTap(tester, find.byTooltip('最近对话'));
      expect(find.text('已删除对话'), findsNothing);
      expect(find.text('合成对话'), findsOneWidget);
      await ioTap(tester, find.byTooltip('删除对话'));
      expect(find.textContaining('删除后无法恢复'), findsOneWidget);
      await ioTap(tester, find.text('保留'));
      expect(deleteRequests, 0);
      expect(find.text('合成对话'), findsOneWidget);
      await ioTap(tester, find.byTooltip('删除对话'));
      await ioTap(tester, find.text('删除对话'));
      expect(deleteRequests, 1);
      expect(find.text('合成对话'), findsNothing);
      expect(find.text('还没有历史对话'), findsOneWidget);
      expect(find.text('撤销'), findsNothing);
      expect(find.text('恢复'), findsNothing);
      await ioTap(tester, find.byTooltip('返回对话'));
      expect(find.text('合成旧消息'), findsNothing);
      expect(find.text('合成旧回答'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  test(
    'deleting current conversation invalidates late history responses',
    () async {
      final f = ScheduleFixture();
      f.c.semesterId = 's';
      final historyEntered = Completer<void>();
      final lateHistory = Completer<ResponseBody>();
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/agent/history')) {
          historyEntered.complete();
          return lateHistory.future;
        }
        expect(r.method, 'DELETE');
        expect(r.path.endsWith('/agent/threads/removed'), isTrue);
        return body({'id': 'removed', 'deleted_at': '2026-10-08T06:00:00Z'});
      });
      final c = AgentController(f.c, 's')
        ..threadId = 'removed'
        ..threads = [
          {'id': 'removed'},
          {'id': 'kept'},
        ]
        ..runs = [
          {'id': 'removed-run', 'status': 'running'},
        ];
      final loading = c.loadHistory(reset: true);
      await historyEntered.future;
      expect(await c.deleteThread('removed'), isTrue);
      lateHistory.complete(
        body({
          'threads': [
            {'id': 'removed'},
          ],
          'has_more': false,
        }),
      );
      await loading;
      expect(c.threads.map((row) => row['id']), ['kept']);
      expect(c.threadId, isNull);
      expect(c.runs, isEmpty);
      expect(c.historyLoading, isFalse);
      expect(c.processing, isFalse);
      c.dispose();
      f.c.dispose();
    },
  );

  testWidgets(
    'nested assistant deletion retires covered media and late responses',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      final pollEntered = Completer<void>();
      final delayedRun = Completer<ResponseBody>();
      final recognitionEntered = Completer<void>();
      final delayedRecognition = Completer<ResponseBody>();
      var deleted = false;
      final oldRun = <String, dynamic>{
        'id': 'nested-r',
        'thread_id': 'nested-t',
        'status': 'completed',
        'text': '旧对话消息',
        'answer': '旧对话回答',
        'cards': [],
      };
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/agent/threads/nested-t')) {
          if (r.method == 'DELETE') {
            deleted = true;
            return body({
              'id': 'nested-t',
              'deleted_at': '2026-10-08T06:00:00Z',
            });
          }
          return body({
            'semester_id': 's',
            'runs': [oldRun],
          });
        }
        if (r.path.endsWith('/agent/history')) {
          return body({
            'threads': deleted
                ? []
                : [
                    {'id': 'nested-t', 'title': '覆盖层之前的对话'},
                  ],
            'has_more': false,
          });
        }
        if (r.path.endsWith('/agent/runs/nested-r')) {
          pollEntered.complete();
          return delayedRun.future;
        }
        if (r.path.endsWith('/sources/nested-source')) {
          expect(r.method, 'GET');
          recognitionEntered.complete();
          return delayedRecognition.future;
        }
        expect(r.path.endsWith('/sources/nested-source/cancel'), isFalse);
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      final draftStore = CaptureDrafts(f.c.cache, f.c.owner!, () => true);
      await mount(
        tester,
        AgentPage(
          controller: f.c,
          semester: const {'id': 's'},
          initialThreadId: 'nested-t',
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      final coveredMedia =
          (tester.state(find.byType(AgentPage)) as dynamic).media
              as InlineCaptureController;
      late Future<void> recognizing;
      await tester.runAsync(() async {
        await draftStore.save('inline:s:assistant:s', {
          'kind': 'audio',
          'source': {
            'id': 'nested-source',
            'semester_id': 's',
            'kind': 'audio',
            'status': 'running',
            'version': 1,
            'reference_at': '2026-10-08T06:00:00Z',
          },
        });
        await draftStore.save('inline:s:independent', {
          'local': '/shared-independent.wav',
          'kind': 'audio',
        });
        recognizing = coveredMedia.restore(scope: 'assistant:s');
        await Future<void>.delayed(const Duration(milliseconds: 35));
      });
      for (
        var frame = 0;
        frame < 4 && !recognitionEntered.isCompleted;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 35)),
        );
      }
      expect(
        recognitionEntered.isCompleted,
        isTrue,
        reason:
            'Pending recognition must issue its held status read before deletion',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(coveredMedia.hasPending, isTrue);
      final coveredController = tester
          .widgetList<AnimatedBuilder>(find.byType(AnimatedBuilder))
          .map((widget) => widget.animation)
          .whereType<AgentController>()
          .single;
      await tester.enterText(find.byType(TextField), '删除后不能复活的草稿');
      coveredController.runs = [
        {...oldRun, 'status': 'running'},
      ];
      late Future<void> polling;
      await tester.runAsync(() async {
        polling = coveredController.poll();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(pollEntered.isCompleted, isTrue);
      });
      final navigator = Navigator.of(tester.element(find.byType(AgentPage)));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => AgentPage(
              controller: f.c,
              semester: const {'id': 's'},
              initialText: '另一个事项的独立草稿',
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final secondPage = tester.state(find.byType(AgentPage)) as dynamic;
      for (var step = 0; step < 8 && secondPage.media.busy; step++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        secondPage.media.busy,
        isFalse,
        reason: 'Independent context must finish its empty restore',
      );
      await ioTap(tester, find.byTooltip('最近对话'));
      await ioTap(tester, find.byTooltip('删除对话'));
      await ioTap(tester, find.text('删除对话'));
      expect(coveredController.threadId, isNull);
      expect(coveredController.runs, isEmpty);
      expect(coveredMedia.hasPending, isFalse);
      expect(coveredMedia.busy, isFalse);
      expect(coveredMedia.phase, 'idle');
      expect(coveredMedia.error, isNull);
      await tester.runAsync(() async {
        delayedRun.complete(body(oldRun));
        delayedRecognition.complete(
          body({
            'id': 'nested-source',
            'semester_id': 's',
            'kind': 'audio',
            'status': 'recognized',
            'version': 2,
            'text': '不能复活的迟到识别文字',
            'reference_at': '2026-10-08T06:00:00Z',
          }),
        );
        await polling;
        await recognizing;
      });
      expect(coveredController.runs, isEmpty);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('旧对话消息'), findsNothing);
      expect(find.text('旧对话回答'), findsNothing);
      expect(find.text('不能复活的迟到识别文字'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      expect(
        await tester.runAsync(
          () => draftStore.read('assistant:s:thread:nested-t'),
        ),
        isNull,
      );
      final emptyDraft = await tester.runAsync(
        () => draftStore.read('assistant:s'),
      );
      expect(emptyDraft?['thread_id'], isNull);
      expect(emptyDraft?['editing_run'], isNull);
      expect(emptyDraft?['text'], isEmpty);
      expect(emptyDraft?['pending_media'], isFalse);
      expect(
        await tester.runAsync(() => draftStore.read('inline:s:assistant:s')),
        isNull,
      );
      final independentMedia = await tester.runAsync(
        () => draftStore.read('inline:s:independent'),
      );
      expect(independentMedia?['local'], '/shared-independent.wav');
      final independentKey =
          'assistant-context:s:${base64Url.encode(utf8.encode('另一个事项的独立草稿'))}';
      final independentDraft = await tester.runAsync(
        () => draftStore.read(independentKey),
      );
      expect(independentDraft?['text'], '另一个事项的独立草稿');
      f.c.dispose();
    },
  );

  test(
    'deleted conversation retires matching session and draft references only',
    () async {
      final client = Object();
      ConversationSession context(String semester, String scope, String id) =>
          ConversationSessions.forContext(
              client,
              owner: 'a',
              generation: 1,
              semester: semester,
              context: scope,
            )
            ..threadId = id
            ..editingRun = {'id': 'run'}
            ..editBackup = {'text': 'draft'};
      final first = context('s', 'assistant:s', 'removed');
      final second = context('s', 'assistant-context:s:linked', 'removed');
      final kept = context('s', 'assistant-context:s:kept', 'kept');
      final otherSemester = context('other', 'assistant:other', 'removed');
      ConversationSessions.forgetThread(
        client,
        owner: 'a',
        generation: 2,
        semester: 's',
        threadId: 'removed',
      );
      expect(first.threadId, 'removed');
      ConversationSessions.forgetThread(
        client,
        owner: 'a',
        generation: 1,
        semester: 's',
        threadId: 'removed',
      );
      expect(first.threadId, isNull);
      expect(second.threadId, isNull);
      expect(first.editingRun, isNull);
      expect(second.editBackup, isNull);
      expect(kept.threadId, 'kept');
      expect(otherSemester.threadId, 'removed');
      final cache = MemoryStore();
      await cache.write('capture:a', {
        'assistant:s': {'thread_id': 'removed', 'text': 'draft'},
        'assistant:s:thread:removed': {'thread_id': 'removed'},
        'assistant-context:s:linked': {'thread_id': 'removed'},
        'assistant-context-latest:s': {'key': 'assistant-context:s:linked'},
        'assistant-context:s:kept': {'thread_id': 'kept'},
        'assistant:other': {'thread_id': 'removed'},
        'inline:s': {'local': '/shared-source.wav'},
      });
      await CaptureDrafts(
        cache,
        'a',
        () => true,
      ).clearConversation('s', 'removed');
      expect((await cache.read('capture:a'))!.keys.toSet(), {
        'assistant-context:s:kept',
        'assistant:other',
        'inline:s',
      });
    },
  );
}
