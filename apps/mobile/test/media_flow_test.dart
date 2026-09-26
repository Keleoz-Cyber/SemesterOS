import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'ui_polish_test.dart' show mount;
import 'package:semester_os/features/media/drafts.dart';
import 'package:semester_os/features/media/media_input.dart';
import 'package:semester_os/features/media/media_capture_page.dart';
import 'package:semester_os/features/items/capture_page.dart';
import 'package:semester_os/features/items/item_form.dart';
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
void main() {
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
        find.text('用这些文字整理事项'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await settleIo(tester);
      await tester.ensureVisible(find.text('用这些文字整理事项'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('用这些文字整理事项'));
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
      await tester.scrollUntilVisible(
        find.text('保存文字并手动填写事项'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('保存文字并手动填写事项'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
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
      await tester.scrollUntilVisible(
        find.text('不上传文件，直接手动填写'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await ioTap(tester, find.text('不上传文件，直接手动填写'));
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
      expect(find.text('原消息时间：2026-09-19 08:00'), findsOneWidget);
      await capture(tester, 'media-review-draft');
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
      final saved = await tester.runAsync(
        () => CaptureDrafts(f.c.cache, 'preview', () => true).read('media:s'),
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
    await tester.scrollUntilVisible(
      find.text('原消息时间：2026-09-20 08:00'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('原消息时间：2026-09-20 08:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('21'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await settleIo(tester);
    final saved = await tester.runAsync(
      () => CaptureDrafts(f.c.cache, 'preview', () => true).read('media:s'),
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
      await tester.scrollUntilVisible(
        find.text('先保存文字，稍后整理'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(() => tester.tap(find.text('先保存文字，稍后整理')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(
        find.text('取消当前处理，保留草稿'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await ioTap(tester, find.text('取消当前处理，保留草稿'));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('source-b')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
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
    await route(tester, page(f));
    await settleIo(tester);
    await ioTap(tester, find.text('录一段通知'));
    await tester.scrollUntilVisible(
      find.text('麦克风权限未开启，仍可选图或手工填写'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
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
          .widget<TextField>(find.byKey(const Key('capture-text')))
          .controller!
          .text,
      '保留的文字通知',
    );
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
    f.c.dispose();
  });
}
