import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/planning/date_time_picker.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'package:semester_os/ui/app_date_time_picker.dart';
import 'package:semester_os/ui/app_time_range_picker.dart';
import 'package:semester_os/ui/clock_controls.dart';

import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

Finder endpoint(bool ending) =>
    find.byKey(ValueKey('range-clock-${ending ? 'end' : 'start'}'));
Finder column(Finder scope, bool hour) => find.descendant(
  of: scope,
  matching: find.byKey(
    Key(hour ? 'app-clock-hour-wheel' : 'app-clock-minute-wheel'),
  ),
);
Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> forward(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  final extent = tester.widget<ListWheelScrollView>(target).itemExtent;
  await tester.timedDrag(
    target,
    Offset(0, -extent),
    const Duration(milliseconds: 800),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void expectMinimal() {
  for (final text in ['小时', '分钟', '常用分钟', '键盘', '滚轮', '直接输入']) {
    expect(find.text(text), findsNothing);
  }
  expect(find.textContaining('时长'), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);

  testWidgets(
    'paired clock columns edit independently and allow explicit 24:00 only for end',
    (tester) async {
      AppClockRange? result;
      await mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => AppButton(
              onPressed: () async => result = await showAppClockRangePicker(
                context: context,
                initialStartMinutes: 1377,
                initialEndMinutes: 1439,
                allowEndOfDay: true,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tap(tester, find.text('打开'));
      expectMinimal();
      expect(find.byType(ListWheelScrollView), findsNWidgets(4));
      expect(
        tester.getTopLeft(endpoint(false)).dy,
        tester.getTopLeft(endpoint(true)).dy,
      );
      await forward(tester, column(endpoint(true), true));
      expect(tester.widget<AppMinuteWheel>(endpoint(true)).value, 1440);
      expect(tester.widget<AppMinuteWheel>(endpoint(false)).value, 1377);
      final endMinute = tester.widget<ListWheelScrollView>(
        column(endpoint(true), false),
      );
      expect(
        (endMinute.childDelegate as ListWheelChildBuilderDelegate).childCount,
        1,
      );
      expect(endMinute.physics, isA<NeverScrollableScrollPhysics>());
      final startHour = tester.widget<ListWheelScrollView>(
        column(endpoint(false), true),
      );
      expect(
        (startHour.childDelegate as ListWheelChildBuilderDelegate).childCount,
        24,
      );
      await capture(tester, 'minimal-paired-midnight');
      await tap(tester, find.byKey(const Key('clock-range-confirm')));
      expect(result!.startMinutes, 1377);
      expect(result!.endMinutes, 1440);
      expect(result!.endText, '24:00');
    },
  );

  testWidgets(
    'same-day range order validates while every arbitrary minute remains selectable',
    (tester) async {
      AppClockRange? result;
      await mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => AppButton(
              onPressed: () async => result = await showAppClockRangePicker(
                context: context,
                initialStartMinutes: 607,
                initialEndMinutes: 599,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tap(tester, find.text('打开'));
      await tap(tester, find.byKey(const Key('clock-range-confirm')));
      expect(find.text('结束时间需要晚于开始时间'), findsOneWidget);
      expect(result, isNull);
      final wheel = tester.widget<AppMinuteWheel>(endpoint(true));
      for (var minute = 0; minute < 60; minute++) {
        wheel.onChanged(660 + minute);
        await tester.pump();
        expect(
          tester.widget<AppMinuteWheel>(endpoint(true)).value,
          660 + minute,
        );
      }
      await tap(tester, find.byKey(const Key('clock-range-confirm')));
      expect(result!.endMinutes, 719);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '320dp clock pair stacks without overflow at text scale $scale',
      (tester) async {
        AppClockRange? result;
        await mount(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => AppButton(
                onPressed: () async => result = await showAppClockRangePicker(
                  context: context,
                  initialStartMinutes: 1437,
                  initialEndMinutes: 1440,
                  allowEndOfDay: true,
                ),
                child: const Text('打开'),
              ),
            ),
          ),
          width: 320,
          height: 640,
          textScale: scale,
        );
        await tap(tester, find.text('打开'));
        expectMinimal();
        final confirm = find.byKey(const Key('clock-range-confirm'));
        expect(confirm.hitTestable(), findsOneWidget);
        expect(tester.getBottomRight(confirm).dy, lessThanOrEqualTo(640));
        expect(
          tester.getTopLeft(endpoint(true)).dy,
          greaterThan(tester.getBottomLeft(endpoint(false)).dy),
        );
        await capture(tester, 'minimal-clock-320-$scale');
        await tap(tester, find.byKey(const Key('clock-range-confirm')));
        expect(result!.endMinutes, 1440);
      },
    );
  }

  testWidgets(
    'fixed confirmation remains visible for each time family at large text and landscape',
    (tester) async {
      for (final landscape in [false, true]) {
        final width = landscape ? 640.0 : 320.0;
        final height = landscape ? 360.0 : 640.0;
        final scale = landscape ? 1.0 : 2.0;
        final suffix = landscape ? 'landscape' : '320-2.0';
        Future<void> open(Future<void> Function(BuildContext) picker) async {
          await mount(
            tester,
            Scaffold(
              body: Builder(
                builder: (context) => AppButton(
                  onPressed: () => picker(context),
                  child: const Text('打开'),
                ),
              ),
            ),
            width: width,
            height: height,
            textScale: scale,
          );
          await tap(tester, find.text('打开'));
        }

        void visible(String key) {
          final confirm = find.byKey(Key(key));
          expect(confirm.hitTestable(), findsOneWidget);
          expect(tester.getBottomRight(confirm).dy, lessThanOrEqualTo(height));
          expect(tester.takeException(), isNull);
        }

        await open((context) async {
          await showAppDateTimePicker(
            context: context,
            initialDate: DateTime.utc(2026, 10, 4, 23, 57),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
        });
        visible('date-time-confirm');
        await capture(tester, 'minimal-datetime-calendar-$suffix');
        await tap(tester, find.byTooltip('取消选择'));

        await open((context) async {
          await showAppDateTimeRangePicker(
            context: context,
            initialStart: DateTime.utc(2026, 10, 4, 23, 57),
            initialEnd: DateTime.utc(2026, 10, 5, 0, 7),
            showLabel: true,
            initialLabel: '社团活动',
          );
        });
        visible('date-time-range-confirm');
        await capture(tester, 'minimal-datetime-pair-$suffix');
        await tap(tester, find.byKey(const ValueKey('range-date-start')));
        visible('date-time-range-confirm');
        await capture(tester, 'minimal-datetime-range-calendar-$suffix');
        await tap(tester, find.byTooltip('取消选择'));
      }
    },
  );

  testWidgets(
    'single date and clock share one sheet and preserve chosen wall fields',
    (tester) async {
      DateTime? result;
      await mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => AppButton(
              onPressed: () async => result = await showAppDateTimePicker(
                context: context,
                initialDate: DateTime.utc(2026, 10, 3, 23, 37),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tap(tester, find.text('打开'));
      await capture(tester, 'minimal-datetime-calendar');
      await tap(tester, find.text('4').last);
      expectMinimal();
      expect(find.byType(AppClockWheel), findsOneWidget);
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.byType(TimePickerDialog), findsNothing);
      tester
          .widget<AppClockWheel>(find.byType(AppClockWheel))
          .onChanged(const TimeOfDay(hour: 0, minute: 17));
      await tester.pumpAndSettle();
      await capture(tester, 'minimal-datetime-clock');
      await tap(tester, find.byKey(const Key('date-time-confirm')));
      expect(result, DateTime.utc(2026, 10, 4, 0, 17));
    },
  );

  testWidgets(
    'cross-day school range returns UTC instants and optional label; inline dates stay editable',
    (tester) async {
      AppDateTimeRange? result;
      final initialStart = DateTime.parse('2026-10-04T23:57:00+08:00');
      final initialEnd = DateTime.parse('2026-10-05T00:07:00+08:00');
      await mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => AppButton(
              onPressed: () async => result = await pickSchoolDateTimeRange(
                context,
                initialStart: initialStart,
                initialEnd: initialEnd,
                showLabel: true,
                initialLabel: '  社团活动  ',
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tap(tester, find.text('打开'));
      expectMinimal();
      await capture(tester, 'minimal-datetime-pair');
      await tap(tester, find.byKey(const ValueKey('range-date-end')));
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      await capture(tester, 'minimal-datetime-range-calendar');
      await tap(tester, find.text('6').last);
      expect(tester.widget<AppMinuteWheel>(endpoint(true)).value, 7);
      await tap(tester, find.byKey(const Key('date-time-range-confirm')));
      expect(result!.start, initialStart.toUtc());
      expect(result!.end, DateTime.parse('2026-10-06T00:07:00+08:00').toUtc());
      expect(result!.label, '社团活动');
      await tap(tester, find.text('打开'));
      await forward(tester, column(endpoint(false), false));
      await tap(tester, find.byTooltip('取消选择'));
      expect(result, isNull);
    },
  );
}
