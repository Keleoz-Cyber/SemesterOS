import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/timetable/semester_view.dart';
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets(
    'semester management exposes edit and delete without hiding import',
    (tester) async {
      final current = {
        'id': 's',
        'name': '测试学期',
        'first_monday': '2026-08-31',
        'total_weeks': 20,
        'revision': 2,
      };
      var edits = 0, deletes = 0;
      await mount(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SemesterView(
              semesters: [current],
              current: current,
              onSelect: (_) {},
              onCreate: () {},
              onImport: () {},
              onManual: () {},
              onEdit: () => edits++,
              onDelete: () => deletes++,
            ),
          ),
        ),
        width: 390,
      );
      expect(find.text('修改校历与节次'), findsOneWidget);
      expect(find.text('删除当前学期'), findsOneWidget);
      expect(find.text('重新导入教务课表'), findsOneWidget);
      await tester.ensureVisible(find.text('修改校历与节次'));
      await tester.tap(find.text('修改校历与节次'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('删除当前学期'));
      await tester.tap(find.text('删除当前学期'));
      await tester.pumpAndSettle();
      expect(edits, 1);
      expect(deletes, 1);
      await capture(tester, 'semester-management-actions');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('management actions remain reachable at 320dp and large text', (
    tester,
  ) async {
    final current = {
      'id': 's',
      'name': '2026—2027学年第一学期',
      'first_monday': '2026-08-31',
      'total_weeks': 20,
      'revision': 2,
    };
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SemesterView(
            semesters: [current],
            current: current,
            onSelect: (_) {},
            onCreate: () {},
            onImport: () {},
            onManual: () {},
            onEdit: () {},
            onDelete: () {},
          ),
        ),
      ),
      width: 320,
      height: 760,
      textScale: 2,
    );
    await tester.scrollUntilVisible(
      find.text('删除当前学期'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('删除当前学期'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'semester-management-large');
    await tester.pumpWidget(const SizedBox());
  });
}
