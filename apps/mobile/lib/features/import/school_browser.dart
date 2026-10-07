import 'school_adapters.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

const _compatibility = MethodChannel('cn.semesteros/school_browser');

Future<void> installSchoolBrowserCompatibility(WebViewController web) async {
  final platform = web.platform;
  if (platform is AndroidWebViewController) {
    await platform.setUseWideViewPort(true);
    await _compatibility.invokeMethod<void>('install', {
      'identifier': platform.webViewIdentifier,
    });
  }
}

Future<void> removeSchoolBrowserCompatibility(WebViewController web) async {
  final platform = web.platform;
  if (platform is AndroidWebViewController) {
    await _compatibility.invokeMethod<void>('remove', {
      'identifier': platform.webViewIdentifier,
    });
  }
}

/// Keep the installed Chromium version; only its desktop identity is changed.
/// Never pin a browser version or suppress the school's page scripts.
String? schoolBrowserAgent(SchoolAdapter school, String? installedAgent) {
  if (!school.desktopBrowser || installedAgent == null) return installedAgent;
  final chrome = RegExp(
    r'(?:Chrome|Chromium)/[\d.]+',
  ).firstMatch(installedAgent);
  final webkit = RegExp(r'AppleWebKit/[\d.]+').firstMatch(installedAgent);
  final safari = RegExp(r'Safari/[\d.]+').firstMatch(installedAgent);
  if (chrome == null || webkit == null || safari == null) return installedAgent;
  return 'Mozilla/5.0 (X11; Linux x86_64) ${webkit[0]} '
      '(KHTML, like Gecko) ${chrome[0]} ${safari[0]}';
}
