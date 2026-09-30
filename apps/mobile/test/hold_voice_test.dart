import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/media/hold_voice_button.dart';
import 'package:semester_os/features/media/media_input.dart';

class HoldInput implements MediaInput {
  Completer<bool>? permission;
  int starts = 0, stops = 0, releases = 0, disposals = 0;
  bool allowed = true;
  @override
  Future<String?> image({bool recover = false}) async => null;
  @override
  Future<bool> start() async {
    starts++;
    return permission == null ? allowed : permission!.future;
  }

  @override
  Future<String?> stop() async {
    stops++;
    return 'temporary.wav';
  }

  @override
  Future<void> release(String path) async {
    releases++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    HoldInput input,
    Future<void> Function(String) onRecorded, {
    ValueChanged<String>? onError,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: HoldVoiceButton(
                input: input,
                onRecorded: onRecorded,
                onError: onError ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'opening voice does not start microphone; release captures once',
    (tester) async {
      final input = HoldInput();
      var captures = 0;
      await mount(tester, input, (_) async {
        captures++;
      });
      expect(input.starts, 0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldVoiceButton)),
      );
      await tester.pump();
      expect(input.starts, 1);
      await gesture.up();
      await tester.pump();
      expect(captures, 1);
      expect(input.stops, 1);
      expect(input.releases, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('slide upwards discards the audio without handing off', (
    tester,
  ) async {
    final input = HoldInput();
    var captures = 0;
    await mount(tester, input, (_) async {
      captures++;
    });
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldVoiceButton)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, -90));
    await tester.pump();
    expect(find.text('松开取消'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(captures, 0);
    expect(input.stops, 1);
    expect(input.releases, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('releasing during permission request prevents late recording', (
    tester,
  ) async {
    final input = HoldInput()..permission = Completer<bool>();
    var captures = 0;
    await mount(tester, input, (_) async {
      captures++;
    });
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldVoiceButton)),
    );
    await tester.pump();
    await gesture.up();
    input.permission!.complete(true);
    await tester.pump();
    expect(captures, 0);
    expect(input.stops, 1);
    expect(input.releases, 1);
    expect(find.text('按住说话'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unmount while awaiting permission cleans up in order', (
    tester,
  ) async {
    final input = HoldInput()..permission = Completer<bool>();
    var captures = 0;
    await mount(tester, input, (_) async {
      captures++;
    });
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldVoiceButton)),
    );
    await tester.pumpWidget(const SizedBox());
    expect(input.disposals, 0);
    input.permission!.complete(true);
    await tester.pump();
    expect(input.stops, 1);
    expect(input.releases, 1);
    expect(input.disposals, 1);
    expect(captures, 0);
    await gesture.up();
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmount during recording stops and discards before disposal', (
    tester,
  ) async {
    final input = HoldInput();
    var captures = 0;
    await mount(tester, input, (_) async {
      captures++;
    });
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldVoiceButton)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(input.stops, 1);
    expect(input.releases, 1);
    expect(input.disposals, 1);
    expect(captures, 0);
    await gesture.up();
    expect(tester.takeException(), isNull);
  });

  testWidgets('temporary recording lives until the consumer finishes', (
    tester,
  ) async {
    final input = HoldInput();
    final consumed = Completer<void>();
    await mount(tester, input, (_) => consumed.future);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldVoiceButton)),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(input.releases, 0);
    consumed.complete();
    await tester.pump();
    expect(input.releases, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('permission denial leaves a reusable button', (tester) async {
    final input = HoldInput()..allowed = false;
    String? error;
    await mount(tester, input, (_) async {}, onError: (value) => error = value);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldVoiceButton)),
    );
    await tester.pump();
    await gesture.up();
    expect(error, contains('麦克风权限'));
    expect(input.stops, 0);
    expect(find.text('按住说话'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
