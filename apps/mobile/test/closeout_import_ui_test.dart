import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:semester_os/features/semester/period_editor.dart';
import 'package:semester_os/features/import/school_picker.dart';
import 'package:semester_os/features/import/school_adapters.dart';
import 'package:semester_os/features/timetable/shell_page.dart';
import 'package:semester_os/ui/empty_states.dart';
import 'profile_navigation_test.dart' show appFixture, mountApp;
import 'centers_flow_test.dart' show settleIo;
import 'ui_polish_test.dart' show mount;

void main() {
  testWidgets(
    'all ten school periods are visible without a disclosure at large text',
    (tester) async {
      final text = TextEditingController(
        text: hautPeriods
            .map((p) => '${p['section']} ${p['start']} ${p['end']}')
            .join('\n'),
      );
      final field = GlobalKey<FormFieldState<String>>();
      await mount(
        tester,
        Scaffold(
          body: ListView(
            children: [
              PeriodEditor(controller: text, fieldKey: field, enabled: true),
            ],
          ),
        ),
        textScale: 1.6,
      );
      expect(find.byKey(const ValueKey('period-10')), findsOneWidget);
      expect(find.textContaining('查看全部'), findsNothing);
      expect(find.textContaining('收起'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('period-10')));
      await tester.pumpAndSettle();
      expect(find.text('21:05'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      text.dispose();
    },
  );

  testWidgets('help to course import keeps a visible back route to help', (
    tester,
  ) async {
    final app = appFixture();
    await mountApp(tester, app);
    final router = GoRouter.of(tester.element(find.byType(ShellPage)));
    router.push('/help');
    await settleIo(tester);
    await tester.tap(find.text('课程表'));
    await settleIo(tester);
    expect(find.byType(SchoolPickerPage), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await settleIo(tester);
    expect(find.byType(OnboardingGuide), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
