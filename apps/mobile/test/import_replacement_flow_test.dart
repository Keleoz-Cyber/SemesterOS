import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/import/preview.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'controller_test.dart' show MemoryStore;
import 'ui_polish_test.dart' show mount;

void main() {
  testWidgets('changed school course requires review before replacement', (
    tester,
  ) async {
    final old = {
      'title': '概率论',
      'weekday': 3,
      'weeks': [1, 3],
      'sections': [1, 2],
      'location': 'A305',
      'teacher': '',
    };
    final next = {
      ...old,
      'sections': [2, 3],
      'location': 'B404',
    };
    final api = SemesterApi()..session = account('preview');
    api.dio.httpClientAdapter = ControlledTransport((request) async {
      if (request.path.endsWith('/imports')) {
        return body({
          'id': 'batch',
          'semester_id': 's',
          'base_revision': 1,
          'new_count': 0,
          'unchanged_count': 0,
          'changed_count': 1,
          'changed_courses': [
            {'course_id': 'course', 'before': old, 'after': next},
          ],
        }, 201);
      }
      return body({});
    });
    final controller = AppController(
      api,
      MemoryStore(),
      clearSchoolSession: () async {},
    )..semester = {'id': 's', 'name': '真实学期'};
    await mount(
      tester,
      Scaffold(
        body: ImportPreview(
          controller: controller,
          courses: [next],
          source: 'haut_webview',
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
    expect(find.textContaining('原：'), findsOneWidget);
    expect(find.textContaining('新：'), findsOneWidget);
    final save = find.widgetWithText(AppButton, '确认保存课表');
    expect(tester.widget<AppButton>(save).onPressed, isNull);
    final check = find.text('我已核对，替换这些旧课次');
    await tester.scrollUntilVisible(
      check,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(tester.widget<AppButton>(save).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'school reimport keeps missing courses unless user opts to remove',
    (tester) async {
      final course = {
        'title': '软件工程',
        'weekday': 4,
        'weeks': [1, 3],
        'sections': [1, 2],
        'location': 'A305',
        'teacher': '',
      };
      final api = SemesterApi()..session = account('preview');
      api.dio.httpClientAdapter = ControlledTransport((request) async {
        if (request.path.endsWith('/imports')) {
          return body({
            'id': 'batch',
            'semester_id': 's',
            'base_revision': 1,
            'new_count': 0,
            'unchanged_count': 1,
            'changed_count': 0,
            'changed_courses': [],
            'missing_count': 1,
            'missing_courses': [
              {'course_id': 'old', 'before': course},
            ],
          }, 201);
        }
        return body({});
      });
      final controller = AppController(
        api,
        MemoryStore(),
        clearSchoolSession: () async {},
      )..semester = {'id': 's', 'name': '真实学期'};
      await mount(
        tester,
        Scaffold(
          body: ImportPreview(
            controller: controller,
            courses: [course],
            source: 'haut_webview',
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      final checkboxText = find.text('同时移除这些旧教务课程');
      await tester.scrollUntilVisible(
        checkboxText,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      final row = find.ancestor(
        of: checkboxText,
        matching: find.byType(AppCheckRow),
      );
      expect(tester.widget<AppCheckRow>(row).value, false);
      await tester.tap(checkboxText);
      await tester.pumpAndSettle();
      expect(tester.widget<AppCheckRow>(row).value, true);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
