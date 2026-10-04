import 'school_adapters.dart';

const schoolHost = 'jwglxt.haut.edu.cn';

enum SchoolNavigationAction { allow, upgradeHttps, redirectLogin, block }

class SchoolNavigationDecision {
  final SchoolNavigationAction action;
  final Uri? destination;
  const SchoolNavigationDecision(this.action, [this.destination]);
}

bool _matchesOrigin(Uri uri, String origin) {
  final trusted = Uri.parse(origin);
  return uri.scheme == trusted.scheme &&
      uri.host == trusted.host &&
      uri.port == trusted.port &&
      uri.userInfo.isEmpty;
}

bool _insecureLogin(Uri uri, SchoolAdapter school) =>
    uri.scheme == 'http' &&
    school.insecureLoginPaths.contains(
      uri.path.replaceFirst(RegExp(r'/+$'), ''),
    );

bool isTrustedSchoolUrl(String url, {SchoolAdapter school = hautSchool}) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      !_insecureLogin(uri, school) &&
      school.origins.any((origin) => _matchesOrigin(uri, origin));
}

bool isSchoolCourseUrl(String url, {SchoolAdapter school = hautSchool}) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      !_insecureLogin(uri, school) &&
      school.courseOrigins.any((origin) => _matchesOrigin(uri, origin));
}

SchoolNavigationDecision schoolNavigation(
  String url, {
  SchoolAdapter school = hautSchool,
}) {
  if (url == 'about:blank') {
    return const SchoolNavigationDecision(SchoolNavigationAction.allow);
  }
  final uri = Uri.tryParse(url);
  if (uri != null &&
      _insecureLogin(uri, school) &&
      school.origins.any((origin) => _matchesOrigin(uri, origin))) {
    return SchoolNavigationDecision(
      SchoolNavigationAction.redirectLogin,
      Uri.parse(school.loginUrl),
    );
  }
  if (isTrustedSchoolUrl(url, school: school)) {
    return const SchoolNavigationDecision(SchoolNavigationAction.allow);
  }
  if (uri != null &&
      uri.scheme == 'http' &&
      school.httpsUpgradeHosts.contains(uri.host) &&
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
