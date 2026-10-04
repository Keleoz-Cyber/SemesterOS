import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/import/manual_page.dart';
import 'package:semester_os/ui/app_number_picker.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'planning_flow_test.dart' show ioTap;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets('course edit waits for explicit confirmation before PATCH', (
    tester,
  ) async {
    final fixture = ScheduleFixture();
    await tester.runAsync(() => fixture.c.bind('s'));
    final previous = fixture.api.dio.httpClientAdapter as ControlledTransport;
    var patches = 0;
    Map<String, dynamic>? sent;
    fixture.api.dio.httpClientAdapter = ControlledTransport((request) async {
      if (request.method == 'PATCH' && request.path.endsWith('/courses/c')) {
        patches++;
        sent = Map<String, dynamic>.from(request.data);
        return body({
          'id': 'c',
          'semester_id': 's',
          'revision': 2,
          'course': sent,
        });
      }
      return previous.respond(request);
    });
    final old = {
      'title': '概率论',
      'teacher': '教师甲',
      'location': 'A305',
      'source_id': '',
      'weekday': 3,
      'weeks': [1, 3, 5],
      'sections': [1, 2],
      'start_time': '10:00',
      'end_time': '11:35',
      'attendance_exempt': true,
    };
    final semester = {
      'total_weeks': 8,
      // The school's original clock range is valid without these two period
      // numbers being present in the manually configured bell schedule.
      'periods': [
        {'number': 5, 'start': '14:00', 'end': '14:50'},
        {'number': 6, 'start': '15:00', 'end': '15:50'},
      ],
    };
    await mount(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ManualPage.edit(
                  items: fixture.c,
                  existing: old,
                  revision: 1,
                  courseId: 'c',
                  semester: semester,
                ),
              ),
            ),
            child: const Text('打开课程'),
          ),
        ),
      ),
      width: 390,
    );
    await tester.tap(find.text('打开课程'));
    await tester.pumpAndSettle();
    expect(find.text('编辑课程'), findsOneWidget);
    expect(find.text('1,3,5'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('course-weeks')));
    await tester.tap(find.bySemanticsLabel('选择周次'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.bySemanticsLabel('第8周'), findsOneWidget);
    expect(find.bySemanticsLabel('第9周'), findsNothing);
    await tester.tap(find.text('单周'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('取消选择'));
    await tester.pumpAndSettle();
    expect(find.text('第1–5周（单周）'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('选择周次'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('单周'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('第1–7周（单周）'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('course-sections')));
    await tester.tap(find.bySemanticsLabel('选择节次'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('第1节'), findsOneWidget);
    expect(find.bySemanticsLabel('第6节'), findsOneWidget);
    expect(find.bySemanticsLabel('第3节'), findsNothing);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存课程'));
    await tester.pumpAndSettle();
    expect(patches, 0);
    expect(find.text('确认修改课程？'), findsOneWidget);
    await capture(tester, 'manual-course-save-confirm');
    await ioTap(tester, find.text('确认保存'));
    expect(patches, 1);
    expect(sent?['expected_revision'], 1);
    expect(sent?['sections'], [1, 2]);
    expect(sent?['weeks'], [1, 3, 5, 7]);
    expect(sent?['start_time'], '10:00');
    expect(sent?['end_time'], '11:35');
    expect(sent?['attendance_exempt'], true);
    await tester.pumpWidget(const SizedBox());
    fixture.c.dispose();
  });

  testWidgets('number grid keeps confirm reachable with large landscape text', (
    tester,
  ) async {
    var saved = <int>[];
    await mount(
      tester,
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: AppNumberPickerField(
              label: '周次',
              unit: '周',
              values: const [1],
              options: List.generate(20, (i) => i + 1),
              weekShortcuts: true,
              onChanged: (value) => saved = value,
            ),
          ),
        ),
      ),
      width: 844,
      height: 390,
      textScale: 2,
    );
    await tester.tap(find.bySemanticsLabel('选择周次'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final confirm = find.widgetWithText(AppButton, '确定');
    expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(390));
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(saved, [1]);
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
