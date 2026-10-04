import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/items/item_form.dart';
import 'package:semester_os/features/centers/exam_pages.dart';
import 'package:semester_os/features/centers/academic_visuals.dart';
import 'package:semester_os/features/semester/semester_page.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'package:semester_os/ui/app_date_time_picker.dart';
import 'package:semester_os/ui/clock_controls.dart';
import 'package:semester_os/ui/time_input_options.dart';
import 'controller_test.dart' show MemoryStore;
import 'calendar_flow_test.dart' show semester;
import 'api_session_test.dart' show ControlledTransport, body;
import 'inner_items_visual_test.dart' show fixture, settle, reveal;
import 'ui_polish_test.dart' show mount, loadPreviewFonts, capture;

Future<void> launch(
  WidgetTester tester,
  ValueChanged<DateTime?> onResult, {
  DateTime? initial,
  double scale = 1,
  double width = 390,
  AppDateTimeSection section = AppDateTimeSection.date,
}) async {
  await mount(
    tester,
    Scaffold(
      body: Builder(
        builder: (context) => AppButton(
          onPressed: () async => onResult(
            await showAppDateTimePicker(
              context: context,
              initialDate: initial ?? DateTime.utc(2026, 10, 3, 23, 37),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              initialSection: section,
            ),
          ),
          child: const Text('设置日期时间'),
        ),
      ),
    ),
    width: width,
    height: 740,
    textScale: scale,
  );
  await tester.tap(find.text('设置日期时间'));
  await tester.pumpAndSettle();
}

