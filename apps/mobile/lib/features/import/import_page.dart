import '../../ui/app_controls.dart';
import '../../ui/detail_widgets.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../app/controller.dart';
import 'haut_parser.dart';
import 'preview.dart';
import 'school_navigation.dart';

class ImportPage extends StatefulWidget {
  final AppController controller;
  const ImportPage({super.key, required this.controller});
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  late final WebViewController web;
  bool loading = true, reading = false, closed = false, closing = false;
  String? notice, nonce;
  Timer? timeout;
  final redirectBudget = SchoolRedirectBudget();
  static const school =
      'https://jwglxt.haut.edu.cn/jwglxt/xtgl/login_slogin.html';
  bool allowed(String url) => isTrustedSchoolUrl(url);

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
                reading = false;
                if (allowed(url)) notice = null;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => loading = false);
          },
          onNavigationRequest: (r) {
            final decision = schoolNavigation(r.url);
            if (decision.action == SchoolNavigationAction.allow) {
              return NavigationDecision.navigate;
            }
            if (decision.action == SchoolNavigationAction.upgradeHttps &&
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
    await WebViewCookieManager().clearCookies();
    await web.clearLocalStorage();
    await web.loadRequest(Uri.parse(school));
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
        (Uri.tryParse(current)?.path.contains('login_') ?? false)) {
      // A fresh GET avoids re-submitting a login form whose password field was
      // replaced with ciphertext by the school's own script.
      await web.loadRequest(Uri.parse(school));
    } else {
      await web.reload();
    }
  }

  Future<void> read() async {
    final current = await web.currentUrl();
    if (!mounted) return;
    if (current == null || !allowed(current)) {
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
        'assets/haut_reader.js',
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
      if (packet['nonce'] != nonce || !allowed(await web.currentUrl() ?? '')) {
        return;
      }
      nonce = null;
      timeout?.cancel();
      if (packet['kind'] == 'error') {
        throw FormatException('${packet['value']}');
      }
      if (packet['kind'] != 'courses') return;
      final value = packet['value'] as Map;
      final rows = parseHautCourses(value['rows'] as List);
      if (!mounted) return;
      setState(() {
        reading = false;
        notice = '读取到${rows.length}条课程，正在核对学期与节次';
      });
      if (await showImportPreview(
        context,
        widget.controller,
        rows,
        'haut_webview',
        sourceTerm: '${value['sourceTerm'] ?? ''}',
      )) {
        await leave(home: true);
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
    await web.removeJavaScriptChannel('SemesterImport');
    await WebViewCookieManager().clearCookies();
    await web.clearLocalStorage();
    await web.clearCache();
    await web.loadRequest(Uri.parse('about:blank'));
  }

  Future<void> leave({bool home = false}) async {
    if (closing) return;
    closing = true;
    nonce = null;
    timeout?.cancel();
    await clearSchool();
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
      clearSchool();
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
        leading: AppIconButton(
          onPressed: leave,
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回并退出教务登录',
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('河南工业大学', style: TextStyle(fontSize: 18)),
            Text('jwglxt.haut.edu.cn', style: TextStyle(fontSize: 12)),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: WorkflowHeader(steps: ['选择学校', '登录教务', '核对课表'], current: 1),
          ),
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              '在学校原页登录，进入“信息查询 → 个人课表查询”。密码只发送给学校。',
              style: TextStyle(fontSize: 14),
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          Expanded(child: WebViewWidget(controller: web)),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(notice!, style: const TextStyle(fontSize: 14)),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: AppButton(
                  onPressed: reading || closing ? null : read,
                  child: Text(reading ? '正在读取课表…' : '读取当前学期课表'),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
