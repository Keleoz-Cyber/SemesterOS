import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/home/home_preferences.dart';
import 'controller_test.dart' show MemoryStore;

void main() {
  test('home module choices persist per account and semester', () async {
    final cache = MemoryStore();
    final a = HomePreferences(cache, 'a', 's', () => true);
    await a.change(
      order: ['windows', 'deadlines', 'exams', 'plans'],
      enabled: {'windows', 'deadlines'},
    );
    final restored = HomePreferences(cache, 'a', 's', () => true);
    await restored.restore();
    expect(restored.order.first, 'windows');
    expect(restored.enabled, {'windows', 'deadlines'});
    final other = HomePreferences(cache, 'b', 's', () => true);
    await other.restore();
    expect(other.enabled.length, 4);
    final term = HomePreferences(cache, 'a', 't', () => true);
    await term.restore();
    expect(term.order.first, 'deadlines');
    a.dispose();
    restored.dispose();
    other.dispose();
    term.dispose();
  });
}
