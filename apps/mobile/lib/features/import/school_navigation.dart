const schoolHost = 'jwglxt.haut.edu.cn';

enum SchoolNavigationAction { allow, upgradeHttps, block }

class SchoolNavigationDecision {
  final SchoolNavigationAction action;
  final Uri? destination;
  const SchoolNavigationDecision(this.action, [this.destination]);
}

bool isTrustedSchoolUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == schoolHost &&
      uri.port == 443 &&
      uri.userInfo.isEmpty;
}

SchoolNavigationDecision schoolNavigation(String url) {
  if (url == 'about:blank' || isTrustedSchoolUrl(url)) {
    return const SchoolNavigationDecision(SchoolNavigationAction.allow);
  }
  final uri = Uri.tryParse(url);
  if (uri != null &&
      uri.scheme == 'http' &&
      uri.host == schoolHost &&
      uri.port == 80 &&
      uri.userInfo.isEmpty) {
    return SchoolNavigationDecision(
      SchoolNavigationAction.upgradeHttps,
      uri.replace(scheme: 'https', port: 443),
    );
  }
  return const SchoolNavigationDecision(SchoolNavigationAction.block);
}

String blockedSchoolNavigationMessage(String url) {
  final uri = Uri.tryParse(url);
  // Never expose paths, query parameters, fragments, tickets or credentials.
  final origin = uri == null || uri.host.isEmpty
      ? '非网页地址'
      : '${uri.scheme}://${uri.host}';
  return '已暂停跳转到未验证的地址：$origin。请刷新学校页面后重试。';
}

class SchoolRedirectBudget {
  DateTime? _window;
  int _count = 0;

  bool allowUpgrade(DateTime now) {
    if (_window == null ||
        now.isBefore(_window!) ||
        now.difference(_window!) >= const Duration(seconds: 30)) {
      _window = now;
      _count = 0;
    }
    return ++_count <= 5;
  }

  void reset() {
    _window = null;
    _count = 0;
  }
}
