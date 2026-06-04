package lightningmcqueen.proxy

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

object VpnPlugin : PluginRegistry.ActivityResultListener {

    private const val METHOD_CH = "lightningmcqueen.proxy/vpn"
    private const val EVENT_CH  = "lightningmcqueen.proxy/vpn_events"
    private const val VPN_REQ   = 0xF1

    private val mainHandler = Handler(Looper.getMainLooper())
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingConfig: String? = null
    private var pendingExcludedApps: List<String> = emptyList()
    private var pendingResult: MethodChannel.Result? = null

    fun register(activity: Activity, engine: FlutterEngine) {
        this.activity = activity

        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CH)
            .setMethodCallHandler(::onMethodCall)

        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CH)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    // статусы прилетают из фоновых потоков сервиса/libbox, а flutter-каналы
                    // можно трогать только с main-потока — маршалим через main handler
                    SingBoxVpnService.statusListener = { status ->
                        mainHandler.post { eventSink?.success(status) }
                    }
                }
                override fun onCancel(args: Any?) {
                    SingBoxVpnService.statusListener = null
                    eventSink = null
                }
            })
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connect" -> {
                val config = call.argument<String>("config")
                    ?: return result.error("INVALID_ARG", "config required", null)
                val excludedApps = call.argument<List<String>>("excludedApps") ?: emptyList()
                val intent = VpnService.prepare(activity)
                if (intent != null) {
                    pendingConfig = config
                    pendingExcludedApps = excludedApps
                    pendingResult = result
                    activity?.startActivityForResult(intent, VPN_REQ)
                } else {
                    startService(config, excludedApps)
                    result.success(null)
                }
            }
            "disconnect" -> {
                activity?.startService(
                    Intent(activity, SingBoxVpnService::class.java)
                        .setAction(SingBoxVpnService.ACTION_DISCONNECT)
                )
                result.success(null)
            }
            "getInstalledApps" -> {
                val pm = activity?.packageManager
                    ?: return result.error("NO_ACTIVITY", "no activity", null)
                val launchIntent = Intent(Intent.ACTION_MAIN, null).apply {
                    addCategory(Intent.CATEGORY_LAUNCHER)
                }
                @Suppress("DEPRECATION")
                val apps = pm.queryIntentActivities(launchIntent, 0)
                    .map { ri ->
                        mapOf(
                            "package" to ri.activityInfo.packageName,
                            "name" to ri.loadLabel(pm).toString()
                        )
                    }
                    .sortedBy { it["name"] }
                result.success(apps)
            }
            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != VPN_REQ) return false
        if (resultCode == Activity.RESULT_OK) {
            pendingConfig?.let { startService(it, pendingExcludedApps) }
            pendingResult?.success(null)
        } else {
            pendingResult?.error("PERMISSION_DENIED", "VPN permission denied", null)
        }
        pendingConfig = null
        pendingExcludedApps = emptyList()
        pendingResult = null
        return true
    }

    private fun startService(config: String, excludedApps: List<String>) {
        activity?.startService(
            Intent(activity, SingBoxVpnService::class.java)
                .setAction(SingBoxVpnService.ACTION_CONNECT)
                .putExtra(SingBoxVpnService.EXTRA_CONFIG, config)
                .putStringArrayListExtra(
                    SingBoxVpnService.EXTRA_EXCLUDED_APPS,
                    ArrayList(excludedApps)
                )
        )
    }
}
