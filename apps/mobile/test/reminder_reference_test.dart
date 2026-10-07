import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:semester_os/features/items/reminder_editor.dart';
import 'package:semester_os/ui/campus_theme.dart';
import 'package:semester_os/ui/forui_theme.dart';

// Keep reminder verification independent of unrelated app routes.
Future<void> mount(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: campusTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        FLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      builder: (_, child) => ShiriForuiTheme(child: child!),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('only an explicit usable anchor enables advance reminders', () {
    expect(reminderHasReferenceTime('task', {'precision': 'unknown'}), isFalse);
    expect(
      reminderHasReferenceTime('task', {
        'precision': 'date',
        'date': '2026-10-06',
      }),
      isFalse,
    );
    expect(
      reminderHasReferenceTime('task', {
        'precision': 'date',
        'day_end_confirmed': true,
      }),
      isTrue,
    );
    expect(
      reminderHasReferenceTime('exam', {
        'precision': 'date',
        'day_end_confirmed': true,
      }),
      isFalse,
    );
    const exact = {'precision': 'exact', 'at': '2026-10-06T09:00:00+08:00'};
    expect(reminderHasReferenceTime('task', exact), isTrue);
    expect(
      reminderHasReferenceTime('task', {...exact, 'meaning': 'start'}),
      isTrue,
    );
    expect(
      reminderHasReferenceTime('exam', {...exact, 'meaning': 'start'}),
      isTrue,
    );
    expect(
      reminderHasReferenceTime('task', {...exact, 'meaning': 'window'}),
      isFalse,
    );
  });
  testWidgets('a task without a deadline asks for the reminder time directly', (
    tester,
  ) async {
    await mount(
      tester,
      const ReminderEditor(kind: 'task', hasReferenceTime: false),
    );
    expect(find.text('选择提醒日期和时间'), findsOneWidget);
    expect(find.text('提前提醒'), findsNothing);
    expect(find.text('提前多久'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'an existing disabled advance rule can still be reviewed after its anchor is removed',
    (tester) async {
      await mount(
        tester,
        const ReminderEditor(
          kind: 'task',
          hasReferenceTime: false,
          initial: {'mode': 'relative', 'lead_minutes': 1440, 'enabled': false},
        ),
      );
      expect(find.text('提前提醒'), findsOneWidget);
      expect(find.text('指定时刻'), findsOneWidget);
      expect(find.text('提前1天'), findsOneWidget);
      await tester.tap(find.text('指定时刻'));
      await tester.pumpAndSettle();
      expect(find.text('选择提醒日期和时间'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('custom lead stays editable after entering a preset value', (
    tester,
  ) async {
    await mount(
      tester,
      const ReminderEditor(
        kind: 'event',
        initial: {'mode': 'relative', 'lead_minutes': 7, 'enabled': true},
      ),
    );
    await tester.enterText(find.byType(EditableText), '30');
    await tester.tap(find.text('更多设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('启用这条提醒'));
    await tester.tap(find.text('启用这条提醒'));
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '30',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
