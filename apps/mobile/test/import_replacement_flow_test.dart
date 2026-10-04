import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/import/preview.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'controller_test.dart' show MemoryStore;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets('HLJU extras share review and require a first-week choice', (
    tester,
  ) async {
    final exam = {
      'kind': 'exam',
      'source_id': 'hlju:exam',
      'title': '软件工程考试',
      'start_at': '2026-12-15T09:00:00+08:00',
      'end_at': '2026-12-15T11:00:00+08:00',
    };
    final practice = {
      'kind': 'unplaced_course',
      'source_id': 'hlju:practice',
      'title': '专业实践',
      'teacher': '李老师',
      'weeks': [17, 18],
    };
    Map? previewRequest;
    final api = SemesterApi()..session = account('hlju-preview');
    api.dio.httpClientAdapter = ControlledTransport((request) async {
      if (request.path.endsWith('/imports')) {
        previewRequest = request.data as Map;
        return body({
          'id': 'batch',
          'semester_id': 's',
          'base_revision': 1,
          'new_count': 0,
          'unchanged_count': 0,
          'new_extra_count': 1,
          'unchanged_extra_count': 0,
          'changed_count': 1,
          'changed_courses': [],
          'changed_extras': [
            {
              'resource_id': 'exam',
              'kind': 'exam',
              'before': exam,
              'after': exam,
            },
          ],
          'protected_extras': [
            {
              'resource_id': 'practice',
              'kind': 'unplaced_course',
              'before': practice,
              'after': practice,
            },
          ],
        }, 201);
      }
      return body({});
    });
    final controller = AppController(
      api,
      MemoryStore(),
      clearSchoolSession: () async {},
    )..semester = {'id': 's', 'name': '真实学期', 'first_monday': '2026-08-31'};
    await mount(
      tester,
      Scaffold(
        body: ImportPreview(
          controller: controller,
          courses: const [],
          extras: [exam, practice],
          source: 'hlju_webview',
          sourceTerm: '2026—2027 第一学期',
          sourceFirstMonday: '2026-08-24',
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
    expect(previewRequest!['extras'], [exam, practice]);
    expect(previewRequest!['source_first_monday'], '2026-08-24');
    final save = find.widgetWithText(AppButton, '确认保存课表');
    expect(tester.widget<AppButton>(save).onPressed, isNull);
    await capture(tester, 'import-calendar-choice');
    await tester.ensureVisible(find.text('保留当前日期'));
    await tester.tap(find.text('保留当前日期'));
    await tester.pumpAndSettle();
    expect(controller.semester!['first_monday'], '2026-08-31');
    await tester.scrollUntilVisible(
      find.text('2026/12/15 09:00—11:00'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('2026/12/15 09:00—11:00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('第17—18周 · 教师 李老师'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('第17—18周 · 教师 李老师'), findsOneWidget);
    await tester.ensureVisible(find.text('考试与实践安排 · 2'));
    await capture(tester, 'import-extra-dated-and-unplaced');
    await tester.scrollUntilVisible(
      find.text('保留你修改的安排'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('保留你修改的安排'), findsOneWidget);
    final check = find.text('我已核对，更新这些安排');
    await tester.scrollUntilVisible(
      check,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(tester.widget<AppButton>(save).onPressed, isNotNull);
    expect(find.textContaining('未填写'), findsNothing);
    expect(find.textContaining('默认'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

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
    expect(find.text('第1–2节'), findsOneWidget);
    expect(find.text('第2–3节'), findsAtLeastNWidgets(1));
    expect(find.text('A305'), findsOneWidget);
    expect(find.text('B404'), findsAtLeastNWidgets(1));
    await capture(tester, 'import-comparison');
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
