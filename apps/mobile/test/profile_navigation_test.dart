import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/app/semester_app.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/profile/profile_page.dart';
import 'package:semester_os/features/profile/profile_scope.dart';
import 'package:semester_os/features/accounts/auth_page.dart';
import 'package:semester_os/features/semester/semester_page.dart';
import 'package:semester_os/features/timetable/shell_page.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'controller_test.dart' show MemoryStore;
import 'profile_flow_test.dart' show profileData;
import 'centers_flow_test.dart' show settleIo;
import 'planning_flow_test.dart' show ioTap;

AppController appFixture({
  Completer<ResponseBody>? pendingProfile,
  bool restored = true,
}) {
  FlutterSecureStorage.setMockInitialValues({
    if (restored) 'semesteros_session': jsonEncode(account('a')),
  });
  final api = SemesterApi();
  final now = schoolNow();
  final monday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  final semester = {
    'id': 's',
    'name': '本学期',
    'first_monday': monday.toIso8601String().substring(0, 10),
    'total_weeks': 20,
    'revision': 0,
    'periods': [
      {'number': 1, 'start': '08:00', 'end': '08:50'},
    ],
  };
  api.dio.httpClientAdapter = ControlledTransport((r) async {
    final path = r.uri.path;
    if (r.path.endsWith('/auth/login')) return body(account('a'));
    if (r.path.endsWith('/me/profile')) {
      if (r.method == 'PUT') return body({...r.data, 'version': 1});
      return pendingProfile == null
          ? body(profileData())
          : pendingProfile.future;
    }
    if (path.endsWith('/semesters')) return body([semester]);
    if (path.endsWith('/timetable')) {
      return body({'semester_id': 's', 'revision': 0, 'events': []});
    }
    if (path.endsWith('/items') || path.endsWith('/courses')) return body([]);
    if (path.endsWith('/reminders')) {
      return body({
        'owner_id': 'a',
        'reminders': [],
        'synced_at': '2026-10-02T00:00:00Z',
      });
    }
    if (path.endsWith('/day-brief')) {
      return body({
        'semester_id': 's',
        'revision': 0,
        'date': r.uri.queryParameters['day'],
        'valid_until': '2099-01-01T00:00:00Z',
        'entries': [],
        'suggestions': [],
      });
    }
    if (path.endsWith('/risk')) {
      return body({
        'revision': 0,
        'items': [],
        'critical_windows': [],
        'valid_until': '2099-01-01T00:00:00Z',
      });
    }
    if (path.endsWith('/plans')) {
      return body({'revision': 0, 'blocks': [], 'invalid_blocks': []});
    }
    return body({'id': 'a', 'username': '测试账号'});
  });
  return AppController(api, MemoryStore(), clearSchoolSession: () async {});
}

Future<void> mountApp(WidgetTester tester, AppController app) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWithValue(app)],
      child: const SemesterApp(),
    ),
  );
  await settleIo(tester);
}

void main() {
  testWidgets('a new login offers optional setup after the auth redirect', (
    tester,
  ) async {
    final app = appFixture(restored: false);
    await mountApp(tester, app);
    expect(find.byType(AuthPage), findsOneWidget);
    final auth = tester.element(find.byType(AuthPage));
    final router = GoRouter.of(auth);
    final profile = auth
        .getInheritedWidgetOfExactType<ProfileScope>()!
        .notifier!;
    await tester.enterText(find.byKey(const Key('username')), 'test_account');
    await tester.enterText(
      find.byKey(const Key('password')),
      'test_password_2026',
    );
    await ioTap(tester, find.byKey(const Key('auth-submit')));
    await settleIo(tester);
    expect(app.loggedIn, true);
    expect(profile.owner, 'a');
    expect(profile.loading, false);
    expect(profile.profile.onboardingCompleted, false);
    expect(find.byType(ProfilePage), findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/',
      reason: 'Incomplete identity must not interrupt the student with a route',
    );
    await ioTap(tester, find.byKey(const Key('student-profile-setup')));
    await settleIo(tester);
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/profile/setup',
      reason:
          'Profile setup opens only after the student chooses the suggestion',
    );
    expect(find.byKey(const Key('profile-school')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets(
    'restored home offers guide once and account route stays available after skip',
    (tester) async {
      final app = appFixture();
      await mountApp(tester, app);
      expect(find.byType(ProfilePage), findsNothing);
      expect(find.byKey(const Key('student-profile-setup')), findsOneWidget);
      await ioTap(tester, find.byKey(const Key('student-profile-setup')));
      await settleIo(tester);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text('填写个人资料'), findsOneWidget);
      await ioTap(tester, find.byTooltip('稍后填写'));
      await settleIo(tester);
      expect(find.byType(ProfilePage), findsNothing);
      expect(find.byKey(const Key('student-profile-setup')), findsNothing);
      expect(find.byType(ShellPage), findsOneWidget);
      app.notifyListeners();
      await settleIo(tester);
      expect(find.byType(ProfilePage), findsNothing);
      await tester.tap(find.byTooltip('账户'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-profile')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text('个人资料'), findsOneWidget);
      expect(find.text('填写个人资料'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets('a delayed profile response cannot hijack semester creation', (
    tester,
  ) async {
    final pending = Completer<ResponseBody>();
    final app = appFixture(pendingProfile: pending);
    await mountApp(tester, app);
    expect(find.byType(ShellPage), findsOneWidget);
    final router = GoRouter.of(tester.element(find.byType(ShellPage)));
    router.go('/semester/new');
    await tester.pumpAndSettle();
    expect(find.byType(SemesterPage), findsOneWidget);
    pending.complete(body(profileData()));
    await settleIo(tester);
    expect(find.byType(ProfilePage), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/semester/new');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets(
    'a pushed semester route is also protected while the root URI stays home',
    (tester) async {
      final pending = Completer<ResponseBody>();
      final app = appFixture(pendingProfile: pending);
      await mountApp(tester, app);
      final router = GoRouter.of(tester.element(find.byType(ShellPage)));
      router.push('/semester/new');
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/');
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/semester/new',
      );
      pending.complete(body(profileData()));
      await settleIo(tester);
      expect(find.byType(ProfilePage), findsNothing);
      expect(find.byType(SemesterPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
