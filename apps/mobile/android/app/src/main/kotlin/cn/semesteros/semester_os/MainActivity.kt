package cn.semesteros.semester_os

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var incomingChannel: MethodChannel? = null
    private val inputWorker = Executors.newSingleThreadExecutor()
    private val inboxLock = Any()
    private val inboxPreferences by lazy { getSharedPreferences("incoming_notice", MODE_PRIVATE) }
    private val inboxDirectory by lazy { File(filesDir, "incoming-notices") }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        incomingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cn.semesteros/incoming_notice")
        incomingChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingDrafts" -> result.success(pendingDrafts().map { draftMap(it) })
                "acknowledgeDraft" -> {
                    val id = call.argument<String>("id")
                    synchronized(inboxLock) {
                        persistDrafts(pendingDrafts().filter { it.optString("id") != id })
                    }
                    result.success(null)
                }
                "releaseImages" -> {
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    inputWorker.execute {
                        val parent = inboxDirectory.canonicalPath + File.separator
                        paths.forEach { path ->
                            val file = File(path)
                            if (file.canonicalPath.startsWith(parent)) file.delete()
                        }
                    }
                    result.success(null)
                }
                "clipboardStatus" -> {
                    // Description and timestamp do not expose clipboard contents.
                    val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                    val description = clipboard.primaryClipDescription
                    val hasText = description?.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) == true ||
                        description?.hasMimeType(ClipDescription.MIMETYPE_TEXT_HTML) == true
                    val timestamp = if (Build.VERSION.SDK_INT >= 26) description?.timestamp ?: 0L else 0L
                    val token = "clipboard:$timestamp"
                    val handled = inboxPreferences.getStringSet("handled_clipboard", emptySet()) ?: emptySet()
                    result.success(mapOf("has_text" to hasText, "token" to token, "handled" to handled.contains(token)))
                }
                "markClipboardHandled" -> {
                    val token = call.argument<String>("token")
                    val handled = (inboxPreferences.getStringSet("handled_clipboard", emptySet()) ?: emptySet()).toMutableSet()
                    if (token != null) handled.add(token)
                    inboxPreferences.edit().putStringSet("handled_clipboard", handled.toList().takeLast(32).toSet()).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureIncoming(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureIncoming(intent)
    }

    @Suppress("DEPRECATION")
    private fun captureIncoming(intent: Intent?) {
        if (intent == null || intent.getBooleanExtra("semesteros_input_captured", false)) return
        if (intent.action !in listOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE, Intent.ACTION_PROCESS_TEXT)) return
        intent.putExtra("semesteros_input_captured", true)
        val text = when (intent.action) {
            Intent.ACTION_PROCESS_TEXT -> intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
            else -> intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        } ?: ""
        val images = mutableListOf<Uri>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            images.addAll(intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList())
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { images.add(it) }
        }
        intent.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) clip.getItemAt(index).uri?.let { images.add(it) }
        }
        val imageUris = images.distinct().filter {
            (runCatching { contentResolver.getType(it) }.getOrNull() ?: intent.type ?: "").startsWith("image/")
        }
        if (text.isBlank() && imageUris.isEmpty()) return
        inputWorker.execute {
            val id = UUID.randomUUID().toString()
            val copied = mutableListOf<String>()
            var failed = 0
            inboxDirectory.mkdirs()
            imageUris.forEachIndexed { index, uri ->
                val extension = when (runCatching { contentResolver.getType(uri) }.getOrNull()) {
                    "image/png" -> "png"
                    "image/webp" -> "webp"
                    else -> "jpg"
                }
                val file = File(inboxDirectory, "$id-$index.$extension")
                try {
                    contentResolver.openInputStream(uri).use { source ->
                        requireNotNull(source)
                        file.outputStream().use { target ->
                            val buffer = ByteArray(64 * 1024)
                            var size = 0L
                            while (true) {
                                val count = source.read(buffer)
                                if (count < 0) break
                                size += count
                                require(size <= 10 * 1024 * 1024) { "image too large" }
                                target.write(buffer, 0, count)
                            }
                        }
                    }
                    copied.add(file.path)
                } catch (_: Exception) {
                    failed++
                    file.delete()
                }
            }
            val warnings = mutableListOf<String>()
            if (failed > 0) warnings.add("有${failed}张图片未能带入，请重新选择、压缩过大的图片或粘贴文字。")
            val draft = JSONObject().put("id", id).put("text", text)
                .put("image_paths", JSONArray(copied))
            if (warnings.isNotEmpty()) draft.put("warning", warnings.joinToString(""))
            if (text.isBlank() && copied.isEmpty()) {
                // Preserve a visible explanation even if the provider denied every URI.
                draft.put("text", "").put("warning", warnings.joinToString(""))
            }
            synchronized(inboxLock) { persistDrafts(pendingDrafts() + draft) }
            Handler(Looper.getMainLooper()).post {
                incomingChannel?.invokeMethod("incomingDraft", draftMap(draft))
            }
        }
    }

    private fun pendingDrafts(): List<JSONObject> = synchronized(inboxLock) {
        try {
            val values = JSONArray(inboxPreferences.getString("drafts", "[]"))
            (0 until values.length()).map { values.getJSONObject(it) }
        } catch (_: Exception) { emptyList() }
    }

    private fun persistDrafts(values: List<JSONObject>) {
        inboxPreferences.edit().putString("drafts", JSONArray(values).toString()).commit()
    }

    private fun draftMap(value: JSONObject): Map<String, Any?> {
        val files = value.optJSONArray("image_paths") ?: JSONArray()
        return mapOf(
            "id" to value.optString("id"), "text" to value.optString("text"),
            "image_paths" to (0 until files.length()).map { files.getString(it) },
            "warning" to if (value.has("warning")) value.getString("warning") else null
        )
    }

    override fun onDestroy() {
        incomingChannel?.setMethodCallHandler(null)
        incomingChannel = null
        inputWorker.shutdown()
        super.onDestroy()
    }
}
