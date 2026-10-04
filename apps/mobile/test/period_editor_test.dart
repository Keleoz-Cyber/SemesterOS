import 'package:semester_os/ui/app_time_range_picker.dart';
import 'package:semester_os/ui/clock_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/semester/period_editor.dart';
import 'package:semester_os/ui/detail_widgets.dart';
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets(
    'confirming a picker preserves other period changes made while it was open',
    (tester) async {
      final times = TextEditingController(text: '1 08:00 08:50\n2 10:10 11:00');
      final field = GlobalKey<FormFieldState<String>>();
      await mount(
        tester,
        Scaffold(
          body: ListView(
            children: [
              PeriodEditor(controller: times, fieldKey: field, enabled: true),
            ],
          ),
        ),
      );
      await tester.tap(find.text('08:00'));
      await tester.pumpAndSettle();
      times.text = '1 08:00 08:50\n2 10:30 11:30';
      Navigator.pop(
        tester.element(find.byType(AppClockRangePicker)),
        const AppClockRange(startMinutes: 465, endMinutes: 530),
      );
      await tester.pumpAndSettle();
      expect(times.text, '1 07:45 08:50\n2 10:30 11:30');
      await tester.pumpWidget(const SizedBox());
      times.dispose();
    },
  );
  testWidgets(
    'canceling a clock draft changes no period and leaves prior keyboard closed',
    (tester) async {
      final previous = FocusNode();
      final times = TextEditingController(text: '1 10:10 11:00');
      final field = GlobalKey<FormFieldState<String>>();
      await mount(
        tester,
        Scaffold(
          body: ListView(
            children: [
              TextField(focusNode: previous),
              PeriodEditor(controller: times, fieldKey: field, enabled: true),
            ],
          ),
        ),
        textScale: 1.6,
      );
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.tap(find.text('10:10'));
      await tester.pumpAndSettle();
      tester
          .widget<AppMinuteWheel>(
            find.byKey(const ValueKey('range-clock-start')),
          )
          .onChanged(600);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(times.text, '1 10:10 11:00');
      expect(previous.hasFocus, isFalse);
      await tester.pumpWidget(const SizedBox());
      previous.dispose();
      times.dispose();
    },
  );
  testWidgets('replacing the draft controller detaches the old one', (
    tester,
  ) async {
    final old = TextEditingController(text: '1 08:00 08:50');
    final next = TextEditingController(text: '1 09:00 09:50');
    final selected = ValueNotifier(old);
    final field = GlobalKey<FormFieldState<String>>();
    await mount(
      tester,
      Scaffold(
        body: ValueListenableBuilder(
          valueListenable: selected,
          builder: (_, controller, _) => ListView(
            children: [
              PeriodEditor(
                controller: controller,
                fieldKey: field,
                enabled: true,
              ),
            ],
          ),
        ),
      ),
    );
    selected.value = next;
    await tester.pumpAndSettle();
    old.text = 'invalid';
    await tester.pumpAndSettle();
    expect(find.text('09:00'), findsOneWidget);
    expect(field.currentState!.value, next.text);
    expect(field.currentState!.validate(), isTrue);
    await tester.pumpWidget(const SizedBox());
    old.dispose();
    next.dispose();
    selected.dispose();
  });
  testWidgets(
    'an unreadable saved draft can restart through structured time rows',
    (tester) async {
      final times = TextEditingController(text: '1 08:');
      final field = GlobalKey<FormFieldState<String>>();
      await mount(
        tester,
        Scaffold(
          body: ListView(
            children: [
              PeriodEditor(controller: times, fieldKey: field, enabled: true),
            ],
          ),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(field.currentState!.validate(), isFalse);
      await tester.tap(find.text('重新设置节次'));
      await tester.pumpAndSettle();
      expect(times.text, '1 08:00 08:50');
      expect(find.text('08:00'), findsOneWidget);
      expect(find.byTooltip('添加一节'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(field.currentState!.validate(), isTrue);
      await tester.pumpWidget(const SizedBox());
      times.dispose();
    },
  );
  testWidgets('confirming 10:10 to 10:00 does not refocus the previous field', (
    tester,
  ) async {
    final previous = FocusNode();
    final times = TextEditingController(text: '1 08:00 08:50\n2 10:10 11:00');
    final field = GlobalKey<FormFieldState<String>>();
    await mount(
      tester,
      Scaffold(
        body: ListView(
          children: [
            TextField(focusNode: previous),
            PeriodEditor(controller: times, fieldKey: field, enabled: true),
          ],
        ),
      ),
      textScale: 1.6,
    );
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(previous.hasFocus, isTrue);
    await tester.tap(find.text('10:10'));
    await tester.pumpAndSettle();
    tester
        .widget<AppMinuteWheel>(find.byKey(const ValueKey('range-clock-start')))
        .onChanged(600);
    await tester.pumpAndSettle();
    tester
        .widget<AppMinuteWheel>(find.byKey(const ValueKey('range-clock-end')))
        .onChanged(660);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clock-range-confirm')));
    await tester.pumpAndSettle();
    expect(times.text, '1 08:00 08:50\n2 10:00 11:00');
    expect(previous.hasFocus, isFalse);
    expect(find.byType(AppClockRangePicker), findsNothing);
    expect(field.currentState!.validate(), isTrue);
    await tester.pumpWidget(const SizedBox());
    times.dispose();
    previous.dispose();
  });
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
    'period range changes the chosen segment and keeps the full schedule',
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
      expect(find.byType(AppClockRangePicker), findsOneWidget);
      Navigator.pop(
        tester.element(find.byType(AppClockRangePicker)),
        const AppClockRange(startMinutes: 465, endMinutes: 530),
      );
      await tester.pumpAndSettle();
      expect(times.text, '1 07:45 08:50\n2 09:00 09:50');
      expect(field.currentState!.validate(), isTrue);
      await tester.pumpWidget(const SizedBox());
      times.dispose();
    },
  );
  testWidgets(
    'invalid duplicate draft can restore the previous valid schedule',
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
      expect(find.text('节次时间需要重新设置'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('恢复作息'));
      await tester.pumpAndSettle();
      expect(times.text, '1 08:00 08:50\n2 09:00 09:50');
      expect(field.currentState!.validate(), isTrue);
      expect(find.text('09:00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      times.dispose();
    },
  );
}
