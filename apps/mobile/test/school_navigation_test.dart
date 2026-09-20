import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/import/school_navigation.dart';

void main() {
  test('official HTTPS pages and cleanup blank page remain navigable', () {
    expect(
      schoolNavigation(
        'https://jwglxt.haut.edu.cn/jwglxt/xtgl/login_slogin.html',
      ).action,
      SchoolNavigationAction.allow,
    );
    expect(
      schoolNavigation('about:blank').action,
      SchoolNavigationAction.allow,
    );
    expect(isTrustedSchoolUrl('about:blank'), false);
  });

  test(
    'observed same-host HTTP redirect is upgraded without losing the route',
    () {
      final result = schoolNavigation(
        'http://jwglxt.haut.edu.cn/jwglxt/xtgl/login_slogin.html',
      );
      expect(result.action, SchoolNavigationAction.upgradeHttps);
      expect(
        result.destination.toString(),
        'https://jwglxt.haut.edu.cn/jwglxt/xtgl/login_slogin.html',
      );
    },
  );

  test(
    'upgrades preserve synthetic query parameters and the fragment inside WebView',
    () {
      final result = schoolNavigation(
        'http://jwglxt.haut.edu.cn:80/jwglxt/xtgl/index_initMenu.html?gnmkdm=N2151&ticket=synthetic-test#section',
      );
      expect(result.action, SchoolNavigationAction.upgradeHttps);
      expect(result.destination!.scheme, 'https');
      expect(result.destination!.port, 443);
      expect(result.destination!.path, '/jwglxt/xtgl/index_initMenu.html');
      expect(result.destination!.query, 'gnmkdm=N2151&ticket=synthetic-test');
      expect(result.destination!.fragment, 'section');
      expect(isTrustedSchoolUrl(result.destination.toString()), true);
    },
  );

  test(
    'does not allow unverified hosts, embedded credentials, or nonstandard ports',
    () {
      for (final url in [
        'https://example.com/login',
        'https://jwglxt.haut.edu.cn.example.com/',
        'https://jwglxt.haut.edu.cn@example.com/',
        'https://user:secret@jwglxt.haut.edu.cn/',
        'https://jwglxt.haut.edu.cn:8443/',
        'http://jwglxt.haut.edu.cn:8080/',
        'javascript:alert(1)',
        'file:///etc/passwd',
      ]) {
        expect(
          schoolNavigation(url).action,
          SchoolNavigationAction.block,
          reason: url,
        );
      }
    },
  );

  test('reader never treats plain HTTP as an authenticated trusted page', () {
    expect(
      isTrustedSchoolUrl('http://jwglxt.haut.edu.cn/jwglxt/kbcx/index.html'),
      false,
    );
  });

  test(
    'blocked navigation message never includes synthetic secret-bearing URL parts',
    () {
      final message = blockedSchoolNavigationMessage(
        'https://user:private-value@example.com/session/synthetic-secret?ticket=synthetic-ticket#synthetic-fragment',
      );
      expect(message, contains('https://example.com'));
      for (final secret in [
        'private-value',
        'synthetic-secret',
        'synthetic-ticket',
        'synthetic-fragment',
      ]) {
        expect(message, isNot(contains(secret)));
      }
    },
  );

  test('repeated server redirects stop until refresh or a new window', () {
    final budget = SchoolRedirectBudget();
    final now = DateTime(2026, 9, 20);
    for (var i = 0; i < 5; i++) {
      expect(budget.allowUpgrade(now), true);
    }
    expect(budget.allowUpgrade(now), false);
    expect(budget.allowUpgrade(now.add(const Duration(seconds: 30))), true);
    budget.reset();
    expect(budget.allowUpgrade(now), true);
  });
}
