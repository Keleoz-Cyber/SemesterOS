import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/planning/availability_bulk_sheet.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'package:semester_os/ui/app_time_range_picker.dart';
import 'ui_polish_test.dart' show mount, loadPreviewFonts, capture;

void main() {
  setUpAll(loadPreviewFonts);
  test('weekly batch preserves other days and merges overlapping ranges', () {
    final existing = [
      {'weekday': 1, 'start': '19:00', 'end': '21:00'},
      {'weekday': 6, 'start': '09:00', 'end': '10:00'},
    ];
    final pattern = WeeklyTimePattern(
      days: {1, 3},
      windows: const [
        AppClockRange(startMinutes: 1170, endMinutes: 1290),
        AppClockRange(startMinutes: 465, endMinutes: 517),
      ],
    );
    final result = applyWeeklyPattern(existing, pattern);
    expect(result, [
      {'weekday': 1, 'start': '07:45', 'end': '08:37'},
      {'weekday': 1, 'start': '19:00', 'end': '21:30'},
      {'weekday': 3, 'start': '07:45', 'end': '08:37'},
      {'weekday': 3, 'start': '19:30', 'end': '21:30'},
      {'weekday': 6, 'start': '09:00', 'end': '10:00'},
    ]);
    final replace = applyWeeklyPattern(
      existing,
      WeeklyTimePattern(
        days: {1},
        windows: const [AppClockRange(startMinutes: 1380, endMinutes: 1440)],
        replace: true,
      ),
    );
    expect(replace, [
      {'weekday': 1, 'start': '23:00', 'end': '24:00'},
      {'weekday': 6, 'start': '09:00', 'end': '10:00'},
    ]);
    expect(
      WeeklyTimePattern.fromJson(pattern.toJson())!.windows.last.endText,
      '08:37',
    );
  });
  testWidgets(
    'custom weekday combination is cancellable and applies several precise ranges',
    (tester) async {
      WeeklyTimePattern? result;
      final initial = WeeklyTimePattern(
        days: {1, 3},
        windows: const [
          AppClockRange(startMinutes: 465, endMinutes: 517),
          AppClockRange(startMinutes: 1150, endMinutes: 1265),
        ],
      );
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: AppButton(
              onPressed: () async {
                result = await showWeeklyTimePattern(context, initial);
              },
              child: const Text('打开批量设置'),
            ),
          ),
        ),
        width: 320,
        height: 720,
        textScale: 1.4,
      );
      await tester.tap(find.text('打开批量设置'));
      await tester.pumpAndSettle();
      expect(find.text('07:45—08:37'), findsOneWidget);
      expect(find.text('19:10—21:05'), findsOneWidget);
      await tester.tap(find.byTooltip('取消选择'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('打开批量设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('工作日'));
      await tester.pumpAndSettle();
      await capture(tester, 'bulk-weekly-custom-large');
      await tester.tap(find.byKey(const Key('bulk-apply')));
      await tester.pumpAndSettle();
      expect(result!.days, {1, 2, 3, 4, 5});
      expect(result!.windows.map((w) => w.startText), ['07:45', '19:10']);
      expect(result!.replace, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
