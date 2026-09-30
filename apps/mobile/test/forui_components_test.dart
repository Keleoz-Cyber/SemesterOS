import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:semester_os/ui/app_picker_field.dart';
import 'package:semester_os/ui/campus_theme.dart';
import 'package:semester_os/ui/detail_widgets.dart';
import 'package:semester_os/ui/forui_theme.dart';
import 'package:semester_os/ui/record_actions.dart';
import 'ui_polish_test.dart' show loadPreviewFonts, previewFont;

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: previewFont
          ? campusTheme().copyWith(
              textTheme: campusTheme().textTheme.apply(
                fontFamily: 'PreviewSans',
              ),
            )
          : campusTheme(),
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      builder: (context, child) => ShiriForuiTheme(
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets('Forui footer preserves disabled action and wraps large labels', (
    tester,
  ) async {
    var calls = 0;
    await _mount(
      tester,
      SizedBox(
        width: 280,
        child: ActionFooter(
          label: '保存已安排部分（仍有45分钟未安排）',
          icon: Icons.save_outlined,
          onPressed: () => calls++,
        ),
      ),
      scale: 2.5,
    );
    expect(find.byType(FButton), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(FButton)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.byType(FButton));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await _mount(tester, const ActionFooter(label: '保存', onPressed: null));
    expect(tester.widget<FButton>(find.byType(FButton)).onPress, isNull);
    await tester.tap(find.byType(FButton));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets(
    'Forui record action keeps its full subtitle at large text sizes',
    (tester) async {
      var calls = 0;
      await _mount(
        tester,
        SizedBox(
          width: 320,
          child: RecordActionTile(
            title: '查看课程安排',
            subtitle: '保留课程详情与所有已关联的学习计划，点击后继续查看。',
            icon: Icons.school_outlined,
            onTap: () => calls++,
          ),
        ),
        scale: 2,
      );
      expect(find.byType(FItem), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('查看课程安排'));
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  testWidgets(
    'searchable Forui picker distinguishes dismissal from explicit null',
    (tester) async {
      String? value = '2';
      var calls = 0;
      final formKey = GlobalKey<FormState>();
      await _mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) => Form(
            key: formKey,
            child: AppPickerField<String>(
              initialValue: value,
              decoration: const InputDecoration(labelText: '关联课程'),
              items: [
                const DropdownMenuItem(value: null, child: Text('不关联课程')),
                const DropdownMenuItem(
                  value: 'disabled',
                  enabled: false,
                  child: Text('不可选择课程'),
                ),
                for (var i = 0; i < 12; i++)
                  DropdownMenuItem(value: '$i', child: Text('课程$i')),
              ],
              validator: (value) => value == null ? '请选择课程' : null,
              onChanged: (next) => setState(() {
                value = next;
                calls++;
              }),
            ),
          ),
        ),
        scale: 1.6,
      );
      await tester.tap(find.byType(AppPickerField<String>));
      await tester.pumpAndSettle();
      expect(find.byType(FTextField), findsOneWidget);
      expect(find.byType(FItem), findsWidgets);
      await tester.tap(find.text('不可选择课程'));
      expect(value, '2');
      expect(calls, 0);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(value, '2');
      expect(calls, 0);
      await tester.tap(find.byType(AppPickerField<String>));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '不关联');
      await tester.pumpAndSettle();
      await tester.tap(find.text('不关联课程'));
      await tester.pumpAndSettle();
      expect(value, isNull);
      expect(calls, 1);
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('请选择课程'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
