import 'dart:async';
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
import '../features/items/items_controller.dart';
import '../features/items/android_notifications.dart';
import '../features/items/reminder_sync.dart';
import '../features/items/item_form.dart';
import '../features/items/item_detail.dart';
import '../features/items/capture_page.dart';

class SemesterApp extends ConsumerStatefulWidget {
  const SemesterApp({super.key});
  @override
  ConsumerState<SemesterApp> createState() => _SemesterAppState();
}

class _SemesterAppState extends ConsumerState<SemesterApp>
    with WidgetsBindingObserver {
  late final AppController controller;
  late final GoRouter router;
  late final ItemsController items;
  late final AndroidNotifications notifications;
  ({String owner, String item})? pendingNotification;
  Timer? riskClock;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    controller = ref.read(appControllerProvider);
    notifications = AndroidNotifications();
    items = ItemsController(
      controller.api,
      controller.cache,
      ReminderSync(notifications),
    );
    items.onUnauthorized = () => controller.logout(remote: false);
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(appChanged);
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
          builder: (_, _) => ShellPage(controller: controller, items: items),
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
        GoRoute(
          path: '/capture',
          builder: (_, _) => controller.semester == null
              ? SemesterPage(controller: controller)
              : CapturePage(controller: items, semester: controller.semester!),
        ),
        GoRoute(
          path: '/items/new',
          builder: (_, state) => controller.semester == null
              ? SemesterPage(controller: controller)
              : ItemFormPage(
                  controller: items,
                  semester: controller.semester!,
                  kind: state.uri.queryParameters['kind'] ?? 'assignment',
                ),
        ),
        GoRoute(
          path: '/items/:id',
          builder: (_, state) => controller.semester == null
              ? SemesterPage(controller: controller)
              : ItemDetailPage(
                  controller: items,
                  semester: controller.semester!,
                  id: state.pathParameters['id']!,
                ),
        ),
      ],
    );
    notifications.onOpen = (owner, item) {
      pendingNotification = (owner: owner, item: item);
      openNotification();
    };
    controller.initialize();
    riskClock = Timer.periodic(const Duration(seconds: 45), (_) {
      if (foreground &&
          controller.ready &&
          controller.loggedIn &&
          !items.busy &&
          !items.riskBusy) {
        items.refreshRisk();
      }
    });
  }

  void appChanged() {
    items.bind(
      controller.ready && controller.loggedIn
          ? (controller.semester?['id'])
          : null,
    );
    final semester = controller.semester;
    if (controller.ready &&
        controller.loggedIn &&
        semester != null &&
        items.observeRevision(semester['id'], semester['revision']) &&
        !items.busy) {
      items.refresh();
    }
    if (controller.ready) {
      notifications.consumeLaunch();
      openNotification();
    }
  }

  Future<void> openNotification() async {
    if (!controller.ready ||
        !controller.loggedIn ||
        pendingNotification == null) {
      return;
    }
    final pending = pendingNotification!;
    pendingNotification = null;
    if (pending.owner != items.owner) return;
    try {
      final item = await items.get(pending.item);
      if (!mounted || pending.owner != items.owner) return;
      final s = controller.semesters
          .where((s) => s['id'] == item['semester_id'])
          .firstOrNull;
      if (s == null) return;
      if (controller.semester?['id'] != s['id']) {
        await controller.selectSemester(s);
      }
      if (mounted && pending.owner == items.owner) {
        router.push('/items/${pending.item}');
      }
    } catch (_) {
      /* An expired/foreign notification cannot expose an item. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed &&
        controller.ready &&
        controller.loggedIn) {
      items.refresh();
    }
  }

  @override
  void dispose() {
    riskClock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(appChanged);
    items.dispose();
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
