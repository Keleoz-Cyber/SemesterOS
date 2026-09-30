import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:semester_os/features/media/drafts.dart';
import 'package:semester_os/features/media/inline_capture_controller.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'media_flow_test.dart' show MediaTestPaths, source;
import 'schedule_flow_test.dart' show ScheduleFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform previousPaths;
  late ScheduleFixture f;
  late InlineCaptureController capture;
  late CaptureDrafts drafts;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('inline-capture-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = MediaTestPaths(temp.path);
    f = ScheduleFixture();
    await f.c.bind('s');
    drafts = CaptureDrafts(f.c.cache, 'preview', () => true);
    capture = InlineCaptureController(controller: f.c, semesterId: 's');
  });
  tearDown(() async {
    capture.dispose();
    f.c.dispose();
    f.api.dio.close();
    PathProviderPlatform.instance = previousPaths;
    await temp.delete(recursive: true);
  });

  test(
    'copies temporary audio and retries upload with the persisted key',
    () async {
      final input = await File(
        '${temp.path}/recording.wav',
      ).writeAsBytes([1, 2, 3]);
      final keys = <String>[];
      var fail = true;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/semesters/s/sources')) {
          keys.add(r.headers['Idempotency-Key'] as String);
          return fail
              ? body({'detail': '网络不可用'}, 503)
              : body({...source('a'), 'status': 'uploaded'});
        }
        expect(r.path, endsWith('/sources/a/recognize'));
        return body({
          ...source('a'),
          'kind': 'audio',
          'status': 'queued',
          'version': 2,
        });
      });
      await capture.capture(input.path, 'audio');
      expect(capture.error, isNotNull);
      expect(capture.local, isNot(input.path));
      await input
          .delete(); // HoldVoiceButton releases its file after this callback.
      expect(await File(capture.local!).readAsBytes(), [1, 2, 3]);
      expect((await drafts.read('inline:s'))!['key'], keys.single);
      capture.dispose();
      capture = InlineCaptureController(controller: f.c, semesterId: 's');
      await capture.restore();
      expect(capture.hasPending, isTrue);
      fail = false;
      await capture.retry();
      expect(keys, [keys.first, keys.first]);
      expect(capture.source?['status'], 'queued');
    },
  );

  test(
    'restores queued recognition, reports transcript, and confirms only explicitly',
    () async {
      await drafts.save('inline:s', {
        'kind': 'audio',
        'key': 'stable',
        'source': {...source('a'), 'kind': 'audio', 'status': 'queued'},
        'reference_at': source('a')['reference_at'],
      });
      capture.dispose();
      final transcripts = <String>[];
      capture = InlineCaptureController(
        controller: f.c,
        semesterId: 's',
        onTranscript: transcripts.add,
      );
      var patches = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.method == 'PATCH') {
          patches++;
          expect(r.data['expected_version'], 2);
          expect(r.data['text'], '我核对后的文字');
          expect(r.data['reference_at'], '2026-09-27T01:00:00Z');
          return body({
            ...source('a'),
            ...Map<String, dynamic>.from(r.data),
            'version': 3,
          });
        }
        expect(r.method, 'GET');
        return body({...source('a'), 'version': 2});
      });
      await capture.restore();
      expect(transcripts, [source('a')['text']]);
      expect(patches, 0);
      final saved = await capture.confirmText(
        '我核对后的文字',
        referenceAt: '2026-09-27T01:00:00Z',
      );
      expect(saved?['version'], 3);
      expect(patches, 1);
      expect(
        (await capture.confirmText(
          '我核对后的文字',
          referenceAt: '2026-09-27T01:00:00+00:00',
        ))?['version'],
        3,
      );
      expect(patches, 1);
      expect(transcripts.length, 1);
      await capture.detach();
      expect(await drafts.read('inline:s'), isNull);
      expect(capture.source, isNull);
    },
  );

  test(
    'account change suppresses delayed recognition and clears visible state',
    () async {
      await drafts.save('inline:s', {
        'source': {...source('a'), 'status': 'queued'},
      });
      final entered = Completer<void>();
      final release = Completer<void>();
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        entered.complete();
        await release.future;
        return body(source('a'));
      });
      final restoring = capture.restore();
      await entered.future;
      f.api.generation++;
      f.api.session = account('another');
      f.c.changed();
      release.complete();
      await restoring;
      expect(capture.source, isNull);
      expect(capture.local, isNull);
      expect(capture.busy, isFalse);
    },
  );

  test(
    'cancel rejects late poll results and persists cancelled source',
    () async {
      await drafts.save('inline:s', {
        'source': {...source('a'), 'status': 'queued'},
      });
      var delay = false;
      final entered = Completer<void>();
      final release = Completer<void>();
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/cancel')) {
          expect(r.data['expected_version'], 1);
          return body({...source('a'), 'status': 'cancelled', 'version': 2});
        }
        if (delay) {
          entered.complete();
          await release.future;
          return body({...source('a'), 'version': 2});
        }
        return body({...source('a'), 'status': 'queued'});
      });
      await capture.restore();
      delay = true;
      final checking = capture.checkJob();
      await entered.future;
      await capture.cancel();
      release.complete();
      await checking;
      expect(capture.source?['status'], 'cancelled');
      expect((await drafts.read('inline:s'))!['source']['status'], 'cancelled');
    },
  );

  test(
    'disposed controller neither emits nor persists a delayed poll response',
    () async {
      await drafts.save('inline:s', {
        'source': {...source('a'), 'status': 'queued'},
      });
      final entered = Completer<void>();
      final release = Completer<void>();
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        entered.complete();
        await release.future;
        return body(source('a'));
      });
      final restoring = capture.restore();
      await entered.future;
      capture.dispose();
      release.complete();
      await restoring;
      expect((await drafts.read('inline:s'))!['source']['status'], 'queued');
    },
  );

  test(
    'cancelling an in-flight upload prevents late recognition or reattachment',
    () async {
      final input = await File(
        '${temp.path}/recording.wav',
      ).writeAsBytes([1, 2, 3]);
      final entered = Completer<void>();
      final release = Completer<void>();
      var requests = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        requests++;
        expect(r.path, contains('/semesters/s/sources'));
        entered.complete();
        await release.future;
        return body({...source('a'), 'status': 'uploaded'});
      });
      final uploading = capture.capture(input.path, 'audio');
      await entered.future;
      await capture.cancel();
      release.complete();
      await uploading;
      expect(requests, 1);
      expect(capture.hasPending, isFalse);
      expect(capture.busy, isFalse);
      expect(await drafts.read('inline:s'), isNull);
    },
  );

  test(
    'failed recognition offers a specific error and does not confirm text',
    () async {
      await drafts.save('inline:s', {
        'source': {...source('a'), 'status': 'queued'},
      });
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        expect(r.method, 'GET');
        return body({
          ...source('a'),
          'status': 'failed',
          'text': '',
          'error_code': 'EMPTY_TRANSCRIPT',
        });
      });
      await capture.restore();
      expect(capture.phase, 'failed');
      expect(capture.error, contains('没有识别到文字'));
      expect(capture.hasPending, isTrue);
      expect(capture.busy, isFalse);
    },
  );

  test('NO_USABLE_TEXT distinguishes audio from image', () async {
    await drafts.save('inline:s', {
      'source': {...source('a'), 'kind': 'audio', 'status': 'queued'},
    });
    f.api.dio.httpClientAdapter = ControlledTransport(
      (r) async => body({
        ...source('a'),
        'kind': 'audio',
        'status': 'failed',
        'text': '',
        'error_code': 'NO_USABLE_TEXT',
      }),
    );
    await capture.restore();
    expect(capture.error, '没有识别到语音，请重新录音或直接输入。');
  });

  test(
    'lost confirmation response reconciles the changed version without another PATCH',
    () async {
      await drafts.save('inline:s', {'source': source('a')});
      var server = source('a');
      var patches = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.method == 'PATCH') {
          patches++;
          server = {
            ...server,
            'version': 2,
            'text': r.data['text'],
            'reference_at': r.data['reference_at'],
          };
          return body({'detail': '响应丢失'}, 503);
        }
        return body(server);
      });
      await capture.restore();
      expect((await capture.confirmText('核对的文字'))?['version'], 2);
      expect((await capture.confirmText('核对的文字'))?['version'], 2);
      expect(patches, 1);
    },
  );

  test(
    'unsuccessful PATCH cannot confirm matching unreviewed recognition text',
    () async {
      await drafts.save('inline:s', {'source': source('a')});
      var patches = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.method == 'PATCH') {
          patches++;
          return body({'detail': '保存失败'}, 503);
        }
        return body(source('a'));
      });
      await capture.restore();
      expect(await capture.confirmText(source('a')['text']), isNull);
      expect(await capture.confirmText(source('a')['text']), isNull);
      expect(patches, 2);
      expect((await drafts.read('inline:s'))!['confirmed_version'], isNull);
    },
  );

  test(
    'conversation draft scopes do not recover each others attachments',
    () async {
      await drafts.save('inline:s:assistant-context:s:first', {
        'source': source('a'),
      });
      f.api.dio.httpClientAdapter = ControlledTransport(
        (r) async => body(source('a')),
      );
      await capture.restore(scope: 'assistant-context:s:second');
      expect(capture.hasPending, isFalse);
      await capture.restore(scope: 'assistant-context:s:first');
      expect(capture.source?['id'], 'a');
      await capture.restore(scope: 'assistant-context:s:second');
      expect(capture.draftKey, 'inline:s:assistant-context:s:first');
      await capture.detach();
      expect(await drafts.read('inline:s:assistant-context:s:first'), isNull);
    },
  );

  test(
    'restoring confirmed text does not replay it as a new transcript',
    () async {
      await drafts.save('inline:s', {
        'source': source('a'),
        'confirmed_text': source('a')['text'],
        'confirmed_reference': source('a')['reference_at'],
        'confirmed_version': 1,
      });
      capture.dispose();
      final transcripts = <String>[];
      capture = InlineCaptureController(
        controller: f.c,
        semesterId: 's',
        onTranscript: transcripts.add,
      );
      f.api.dio.httpClientAdapter = ControlledTransport(
        (r) async => body(source('a')),
      );
      await capture.restore();
      expect(transcripts, isEmpty);
    },
  );

  test(
    'pending confirmation survives reopening and refreshes before another PATCH',
    () async {
      await drafts.save('inline:s', {
        'source': source('a'),
        'pending_confirmation': {
          'version': 1,
          'text': '已核对',
          'reference_at': source('a')['reference_at'],
        },
      });
      capture.dispose();
      final transcripts = <String>[];
      capture = InlineCaptureController(
        controller: f.c,
        semesterId: 's',
        onTranscript: transcripts.add,
      );
      var gets = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        expect(r.method, 'GET');
        gets++;
        return body({...source('a'), 'version': 2, 'text': '已核对'});
      });
      await capture.restore();
      expect(transcripts, isEmpty);
      expect((await capture.confirmText('已核对'))?['version'], 2);
      expect(gets, 2);
      expect(transcripts, isEmpty);
    },
  );
}
