import '../../core/cache.dart';

class ReminderPreferences {
  final bool classReminders;
  final int classLeadMinutes;
  final bool quietEnabled;
  final int quietStart, quietEnd;
  const ReminderPreferences({
    this.classReminders = false,
    this.classLeadMinutes = 15,
    this.quietEnabled = false,
    this.quietStart = 22 * 60,
    this.quietEnd = 8 * 60,
  });
  factory ReminderPreferences.fromJson(Map<String, dynamic>? value) {
    final lead = value?['class_lead_minutes'];
    return ReminderPreferences(
      classReminders: value?['class_reminders'] == true,
      classLeadMinutes: lead is int && lead >= 0 && lead <= 120 ? lead : 15,
      quietEnabled: value?['quiet_enabled'] == true,
      quietStart: (value?['quiet_start'] as int? ?? 1320).clamp(0, 1439),
      quietEnd: (value?['quiet_end'] as int? ?? 480).clamp(0, 1439),
    );
  }
  Map<String, dynamic> toJson() => {
    'class_reminders': classReminders,
    'class_lead_minutes': classLeadMinutes,
    'quiet_enabled': quietEnabled,
    'quiet_start': quietStart,
    'quiet_end': quietEnd,
  };
  Map<String, dynamic> get query => {
    if (classReminders) 'course_lead_minutes': classLeadMinutes,
  };
  bool accepts(Map<String, dynamic> rule) =>
      rule['resource_type'] != 'course' ||
      (classReminders && rule['lead_minutes'] == classLeadMinutes);

  ReminderPreferences copyWith({
    bool? classReminders,
    int? classLeadMinutes,
    bool? quietEnabled,
    int? quietStart,
    int? quietEnd,
  }) => ReminderPreferences(
    classReminders: classReminders ?? this.classReminders,
    classLeadMinutes: classLeadMinutes ?? this.classLeadMinutes,
    quietEnabled: quietEnabled ?? this.quietEnabled,
    quietStart: quietStart ?? this.quietStart,
    quietEnd: quietEnd ?? this.quietEnd,
  );
  Map<String, dynamic> notification(Map<String, dynamic> rule) {
    final at = DateTime.tryParse(
      '${rule['trigger_at']}',
    )?.toUtc().add(const Duration(hours: 8));
    if (!quietEnabled || at == null || quietStart == quietEnd) return rule;
    final minutes = at.hour * 60 + at.minute;
    final quiet = quietStart < quietEnd
        ? minutes >= quietStart && minutes < quietEnd
        : minutes >= quietStart || minutes < quietEnd;
    return {...rule, if (quiet) 'quiet': true};
  }
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
