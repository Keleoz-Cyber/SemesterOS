package cn.semesteros.semester_os

import android.app.*
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.*
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.widget.RemoteViews
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** A system-rendered snapshot. Alarms wake this receiver at changes, not a resident process. */
object DeviceSurfaces {
    private const val LIVE_ID = 170001
    private const val TEST_ID = 170002
    private const val CHANNEL = "shiri_live_activity"
    private fun prefs(c: Context) = c.getSharedPreferences("device_surfaces", Context.MODE_PRIVATE)
    private fun snapshot(c: Context) = runCatching { JSONObject(prefs(c).getString("snapshot", "{}")!!) }.getOrDefault(JSONObject())
    private fun millis(value: String): Long = runCatching { Instant.parse(value).toEpochMilli() }.getOrDefault(0L)
    private fun time(value: Long) = DateTimeFormatter.ofPattern("MM-dd HH:mm").withZone(ZoneId.of("Asia/Shanghai")).format(Instant.ofEpochMilli(value))
    private fun rows(data: JSONObject): List<JSONObject> {
        val array = data.optJSONArray("entries") ?: return emptyList()
        return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
    }
    private fun open(c: Context, route: String): PendingIntent {
        val intent = Intent(c, MainActivity::class.java).putExtra("shiri_route", route)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(c, route.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    private fun receiver(c: Context, action: String) = PendingIntent.getBroadcast(c, action.hashCode(),
        Intent(c, SurfaceReceiver::class.java).setAction(action), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun sync(c: Context, json: String) {
        val old = snapshot(c)
        val data = JSONObject(json)
        if (old.optString("owner") != data.optString("owner") || old.optString("semester") != data.optString("semester")) {
            stop(c)
        }
        prefs(c).edit().putString("snapshot", json).commit()
        render(c)
    }
    fun stop(c: Context) {
        prefs(c).edit().remove("tracked").remove("tracked_until").commit()
        (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(LIVE_ID)
    }
    fun track(c: Context, id: String) {
        require((c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()) { "请先允许拾日发送通知" }
        val data = snapshot(c)
        require(data.optString("owner").isNotEmpty()) { "请登录后再跟踪安排" }
        val row = rows(data).firstOrNull { it.optString("id") == id } ?: error("安排已有变化，请刷新")
        val now = System.currentTimeMillis()
        val start = millis(row.optString("start_at"))
        val end = millis(row.optString("end_at"))
        require(start > 0 && start <= now + 15 * 60_000 && (end == 0L || end > now)) { "可以跟踪正在进行或15分钟内开始的安排" }
        prefs(c).edit().putString("tracked", id).putLong("tracked_until", if (end > 0) end else now + 12 * 3600_000).commit()
        render(c)
    }
    fun render(c: Context) {
        val data = snapshot(c)
        val now = System.currentTimeMillis()
        val entries = rows(data)
        val upcoming = entries.filter {
            val end = millis(it.optString("end_at")); val start = millis(it.optString("start_at"))
            start > 0 && (if (end > 0) end > now else start >= now)
        }.sortedBy { millis(it.optString("start_at")) }
        val manager = AppWidgetManager.getInstance(c)
        val ids = manager.getAppWidgetIds(ComponentName(c, ScheduleWidget::class.java))
        for (id in ids) {
            val views = RemoteViews(c.packageName, R.layout.schedule_widget)
            views.setTextViewText(R.id.widget_title, "拾日 · 接下来的安排")
            val first = upcoming.firstOrNull()
            views.setTextViewText(R.id.widget_next, first?.optString("title") ?: if (data.optString("owner").isEmpty()) "打开拾日登录" else "暂时没有已记录的安排")
            views.setTextViewText(R.id.widget_time, first?.let { time(millis(it.optString("start_at"))) + "  " + it.optString("location") } ?: "")
            val deadlines = data.optJSONArray("deadlines")
            val deadline = if (deadlines != null && deadlines.length() > 0) deadlines.getJSONObject(0) else null
            val deadlineTime = deadline?.optJSONObject("time")
            val due = deadlineTime?.optString("at")?.let { millis(it) } ?: 0L
            val dueText = if (due > 0) time(due) else deadlineTime?.optString("date") ?: ""
            views.setTextViewText(R.id.widget_other, (upcoming.drop(1).take(1).map { time(millis(it.optString("start_at"))) + "  " + it.optString("title") } +
                if (deadline != null) listOf("待办 " + dueText + " " + deadline.optString("title")) else emptyList()).joinToString("\n"))
            val saved = data.optLong("synced_at")
            views.setTextViewText(R.id.widget_status, if (saved > 0) "本机记录 · " + time(saved) + "更新" else "点击打开拾日")
            views.setOnClickPendingIntent(R.id.widget_body, open(c, first?.optString("route") ?: "/"))
            views.setOnClickPendingIntent(R.id.widget_add, open(c, "/assistant"))
            manager.updateAppWidget(id, views)
        }
        val tracked = prefs(c).getString("tracked", null)
        val row = entries.firstOrNull { it.optString("id") == tracked }
        val knownEnd = row?.let { millis(it.optString("end_at")) } ?: 0L
        val until = if (knownEnd > 0) knownEnd else prefs(c).getLong("tracked_until", 0)
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (row == null || until <= now || data.optString("owner").isEmpty()) {
            stop(c)
        } else {
            ensureChannel(c)
            if (Build.VERSION.SDK_INT < 24 || nm.areNotificationsEnabled()) {
                val start = millis(row.optString("start_at")); val end = millis(row.optString("end_at"))
                val waiting = start > now
                val text = (if (waiting) "即将开始" else if (end > 0) "正在进行" else "结束时间未定") + " · " + time(start) + "  " + row.optString("location")
                val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, CHANNEL) else Notification.Builder(c)
                builder.setSmallIcon(R.drawable.ic_notification).setContentTitle(row.optString("title"))
                    .setContentText(text).setStyle(Notification.BigTextStyle().bigText(text))
                    .setContentIntent(open(c, row.optString("route", "/"))).setOngoing(true).setOnlyAlertOnce(true)
                    .setVisibility(Notification.VISIBILITY_PRIVATE).setCategory(Notification.CATEGORY_EVENT)
                    .setWhen(if (waiting) start else if (end > 0) end else start).setUsesChronometer(true)
                    .setChronometerCountDown(waiting || end > 0)
                    .setDeleteIntent(receiver(c, "shiri.stopTracking"))
                    .addAction(Notification.Action.Builder(null, "停止跟踪", receiver(c, "shiri.stopTracking")).build())
                if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter(until - now)
                // Reflection preserves compatibility with older compile/runtime APIs and OEMs.
                if (Build.VERSION.SDK_INT >= 36) runCatching {
                    Notification.Builder::class.java.getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType).invoke(builder, true)
                }
                runCatching { nm.notify(LIVE_ID, builder.build()) }
            }
        }
        val boundaries = entries.flatMap { listOf(millis(it.optString("start_at")), millis(it.optString("end_at"))) }
            .filter { it > now + 1000 }.toMutableList()
        if (until > now) boundaries.add(until)
        val alarm = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = receiver(c, "shiri.refreshSurfaces")
        alarm.cancel(pending)
        boundaries.minOrNull()?.let {
            try {
                if (Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()) alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, it, pending)
                else alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, it, pending)
            } catch (_: SecurityException) { alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, it, pending) }
        }
    }
    private fun ensureChannel(c: Context) {
        if (Build.VERSION.SDK_INT >= 26) (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(NotificationChannel(CHANNEL, "进行中安排", NotificationManager.IMPORTANCE_LOW))
    }
    fun test(c: Context) {
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!nm.areNotificationsEnabled()) error("请先允许拾日发送通知")
        if (Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(NotificationChannel("shiri_test", "测试提醒", NotificationManager.IMPORTANCE_DEFAULT))
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, "shiri_test") else Notification.Builder(c)
        nm.notify(TEST_ID, b.setSmallIcon(R.drawable.ic_notification).setContentTitle("拾日测试提醒")
            .setContentText("这是一条测试通知，不会修改你的日程").setAutoCancel(true).setContentIntent(open(c, "/reminders")).build())
    }
    fun status(c: Context): Map<String, Any> {
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val pm = c.getSystemService(Context.POWER_SERVICE) as PowerManager
        val alarm = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val promoted = if (Build.VERSION.SDK_INT >= 36) runCatching {
            NotificationManager::class.java.getMethod("canPostPromotedNotifications").invoke(nm) as Boolean
        }.getOrDefault(false) else false
        return mapOf("sdk" to Build.VERSION.SDK_INT, "notifications" to nm.areNotificationsEnabled(),
            "exact" to (Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()),
            "battery_unrestricted" to pm.isIgnoringBatteryOptimizations(c.packageName), "promoted" to promoted,
            "tracked" to (prefs(c).getString("tracked", "") ?: ""),
            "entries" to rows(snapshot(c)).map { it.toString() })
    }
}

