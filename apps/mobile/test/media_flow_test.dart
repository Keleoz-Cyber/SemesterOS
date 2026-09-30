import 'package:semester_os/ui/forui_theme.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'ui_polish_test.dart' show mount;
import 'package:semester_os/features/media/drafts.dart';
import 'package:semester_os/features/media/media_input.dart';
import 'package:semester_os/features/media/hold_voice_button.dart';
import 'package:semester_os/features/media/media_capture_page.dart';
import 'package:semester_os/features/items/capture_page.dart';
import 'package:semester_os/features/items/item_form.dart';
import 'package:semester_os/features/items/items_controller.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'controller_test.dart' show MemoryStore;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'planning_flow_test.dart' show route, ioTap;
import 'centers_flow_test.dart' show settleIo;
import 'ui_polish_test.dart' show capture, loadPreviewFonts;

class FakeMedia implements MediaInput {
  @override
  Future<String?> image({bool recover = false}) async => null;
  @override
  Future<bool> start() async => false;
  @override
  Future<String?> stop() async => null;
  @override
  Future<void> release(String path) async {}
  @override
  Future<void> dispose() async {}
}

class EntryMedia extends FakeMedia {
  EntryMedia({this.path, this.allowRecording = true, this.startGate});
  final String? path;
  final bool allowRecording;
  final Completer<bool>? startGate;
  int picks = 0, starts = 0, stops = 0;
  @override
  Future<String?> image({bool recover = false}) async {
    picks++;
    return path;
  }

  @override
  Future<bool> start() async {
    starts++;
    return startGate == null ? allowRecording : await startGate!.future;
  }

  @override
  Future<String?> stop() async {
    stops++;
    return path;
  }
}

