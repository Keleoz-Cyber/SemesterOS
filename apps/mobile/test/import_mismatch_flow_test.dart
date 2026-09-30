import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/import/preview.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'controller_test.dart' show MemoryStore;
import 'ui_polish_test.dart' show mount;

void main() {
  testWidgets(
    'import with missing section leads to editable semester settings',
    (tester) async {
      final api = SemesterApi()..session = account('preview');
      api.dio.httpClientAdapter = ControlledTransport((request) async {
        if (request.path.endsWith('/imports')) {
          return body({
            'code': 'CALENDAR_MISMATCH',
            'message': '教务课表使用第11节，当前学期没有这节的时间',
          }, 422);
        }
        return body({});
      });
      final controller =
          AppController(api, MemoryStore(), clearSchoolSession: () async {})
            ..semester = {
              'id': 's',
              'name': '测试学期',
              'first_monday': '2026-08-31',
              'total_weeks': 20,
              'revision': 0,
              'periods': [
                {'number': 1, 'start': '08:00', 'end': '08:50'},
              ],
            };
      await mount(
        tester,
        Scaffold(
          body: ImportPreview(
            controller: controller,
            courses: const [
              {
                'title': '课程',
                'weekday': 1,
                'weeks': [1],
                'sections': [11],
              },
            ],
            source: 'haut_webview',
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      expect(find.textContaining('第11节'), findsAtLeastNWidgets(1));
      final action = find.text('修改学期周数或节次');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('修改学期设置'), findsOneWidget);
      controller.dispose();
    },
  );
}
