import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/semester/period_editor.dart';
import 'package:semester_os/ui/detail_widgets.dart';
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets(
    'quick buttons append a reviewable period and remove only the last',
    (tester) async {
      final times = TextEditingController(text: '1 08:00 08:50\n2 09:00 09:50');
      final field = GlobalKey<FormFieldState<String>>();
      await mount(
        tester,
        Scaffold(
          body: Form(
            child: ListView(
              children: [
                PeriodEditor(controller: times, fieldKey: field, enabled: true),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('添加一节'));
      await tester.pumpAndSettle();
      expect(times.text, '1 08:00 08:50\n2 09:00 09:50\n3 10:00 10:50');
      expect(find.text('10:00'), findsOneWidget);
      expect(find.textContaining('建议值'), findsNothing);
      await capture(tester, 'period-quick-actions-normal');
      await tester.tap(find.byTooltip('减少一节'));
      await tester.pumpAndSettle();
      expect(times.text, '1 08:00 08:50\n2 09:00 09:50');
      expect(field.currentState!.validate(), isTrue);
      await tester.pumpWidget(const SizedBox());
      times.dispose();
    },
  );

  testWidgets('quick removal never leaves a semester without periods', (
    tester,
  ) async {
    final times = TextEditingController(text: '1 08:00 08:50');
    final field = GlobalKey<FormFieldState<String>>();
    await mount(
      tester,
      Scaffold(
        body: Form(
          child: ListView(
            children: [
              PeriodEditor(controller: times, fieldKey: field, enabled: true),
            ],
          ),
        ),
      ),
    );
    expect(find.byTooltip('减少一节'), findsOneWidget);
    await tester.tap(find.byTooltip('减少一节'));
    await tester.pumpAndSettle();
    expect(times.text, '1 08:00 08:50');
    await tester.pumpWidget(const SizedBox());
    times.dispose();
  });

  testWidgets('quick controls fit a narrow screen with larger text', (
    tester,
  ) async {
    final times = TextEditingController(text: '1 08:00 08:50\n2 09:00 09:50');
    final field = GlobalKey<FormFieldState<String>>();
    await mount(
      tester,
      Scaffold(
        body: Form(
          child: ListView(
            children: [
              PeriodEditor(controller: times, fieldKey: field, enabled: true),
            ],
          ),
        ),
      ),
      width: 320,
      textScale: 1.6,
    );
    expect(find.byTooltip('添加一节'), findsOneWidget);
    expect(find.byTooltip('减少一节'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'period-quick-actions-large');
    await tester.pumpWidget(const SizedBox());
    times.dispose();
  });

  testWidgets(
    'period picker changes only the chosen clock and keeps the full schedule',
    (tester) async {
      final times = TextEditingController(text: '1 08:00 08:50\n2 09:00 09:50');
      final field = GlobalKey<FormFieldState<String>>();
      await mount(
        tester,
        Scaffold(
          body: Form(
            child: ListView(
              children: [
                EditorSection(
                  title: '节次',
                  icon: Icons.schedule,
                  children: [
                    PeriodEditor(
                      controller: times,
                      fieldKey: field,
                      enabled: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('08:00'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      Navigator.pop(
        tester.element(find.byType(TimePickerDialog)),
        const TimeOfDay(hour: 7, minute: 45),
      );
      await tester.pumpAndSettle();
      expect(times.text, '1 07:45 08:50\n2 09:00 09:50');
      expect(field.currentState!.validate(), isTrue);
      await tester.pumpWidget(const SizedBox());
      times.dispose();
    },
  );
  testWidgets(
    'invalid bulk draft stays editable and cannot validate as a schedule',
    (tester) async {
      final times = TextEditingController(text: '1 08:00 08:50\n2 09:00 09:50');
      final field = GlobalKey<FormFieldState<String>>();
      await mount(
        tester,
        Scaffold(
          body: Form(
            child: ListView(
              children: [
                EditorSection(
                  title: '节次',
                  icon: Icons.schedule,
                  children: [
                    PeriodEditor(
                      controller: times,
                      fieldKey: field,
                      enabled: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      times.text = '1 08:00 08:50\n1 09:00 09:50';
      await tester.pumpAndSettle();
      expect(field.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('第2行的第1节重复了'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        times.text,
      );
      await tester.pumpWidget(const SizedBox());
      times.dispose();
    },
  );
}
