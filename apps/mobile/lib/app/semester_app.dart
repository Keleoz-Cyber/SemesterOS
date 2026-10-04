import 'package:forui/forui.dart';
import '../ui/forui_theme.dart';
import '../ui/accessibility.dart';
import '../ui/empty_states.dart';
import '../ui/assistant_scope.dart';
import '../ui/brand.dart';
import '../features/agent/assistant_sheet.dart';
import '../features/calendar/event_form.dart';
import '../features/calendar/calendar_panel.dart';
import '../features/agent/agent_page.dart';
import '../features/insights/insights_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'controller.dart';
import '../ui/campus_theme.dart';
import '../features/accounts/auth_page.dart';
import '../features/semester/semester_page.dart';
import '../features/timetable/shell_page.dart';
import '../features/import/import_page.dart';
import '../features/import/school_picker.dart';
import '../features/import/school_adapters.dart';
import '../features/import/manual_page.dart';
import '../features/items/items_controller.dart';
import '../features/items/android_notifications.dart';
import '../features/items/reminder_sync.dart';
import '../features/items/reminder_settings.dart';
import '../features/items/notification_target.dart';
import '../features/media/incoming_notice_draft.dart';
import '../ui/app_controls.dart';
import '../features/items/item_form.dart';
import '../features/items/item_detail.dart';
import '../features/centers/semester_centers.dart';
import '../features/centers/exam_pages.dart';
import '../features/operations/operation_page.dart';
import '../features/profile/profile_controller.dart';
import '../features/profile/profile_page.dart';
import '../features/profile/profile_scope.dart';

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
  late final ProfileController profile;
  late final IncomingNoticeController incoming;
  NotificationTarget? pendingNotification;
  String? openedDraftId;
  String? notificationOwner;
  bool notificationReady = false, incomingScheduled = false;
  final navigator = GlobalKey<NavigatorState>();
  Timer? riskClock;
  bool foreground = true;
  bool routeRebuildScheduled = false;
  @override
  void initState() {
    super.initState();
    controller = ref.read(appControllerProvider);
    incoming = IncomingNoticeController(controller.cache);
    incoming.addListener(incomingChanged);
    profile = ProfileController(controller.api, controller.cache);
    profile.onUnauthorized = () => controller.logout(remote: false);
    notifications = AndroidNotifications();
    items = ItemsController(
      controller.api,
      controller.cache,
      ReminderSync(notifications),
    );
    items.onUnauthorized = () => controller.logout(remote: false);
    items.onRealityChanged = (receipt) async {
      await controller.acknowledgeImport(receipt);
      if (controller.semester?['id'] == receipt['semester_id']) {
        await controller.loadWeek(controller.week);
      }
    };
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(appChanged);
    router = GoRouter(
      navigatorKey: navigator,
      refreshListenable: Listenable.merge([controller, incoming]),
      redirect: (_, state) {
        if (!controller.ready) return null;
        if (!controller.loggedIn && state.uri.path != '/auth') return '/auth';
        if (controller.loggedIn && state.uri.path == '/auth') return '/';
        return null;
      },
      routes: [
        GoRoute(
          path: '/calendar',
          builder: (_, _) => controller.semester == null
              ? SemesterPage(controller: controller)
              : Scaffold(
                  appBar: AppBar(title: const Text('日程')),
                  body: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
                    children: [CalendarPanel(app: controller, items: items)],
                  ),
                ),
        ),
        GoRoute(
          path: '/insights',
          builder: (_, state) => controller.semester == null
              ? SemesterPage(controller: controller)
              : InsightsPage(
                  controller: items,
                  semester: controller.semester!,
                  initialQuery: state.uri.queryParameters,
                ),
        ),
        GoRoute(
          path: '/assistant',
          builder: (_, state) {
            final draft = state.extra is IncomingNoticeDraft
                ? state.extra as IncomingNoticeDraft
                : null;
            return controller.semester == null
                ? SemesterPage(controller: controller)
                : AgentPage(
                    controller: items,
                    semester: controller.semester!,
                    initialMediaKind: state.uri.queryParameters['input'],
                    initialText: draft?.text,
                    initialImagePaths: draft?.imagePaths ?? const [],
                    initialDraftId: draft?.id,
                    onInitialDraftAccepted: draft == null
                        ? null
                        : () => unawaited(
                            incoming
                                .accepted(draft.id)
                                .catchError((Object _) {}),
                          ),
                  );
          },
        ),
        GoRoute(
          path: '/events/new',
          builder: (_, state) => controller.semester == null
              ? SemesterPage(controller: controller)
              : EventFormPage(
                  controller: items,
                  semester: controller.semester!,
                ),
        ),
        GoRoute(
          path: '/events/:id',
          builder: (_, state) => controller.semester == null
              ? SemesterPage(controller: controller)
              : EventDetailPage(
                  controller: items,
                  semester: controller.semester!,
                  eventId: state.pathParameters['id']!,
                ),
        ),
        GoRoute(
          path: '/operations',
          builder: (_, state) => OperationPage(
            controller: items,
            contextItemId: state.uri.queryParameters['item'],
          ),
        ),
        GoRoute(
          path: '/capture/media',
          builder: (_, state) => controller.semester == null
              ? SemesterPage(controller: controller)
              : AgentPage(
                  controller: items,
                  semester: controller.semester!,
                  initialMediaKind:
                      state.uri.queryParameters['kind'] ?? 'image',
                ),
        ),
        GoRoute(
          path: '/courses/:id',
          builder: (_, state) => CourseHubPage(
            controller: items,
            courseId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/exams/:id',
          builder: (_, state) => controller.semester == null
              ? SemesterPage(controller: controller)
              : ExamCenterPage(
                  controller: items,
                  semester: controller.semester!,
                  examId: state.pathParameters['id']!,
                ),
        ),
        GoRoute(
          path: '/',
          builder: (_, state) => ShellPage(
            controller: controller,
            items: items,
            initialTab:
                int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
          ),
        ),
        GoRoute(
          path: '/help',
          builder: (_, _) => OnboardingGuide(
            onComplete: () {
              if (router.canPop()) {
                router.pop();
              } else {
                router.go('/');
              }
            },
            onTimetable: () => router.go(
              controller.semester == null ? '/semester/new' : '/import',
            ),
            onNotice: () => router.go(
              controller.semester == null ? '/semester/new' : '/assistant',
            ),
            onPlanning: () => router.go('/?tab=2'),
          ),
        ),
        GoRoute(
          path: '/auth',
          builder: (_, state) => AuthPage(
            controller: controller,
            initialMode: state.uri.queryParameters['mode'] == 'register'
                ? 1
                : 0,
            pendingNoticeCount: incoming.count,
          ),
        ),
        GoRoute(
          path: '/reminders',
          builder: (_, _) => ReminderSettingsPage(controller: items),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, _) =>
              ProfilePage(controller: profile, onDone: closeProfile),
        ),
        GoRoute(
          path: '/profile/setup',
          builder: (_, _) => ProfilePage(
            controller: profile,
            onboarding: true,
            onDone: closeProfile,
          ),
        ),
        GoRoute(
          path: '/semester/new',
          builder: (_, _) => SemesterPage(
            controller: controller,
            pendingNoticeCount: incoming.count,
          ),
        ),
        GoRoute(
          path: '/import',
          builder: (context, _) => SchoolPickerPage(
            onSelect: (school) => context.push('/import/${school.id}'),
            onManual: () => context.push('/manual'),
          ),
        ),
        GoRoute(
          path: '/import/:school',
          builder: (context, state) {
            if (controller.semester == null) {
              return SemesterPage(controller: controller);
            }
            final school = schoolAdapter(state.pathParameters['school']!);
            return school == null
                ? SchoolPickerPage(
                    onSelect: (school) => context.push('/import/${school.id}'),
                    onManual: () => context.push('/manual'),
                  )
                : ImportPage(controller: controller, school: school);
          },
        ),
        GoRoute(
          path: '/manual',
          builder: (_, _) => ManualPage(controller: controller),
        ),
        GoRoute(
          path: '/capture',
          builder: (_, _) => controller.semester == null
              ? SemesterPage(controller: controller)
              : AgentPage(
                  controller: items,
                  semester: controller.semester!,
                  autofocus: true,
                ),
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
    notifications.onTarget = (target) {
      notificationOwner = target.ownerId;
      pendingNotification = target;
      openNotification();
    };
    notifications.onAction = (target) async {
      if (!controller.ready ||
          !controller.loggedIn ||
          controller.sessionLoading ||
          items.owner == null) {
        pendingNotification = target;
        return true;
      }
      return items.handleNotificationAction(target);
    };
    router.routerDelegate.addListener(routeChanged);
    unawaited(
      notifications.initialize().catchError((Object _) {}).then((_) {
        if (!mounted) return;
        notificationReady = true;
        if (controller.ready &&
            controller.loggedIn &&
            !controller.sessionLoading) {
          notifications.consumeLaunch();
        }
      }),
    );
    unawaited(incoming.initialize());
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
    unawaited(
      profile.bind(
        controller.ready && controller.loggedIn
            ? '${controller.user['id']}'
            : null,
      ),
    );
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
      if (controller.loggedIn && !controller.sessionLoading) {
        notifications.consumeLaunch();
      }
      openNotification();
      openIncoming();
    }
    if (mounted) setState(() {});
  }

  void closeProfile() {
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
  }

  String get currentPath =>
      router.routerDelegate.currentConfiguration.lastOrNull?.matchedLocation ??
      '';

  void routeChanged() {
    if (currentPath != '/assistant') openedDraftId = null;
    if (!mounted) return;
    // Router restoration can notify while descendants are being built.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (routeRebuildScheduled) return;
      routeRebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        routeRebuildScheduled = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void incomingChanged() {
    if (!mounted) return;
    setState(() {});
    openIncoming();
  }

  void openIncoming({bool explicit = false}) {
    if (incomingScheduled ||
        !mounted ||
        !incoming.ready ||
        !controller.ready ||
        !controller.loggedIn ||
        controller.sessionLoading ||
        incoming.next == null ||
        (openedDraftId != null && !explicit)) {
      return;
    }
    incomingScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      incomingScheduled = false;
      if (!mounted ||
          !controller.ready ||
          !controller.loggedIn ||
          controller.sessionLoading) {
        return;
      }
      final draft = incoming.next;
      if (draft == null || (openedDraftId != null && !explicit)) return;
      if (controller.semester == null) {
        if (currentPath != '/semester/new') router.go('/semester/new');
        return;
      }
      openedDraftId = draft.id;
      if (currentPath == '/assistant') {
        router.go('/assistant', extra: draft);
      } else {
        router.push('/assistant', extra: draft);
      }
      final pageContext = navigator.currentContext;
      if (draft.warning != null && pageContext != null) {
        ScaffoldMessenger.maybeOf(
          pageContext,
        )?.showSnackBar(SnackBar(content: Text(draft.warning!)));
      }
    });
  }

  Future<void> openNotification() async {
    if (!controller.ready ||
        !controller.loggedIn ||
        controller.sessionLoading ||
        pendingNotification == null) {
      return;
    }
    final pending = pendingNotification!;
    pendingNotification = null;
    if (pending.ownerId != items.owner) return;
    try {
      if (pending.actionId.isNotEmpty &&
          await items.handleNotificationAction(pending)) {
        return;
      }
      final type = pending.resourceType;
      final id = pending.resourceId;
      final item = type == 'item' || type == 'exam'
          ? await items.get(id)
          : type == 'course'
          ? Map<String, dynamic>.from(
              await controller.api.request('GET', '/courses/$id'),
            )
          : Map<String, dynamic>.from(
              await controller.api.request(
                'GET',
                '/${type == 'exam' ? 'exams' : 'events'}/$id',
              ),
            );
      if (!mounted || pending.ownerId != items.owner) return;
      final s = controller.semesters
          .where((s) => s['id'] == item['semester_id'])
          .firstOrNull;
      if (s == null) return;
      if (controller.semester?['id'] != s['id']) {
        await controller.selectSemester(s);
      }
      if (mounted && pending.ownerId == items.owner) {
        router.push(
          '/${switch (type) {
            'event' => 'events',
            'exam' => 'exams',
            'course' => 'courses',
            _ => 'items',
          }}/$id',
        );
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
      unawaited(items.refreshOwnerReminders().catchError((Object _) {}));
    }
  }

  Future<void> exitDemo() async {
    await controller.logout();
    if (mounted) router.go('/auth?mode=register');
  }

  Widget entryFrame(BuildContext context, Widget child) {
    final otherShare =
        controller.loggedIn &&
        openedDraftId != null &&
        incoming.next != null &&
        incoming.next!.id != openedDraftId;
    if (!controller.isDemo && !otherShare) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: CampusColors.blueSoft,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (controller.isDemo)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        const Text(
                          '体验中 · 演示学期',
                          style: TextStyle(
                            color: CampusColors.ink,
                            fontSize: 14,
                          ),
                        ),
                        AppTextButton(
                          key: const Key('demo-exit'),
                          onPressed: controller.sessionLoading
                              ? null
                              : exitDemo,
                          child: const Text('退出体验 · 注册/登录'),
                        ),
                      ],
                    ),
                  if (otherShare)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        Text(
                          '还有 ${incoming.count} 条分享',
                          style: const TextStyle(fontSize: 14),
                        ),
                        AppTextButton(
                          key: const Key('incoming-next'),
                          onPressed: () => openIncoming(explicit: true),
                          child: const Text('带入输入框'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    riskClock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(appChanged);
    router.routerDelegate.removeListener(routeChanged);
    incoming.removeListener(incomingChanged);
    incoming.dispose();
    profile.dispose();
    items.dispose();
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: appName,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: const [
      FLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    debugShowCheckedModeBanner: false,
    routerConfig: router,
    theme: campusTheme(),
    highContrastTheme: HighContrastTheme.theme(campusTheme()),
    builder: (context, child) => HighContrastDetector(
      child: ShiriForuiTheme(
        child: ProfileScope(
          controller: profile,
          child: AssistantScope(
            onOpen:
                (
                  pageContext, {
                  initialText,
                  mediaKind,
                  autoSubmit = false,
                }) async {
                  final semester = controller.semester;
                  if (semester == null) {
                    router.push('/semester/new');
                    return;
                  }
                  await openAssistantSheet(
                    pageContext,
                    controller: items,
                    semester: semester,
                    initialText: initialText,
                    mediaKind: mediaKind,
                    autoSubmit: autoSubmit,
                  );
                },
            child: entryFrame(context, child ?? const SizedBox()),
          ),
        ),
      ),
    ),
  );
}
