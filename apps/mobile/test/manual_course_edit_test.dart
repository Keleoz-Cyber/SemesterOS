import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/import/manual_page.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount;

void main() {
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
                ),
              ),
            ),
            child: const Text('打开课程'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开课程'));
    await tester.pumpAndSettle();
    expect(find.text('编辑课程'), findsOneWidget);
    await tester.tap(find.text('保存课程'));
    await tester.pumpAndSettle();
    expect(patches, 0);
    expect(find.text('确认修改课程？'), findsOneWidget);
    await tester.tap(find.text('确认保存'));
    await tester.pumpAndSettle();
    expect(patches, 1);
    expect(sent?['expected_revision'], 1);
    expect(sent?['sections'], [1, 2]);
    await tester.pumpWidget(const SizedBox());
    fixture.c.dispose();
  });
}
