package cn.semesteros.semester_os

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/**
 * Version-pinned adapter for flutter_local_notifications 22.3.1. Its normal
 * boot receiver deletes exact records when permission has been revoked.
 * Convert our future records to the allowed mode first; never replay missed
 * reminders after a long shutdown. Keep unrelated plugin records untouched.
 */
class ReminderBootReceiver : ScheduledNotificationBootReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in setOf(
                Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                "android.intent.action.QUICKBOOT_POWERON",
                "com.htc.intent.action.QUICKBOOT_POWERON",
                AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED,
            )) return
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()
        val preferences = context.getSharedPreferences("scheduled_notifications", Context.MODE_PRIVATE)
        val encoded = preferences.getString("scheduled_notifications", null)
        if (encoded != null) {
            try {
                val records = JSONArray(encoded)
                val future = JSONArray()
                for (index in 0 until records.length()) {
                    val record = records.getJSONObject(index)
                    if (record.optString("channelId") != "semester_items_v1") {
                        future.put(record)
                        continue
                    }
                    val payload = JSONObject(record.optString("payload", "{}"))
                    val trigger = payload.optString("trigger_at")
                    if (trigger.isEmpty() || !Instant.parse(trigger).isAfter(Instant.now())) continue
                    record.put("scheduleMode", if (exact) "exactAllowWhileIdle" else "inexactAllowWhileIdle")
                    payload.put("precise", exact)
                    record.put("payload", payload.toString())
                    future.put(record)
                }
                // The plugin immediately reads these records in this process.
                preferences.edit().putString("scheduled_notifications", future.toString()).apply()
            } catch (error: Exception) {
                Log.e("SemesterReminder", "Could not reconcile reminder records at reboot", error)
            }
        }
        val boot = Intent(intent).setAction(Intent.ACTION_BOOT_COMPLETED)
        super.onReceive(context, boot)
    }
}