class MediaTestPaths extends PathProviderPlatform {
  MediaTestPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class PendingCaptureStore extends MemoryStore {
  final reading = Completer<void>();
  final releaseRead = Completer<void>();
  @override
  Future<Map<String, dynamic>?> read(String owner) async {
    if (owner.startsWith('capture:')) {
      if (!reading.isCompleted) reading.complete();
      await releaseRead.future;
    }
    return super.read(owner);
  }
}

Map<String, dynamic> source(String id) => {
  'id': id,
  'semester_id': 's',
  'kind': 'image',
  'version': 1,
  'status': 'recognized',
  'text': id == 'a' ? '周五交Java实验报告' : '周日提交数学作业',
  'original_text': id == 'a' ? '周五交Java实验报告' : '周日提交数学作业',
  'reference_at': '2026-09-20T00:00:00+00:00',
  'created_at': '2026-09-20T00:00:00+00:00',
  'file_deleted': false,
  'recognition': {},
};
Future<ScheduleFixture> setup(WidgetTester tester, {bool dirty = false}) async {
  final f = ScheduleFixture();
  await tester.runAsync(() => f.c.bind('s'));
  final transport = f.api.dio.httpClientAdapter as ControlledTransport;
  f.api.dio.httpClientAdapter = ControlledTransport((r) async {
    if (r.path.endsWith('/sources')) return body([source('a'), source('b')]);
    if (r.path.endsWith('/sources/a')) return body(source('a'));
    if (r.path.endsWith('/sources/b')) return body(source('b'));
    if (r.path.endsWith('/cancel')) {
      return body({...source('a'), 'version': 2, 'status': 'cancelled'});
    }
    return transport.respond(r);
  });
  await tester.runAsync(
    () => CaptureDrafts(f.c.cache, 'preview', () => true).save('media:s', {
      'kind': 'image',
      'local': Platform.environment['UI_MEDIA_IMAGE'],
      'source': source('a'),
      'text': dirty ? '我核对过的文字' : source('a')['text'],
      'key': 'upload-fixed',
      'reference_at': dirty
          ? '2026-09-19T00:00:00Z'
          : source('a')['reference_at'],
      'dirty': dirty,
    }),
  );
  final imagePath = Platform.environment['UI_MEDIA_IMAGE'];
  if (imagePath != null) {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.runAsync(
      () => precacheImage(
        ResizeImage(FileImage(File(imagePath)), width: 1400),
        tester.element(find.byType(Scaffold)),
      ),
    );
  }
  return f;
}

Widget page(ScheduleFixture f) => MediaCapturePage(
  controller: f.c,
  semester: const {'id': 's', 'total_weeks': 20},
  input: FakeMedia(),
);
Future<void> openMore(
  WidgetTester tester,
  String label, {
  bool select = true,
  bool settle = true,
}) async {
  await tester.tap(find.byTooltip('更多操作'));
  await tester.pumpAndSettle();
  if (select) {
    if (settle) {
      await ioTap(tester, find.text(label));
    } else {
      await tester.runAsync(() => tester.tap(find.text(label)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }
}

void main() {
  for (final kind in ['image', 'audio']) {
    testWidgets(
      'pending $kind draft restored in background enables manual controls on resume',
      (tester) async {
        final f = ScheduleFixture();
        final store = PendingCaptureStore();
        final controller = ItemsController(f.api, store, f.c.reminders);
        await tester.runAsync(() => controller.bind('s'));
        final input = EntryMedia();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => ShiriForuiTheme(child: child!),
            home: MediaCapturePage(
              controller: controller,
              semester: const {'id': 's'},
              kind: kind,
              input: input,
              returnSource: true,
            ),
          ),
        );
        await tester.pump();
        expect(store.reading.isCompleted, isTrue);
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        store.releaseRead.complete();
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(input.starts, 0);
        expect(input.picks, 0);
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isTrue,
        );
        if (kind == 'audio') {
          expect(
            tester
                .widget<HoldVoiceButton>(find.byType(HoldVoiceButton))
                .enabled,
            isTrue,
          );
        } else {
          expect(
            tester
                .widget<AppOutlineButton>(find.byType(AppOutlineButton).first)
                .onPressed,
            isNotNull,
          );
        }
        await openMore(tester, '手动填写事项', select: false);
        expect(find.text('手动填写事项'), findsOneWidget);
        Navigator.pop(tester.element(find.text('手动填写事项')));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await settleIo(tester);
        controller.dispose();
        f.c.dispose();
      },
    );
  }
  testWidgets(
    'backgrounding during microphone start prevents a late recording on resume',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      final gate = Completer<bool>();
      final input = EntryMedia(startGate: gate);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ShiriForuiTheme(child: child!),
          home: MediaCapturePage(
            controller: f.c,
            semester: const {'id': 's'},
            kind: 'audio',
            input: input,
            returnSource: true,
          ),
        ),
      );
      await tester.pump();
      expect(input.starts, 0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldVoiceButton)),
      );
      await tester.pump();
      expect(input.starts, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      gate.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(input.stops, 1);
      expect(find.textContaining(RegExp(r'松开完成 · [0-9]+s')), findsNothing);
      await gesture.up();
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
      f.c.dispose();
    },
  );
  for (final variant in ['image', 'audio', 'recorded']) {
    final kind = variant == 'recorded' ? 'audio' : variant;
    final supplied = variant == 'recorded';
    testWidgets(
      'assistant $variant entry uploads and recognizes after capture without another tap',
      (tester) async {
        tester.view.physicalSize = const Size(780, 1688);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = ScheduleFixture();
        await tester.runAsync(() => f.c.bind('s'));
        final folder = await tester.runAsync(
          () => Directory.systemTemp.createTemp('media-entry-'),
        );
        final previous = PathProviderPlatform.instance;
        PathProviderPlatform.instance = MediaTestPaths(folder!.path);
        addTearDown(() async {
          PathProviderPlatform.instance = previous;
          await folder.delete(recursive: true);
        });
        final file = await tester.runAsync(
          () => File('${folder.path}/image.png').writeAsBytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=',
            ),
          ),
        );
        final input = EntryMedia(path: file!.path);
        var uploads = 0, recognitions = 0;
        final old = f.api.dio.httpClientAdapter as ControlledTransport;
        f.api.dio.httpClientAdapter = ControlledTransport((r) async {
          if (r.uri.path.endsWith('/sources') && r.method == 'POST') {
            uploads++;
            return body({
              ...source('a'),
              'kind': kind,
              'status': 'uploaded',
              'text': '',
            });
          }
          if (r.path.endsWith('/recognize')) {
            recognitions++;
            return body({...source('a'), 'kind': kind});
          }
          if (r.path.endsWith('/sources')) return body([]);
          if (r.path.endsWith('/sources/a')) {
            return body({...source('a'), 'kind': kind});
          }
          return old.respond(r);
        });
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => ShiriForuiTheme(child: child!),
              home: MediaCapturePage(
                controller: f.c,
                semester: const {'id': 's'},
                kind: kind,
                input: input,
                returnSource: true,
                initialAudioPath: supplied ? file.path : null,
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await settleIo(tester);
        if (kind == 'audio' && !supplied) {
          expect(input.starts, 0);
          expect(uploads, 0);
          final gesture = await tester.startGesture(
            tester.getCenter(find.byType(HoldVoiceButton)),
          );
          await tester.pump();
          expect(input.starts, 1);
          await tester.runAsync(() async {
            await gesture.up();
            await Future<void>.delayed(const Duration(milliseconds: 300));
          });
          await settleIo(tester);
          expect(input.stops, 1);
        }
        if (supplied) {
          expect(input.starts, 0);
          expect(find.byType(HoldVoiceButton), findsNothing);
        }
        expect(input.picks, kind == 'image' ? 1 : 0);
        expect(uploads, 1);
        expect(recognitions, 1);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          source('a')['text'],
        );
        expect(find.text('上传并识别'), findsNothing);
        expect(find.text('发送').hitTestable(), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await settleIo(tester);
        f.c.dispose();
      },
    );
  }

  testWidgets(
    'audio entry preserves legacy image draft and restores its own draft without recording again',
    (tester) async {
      final f = await setup(tester, dirty: true);
      final input = EntryMedia(allowRecording: false);
      await route(
        tester,
        MediaCapturePage(
          controller: f.c,
          semester: const {'id': 's'},
          kind: 'audio',
          input: input,
          returnSource: true,
        ),
      );
      await settleIo(tester);
      expect(input.starts, 0);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.enterText(find.byType(TextField), '我的录音草稿');
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
      final drafts = CaptureDrafts(f.c.cache, 'preview', () => true);
      expect(
        (await tester.runAsync(() => drafts.read('media:s')))!['text'],
        '我核对过的文字',
      );
      expect(
        (await tester.runAsync(() => drafts.read('media:s:audio')))!['text'],
        '我的录音草稿',
      );
      final reopened = EntryMedia();
      await route(
        tester,
        MediaCapturePage(
          controller: f.c,
          semester: const {'id': 's'},
          kind: 'audio',
          input: reopened,
          returnSource: true,
        ),
      );
      await settleIo(tester);
      expect(reopened.starts, 0);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '我的录音草稿',
      );
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
      f.c.dispose();
    },
  );
  testWidgets(
    'reviewed media returns to assistant without invoking old parser',
    (tester) async {
      final f = await setup(tester);
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      Map<String, dynamic>? returned;
      var legacyParses = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/sources/a') && r.method == 'PATCH') {
          return body({...source('a'), 'version': 2, 'text': r.data['text']});
        }
        if (r.path.endsWith('/capture/text')) {
          legacyParses++;
          return body({'message': '不应调用'}, 400);
        }
        return old.respond(r);
      });
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                returned = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MediaCapturePage(
                      controller: f.c,
                      semester: const {'id': 's', 'total_weeks': 20},
                      input: FakeMedia(),
                      returnSource: true,
                    ),
                  ),
                );
              },
              child: const Text('选择通知'),
            ),
          ),
        ),
      );
      await ioTap(tester, find.text('选择通知'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('发送'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await settleIo(tester);
      await tester.ensureVisible(find.text('发送'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('发送'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump(const Duration(milliseconds: 400));
      await settleIo(tester);
      expect(returned?['id'], 'a');
      expect(returned?['version'], 2);
      expect(legacyParses, 0);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'assistant media manual fallback can return without a Map bool type error',
    (tester) async {
      final f = await setup(tester);
      bool returned = false;
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MediaCapturePage(
                      controller: f.c,
                      semester: const {'id': 's', 'total_weeks': 20},
                      input: FakeMedia(),
                      returnSource: true,
                    ),
                  ),
                );
                returned = true;
              },
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await ioTap(tester, find.text('打开'));
      await settleIo(tester);
      await openMore(tester, '手动填写事项');
      await settleIo(tester);
      expect(find.byType(ItemFormPage), findsOneWidget);
      Navigator.pop(tester.element(find.byType(ItemFormPage)), true);
      await settleIo(tester);
      expect(returned, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  setUpAll(loadPreviewFonts);
  testWidgets(
    'manual fallback works without a microphone recording or uploaded source',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/sources')) return body([]);
        return old.respond(r);
      });
      await route(tester, page(f));
      await settleIo(tester);
      await openMore(tester, '手动填写事项');
      expect(find.byType(ItemFormPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
      f.c.dispose();
    },
  );
  test(
    'drafts survive store recreation and late old-account saves are ignored',
    () async {
      final cache = MemoryStore();
      var valid = true;
      final a = CaptureDrafts(cache, 'a', () => valid);
      await a.save('text:s', {'text': '草稿'});
      expect(
        (await CaptureDrafts(cache, 'a', () => true).read('text:s'))!['text'],
        '草稿',
      );
      valid = false;
      await a.save('text:s', {'text': '迟到写入'});
      expect(
        await CaptureDrafts(cache, 'b', () => true).read('text:s'),
        isNull,
      );
      expect(
        (await CaptureDrafts(cache, 'a', () => true).read('text:s'))!['text'],
        '草稿',
      );
    },
  );
  testWidgets(
    'edited transcript and reference survive reopening and remote refresh',
    (tester) async {
      final f = await setup(tester, dirty: true);
      await route(tester, page(f));
      await settleIo(tester);
      final fixtureImage = Platform.environment['UI_MEDIA_IMAGE'];
      if (fixtureImage != null) {
        await tester.pumpAndSettle();
        expect(
          tester.widget<RawImage>(find.byType(RawImage).first).image,
          isNotNull,
        );
      }
      await capture(tester, 'media-source-preview');
      await tester.scrollUntilVisible(
        find.byType(TextField),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '我核对过的文字',
      );
      await openMore(tester, '原消息时间：2026-09-19 08:00', select: false);
      expect(find.text('原消息时间：2026-09-19 08:00'), findsOneWidget);
      Navigator.pop(tester.element(find.text('原消息时间：2026-09-19 08:00')));
      await tester.pumpAndSettle();
      await capture(tester, 'media-review-draft');
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
      final saved = await tester.runAsync(
        () => CaptureDrafts(
          f.c.cache,
          'preview',
          () => true,
        ).read('media:s:image'),
      );
      expect(saved!['text'], '我核对过的文字');
      expect(saved['dirty'], isTrue);
      f.c.dispose();
    },
  );
  testWidgets('changing only message date marks local draft dirty', (
    tester,
  ) async {
    final f = await setup(tester);
    await route(tester, page(f));
    await settleIo(tester);
    await openMore(tester, '原消息时间：2026-09-20 08:00');
    await tester.pumpAndSettle();
    await tester.tap(find.text('21'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await settleIo(tester);
    final saved = await tester.runAsync(
      () =>
          CaptureDrafts(f.c.cache, 'preview', () => true).read('media:s:image'),
    );
    expect(saved!['dirty'], isTrue);
    expect(saved['reference_at'], startsWith('2026-09-21'));
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
    f.c.dispose();
  });
  testWidgets(
    'cancelled save response cannot switch source B back to source A',
    (tester) async {
      final f = await setup(tester);
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      final gate = Completer<dynamic>();
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.method == 'PATCH') return await gate.future;
        return old.respond(r);
      });
      await route(tester, page(f));
      await settleIo(tester);
      await openMore(tester, '保存文字，稍后整理', settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(
        find.text('取消当前处理，保留草稿'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await ioTap(tester, find.text('取消当前处理，保留草稿'));
      await openMore(tester, '最近上传');
      await ioTap(tester, find.byKey(const ValueKey('source-b')));
      gate.complete(body({...source('a'), 'version': 2}));
      await settleIo(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        source('b')['text'],
      );
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
      f.c.dispose();
    },
  );
  testWidgets('microphone permission refusal keeps manual text available', (
    tester,
  ) async {
    final f = await setup(tester);
    await route(
      tester,
      MediaCapturePage(
        controller: f.c,
        semester: const {'id': 's'},
        kind: 'audio',
        input: FakeMedia(),
      ),
    );
    await settleIo(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldVoiceButton)),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.text('麦克风权限未开启，可以改用文字输入。'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
    f.c.dispose();
  });
  testWidgets('text capture restores saved text after reopening', (
    tester,
  ) async {
    final f = ScheduleFixture();
    await tester.runAsync(() => f.c.bind('s'));
    await tester.runAsync(
      () => CaptureDrafts(f.c.cache, 'preview', () => true).save('text:s', {
        'text': '保留的文字通知',
        'reference_at': '2026-09-19T00:00:00Z',
      }),
    );
    await route(
      tester,
      CapturePage(controller: f.c, semester: const {'id': 's'}),
    );
    await settleIo(tester);
    expect(
      tester
          .widget<AppField>(find.byKey(const Key('capture-text')))
          .controller!
          .text,
      '保留的文字通知',
    );
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
    f.c.dispose();
  });
}
