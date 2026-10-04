import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/items/notification_target.dart';
import 'package:semester_os/features/items/reminder_preferences.dart';
import 'controller_test.dart' show MemoryStore;

void main() {
  test(
    'course opt-in remains account scoped and filters stale course leads',
    () async {
      final store = ReminderPreferenceStore(MemoryStore());
      await store.write(
        'a',
        const ReminderPreferences(classReminders: true, classLeadMinutes: 30),
      );
      final a = await store.read('a'), b = await store.read('b');
      expect(a.query, {'course_lead_minutes': 30});
      expect(b.classReminders, isFalse);
      expect(b.classLeadMinutes, 15);
      expect(
        a.accepts({'resource_type': 'course', 'lead_minutes': 15}),
        isFalse,
      );
      expect(
        b.accepts({'resource_type': 'course', 'lead_minutes': 15}),
        isFalse,
      );
      expect(b.accepts({'resource_type': 'exam'}), isTrue);
    },
  );
  test(
    'typed payload preserves event/course targets and actual school time/place',
    () {
      final data = {
        'owner_id': 'a',
        'resource_type': 'course',
        'resource_id': 'c',
        'semester_id': 's',
        'start_at': '2026-10-01T00:00:00Z',
        'place': 'A305',
      };
      final target = NotificationTarget.decode(
        jsonEncode(data),
        actionId: 'snooze_10',
        notificationId: 17,
      )!;
      expect(target.resourceType, 'course');
      expect(target.resourceId, 'c');
      expect(target.notificationId, 17);
      expect(reminderBody(data), '上课 10月1日 08:00 · A305');
      final legacy = NotificationTarget.decode(
        jsonEncode({'owner_id': 'a', 'item_id': 'event:e'}),
      )!;
      expect(legacy.resourceType, 'event');
      expect(legacy.resourceId, 'e');
      expect(
        NotificationTarget.decode(
          '{"owner_id":"a","resource_type":"unknown","resource_id":"c"}',
        ),
        isNull,
      );
    },
  );
}