class ScheduleWidget : AppWidgetProvider() {
    override fun onUpdate(c: Context, manager: AppWidgetManager, ids: IntArray) = DeviceSurfaces.render(c)
}

class SurfaceReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, intent: Intent) {
        if (intent.action == "shiri.stopTracking") DeviceSurfaces.stop(c)
        DeviceSurfaces.render(c)
    }
}

/** Storage Access Framework lets the user choose the destination; no storage permission. */
class SurfaceBridge(private val activity: MainActivity, channel: MethodChannel) {
    private var exportResult: MethodChannel.Result? = null
    private var exportText: String? = null
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "sync" -> { DeviceSurfaces.sync(activity, call.arguments as String); result.success(null) }
                    "status" -> result.success(DeviceSurfaces.status(activity))
                    "track" -> { DeviceSurfaces.track(activity, call.argument<String>("id")!!); result.success(null) }
                    "stop" -> { DeviceSurfaces.stop(activity); result.success(null) }
                    "test" -> { DeviceSurfaces.test(activity); result.success(null) }
                    "batterySettings" -> { activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)); result.success(null) }
                    "promotedSettings" -> {
                        val intent = Intent(if (Build.VERSION.SDK_INT >= 36) "android.settings.MANAGE_APP_PROMOTED_NOTIFICATIONS" else Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                        activity.startActivity(intent); result.success(null)
                    }
                    "pinWidget" -> {
                        val manager = AppWidgetManager.getInstance(activity)
                        if (Build.VERSION.SDK_INT >= 26 && manager.isRequestPinAppWidgetSupported) {
                            manager.requestPinAppWidget(ComponentName(activity, ScheduleWidget::class.java), null, null)
                        } else error("请长按桌面，在小组件列表中添加拾日")
                        result.success(null)
                    }
                    "export" -> {
                        if (exportResult != null) error("请先完成上一次导出")
                        exportText = call.arguments as String
                        exportResult = result
                        activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE).setType("application/json")
                            .putExtra(Intent.EXTRA_TITLE, "拾日个人数据.json"), 7201)
                    }
                    "consumeRoute" -> {
                        val route = activity.intent.getStringExtra("shiri_route")
                        activity.intent.removeExtra("shiri_route"); result.success(route)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                if (call.method == "export") { exportResult = null; exportText = null }
                result.error("SURFACE_ERROR", e.message ?: "操作未完成", null)
            }
        }
    }
    fun activityResult(requestCode: Int, resultCode: Int, intent: Intent?): Boolean {
        if (requestCode != 7201) return false
        val result = exportResult; val text = exportText
        exportResult = null; exportText = null
        if (result == null || text == null) return true
        if (resultCode != Activity.RESULT_OK || intent?.data == null) { result?.success(false); return true }
        try {
            activity.contentResolver.openOutputStream(intent.data!!, "wt")!!.use { it.write((text ?: "").toByteArray(Charsets.UTF_8)) }
            result?.success(true)
        } catch (e: Exception) { result?.error("EXPORT_FAILED", "文件未保存，请重新选择位置", null) }
        return true
    }
}
