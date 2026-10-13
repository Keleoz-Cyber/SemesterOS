import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/ui/app_text_entry_dialog.dart';
import 'ui_polish_test.dart' show mount, loadPreviewFonts;

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets(
    'typing and closing a dialog keeps controllers alive through reverse animation',
    (tester) async {
      Map<String, String>? result;
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<Map<String, String>>(
                  context: context,
                  builder: (_) => const AppTextEntryDialog(
                    title: '修改地点',
                    confirmLabel: '更新预览',
                    fields: [AppTextEntry('location', '地点')],
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '6108');
      await tester.tap(find.text('更新预览'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(result, {'location': '6108'});
      expect(tester.takeException(), isNull);
    },
  );
}
