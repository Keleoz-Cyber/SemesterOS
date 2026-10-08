import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/media/hold_voice_button.dart';
import 'hold_voice_test.dart' show HoldInput;

void main() {
  testWidgets(
    'compact voice tap opens only, long hold captures and upward cancels',
    (tester) async {
      final input = HoldInput();
      var opens = 0, captures = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HoldVoiceButton(
                compact: true,
                input: input,
                onTap: () => opens++,
                onRecorded: (_) async {
                  captures++;
                },
                onError: (_) {},
              ),
            ),
          ),
        ),
      );
      final button = find.byType(HoldVoiceButton);
      await tester.tap(button);
      await tester.pump();
      expect(opens, 1);
      expect(input.starts, 0);
      var gesture = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(input.starts, 1);
      await gesture.up();
      await tester.pump();
      expect(captures, 1);
      expect(input.releases, 1);
      gesture = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -90));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(captures, 1);
      expect(input.stops, 2);
      expect(input.releases, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
