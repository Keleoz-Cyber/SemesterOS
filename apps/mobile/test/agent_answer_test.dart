import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/agent/agent_answer.dart';
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets(
    'assistant formats emphasis and lists without fetching model images',
    (tester) async {
      await mount(
        tester,
        const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: AgentAnswer(
              '你添加的提醒是：\n\n- **提醒时间**：2026-09-27 11:43\n- **事项**：领取材料\n\n![来源截图](https://example.invalid/private.png)',
            ),
          ),
        ),
        width: 360,
        textScale: 1.6,
      );
      final rendered = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((w) => w.textSpan?.toPlainText() ?? w.data ?? '')
          .join('\n');
      expect(rendered, contains('提醒时间：2026-09-27 11:43'));
      expect(rendered, contains('事项：领取材料'));
      expect(rendered, isNot(contains('**')));
      expect(find.byType(Image), findsNothing);
      expect(find.text('来源截图'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'assistant-rich-answer');
    },
  );
}
