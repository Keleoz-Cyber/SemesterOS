import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/ui/app_picker_field.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/features/media/hold_voice_button.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'centers_flow_test.dart' show settleIo;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  testWidgets('single value sheet can search and explicitly clear a value', (
    tester,
  ) async {
    String? value = '3';
    await mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: AppPickerField<String>(
            initialValue: value,
            decoration: const InputDecoration(labelText: '关联课程'),
            items: [
              const DropdownMenuItem(value: null, child: Text('不关联课程')),
              for (var i = 0; i < 12; i++)
                DropdownMenuItem(value: '$i', child: Text('课程$i')),
            ],
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      ),
      textScale: 1.6,
    );
    await tester.tap(find.byType(AppPickerField<String>));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不关联');
    await tester.pumpAndSettle();
    await capture(tester, 'picker-search-large');
    await tester.tap(find.text('不关联课程'));
    await tester.pumpAndSettle();
    expect(value, isNull);
    expect(find.text('不关联课程'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.6]) {
    testWidgets(
      'voice mode uses the same composer and preserves typed draft $scale',
      (tester) async {
        final f = ScheduleFixture();
        final old = f.api.dio.httpClientAdapter as ControlledTransport;
        f.api.dio.httpClientAdapter = ControlledTransport((r) async {
          if (r.path.contains('/agent/threads?')) return body([]);
          return old.respond(r);
        });
        await tester.runAsync(() => f.c.bind('s'));
        await mount(
          tester,
          AgentPage(
            controller: f.c,
            semester: const {'id': 's', 'name': '本学期'},
            initialMediaKind: 'audio',
          ),
          textScale: scale,
        );
        await settleIo(tester);
        expect(find.byType(HoldVoiceButton), findsOneWidget);

        expect(find.text('开始录音'), findsNothing);
        await capture(tester, 'voice-composer-$scale');
        await tester.tap(find.byTooltip('切换键盘输入'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '明天下午四点组会');
        await tester.tap(find.byTooltip('切换语音输入'));
        await tester.pumpAndSettle();
        expect(find.byType(HoldVoiceButton), findsOneWidget);
        await tester.tap(find.byTooltip('切换键盘输入'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          '明天下午四点组会',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        f.c.dispose();
      },
    );
  }
}
