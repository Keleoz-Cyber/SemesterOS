import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/items/reminder_preferences.dart';

void main() {
  test('quiet hours crossing midnight do not shift the reminder time', () {
    const p = ReminderPreferences(quietEnabled: true);
    for (final pair in {'2026-10-13T14:00:00Z': true, '2026-10-13T23:59:00Z': true, '2026-10-14T00:00:00Z': false}.entries) {
      final row = p.notification({'trigger_at': pair.key});
      expect(row['quiet'] == true, pair.value);
      expect(row['trigger_at'], pair.key);
    }
    expect(p.copyWith(classReminders: true).quietEnabled, isTrue);
  });
  test('default reminders retain their original notification policy', () {
    final source = {'trigger_at': '2026-10-13T15:00:00Z'};
    expect(const ReminderPreferences().notification(source), source);
  });
}
