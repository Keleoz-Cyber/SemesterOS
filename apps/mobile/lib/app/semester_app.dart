import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'controller.dart';
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
    debugShowCheckedModeBanner: false,
    routerConfig: router,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F46E5)),
      scaffoldBackgroundColor: const Color(0xFFF7F8FC),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7F8FC),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(
          fontSize: 16,
          height: 1.45,
          color: Color(0xFF1F2937),
        ),
      ),
      useMaterial3: true,
    ),
  );
}
