import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'controller.dart';
import '../ui/campus_theme.dart';
import '../features/accounts/auth_page.dart';
import '../features/semester/semester_page.dart';
import '../features/timetable/shell_page.dart';
import '../features/import/import_page.dart';
import '../features/import/manual_page.dart';

class SemesterApp extends ConsumerStatefulWidget {
  const SemesterApp({super.key});
  @override
  ConsumerState<SemesterApp> createState() => _SemesterAppState();
}

class _SemesterAppState extends ConsumerState<SemesterApp> {
  late final AppController controller;
  late final GoRouter router;
  @override
  void initState() {
    super.initState();
    controller = ref.read(appControllerProvider);
    router = GoRouter(
      refreshListenable: controller,
      redirect: (_, state) {
        if (!controller.ready) return null;
        if (!controller.loggedIn && state.uri.path != '/auth') return '/auth';
        if (controller.loggedIn && state.uri.path == '/auth') return '/';
        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => ShellPage(controller: controller),
        ),
        GoRoute(
          path: '/auth',
          builder: (_, _) => AuthPage(controller: controller),
        ),
        GoRoute(
          path: '/semester/new',
          builder: (_, _) => SemesterPage(controller: controller),
        ),
        GoRoute(
          path: '/import',
          builder: (_, _) => ImportPage(controller: controller),
        ),
        GoRoute(
          path: '/manual',
          builder: (_, _) => ManualPage(controller: controller),
        ),
      ],
    );
    controller.initialize();
  }

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: '学期OS',
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    debugShowCheckedModeBanner: false,
    routerConfig: router,
    theme: campusTheme(),
  );
}
