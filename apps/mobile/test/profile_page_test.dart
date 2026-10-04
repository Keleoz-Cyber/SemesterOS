import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/profile/profile_controller.dart';
import 'package:semester_os/features/profile/profile_page.dart';
import 'package:semester_os/features/profile/profile_scope.dart';
import 'package:semester_os/features/timetable/shell_page.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'package:semester_os/ui/app_choice_strip.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'controller_test.dart' show MemoryStore;
import 'profile_flow_test.dart' show profileData;
import 'planning_flow_test.dart' show ioTap;
import 'ui_polish_test.dart'
    show mount, capture, loadPreviewFonts, sampleController, sampleItems;

Finder input(String id) => find.descendant(
  of: find.byKey(Key('profile-$id')),
  matching: find.byType(TextField),
);

Future<void> reveal(WidgetTester tester, String id) =>
    tester.scrollUntilVisible(
      find.byKey(Key('profile-$id')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(loadPreviewFonts);

  testWidgets(
    'optional guide saves known school and free role with all other fields blank',
    (tester) async {
      final api = SemesterApi()..session = account('a');
      Map<String, dynamic>? sent;
      api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.method == 'PUT') {
          sent = Map<String, dynamic>.from(r.data);
          return body({...r.data, 'version': 3});
        }
        return body(profileData(version: 2, school: '测试大学'));
      });
      final controller = ProfileController(api, MemoryStore());
      await tester.runAsync(() => controller.bind('a'));
      var done = 0;
      var reduceMotion = false;
      late StateSetter updateMotion;
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, update) {
            updateMotion = update;
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reduceMotion),
              child: ProfilePage(
                controller: controller,
                onboarding: true,
                onDone: () => done++,
              ),
            );
          },
        ),
      );
      expect(
        tester.widget<TextField>(input('school')).controller!.text,
        '测试大学',
      );
      await reveal(tester, 'education');
      await tester.pumpAndSettle();
      final choices = find.descendant(
        of: find.byKey(const Key('profile-education')),
        matching: find.byType(FButton),
      );
      expect(choices, findsNWidgets(2));
      expect(find.text('未填写'), findsNothing);
      expect(
        tester.widgetList<FButton>(choices).every((b) => !b.selected),
        isTrue,
      );
      final strip = find.byType(AppOptionalChoiceStrip<String>);
      final bounds = tester.getRect(strip);
      final surface = find.byKey(const Key('choice-strip-surface'));
      await tester.tap(find.text('本科'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.widgetList<FButton>(choices).map((b) => b.selected), [
        true,
        false,
      ]);
      await tester.pumpAndSettle();
      await capture(tester, 'profile-education-undergraduate');
      final firstPosition = tester.getRect(surface).left;
      await tester.tap(find.text('研究生'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.widgetList<FButton>(choices).map((b) => b.selected), [
        false,
        true,
      ]);
      expect(tester.getRect(strip), bounds);
      expect(tester.getRect(surface).left, greaterThan(firstPosition));
      final middlePosition = tester.getRect(surface).left;
      await capture(tester, 'profile-education-mid-slide');
      await tester.pumpAndSettle();
      expect(tester.getRect(surface).left, greaterThan(middlePosition));
      final lastPosition = tester.getRect(surface).left;
      await capture(tester, 'profile-education-postgraduate');
      // A second tap can retarget an unfinished transition without delaying
      // selection, freezing the field or adding another row.
      await tester.tap(find.text('本科'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tap(find.text('研究生'));
      await tester.pump();
      expect(tester.widgetList<FButton>(choices).map((b) => b.selected), [
        false,
        true,
      ]);
      expect(tester.getRect(strip), bounds);
      updateMotion(() => reduceMotion = true);
      await tester.pump();
      expect(tester.getRect(surface).left, lastPosition);
      await tester.tap(find.text('本科'));
      await tester.pump();
      expect(tester.getRect(surface).left, firstPosition);
      await tester.tap(find.text('本科'));
      await tester.pump();
      expect(
        tester.widgetList<FButton>(choices).every((b) => !b.selected),
        isTrue,
      );
      expect(tester.getRect(strip), bounds);
      expect(tester.binding.transientCallbackCount, 0);
      await capture(tester, 'profile-education-unselected');
      await reveal(tester, 'role');
      await tester.enterText(input('role'), '校运动会临时联系人');
      await reveal(tester, 'save');
      await ioTap(tester, find.byKey(const Key('profile-save')));
      expect(sent?['class_role'], '校运动会临时联系人');
      expect(sent?['college'], '');
      expect(sent?['education_level'], isNull);
      expect(sent?['entry_year'], isNull);
      expect(done, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      api.dio.close();
    },
  );

  testWidgets(
    'skip immediately permits use while its server request is pending',
    (tester) async {
      final api = SemesterApi()..session = account('a');
      final pending = Completer<ResponseBody>();
      api.dio.httpClientAdapter = ControlledTransport(
        (r) async => r.method == 'PUT' ? pending.future : body(profileData()),
      );
      final controller = ProfileController(api, MemoryStore());
      await tester.runAsync(() => controller.bind('a'));
      var done = 0;
      await mount(
        tester,
        ProfilePage(
          controller: controller,
          onboarding: true,
          onDone: () => done++,
        ),
      );
      await reveal(tester, 'skip');
      await ioTap(tester, find.byKey(const Key('profile-skip')));
      expect(done, 1);
      expect(controller.needsOnboarding, false);
      pending.complete(body(profileData(version: 1, completed: true)));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      api.dio.close();
    },
  );

  testWidgets(
    'conflict requires review and keeps edits until explicit resave',
    (tester) async {
      final api = SemesterApi()..session = account('a');
      var reads = 0, puts = 0;
      Map<String, dynamic>? sent;
      api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.method == 'PUT') {
          puts++;
          if (puts == 1) return body({}, 409);
          sent = Map<String, dynamic>.from(r.data);
          return body({...r.data, 'version': 3});
        }
        reads++;
        return body(
          profileData(version: reads, role: '远端职务$reads', completed: true),
        );
      });
      final controller = ProfileController(api, MemoryStore());
      await tester.runAsync(() => controller.bind('a'));
      var done = 0;
      await mount(
        tester,
        ProfilePage(controller: controller, onDone: () => done++),
      );
      await reveal(tester, 'role');
      await tester.enterText(input('role'), '当前职务');
      await reveal(tester, 'save');
      await ioTap(tester, find.byKey(const Key('profile-save')));
      expect(puts, 1);
      expect(controller.profile.classRole, '远端职务2');
      await reveal(tester, 'save');
      expect(
        tester
            .widget<AppButton>(find.byKey(const Key('profile-save')))
            .onPressed,
        isNull,
      );
      await reveal(tester, 'role');
      expect(tester.widget<TextField>(input('role')).controller!.text, '当前职务');
      await reveal(tester, 'review');
      await ioTap(tester, find.byKey(const Key('profile-review')));
      expect(find.text('最新：远端职务2'), findsOneWidget);
      await capture(tester, 'profile-conflict-review');
      await ioTap(tester, find.text('保留当前填写'));
      await reveal(tester, 'save');
      await ioTap(tester, find.byKey(const Key('profile-save')));
      expect(puts, 2);
      expect(sent?['expected_version'], 2);
      expect(sent?['class_role'], '当前职务');
      expect(done, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      api.dio.close();
    },
  );

  testWidgets('account sheet retains the personal profile entry', (
    tester,
  ) async {
    final app = sampleController();
    final profile = ProfileController(app.api, app.cache);
    final items = (await tester.runAsync(() => sampleItems(app)))!;
    await mount(
      tester,
      ProfileScope(
        controller: profile,
        child: ShellPage(controller: app, items: items),
      ),
    );
    await tester.tap(find.byTooltip('账户'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-profile')), findsOneWidget);
    expect(find.text('个人资料'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'profile-account-entry');
    await tester.pumpWidget(const SizedBox());
    profile.dispose();
    items.dispose();
    app.dispose();
  });

  for (final layout in [
    (name: 'normal', width: 390.0, height: 844.0, scale: 1.0),
    (name: 'small-large', width: 320.0, height: 760.0, scale: 2.0),
    (name: 'landscape', width: 740.0, height: 390.0, scale: 1.0),
  ]) {
    testWidgets(
      'profile form ${layout.name} stays usable with keyboard and large text',
      (tester) async {
        final api = SemesterApi()..session = account('a');
        api.dio.httpClientAdapter = ControlledTransport(
          (_) async => body(profileData(school: '测试大学')),
        );
        final controller = ProfileController(api, MemoryStore());
        await tester.runAsync(() => controller.bind('a'));
        await mount(
          tester,
          ProfilePage(controller: controller, onboarding: true, onDone: () {}),
          width: layout.width,
          height: layout.height,
          textScale: layout.scale,
        );
        expect(tester.takeException(), isNull);
        await capture(tester, 'profile-${layout.name}-top');
        await reveal(tester, 'role');
        await tester.enterText(input('role'), '学习委员 / 临时联络人');
        tester.view.viewInsets = const FakeViewPadding(bottom: 420);
        await tester.pumpAndSettle();
        await reveal(tester, 'role');
        expect(tester.takeException(), isNull);
        await capture(tester, 'profile-${layout.name}-keyboard');
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await reveal(tester, 'skip');
        expect(
          find.byKey(const Key('profile-save')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('profile-skip')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await capture(tester, 'profile-${layout.name}-bottom');
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        api.dio.close();
      },
    );
  }
}