Finder input() => find.descendant(
  of: find.byKey(const Key('app-clock-input')),
  matching: find.byType(TextField),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);

  for (final scale in [1.0, 1.6]) {
    testWidgets(
      'one window commits the chosen day and arbitrary minute $scale',
      (tester) async {
        DateTime? result;
        await launch(
          tester,
          (value) => result = value,
          scale: scale,
          width: scale == 1 ? 390 : 320,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('23:37'), findsOneWidget);
        await capture(tester, 'datetime-calendar-$scale');
        await tester.tap(find.text('4').last);
        await tester.pumpAndSettle();
        expect(find.byType(AppClockWheel), findsOneWidget);
        expect(find.byType(DatePickerDialog), findsNothing);
        expect(find.byType(TimePickerDialog), findsNothing);
        expect(result, isNull);
        expect(tester.takeException(), isNull);
        await capture(tester, 'datetime-wheel-$scale');
        tester
            .widget<AppClockWheel>(find.byType(AppClockWheel))
            .onChanged(const TimeOfDay(hour: 0, minute: 17));
        await tester.pumpAndSettle();
        expect(
          tester.widget<AppClockWheel>(find.byType(AppClockWheel)).value,
          const TimeOfDay(hour: 0, minute: 17),
        );
        expect(tester.takeException(), isNull);
        await capture(tester, 'datetime-wheel-precise-$scale');
        await tester.tap(find.byKey(const Key('date-time-confirm')));
        await tester.pumpAndSettle();
        expect(result, DateTime.utc(2026, 10, 4, 0, 17));
      },
    );
  }

  testWidgets('clock draft survives calendar round trip and close cancels', (
    tester,
  ) async {
    DateTime? result;
    await launch(
      tester,
      (value) => result = value,
      section: AppDateTimeSection.time,
    );
    tester
        .widget<AppClockWheel>(find.byType(AppClockWheel))
        .onChanged(const TimeOfDay(hour: 0, minute: 17));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10月3日'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('00:17'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppClockWheel>(find.byType(AppClockWheel)).value,
      const TimeOfDay(hour: 0, minute: 17),
    );

    expect(tester.takeException(), isNull);
    await capture(tester, 'datetime-wheel-roundtrip');
    await tester.tap(find.byTooltip('取消选择'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byType(AppDateTimeSelection), findsNothing);
  });

  testWidgets('saved date outside picker defaults remains editable', (
    tester,
  ) async {
    DateTime? result;
    final existing = DateTime.utc(2122, 9, 4, 10, 5);
    await launch(tester, (value) => result = value, initial: existing);
    final calendar = tester.widget<CalendarDatePicker>(
      find.byKey(const Key('date-time-calendar')),
    );
    expect(calendar.initialDate, DateUtils.dateOnly(existing));
    expect(calendar.lastDate, DateUtils.dateOnly(existing));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('date-time-confirm')));
    await tester.pumpAndSettle();
    expect(result, existing);
  });

  testWidgets(
    'cancel adding an exact clock preserves the real item date precision',
    (tester) async {
      final f = await fixture(tester);
      await mount(
        tester,
        ItemFormPage(
          controller: f.c,
          semester: semester(),
          initial: {
            'id': 't',
            'title': '提交报名材料',
            'kind': 'task',
            'time': {'precision': 'date', 'date': '2026-10-03'},
          },
        ),
      );
      await settle(tester);
      await reveal(tester, find.text('添加具体时刻'));
      await tester.tap(find.text('添加具体时刻'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDateTimeSelection), findsOneWidget);
      expect(find.byType(DatePickerDialog), findsNothing);
      await tester.tap(find.byTooltip('取消选择'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TimeInputOptions>(find.byType(TimeInputOptions))
            .precision,
        'date',
      );
      expect(find.byKey(const Key('item-date')), findsOneWidget);
      expect(find.byKey(const Key('item-date-time')), findsNothing);
      expect(find.textContaining('10月3日'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'item-date-cancel');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'Monday guide includes a future saved draft and cancel keeps it',
    (tester) async {
      final original = {
        'id': 's',
        'name': '未来学期',
        'first_monday': '2040-09-04',
        'total_weeks': 20,
        'revision': 1,
        'periods': [
          {'number': 1, 'start': '08:00', 'end': '08:50'},
        ],
      };
      final controller = AppController(
        SemesterApi(),
        MemoryStore(),
        clearSchoolSession: () async {},
      );
      await mount(
        tester,
        SemesterPage(controller: controller, existing: original),
      );
      await tester.tap(find.byKey(const Key('first-monday')));
      await tester.pumpAndSettle();
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      final saved = DateTime.parse(original['first_monday'] as String);
      final guide = saved.subtract(Duration(days: saved.weekday - 1));
      expect(picker.initialDate, guide);
      expect(picker.lastDate.isBefore(guide), isFalse);
      expect(picker.selectableDayPredicate!(guide), isTrue);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('2040-09-04'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'exam precision changes retain dates and confirmed cross-day clocks',
    (tester) async {
      final f = await fixture(tester);
      Map<String, dynamic>? sent;
      final transport = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/reschedule/preview')) {
          sent = Map<String, dynamic>.from(r.data);
          return body({'message': '仅验证改期请求'}, 422);
        }
        return transport.respond(r);
      });
      await mount(
        tester,
        ExamReschedulePage(
          controller: f.c,
          exam: {
            'id': 'x',
            'semester_id': 's',
            'title': '概率论考试',
            'kind': 'exam',
            'certainty': 'formal',
            'version': 4,
            'time': {
              'precision': 'exact',
              'at': '2026-10-03T23:37:00+08:00',
              'end_at': '2026-10-04T00:17:00+08:00',
            },
          },
        ),
      );
      await reveal(tester, find.text('只记日期'));
      await tester.tap(find.text('只记日期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5').last);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加具体时刻'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppDateTimeSelection>(find.byType(AppDateTimeSelection))
            .value,
        DateTime.utc(2026, 10, 5, 23, 37),
      );
      await tester.tap(find.byTooltip('取消选择'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TimeInputOptions>(find.byType(TimeInputOptions))
            .precision,
        'date',
      );
      await tester.tap(find.text('时间方式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日期范围'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新结束'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6').last);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加日期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加具体时刻'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('date-time-confirm')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TimeInputOptions>(find.byType(TimeInputOptions))
            .precision,
        'exact',
      );
      expect(
        tester
            .widget<AcademicMomentControl>(
              find.byWidgetPredicate(
                (w) => w is AcademicMomentControl && w.label == '新开始',
              ),
            )
            .value,
        contains('23:37'),
      );
      expect(
        tester
            .widget<AcademicMomentControl>(
              find.byWidgetPredicate(
                (w) => w is AcademicMomentControl && w.label == '新结束',
              ),
            )
            .value,
        contains('00:17'),
      );
      await capture(tester, 'exam-preserved-cross-day');
      await tester.runAsync(() async {
        await tester.tap(find.text('查看改期影响'));
        await Future<void>.delayed(const Duration(milliseconds: 90));
      });
      await tester.pumpAndSettle();
      expect(sent?['time'], {
        'precision': 'exact',
        'at': '2026-10-05T15:37:00.000Z',
        'end_at': '2026-10-05T16:17:00.000Z',
      });
      expect(sent?['expected_version'], 4);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'adding an exact exam start does not invent a date-only end clock',
    (tester) async {
      final f = await fixture(tester);
      Map<String, dynamic>? sent;
      final transport = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/reschedule/preview')) {
          sent = Map<String, dynamic>.from(r.data);
          return body({'message': '仅验证改期请求'}, 422);
        }
        return transport.respond(r);
      });
      await mount(
        tester,
        ExamReschedulePage(
          controller: f.c,
          exam: {
            'id': 'x',
            'semester_id': 's',
            'title': '概率论考试',
            'kind': 'exam',
            'certainty': 'formal',
            'version': 4,
            'time': {
              'precision': 'range',
              'date': '2026-10-03',
              'end_date': '2026-10-04',
            },
          },
        ),
      );
      await reveal(tester, find.text('添加日期'));
      await tester.tap(find.text('添加日期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加具体时刻'));
      await tester.pumpAndSettle();
      tester
          .widget<AppClockWheel>(find.byType(AppClockWheel))
          .onChanged(const TimeOfDay(hour: 23, minute: 37));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('date-time-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('添加结束时间'), findsOneWidget);
      expect(find.text('结束时刻待确认'), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.text('查看改期影响'));
        await Future<void>.delayed(const Duration(milliseconds: 90));
      });
      await tester.pumpAndSettle();
      expect(sent?['time'], {
        'precision': 'exact',
        'at': '2026-10-03T15:37:00.000Z',
        'end_at': null,
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
}
