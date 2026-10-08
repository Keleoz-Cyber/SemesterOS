import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/features/media/hold_voice_button.dart';
import 'package:semester_os/features/media/drafts.dart';
import 'package:semester_os/ui/app_sheet.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'media_flow_test.dart' show MediaTestPaths;
import 'centers_flow_test.dart' show settleIo;
import 'ui_polish_test.dart' show mount, loadPreviewFonts;

bool hitIncludes(HitTestResult result, RenderObject target) =>
    result.path.any((entry) {
      if (entry.target is! RenderObject) return false;
      RenderObject? node = entry.target as RenderObject;
      while (node != null) {
        if (identical(node, target)) return true;
        node = node.parent;
      }
      return false;
    });

String hitDescription(HitTestResult result) => result.path
    .map(
      (entry) =>
          '${entry.target.runtimeType}: '
          '${entry.target is RenderObject ? (entry.target as RenderObject).debugCreator : entry.target}',
    )
    .join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  for (final morph in [false, true]) {
    testWidgets(
      'real AgentPage footer and history retain hit geometry, morph=$morph',
      (tester) async {
        final folder = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('sheet-hit-'),
        ))!;
        final oldPaths = PathProviderPlatform.instance;
        PathProviderPlatform.instance = MediaTestPaths(folder.path);
        final f = ScheduleFixture();
        var initialThreadReads = 0;
        final original = f.api.dio.httpClientAdapter as ControlledTransport;
        f.api.dio.httpClientAdapter = ControlledTransport((request) async {
          if (request.path.endsWith('/agent/history')) {
            return body({
              'threads': [
                {
                  'id': 'history-hit',
                  'title': '有真实历史消息',
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                },
              ],
              'has_more': false,
            });
          }
          if (request.path.contains('/agent/threads/')) {
            if (request.path.endsWith('/agent/threads/current-hit')) {
              initialThreadReads++;
            }
            return body({
              'semester_id': 's',
              'runs': request.path.endsWith('/history-hit')
                  ? [
                      {
                        'id': 'hit-run',
                        'thread_id': 'history-hit',
                        'status': 'completed',
                        'text': '历史问题确实存在',
                        'answer': '历史回复确实存在',
                        'cards': [],
                      },
                    ]
                  : [],
              'has_more': false,
            });
          }
          return original.respond(request);
        });
        addTearDown(() async {
          PathProviderPlatform.instance = oldPaths;
          f.c.dispose();
          f.api.dio.close();
          await folder.delete(recursive: true);
        });
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetPadding);
        await tester.runAsync(() async {
          await f.c.bind('s');
          await CaptureDrafts(f.c.cache, 'preview', () => true).save(
            'assistant:s',
            {'text': '', 'pending_media': false, 'image_paths': <String>[]},
          );
        });
        await mount(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAppSheet<void>(
                  context: context,
                  heightFactor: .9,
                  originRect: morph
                      ? const Rect.fromLTWH(325, 750, 52, 52)
                      : null,
                  builder: (_) => AgentPage(
                    controller: f.c,
                    semester: const {'id': 's', 'name': '学期'},
                    embedded: true,
                    initialMediaKind: 'audio',
                    initialThreadId: 'current-hit',
                    autofocus: false,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        );
        tester.view.devicePixelRatio = 2.75;
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.viewPadding = const FakeViewPadding(top: 66, bottom: 63);
        tester.view.padding = const FakeViewPadding(top: 66, bottom: 63);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        final anyAgent = find.byType(AgentPage, skipOffstage: false);
        for (
          var frame = 0;
          frame < 12 && anyAgent.evaluate().isEmpty;
          frame++
        ) {
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(anyAgent, findsOneWidget);
        final firstFrameState = tester.state(anyAgent);
        await settleIo(tester);
        final agentState = tester.state(find.byType(AgentPage));
        expect(
          initialThreadReads,
          1,
          reason:
              'Opening the sheet must read the selected thread once; morph=$morph',
        );
        expect(
          agentState,
          same(firstFrameState),
          reason:
              'Source geometry becoming available must not remount AgentPage; morph=$morph',
        );
        final keyboard = find.byTooltip('切换键盘输入');
        expect(keyboard, findsOneWidget);
        final initialCenter = tester.getCenter(keyboard);
        final initialHit = tester.hitTestOnBinding(initialCenter);
        expect(
          hitIncludes(initialHit, tester.renderObject(keyboard)),
          isTrue,
          reason: hitDescription(initialHit),
        );
        await tester.tapAt(initialCenter);
        await settleIo(tester);
        expect(find.byKey(const Key('agent-input')), findsOneWidget);
        await tester.tap(find.byKey(const Key('agent-input')));
        tester.view.viewInsets = const FakeViewPadding(bottom: 820);
        tester.view.padding = const FakeViewPadding(top: 66);
        await tester.pumpAndSettle();
        final voice = find.byTooltip('切换语音输入');
        final center = tester.getCenter(voice);
        final hit = tester.hitTestOnBinding(center);
        expect(
          hitIncludes(hit, tester.renderObject(voice)),
          isTrue,
          reason:
              'Painted footer center $center, old center $initialCenter\n${hitDescription(hit)}',
        );
        await tester.tapAt(center);
        await settleIo(tester);
        expect(find.byTooltip('切换键盘输入'), findsOneWidget);
        expect(find.byType(HoldVoiceButton), findsOneWidget);
        expect(tester.state(find.byType(AgentPage)), same(agentState));
        tester.view.viewInsets = const FakeViewPadding();
        tester.view.padding = const FakeViewPadding(top: 66, bottom: 63);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('最近对话'));
        await settleIo(tester);
        await tester.tapAt(tester.getCenter(find.text('有真实历史消息')));
        await settleIo(tester);
        expect(find.text('历史问题确实存在'), findsOneWidget);
        expect(find.text('历史回复确实存在'), findsOneWidget);
        expect(tester.state(find.byType(AgentPage)), same(agentState));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await settleIo(tester);
      },
    );
  }
}
