import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/planning/availability_page.dart';
import 'package:semester_os/features/planning/date_time_picker.dart';
import 'package:semester_os/features/planning/schedule_page.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'package:semester_os/ui/clock_controls.dart';
import 'package:semester_os/ui/app_time_range_picker.dart';

import 'api_session_test.dart' show ControlledTransport, body;
import 'planning_flow_test.dart' show PlanningFixture, bind, ioTap, route;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

Finder clockEdge(bool ending) =>
    find.byKey(ValueKey('range-clock-${ending ? 'end' : 'start'}'));
Future<void> setClock(WidgetTester tester, bool ending, int minute) async {
  tester.widget<AppMinuteWheel>(clockEdge(ending)).onChanged(minute);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> clockRange(
  WidgetTester tester,
  ValueChanged<AppClockRange?> result, {
  int start = 487,
  int end = 604,
  bool midnight = false,
  double width = 390,
  double height = 844,
  double scale = 1,
}) async {
  await mount(
    tester,
    Scaffold(
      body: Builder(
        builder: (context) => AppButton(
          onPressed: () async => result(
            await showAppClockRangePicker(
              context: context,
              initialStartMinutes: start,
              initialEndMinutes: end,
              allowEndOfDay: midnight,
            ),
          ),
          child: const Text('打开时段'),
        ),
      ),
    ),
    width: width,
    height: height,
    textScale: scale,
  );
  await tap(tester, find.text('打开时段'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);

  testWidgets(
    'clock range preserves exact minutes and cancels the whole draft',
    (tester) async {
      AppClockRange? result;
      await clockRange(tester, (v) => result = v);
      expect(tester.widget<AppMinuteWheel>(clockEdge(false)).value, 487);
      expect(tester.widget<AppMinuteWheel>(clockEdge(true)).value, 604);
      await tap(tester, find.byKey(const Key('clock-range-confirm')));
      expect(result!.startMinutes, 487);
      expect(result!.endMinutes, 604);
      await tap(tester, find.text('打开时段'));
      await setClock(tester, false, 488);
      expect(tester.widget<AppMinuteWheel>(clockEdge(false)).value, 488);
      await tap(tester, find.byTooltip('取消选择'));
      expect(result, isNull);
    },
  );

  testWidgets('midnight is an explicit 24:00 wheel endpoint', (tester) async {
    AppClockRange? result;
    await clockRange(
      tester,
      (v) => result = v,
      start: 1437,
      end: 1440,
      midnight: true,
    );
    expect(tester.widget<AppMinuteWheel>(clockEdge(true)).value, 1440);

    await setClock(tester, false, 1439);
    await tap(tester, find.byKey(const Key('clock-range-confirm')));
    expect(result!.startText, '23:59');
    expect(result!.endText, '24:00');
    expect(result!.endMinutes, 1440);
  });

  testWidgets(
    'invalid original range stays editable without changing endpoints',
    (tester) async {
      AppClockRange? result;
      await clockRange(tester, (v) => result = v, start: 600, end: 510);
      await tap(tester, find.byKey(const Key('clock-range-confirm')));
      expect(find.text('结束时间需要晚于开始时间'), findsOneWidget);
      expect(tester.widget<AppMinuteWheel>(clockEdge(false)).value, 600);
      expect(tester.widget<AppMinuteWheel>(clockEdge(true)).value, 510);
      await setClock(tester, true, 607);
      await tap(tester, find.byKey(const Key('clock-range-confirm')));
      expect(result!.startMinutes, 600);
      expect(result!.endMinutes, 607);
    },
  );

  testWidgets('school range returns cross-day UTC instants and trimmed label', (
    tester,
  ) async {
    AppDateTimeRange? result;
    final start = DateTime.parse('2026-10-04T23:57:00+08:00');
    final end = DateTime.parse('2026-10-05T00:07:00+08:00');
    await mount(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => AppButton(
            onPressed: () async => result = await pickSchoolDateTimeRange(
              context,
              initialStart: start,
              initialEnd: end,
              showLabel: true,
              initialLabel: '  社团活动  ',
            ),
            child: const Text('打开日期时段'),
          ),
        ),
      ),
    );
    await tap(tester, find.text('打开日期时段'));
    expect(tester.widget<AppMinuteWheel>(clockEdge(false)).value, 1437);
    expect(tester.widget<AppMinuteWheel>(clockEdge(true)).value, 7);
    await tap(tester, find.byKey(const Key('date-time-range-confirm')));
    expect(result!.start, start.toUtc());
    expect(result!.end, end.toUtc());
    expect(result!.start.isUtc, isTrue);
    expect(result!.label, '社团活动');
    await tap(tester, find.text('打开日期时段'));
    await setClock(tester, true, 17);

    await tap(tester, find.byTooltip('取消选择'));
    expect(result, isNull);
  });

  testWidgets(
    'availability writes exact midnight only after page confirmation',
    (tester) async {
      final f = PlanningFixture();
      f.preferences = {
        'configured': true,
        'version': 1,
        'weekly': [
          {'weekday': 1, 'start': '23:57', 'end': '24:00'},
        ],
        'exclusions': <Map<String, dynamic>>[],
      };
      await bind(tester, f);
      await route(tester, AvailabilityPage(controller: f.c));
      await tap(tester, find.text('23:57—24:00'));
      await setClock(tester, false, 1439);
      await tap(tester, find.byTooltip('取消选择'));
      expect(find.text('23:57—24:00'), findsOneWidget);
      expect(f.puts, 0);
      await tap(tester, find.text('23:57—24:00'));
      await tap(tester, find.byKey(const Key('clock-range-confirm')));
      expect(f.puts, 0);
      await tester.ensureVisible(find.text('核对并保存学习时间'));
      await ioTap(tester, find.text('核对并保存学习时间'));
      expect(f.puts, 0);
      await ioTap(tester, find.text('确认保存学习时间'));
      expect(f.puts, 1);
      expect(f.preferences['weekly'], [
        {'weekday': 1, 'start': '23:57', 'end': '24:00'},
      ]);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'availability exclusion edits cross-day time and label in one sheet',
    (tester) async {
      final f = PlanningFixture();
      f.preferences = {
        'configured': true,
        'version': 1,
        'weekly': [
          {'weekday': 1, 'start': '19:07', 'end': '21:03'},
        ],
        'exclusions': [
          {
            'start_at': '2099-12-30T23:57:00+08:00',
            'end_at': '2099-12-31T00:07:00+08:00',
            'label': '社团活动',
          },
        ],
      };
      await bind(tester, f);
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: AppButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => AvailabilityPage(controller: f.c),
                ),
              ),
              child: const Text('打开设置'),
            ),
          ),
        ),
        width: 320,
        height: 640,
        textScale: 2,
      );
      await ioTap(tester, find.text('打开设置'));
      await tester.scrollUntilVisible(
        find.text('社团活动'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, find.text('社团活动'));
      expect(find.byType(AppDateTimeRangePicker), findsOneWidget);
      await capture(tester, 'range-exclusion-calendar-small-large');
      await setClock(tester, true, 780);
      final labelField = find.descendant(
        of: find.byKey(const Key('date-time-range-label')),
        matching: find.byType(EditableText),
      );
      await tester.ensureVisible(labelField);
      await tester.enterText(labelField, '  夜间实验  ');
      tester.view.viewInsets = const FakeViewPadding(bottom: 480);
      await tester.pumpAndSettle();
      await tester.ensureVisible(labelField);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('date-time-range-confirm')),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'range-exclusion-keyboard-small-large');
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('date-time-range-confirm')).hitTestable(),
        findsOneWidget,
      );
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('date-time-range-confirm')));
      expect(f.puts, 0);
      await tester.ensureVisible(find.text('核对并保存学习时间'));
      await ioTap(tester, find.text('核对并保存学习时间'));
      await ioTap(tester, find.text('确认保存学习时间'));
      expect(f.puts, 1);
      final saved = (f.preferences['exclusions'] as List).single as Map;
      expect(
        DateTime.parse(saved['start_at']),
        DateTime.parse('2099-12-30T23:57:00+08:00'),
      );
      expect(
        DateTime.parse(saved['end_at']),
        DateTime.parse('2099-12-31T13:00:00+08:00'),
      );
      expect(saved['label'], '夜间实验');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets('schedule candidate keeps 24:00 through one range confirmation', (
    tester,
  ) async {
    final f = ScheduleFixture();
    Map<String, dynamic>? saved;
    final previous = f.api.dio.httpClientAdapter as ControlledTransport;
    f.api.dio.httpClientAdapter = ControlledTransport((request) async {
      if (request.path.endsWith('/schedule/setup')) {
        return body({
          'revision': 1,
          'tasks': [
            {...f.item, 'can_schedule': true},
          ],
          'availability': {
            'needs_confirmation': true,
            'current': {'version': 1},
            'candidate': {
              'weekly': [
                {'weekday': 1, 'start': '23:57', 'end': '24:00'},
              ],
              'exclusions': [],
            },
          },
        });
      }
      if (request.path.endsWith('/availability') && request.method == 'PUT') {
        saved = Map<String, dynamic>.from(request.data);
        return body({'version': 2, 'revision': 2});
      }
      return previous.respond(request);
    });
    await tester.runAsync(() => f.c.bind('s'));
    await route(tester, SchedulePage(controller: f.c));
    await tap(tester, find.text('周一 · 23:57—24:00'));
    await setClock(tester, false, 1439);
    await tap(tester, find.byTooltip('取消选择'));
    expect(find.text('周一 · 23:57—24:00'), findsOneWidget);
    expect(saved, isNull);
    await tap(tester, find.text('周一 · 23:57—24:00'));
    await tap(tester, find.byKey(const Key('clock-range-confirm')));
    expect(saved, isNull);
    await ioTap(tester, find.text('确认时段并生成安排'));
    expect(saved!['weekly'], [
      {'weekday': 1, 'start': '23:57', 'end': '24:00'},
    ]);
    expect(f.generated, 1);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });

  testWidgets(
    'actual range sheet fits small large-text viewport and scrolls to confirmation',
    (tester) async {
      AppClockRange? result;
      await clockRange(
        tester,
        (v) => result = v,
        start: 1437,
        end: 1440,
        midnight: true,
        width: 320,
        height: 640,
        scale: 2,
      );
      await capture(tester, 'range-clock-small-large');

      final confirm = find.byKey(const Key('clock-range-confirm'));
      expect(confirm.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, confirm);
      expect(result!.endMinutes, 1440);
    },
  );
}
