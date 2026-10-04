import 'package:semester_os/ui/forui_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/import/school_picker.dart';

void main() {
  testWidgets(
    'school choice distinguishes supported school and manual fallback',
    (tester) async {
      var selected = 0, manual = 0;
      String? schoolId;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ShiriForuiTheme(child: child!),
          home: SchoolPickerPage(
            onSelect: (school) {
              selected++;
              schoolId = school.id;
            },
            onManual: () => manual++,
          ),
        ),
      );
      await tester.tap(find.text('河南工业大学'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(schoolId, 'haut');
      await tester.enterText(find.byType(TextField), '哈尔滨');
      await tester.pump();
      expect(find.text('河南工业大学'), findsNothing);
      expect(find.text('黑龙江大学'), findsOneWidget);
      expect(find.text('本科教务课表'), findsOneWidget);
      await tester.tap(find.text('黑龙江大学'));
      await tester.pumpAndSettle();
      expect(schoolId, 'hlju');
      await tester.enterText(find.byType(TextField), '不存在的示例高校');
      await tester.pump();
      expect(find.text('河南工业大学'), findsNothing);
      expect(find.textContaining('暂未适配'), findsOneWidget);
      await tester.ensureVisible(find.text('手工添加课程'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手工添加课程'));
      await tester.pumpAndSettle();
      expect(manual, 1);
    },
  );
}
