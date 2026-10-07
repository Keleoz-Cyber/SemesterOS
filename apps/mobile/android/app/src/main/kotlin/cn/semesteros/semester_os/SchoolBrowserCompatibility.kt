package cn.semesteros.semester_os

import androidx.webkit.ScriptHandler
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

/** Install before navigation, on this WebView and the exact portal origin only. */
class SchoolBrowserCompatibility : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var binding: FlutterPlugin.FlutterPluginBinding? = null
    private var channel: MethodChannel? = null
    private val scripts = mutableMapOf<Long, ScriptHandler>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        channel = MethodChannel(binding.binaryMessenger, "cn.semesteros/school_browser")
        channel?.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("identifier")?.toLong()
        val owner = binding
        if (id == null || owner == null) {
            result.error("missing_webview", "School WebView is unavailable", null)
            return
        }
        when (call.method) {
            "install" -> {
                if (scripts.containsKey(id)) { result.success(null); return }
                if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                    result.error("unsupported_webview", "Document start scripts are unavailable", null)
                    return
                }
                val web = WebViewFlutterAndroidExternalApi.getWebView(owner, id)
                if (web == null) {
                    result.error("missing_webview", "School WebView is unavailable", null)
                    return
                }
                try {
                    val source = owner.applicationContext.assets
                        .open("flutter_assets/assets/hlju_browser_compat.js")
                        .bufferedReader().use { it.readText() }
                    scripts[id] = WebViewCompat.addDocumentStartJavaScript(
                        web, source, setOf("http://xsxk.hlju.edu.cn")
                    )
                    result.success(null)
                } catch (_: Exception) {
                    result.error("compatibility_unavailable", "School compatibility could not be installed", null)
                }
            }
            "remove" -> { scripts.remove(id)?.remove(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        scripts.values.forEach { runCatching { it.remove() } }
        scripts.clear()
        channel?.setMethodCallHandler(null)
        channel = null
        this.binding = null
    }
}
