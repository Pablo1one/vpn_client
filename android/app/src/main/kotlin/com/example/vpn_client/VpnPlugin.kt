package com.example.vpn_client

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

object VpnPlugin : PluginRegistry.ActivityResultListener {

    private const val METHOD_CH = "com.example.vpn_client/vpn"
    private const val EVENT_CH  = "com.example.vpn_client/vpn_events"
    private const val VPN_REQ   = 0xF1

    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingConfig: String? = null
    private var pendingResult: MethodChannel.Result? = null

    fun register(activity: Activity, engine: FlutterEngine) {
        this.activity = activity

        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CH)
            .setMethodCallHandler(::onMethodCall)

        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CH)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    // Forward current service status on subscribe.
                    SingBoxVpnService.statusListener = { status -> eventSink?.success(status) }
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
                val intent = VpnService.prepare(activity)
                if (intent != null) {
                    pendingConfig = config
                    pendingResult = result
                    activity?.startActivityForResult(intent, VPN_REQ)
                } else {
                    startService(config)
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
            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != VPN_REQ) return false
        if (resultCode == Activity.RESULT_OK) {
            pendingConfig?.let { startService(it) }
            pendingResult?.success(null)
        } else {
            pendingResult?.error("PERMISSION_DENIED", "VPN permission denied", null)
        }
        pendingConfig = null
        pendingResult = null
        return true
    }

    private fun startService(config: String) {
        activity?.startService(
            Intent(activity, SingBoxVpnService::class.java)
                .setAction(SingBoxVpnService.ACTION_CONNECT)
                .putExtra(SingBoxVpnService.EXTRA_CONFIG, config)
        )
    }
}
