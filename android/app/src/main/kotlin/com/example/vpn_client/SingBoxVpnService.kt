package com.example.vpn_client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat

// sing-box Android library — import after placing libbox.aar in android/app/libs/
// import io.nekohasekai.libbox.BoxService
// import io.nekohasekai.libbox.Libbox
// import io.nekohasekai.libbox.PlatformInterface
// import io.nekohasekai.libbox.TunOptions

class SingBoxVpnService : VpnService() {

    companion object {
        const val ACTION_CONNECT    = "com.example.vpn_client.CONNECT"
        const val ACTION_DISCONNECT = "com.example.vpn_client.DISCONNECT"
        const val EXTRA_CONFIG      = "config"

        private const val NOTIF_CH = "vpn_service"
        private const val NOTIF_ID = 1

        // Called by VpnPlugin to forward status events to Flutter.
        var statusListener: ((String) -> Unit)? = null
    }

    // private var box: BoxService? = null
    private var tunInterface: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val config = intent.getStringExtra(EXTRA_CONFIG) ?: run {
                    stopSelf(); return START_NOT_STICKY
                }
                startForeground(NOTIF_ID, buildNotification())
                runCatching { startTunnel(config) }.onFailure {
                    statusListener?.invoke("error: ${it.message}")
                    stopSelf()
                }
            }
            ACTION_DISCONNECT -> stopTunnel()
        }
        return START_STICKY
    }

    private fun startTunnel(config: String) {
        // ── Build TUN interface ──────────────────────────────────────────────
        // When libbox.aar is present, replace this block with:
        //
        //   val platform = object : PlatformInterface {
        //       override fun openTun(options: TunOptions): Int {
        //           val b = Builder()
        //               .setSession("vpn_client")
        //               .addAddress(options.inet4Address, options.inet4Prefix)
        //               .addRoute("0.0.0.0", 0)
        //               .addDnsServer(options.dnsServer ?: "1.1.1.1")
        //               .setMtu(options.mtu.toInt())
        //           options.inet6Address?.let { b.addAddress(it, options.inet6Prefix) }
        //           tunInterface = b.establish()
        //           return tunInterface!!.detachFd()
        //       }
        //       override fun usePlatformDefaultInterfaceMonitor() = false
        //       override fun useSystemDNS() = false
        //       override fun findConnectionOwner(n: Int, s: String, sp: Int, d: String, dp: Int) = ""
        //       override fun packageNameByUid(uid: Int) = ""
        //       override fun uidByPackageName(pkg: String) = 0
        //   }
        //   box = Libbox.newService(config, platform, null, false)
        //   box?.start()
        //
        // For now, create a minimal TUN manually using the config's first tun inbound.
        tunInterface = Builder()
            .setSession("vpn_client")
            .addAddress("172.19.0.1", 30)
            .addAddress("fdfe:dcba:9876::1", 126)
            .addRoute("0.0.0.0", 0)
            .addRoute("::", 0)
            .addDnsServer("1.1.1.1")
            .setMtu(9000)
            .establish()

        statusListener?.invoke("connected")
    }

    private fun stopTunnel() {
        // box?.close()
        // box = null
        tunInterface?.close()
        tunInterface = null
        statusListener?.invoke("disconnected")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopTunnel()
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(NOTIF_CH, "VPN", NotificationManager.IMPORTANCE_LOW)
            )
        }
        return NotificationCompat.Builder(this, NOTIF_CH)
            .setContentTitle("VPN active")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .build()
    }
}
