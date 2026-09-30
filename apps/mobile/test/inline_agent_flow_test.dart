import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/features/media/hold_voice_button.dart';
import 'package:semester_os/features/media/media_capture_page.dart';
import 'package:semester_os/features/media/media_input.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:semester_os/ui/app_sheet.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'media_flow_test.dart' show MediaTestPaths, source;
import 'centers_flow_test.dart' show settleIo;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

class VoiceFixture implements MediaInput {
  final String path;
  int starts = 0;
  VoiceFixture(this.path);
  @override
  Future<bool> start() async {
    starts++;
    return true;
  }

  @override
  Future<String?> stop() async => path;
  @override
  Future<String?> image({bool recover = false}) async => path;
  @override
  Future<void> release(String value) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  for (final scenario in [
    (kind: 'audio', failed: false),
    (kind: 'audio', failed: true),
    (kind: 'image', failed: false),
  ]) {
    final failed = scenario.failed, kind = scenario.kind;
    testWidgets(
      '$kind remains in dialogue through ${failed ? 'failure and text fallback' : 'review and send retry'}',
      (tester) async {
        final folder = await tester.runAsync(
          () => Directory.systemTemp.createTemp('inline-agent-'),
        );
        final oldPaths = PathProviderPlatform.instance;
        PathProviderPlatform.instance = MediaTestPaths(folder!.path);
        addTearDown(() async {
          PathProviderPlatform.instance = oldPaths;
          await folder.delete(recursive: true);
        });
        final file = await tester.runAsync(
          () => File('${folder.path}/voice.wav').writeAsBytes(
            kind == 'image'
                ? base64Decode(
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=',
                  )
                : [1, 2, 3],
          ),
        );
        final voice = VoiceFixture(file!.path);
        final f = ScheduleFixture();
        final old = f.api.dio.httpClientAdapter as ControlledTransport;
        var patches = 0, turns = 0;
        final requests = <Map<String, dynamic>>[];
        var row = <String, dynamic>{
          ...source('a'),
          'kind': kind,
          'status': 'uploaded',
          'text': '',
          'version': 1,
        };
        f.api.dio.httpClientAdapter = ControlledTransport((r) async {
          if (r.path.contains('/agent/threads?')) return body([]);
          if (r.path.endsWith('/agent/threads') && r.method == 'POST') {
            return body({'id': 'thread'});
          }
          if (r.path.contains('/semesters/s/sources')) return body(row);
          if (r.path.endsWith('/sources/a/recognize')) {
            row = {
              ...row,
              'status': failed ? 'failed' : 'recognized',
              'version': 2,
              'text': failed ? '' : '明天下午四点组会',
              'error_code': failed ? 'NO_USABLE_TEXT' : null,
            };
            return body(row);
          }
          if (r.path.endsWith('/sources/a') && r.method == 'PATCH') {
            patches++;
            expect(r.data['text'], '明天下午五点组会');
            row = {...row, 'text': r.data['text'], 'version': 3};
            return body(row);
          }
          if (r.path.endsWith('/sources/a')) return body(row);
          if (r.path.endsWith('/turns')) {
            turns++;
            requests.add(Map<String, dynamic>.from(r.data));
            if (!failed && turns == 1) return body({'detail': 'retry'}, 503);
            return body({
              'id': 'run',
              'status': 'completed',
              'text': r.data['text'],
              'answer': '已收到',
              'cards': [],
            });
          }
          return old.respond(r);
        });
        await tester.runAsync(() => f.c.bind('s'));
        await mount(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAppSheet<void>(
                  context: context,
                  heightFactor: .9,
                  builder: (_) => AgentPage(
                    controller: f.c,
                    semester: const {'id': 's'},
                    initialMediaKind: kind,
                    voiceInput: voice,
                    imageInput: voice,
                    embedded: true,
                  ),
                ),
                child: const Text('打开对话'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开对话'));
        if (kind == 'image') {
          // File copy and decoding run outside the fake clock. Wait for the
          // actual recognition response before settling an animated progress bar.
          for (
            var round = 0;
            round < 40 && row['status'] != 'recognized';
            round++
          ) {
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
          }
          for (var round = 0; round < 8; round++) {
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
          }
          expect(row['status'], 'recognized');
        }
        await settleIo(tester);
        expect(voice.starts, 0);
        if (kind == 'audio') {
          final gesture = await tester.startGesture(
            tester.getCenter(find.byType(HoldVoiceButton)),
          );
          await tester.pump();
          await tester.runAsync(() async {
            await gesture.up();
            await Future<void>.delayed(const Duration(milliseconds: 180));
          });
          await settleIo(tester);
        }
        if (kind == 'image') {
          for (
            var attempt = 0;
            attempt < 20 && row['status'] != 'recognized';
            attempt++
          ) {
            await settleIo(tester);
          }
          await settleIo(tester);
          expect(
            row['status'],
            'recognized',
            reason: tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => t.data)
                .join(' | '),
          );
        }
        expect(find.byType(MediaCapturePage), findsNothing);
        expect(
          find.byType(Sheet),
          findsOneWidget,
          reason: 'recording does not push a second surface',
        );
        expect(find.text('智能输入'), findsOneWidget);
        expect(turns, 0);
        expect(patches, 0, reason: 'recognition alone is not a user review');
        if (failed) {
          expect(find.textContaining('没有识别到'), findsOneWidget);
          await capture(tester, 'inline-voice-failure');
          await tester.tap(find.text('直接输入'));
          await settleIo(tester);
          await tester.enterText(find.byType(TextField).first, '明天下午五点组会');
        } else {
          expect(
            tester
                .widget<TextField>(find.byType(TextField).first)
                .controller!
                .text,
            '明天下午四点组会',
          );
          await capture(tester, 'inline-$kind-recognized');
          await tester.enterText(find.byType(TextField).first, '明天下午五点组会');
        }
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('发送'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await settleIo(tester);
        if (!failed) {
          expect(patches, 1);
          expect(turns, 1);
          await tester.runAsync(() async {
            await tester.tap(find.byTooltip('发送'));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await settleIo(tester);
          expect(
            patches,
            1,
            reason: 'retry reuses the reviewed source version',
          );
          expect(requests[0]['request_id'], requests[1]['request_id']);
          expect(requests.last['source_version'], 3);
        } else {
          expect(patches, 0);
          expect(requests.single.containsKey('source_id'), isFalse);
        }
        expect(requests.last['text'], '明天下午五点组会');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await settleIo(tester);
        f.c.dispose();
      },
    );
  }
}
