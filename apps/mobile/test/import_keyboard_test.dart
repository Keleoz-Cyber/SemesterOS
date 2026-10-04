import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// Only the native test double borrows the platform API bundled by the pinned
// webview_flutter dependency; the production dependency snapshot stays intact.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:semester_os/features/import/import_page.dart';
import 'package:semester_os/features/import/school_adapters.dart';
import 'package:semester_os/ui/forui_theme.dart';
import 'ui_polish_test.dart' show mount, sampleController;

class _SchoolWebPlatform extends WebViewPlatform {
  int mounts = 0, disposals = 0, controllerCreations = 0;
  bool failCleanup = false;
  _SchoolSurfaceState? active;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    controllerCreations++;
    return _SchoolWebController(params, this);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _SchoolNavigation(params);
  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => _SchoolCookies(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _SchoolWidget(params, this);
}

class _SchoolWebController extends PlatformWebViewController {
  _SchoolWebController(super.params, this.probe) : super.implementation();
  final _SchoolWebPlatform probe;
  _SchoolNavigation? navigation;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate value,
  ) async {
    navigation = value as _SchoolNavigation;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    navigation?.started?.call(params.uri.toString());
    navigation?.finished?.call(params.uri.toString());
  }

  @override
  Future<void> clearLocalStorage() async {}
  @override
  Future<void> clearCache() async {}
  @override
  Future<void> removeJavaScriptChannel(String name) async {
    if (probe.failCleanup) throw StateError('synthetic cleanup failure');
  }
}

class _SchoolNavigation extends PlatformNavigationDelegate {
  _SchoolNavigation(super.params) : super.implementation();
  PageEventCallback? started, finished;
  @override
  Future<void> setOnPageStarted(PageEventCallback value) async =>
      started = value;
  @override
  Future<void> setOnPageFinished(PageEventCallback value) async =>
      finished = value;
  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback value) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback value) async {}
}

class _SchoolCookies extends PlatformWebViewCookieManager {
  _SchoolCookies(super.params) : super.implementation();
  @override
  Future<bool> clearCookies() async => true;
}

class _SchoolWidget extends PlatformWebViewWidget {
  _SchoolWidget(super.params, this.probe) : super.implementation();
  final _SchoolWebPlatform probe;
  @override
  Widget build(BuildContext context) => _SchoolSurface(
    // Match the plugin's inner local key. It must not substitute for keeping
    // the actual ImportPage's platform-view ancestor alive.
    key: ValueKey(params.controller),
    probe: probe,
  );
}

class _SchoolSurface extends StatefulWidget {
  final _SchoolWebPlatform probe;
  const _SchoolSurface({super.key, required this.probe});
  @override
  State<_SchoolSurface> createState() => _SchoolSurfaceState();
}

class _SchoolSurfaceState extends State<_SchoolSurface> {
  final text = TextEditingController(), focus = FocusNode();
  @override
  void initState() {
    super.initState();
    widget.probe.mounts++;
    widget.probe.active = this;
  }

  @override
  void dispose() {
    widget.probe.disposals++;
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TextField(
      key: const Key('school-login-input'),
      controller: text,
      focusNode: focus,
    ),
  );
}

void main() {
  testWidgets(
    'cleanup failure still exits the import route and warns the user',
    (tester) async {
      final platform = _SchoolWebPlatform();
      final previous = WebViewPlatform.instance;
      WebViewPlatform.instance = platform;
      final app = sampleController();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: '/import',
            builder: (_, _) => ImportPage(controller: app),
          ),
        ],
      );
      addTearDown(() {
        router.dispose();
        app.dispose();
        if (previous != null) WebViewPlatform.instance = previous;
      });
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (_, child) => ShiriForuiTheme(child: child!),
        ),
      );
      router.push('/import');
      await tester.pumpAndSettle();
      platform.failCleanup = true;
      await tester.tap(find.byTooltip('返回并退出教务登录'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportPage), findsNothing);
      expect(find.textContaining('学校登录缓存清理未完成'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'ImportPage keeps the focused school view when keyboard opens and closes',
    (tester) async {
      final platform = _SchoolWebPlatform();
      final previous = WebViewPlatform.instance;
      WebViewPlatform.instance = platform;
      addTearDown(() {
        if (previous != null) WebViewPlatform.instance = previous;
      });
      final inset = ValueNotifier<double>(0);
      final app = sampleController();
      await mount(
        tester,
        ValueListenableBuilder<double>(
          valueListenable: inset,
          builder: (context, bottom, _) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(viewInsets: EdgeInsets.only(bottom: bottom)),
            child: ImportPage(controller: app, school: hljuSchool),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('school-login-input')),
        'sample-student',
      );
      await tester.pump();
      final original = platform.active!;
      expect(platform.mounts, 1);
      expect(original.focus.hasFocus, true);
      try {
        for (final bottom in [280.0, 0.0]) {
          inset.value = bottom;
          await tester.pumpAndSettle();
          expect(
            platform.mounts,
            1,
            reason:
                'Changing keyboard insets must not mount another native school surface',
          );
          expect(platform.disposals, 0);
          expect(identical(platform.active, original), true);
          expect(original.text.text, 'sample-student');
          expect(original.focus.hasFocus, true);
          expect(platform.controllerCreations, 1);
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        inset.dispose();
        app.dispose();
      }
    },
  );
}
