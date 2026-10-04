import '../../core/cache.dart';

class ReminderPreferences {
  final bool classReminders;
  final int classLeadMinutes;
  const ReminderPreferences({
    this.classReminders = false,
    this.classLeadMinutes = 15,
  });
  factory ReminderPreferences.fromJson(Map<String, dynamic>? value) {
    final lead = value?['class_lead_minutes'];
    return ReminderPreferences(
      classReminders: value?['class_reminders'] == true,
      classLeadMinutes: lead is int && lead >= 0 && lead <= 120 ? lead : 15,
    );
  }
  Map<String, dynamic> toJson() => {
    'class_reminders': classReminders,
    'class_lead_minutes': classLeadMinutes,
  };
  Map<String, dynamic> get query => {
    if (classReminders) 'course_lead_minutes': classLeadMinutes,
  };
  bool accepts(Map<String, dynamic> rule) =>
      rule['resource_type'] != 'course' ||
      (classReminders && rule['lead_minutes'] == classLeadMinutes);
}

/// Separate owner keys avoid overwriting timetable caches or inheriting a
/// previous account's opt-in. No server migration is needed for device options.
class ReminderPreferenceStore {
  final CalendarStore cache;
  const ReminderPreferenceStore(this.cache);
  Future<ReminderPreferences> read(String owner) async =>
      ReminderPreferences.fromJson(
        await cache.read('reminder-settings:$owner'),
      );
  Future<void> write(String owner, ReminderPreferences preferences) =>
      cache.write('reminder-settings:$owner', preferences.toJson());
}
