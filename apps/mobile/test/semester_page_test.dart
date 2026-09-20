import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/semester/semester_page.dart';
import 'package:semester_os/features/semester/semester_validation.dart';
import 'api_session_test.dart' show ControlledTransport, body, account;
import 'controller_test.dart' show MemoryStore;

void main() {
  testWidgets(
    'missing first Monday is explained inline without a network request',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var requests = 0;
      final api = SemesterApi();
      api.dio.httpClientAdapter = ControlledTransport((_) async {
        requests++;
        return body({'message': '请核对必填项、日期、节次和输入格式'}, 422);
      });
      final controller = AppController(
        api,
        MemoryStore(),
        clearSchoolSession: () async {},
      );
      await tester.pumpWidget(
        MaterialApp(home: SemesterPage(controller: controller)),
      );
      await tester.scrollUntilVisible(
        find.byType(CheckboxListTile),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.ensureVisible(find.text('确认创建学期'));
      await tester.tap(find.text('确认创建学期'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(find.text('请选择学校校历第1周的周一'), findsOneWidget);
    },
  );

  testWidgets(
    'first Monday opens a calendar instead of an empty keyboard field',
    (tester) async {
      final controller = AppController(
        SemesterApi(),
        MemoryStore(),
        clearSchoolSession: () async {},
      );
      await tester.pumpWidget(
        MaterialApp(home: SemesterPage(controller: controller)),
      );
      await tester.tap(find.byKey(const Key('first-monday')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.initialDate, isNull);
      expect(picker.selectableDayPredicate!(DateTime(2026, 8, 31)), true);
      expect(picker.selectableDayPredicate!(DateTime(2026, 9, 1)), false);
    },
  );

  test('invalid calendar dates and non-Mondays are not accepted', () {
    expect(validateFirstMonday('2026-02-31'), isNotNull);
    expect(validateFirstMonday('2026-09-01'), contains('必须是周一'));
    expect(validateFirstMonday('2026-08-31'), isNull);
    expect(validateTotalWeeks('0'), isNotNull);
    expect(validateTotalWeeks('20'), isNull);
  });

  test('period errors identify the row or conflicting period', () {
    expect(validateSemesterPeriods('1 25:00 26:00'), contains('第1行'));
    expect(
      validateSemesterPeriods('1 08:00 08:50\n1 09:00 09:50'),
      contains('重复'),
    );
    expect(
      validateSemesterPeriods('1 08:00 09:00\n2 08:50 09:50'),
      contains('重叠'),
    );
    expect(parseSemesterPeriods('1 08:00 08:50\n2 09:00 09:50'), [
      {'number': 1, 'start': '08:00', 'end': '08:50'},
      {'number': 2, 'start': '09:00', 'end': '09:50'},
    ]);
  });

  testWidgets('choosing a Monday and confirming creates the semester', (
    tester,
  ) async {
    Map<String, dynamic>? submitted;
    final api = SemesterApi()..session = account('student');
    api.dio.httpClientAdapter = ControlledTransport((request) async {
      if (request.method == 'POST' && request.path.endsWith('/semesters')) {
        submitted = Map<String, dynamic>.from(request.data);
        return body({'id': 'new-semester'}, 201);
      }
      if (request.path.endsWith('/semesters')) {
        return body([
          {...submitted!, 'id': 'new-semester', 'revision': 0},
        ]);
      }
      if (request.path.contains('/timetable')) {
        return body({'revision': 0, 'events': []});
      }
      return body({'id': 'student'});
    });
    final controller = AppController(
      api,
      MemoryStore(),
      clearSchoolSession: () async {},
    );
    final router = GoRouter(
      initialLocation: '/new',
      routes: [
        GoRoute(
          path: '/new',
          builder: (_, _) => SemesterPage(controller: controller),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('学期已创建')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
      ),
    );
    await tester.tap(find.byKey(const Key('first-monday')));
    await tester.pumpAndSettle();
    final now = schoolNow();
    var firstMonday = DateTime(now.year, now.month, 1);
    firstMonday = firstMonday.add(
      Duration(days: (8 - firstMonday.weekday) % 7),
    );
    await tester.tap(find.text('${firstMonday.day}').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(CheckboxListTile),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.text('确认创建学期'));
    await tester.tap(find.text('确认创建学期'));
    await tester.pumpAndSettle();
    expect(
      submitted!['first_monday'],
      firstMonday.toIso8601String().substring(0, 10),
    );
    expect(find.text('学期已创建'), findsOneWidget);
  });
}
