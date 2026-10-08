import '../../ui/app_loading.dart';
import '../../ui/app_controls.dart';
import '../../ui/campus_theme.dart';
import '../centers/academic_visuals.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../app/controller.dart';
import 'preview.dart';
import 'school_adapters.dart';
import 'school_navigation.dart';
import 'school_browser.dart';

class ImportPage extends StatefulWidget {
  final AppController controller;
  final SchoolAdapter school;
  const ImportPage({
    super.key,
    required this.controller,
    this.school = hautSchool,
  });
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  late final WebViewController web;
  bool loading = true, reading = false, closed = false, closing = false;
  String? notice, nonce;
  String? pageUrl;
  Timer? timeout;
  final redirectBudget = SchoolRedirectBudget();
  SchoolAdapter get school => widget.school;
  bool allowed(String url) => isTrustedSchoolUrl(url, school: school);
  bool coursePage(String url) => isSchoolCourseUrl(url, school: school);

  @override
  void initState() {
    super.initState();
    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('SemesterImport', onMessageReceived: receive)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            nonce = null;
            timeout?.cancel();
            if (mounted) {
              setState(() {
                loading = true;
                pageUrl = url;
                reading = false;
                if (allowed(url)) notice = null;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => loading = false);
          },
          onNavigationRequest: (r) {
            final decision = schoolNavigation(r.url, school: school);
            if (decision.action == SchoolNavigationAction.allow) {
              return NavigationDecision.navigate;
            }
            if ((decision.action == SchoolNavigationAction.upgradeHttps ||
                    decision.action == SchoolNavigationAction.redirectLogin) &&
                r.isMainFrame) {
              if (!redirectBudget.allowUpgrade(DateTime.now())) {
                if (mounted) {
                  setState(() {
                    loading = false;
                    notice = '学校页面短时间内反复跳转，已暂停。请刷新登录页后重试。';
                  });
                }
                return NavigationDecision.prevent;
              }
              // Reject the HTTP request first. Continue on the next event turn in
              // the same WebView so its HTTPS session stays intact.
              unawaited(
                Future<void>(() async {
                  if (!mounted || closing) return;
                  try {
                    await web.loadRequest(decision.destination!);
                  } catch (_) {
                    if (mounted) {
                      setState(() {
                        loading = false;
                        notice = '学校页面跳转未完成，请刷新登录页后重试';
                      });
                    }
                  }
                }),
              );
              return NavigationDecision.prevent;
            }
            if (mounted) {
              setState(() {
                loading = false;
                notice = blockedSchoolNavigationMessage(r.url);
              });
            }
            return NavigationDecision.prevent;
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted) {
              setState(() {
                loading = false;
                notice = '学校页面加载失败，可重试或使用手工录入';
              });
            }
          },
        ),
      );
    open();
  }

  Future<void> open() async {
    redirectBudget.reset();
    if (school.desktopBrowser) {
      // Apply before the first request, including CAS redirects and reloads.
      try {
        final installedAgent = await web.getUserAgent();
        if (!mounted || closing) return;
        await web.setUserAgent(schoolBrowserAgent(school, installedAgent));
        if (!mounted || closing) return;
        await installSchoolBrowserCompatibility(web);
        if (!mounted || closing) {
          await removeSchoolBrowserCompatibility(web);
          return;
        }
      } on PlatformException catch (error) {
        if (mounted) {
          setState(() {
            loading = false;
            notice = error.code == 'unsupported_webview'
                ? '请更新系统 Android System WebView 后再打开黑大教务'
                : '学校页面兼容设置未完成，请退出后重试';
          });
        }
        return;
      }
    }
    if (!mounted || closing) return;
    await WebViewCookieManager().clearCookies();
    if (!mounted || closing) return;
    await web.clearLocalStorage();
    if (!mounted || closing) return;
    await web.loadRequest(Uri.parse(school.loginUrl));
  }

  Future<void> refreshSchool() async {
    redirectBudget.reset();
    nonce = null;
    timeout?.cancel();
    if (mounted) {
      setState(() {
        notice = null;
        reading = false;
      });
    }
    final current = await web.currentUrl();
    if (current == null ||
        !allowed(current) ||
        (Uri.tryParse(current)?.path.contains('login') ?? false)) {
      // A fresh GET avoids re-submitting a login form whose password field was
      // replaced with ciphertext by the school's own script.
      await web.loadRequest(Uri.parse(school.loginUrl));
    } else {
      await web.reload();
    }
  }

  Future<void> read() async {
    final current = await web.currentUrl();
    if (!mounted) return;
    if (current == null || !coursePage(current)) {
      setState(() => notice = '请先进入学校原始课表页面');
      return;
    }
    nonce = List.generate(
      24,
      (_) => Random.secure().nextInt(256).toRadixString(16),
    ).join();
    setState(() {
      reading = true;
      notice = null;
    });
    timeout?.cancel();
    timeout = Timer(const Duration(seconds: 25), () {
      nonce = null;
      if (mounted) {
        setState(() {
          reading = false;
          notice = '读取超时，请确认已进入个人课表查询页';
        });
      }
    });
    try {
      final script = await rootBundle.loadString(
        school.readerAsset,
        cache: false,
      );
      await web.runJavaScript('$script\nsemesterRead(${jsonEncode(nonce)});');
    } catch (_) {
      timeout?.cancel();
      if (mounted) {
        setState(() {
          reading = false;
          notice = '读取未完成，请重试';
        });
      }
    }
  }

  Future<void> receive(JavaScriptMessage message) async {
    if (!mounted || !reading) return;
    try {
      final packet = jsonDecode(message.message) as Map;
      if (packet['nonce'] != nonce ||
          !coursePage(await web.currentUrl() ?? '')) {
        return;
      }
      nonce = null;
      timeout?.cancel();
      if (packet['kind'] == 'error') {
        throw FormatException('${packet['value']}');
      }
      if (packet['kind'] != 'courses') return;
      final value = packet['value'] as Map;
      final parsed = school.parse(value);
      final rows = parsed.courses;
      if (!mounted) return;
      setState(() {
        reading = false;
        notice = '正在核对课表';
      });
      if (await showImportPreview(
        context,
        widget.controller,
        rows,
        school.source,
        sourceTerm: parsed.sourceTerm,
        extras: parsed.extras,
        sourceFirstMonday: parsed.sourceFirstMonday,
        warnings: parsed.warnings,
        metadata: parsed.metadata,
      )) {
        await leave(home: true);
      } else if (mounted && !closing) {
        setState(() => notice = null);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          reading = false;
          notice = e is FormatException ? e.message : '读取未完成，请核对原课表后重试';
        });
      }
    }
  }

  Future<void> clearSchool() async {
    Object? failure;
    StackTrace? failureStack;
    for (final action in <Future<dynamic> Function()>[
      if (school.desktopBrowser) () => removeSchoolBrowserCompatibility(web),
      () => web.removeJavaScriptChannel('SemesterImport'),
      () => WebViewCookieManager().clearCookies(),
      web.clearLocalStorage,
      web.clearCache,
      () => web.loadRequest(Uri.parse('about:blank')),
    ]) {
      try {
        await action();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  Future<void> leave({bool home = false}) async {
    if (closing) return;
    closing = true;
    nonce = null;
    timeout?.cancel();
    try {
      await clearSchool();
    } catch (error) {
      debugPrint('School WebView cleanup incomplete (${error.runtimeType})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已退出课表导入；学校登录缓存清理未完成，请重新打开App重试。')),
        );
      }
    }
    if (!mounted) return;
    setState(() => closed = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (home) {
          context.go('/');
        } else {
          context.pop();
        }
      }
    });
  }

  @override
  void dispose() {
    timeout?.cancel();
    if (!closing) {
      unawaited(
        clearSchool().catchError((Object error) {
          debugPrint(
            'School WebView cleanup incomplete (${error.runtimeType})',
          );
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: closed,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) leave();
    },
    child: Scaffold(
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(1) > 1.4
            ? 96
            : 60,
        leading: AppIconButton(
          onPressed: leave,
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回并退出教务登录',
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '登录教务',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, height: 1.25),
            ),
            Text(
              Uri.tryParse(pageUrl ?? school.loginUrl)?.host ??
                  Uri.parse(school.loginUrl).host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          AppIconButton(
            onPressed: refreshSchool,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新学校页面',
          ),
        ],
      ),
      body: Column(
        children: [
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AcademicStepRail(
                    steps: ['选择学校', '登录教务', '核对课表'],
                    current: 1,
                  ),
                  Text(
                    school.instructions,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: CampusColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            // Keep the native view and its input focus when keyboard chrome hides.
            key: const ValueKey('school-webview'),
            child: AppLoadingOverlay(
              loading: loading,
              label: '正在打开',
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: CampusColors.line),
                    bottom: BorderSide(color: CampusColors.line),
                  ),
                ),
                child: WebViewWidget(controller: web),
              ),
            ),
          ),
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            Material(
              color: CampusColors.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (notice != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: CampusColors.muted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  notice!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.4,
                                    color: CampusColors.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      AppButton(
                        onPressed: loading || reading || closing ? null : read,
                        child: Text(reading ? '正在读取课表…' : '读取当前学期课表'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
