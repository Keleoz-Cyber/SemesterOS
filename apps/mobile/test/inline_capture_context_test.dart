import 'package:semester_os/ui/app_controls.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/features/media/drafts.dart';
import 'package:semester_os/features/media/media_input.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'media_flow_test.dart' show MediaTestPaths, source;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount, loadPreviewFonts;

class RecoverImageInput implements MediaInput {
  RecoverImageInput(this.path);
  final String path;
  int recovered = 0, picked = 0;
  @override
  Future<String?> image({bool recover = false}) async {
    recover ? recovered++ : picked++;
    return path;
  }

  @override
  Future<bool> start() async => false;
  @override
  Future<String?> stop() async => null;
  @override
  Future<void> release(String path) async {}
  @override
  Future<void> dispose() async {}
}

Future<void> flush(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 60));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
}

Future<void> open(
  WidgetTester tester,
  ScheduleFixture f, {
  MediaInput? images,
  String? kind,
}) async {
  await mount(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AgentPage(
                controller: f.c,
                semester: const {'id': 's'},
                imageInput: images,
                initialMediaKind: kind,
              ),
            ),
          ),
          child: const Text('打开'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await flush(tester);
}

String composer(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

AppIconButton toolbarButton(WidgetTester tester, String tooltip) =>
    tester.widget<AppIconButton>(
      find.byWidgetPredicate(
        (widget) => widget is AppIconButton && widget.tooltip == tooltip,
      ),
    );

void main() {
  setUpAll(loadPreviewFonts);

  testWidgets(
    'restored transcript appends to prefix once and preserves later edits',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      final drafts = CaptureDrafts(f.c.cache, 'preview', () => true);
      await tester.runAsync(() async {
        await drafts.save('assistant:s', {
          'text': '请安排：',
          'pending_media': true,
        });
        await drafts.save('inline:s:assistant:s', {
          'source': {...source('a'), 'status': 'queued'},
        });
      });
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/agent/threads?')) return body([]);
        if (r.path.endsWith('/sources/a')) {
          return body({...source('a'), 'version': 2});
        }
        return old.respond(r);
      });
      await open(tester, f);
      expect(composer(tester), '请安排：\n${source('a')['text']}');
      await tester.enterText(find.byType(TextField).first, '我修改后的通知');
      await flush(tester);
      await tester.pumpWidget(const SizedBox());
      await flush(tester, rounds: 2);
      final saved = await tester.runAsync(() => drafts.read('assistant:s'));
      expect(saved?['media_transcript_ack'], 'a:2');
      await open(tester, f);
      expect(composer(tester), '我修改后的通知');
      await tester.pumpWidget(const SizedBox());
      await flush(tester, rounds: 2);
      f.c.dispose();
    },
  );

  testWidgets(
    'empty context draft retains recovery pointer while recognition is queued',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      final drafts = CaptureDrafts(f.c.cache, 'preview', () => true);
      const scope = 'assistant-context:s:pending';
      await tester.runAsync(() async {
        await drafts.save(
          scope,
          {'text': '', 'pending_media': true},
          pointerKey: 'assistant-context-latest:s',
          activatePointer: true,
        );
        await drafts.save('inline:s:$scope', {
          'source': {...source('a'), 'status': 'queued'},
        });
      });
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/agent/threads?')) return body([]);
        if (r.path.endsWith('/sources/a')) {
          return body({...source('a'), 'status': 'queued'});
        }
        return old.respond(r);
      });
      await open(tester, f);
      expect(find.text('正在识别…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await flush(tester, rounds: 2);
      final pointer = await tester.runAsync(
        () => drafts.read('assistant-context-latest:s'),
      );
      final saved = await tester.runAsync(() => drafts.read(scope));
      expect(pointer?['key'], scope);
      expect(saved?['pending_media'], isTrue);
      f.c.dispose();
    },
  );

  testWidgets(
    'lost image result recovers within context without launching another picker',
    (tester) async {
      final folder = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('inline-context-'),
      ))!;
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = MediaTestPaths(folder.path);
      addTearDown(() async {
        PathProviderPlatform.instance = previous;
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        for (var attempt = 0; ; attempt++) {
          try {
            await folder.delete(recursive: true);
            break;
          } on FileSystemException {
            if (attempt == 5) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      });
      final file = (await tester.runAsync(
        () => File('${folder.path}/image.png').writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        ),
      ))!;
      final images = RecoverImageInput(file.path);
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      final drafts = CaptureDrafts(f.c.cache, 'preview', () => true);
      const scope = 'assistant-context:s:picture';
      await tester.runAsync(
        () => drafts.save(
          scope,
          {'text': '', 'picking_image': true},
          pointerKey: 'assistant-context-latest:s',
          activatePointer: true,
        ),
      );
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/agent/threads?')) return body([]);
        if (r.path.contains('/semesters/s/sources')) {
          return body({...source('a'), 'status': 'uploaded'});
        }
        if (r.path.endsWith('/recognize')) {
          return body({...source('a'), 'version': 2});
        }
        return old.respond(r);
      });
      await open(tester, f, images: images, kind: 'image');
      for (var i = 0; i < 20 && composer(tester).isEmpty; i++) {
        await flush(tester, rounds: 2);
      }
      expect(images.recovered, 1);
      expect(images.picked, 0);
      expect(composer(tester), source('a')['text']);
      final inline = await tester.runAsync(
        () => drafts.read('inline:s:$scope'),
      );
      expect(inline?['source']['id'], 'a');
      // Let the native FileImage buffer finish opening/decoding before its
      // Windows temporary directory is removed.
      await flush(tester, rounds: 16);
      await tester.pumpWidget(const SizedBox());
      await flush(tester, rounds: 2);
      final saved = await tester.runAsync(() => drafts.read(scope));
      expect(saved?['picking_image'], isFalse);
      expect(saved?['pending_media'], isTrue);
      expect(tester.takeException(), isNull);
      f.c.dispose();
    },
  );

  testWidgets(
    'pending capture locks history and old selection while explicit send confirms',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      final drafts = CaptureDrafts(f.c.cache, 'preview', () => true);
      await tester.runAsync(() async {
        await drafts.save('assistant:s', {
          'text': '待发送的通知',
          'thread_id': 't',
          'pending_media': true,
        });
        await drafts.save('inline:s:assistant:s', {'source': source('a')});
      });
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      final patch = Completer<void>();
      var patches = 0, turns = 0;
      final run = {
        'id': 'r',
        'status': 'completed',
        'text': '选择课程',
        'answer': '',
        'ambiguous_ids': ['record'],
        'cards': [
          {
            'kind': 'records',
            'data': {
              'records': [
                {'id': 'record', 'title': '旧课程'},
              ],
            },
          },
        ],
      };
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/agent/threads?')) {
          return body([
            {'id': 't', 'title': '对话'},
          ]);
        }
        if (r.path.endsWith('/agent/threads/t')) {
          return body({
            'runs': [run],
          });
        }
        if (r.method == 'PATCH') {
          patches++;
          await patch.future;
          return body({...source('a'), 'version': 2, 'text': r.data['text']});
        }
        if (r.path.endsWith('/sources/a')) return body(source('a'));
        if (r.path.endsWith('/turns')) {
          turns++;
          return body({...run, 'id': 'new'});
        }
        return old.respond(r);
      });
      await open(tester, f);
      expect(toolbarButton(tester, '最近对话').onPressed, isNull);
      expect(toolbarButton(tester, '新对话').onPressed, isNull);
      final selection = find.widgetWithText(AppTextButton, '选这条');
      expect(selection, findsOneWidget);
      expect(tester.widget<AppTextButton>(selection).onPressed, isNull);
      await tester.tap(find.byTooltip('发送'));
      await flush(tester, rounds: 2);
      expect(patches, 1);
      expect(turns, 0);
      expect(toolbarButton(tester, '新对话').onPressed, isNull);
      await tester.runAsync(() async {
        patch.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await flush(tester);
      expect(turns, 1);
      await tester.pumpWidget(const SizedBox());
      await flush(tester, rounds: 2);
      f.c.dispose();
    },
  );
}
