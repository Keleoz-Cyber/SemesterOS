import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/import/school_picker.dart';

void main() {
  testWidgets(
    'school choice distinguishes supported school and manual fallback',
    (tester) async {
      var selected = 0, manual = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SchoolPickerPage(
            onSelect: () => selected++,
            onManual: () => manual++,
          ),
        ),
      );
      await tester.tap(find.text('河南工业大学'));
      expect(selected, 1);
      await tester.enterText(find.byType(TextField), '不存在的示例高校');
      await tester.pump();
      expect(find.text('河南工业大学'), findsNothing);
      expect(find.textContaining('暂未适配'), findsOneWidget);
      await tester.tap(find.text('手工添加课程'));
      expect(manual, 1);
    },
  );
}
