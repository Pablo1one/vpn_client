package lightningmcqueen.proxy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import androidx.core.app.NotificationCompat
import io.nekohasekai.libbox.BoxService
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.InetSocketAddress

// vpn-сервис на базе libbox (sing-box). реализует PlatformInterface: libbox сам
// зовёт openTun, мы строим туннель из TunOptions и отдаём fd. наружу шлём статусы.
// акроним-методы libbox (getMTU, getDNSServerAddress) зовём явно — property-синтаксис
// kotlin их мапит непредсказуемо
class SingBoxVpnService : VpnService(), PlatformInterface {

    companion object {
        const val ACTION_CONNECT    = "lightningmcqueen.proxy.CONNECT"
        const val ACTION_DISCONNECT = "lightningmcqueen.proxy.DISCONNECT"
        const val EXTRA_CONFIG      = "config"
        const val EXTRA_EXCLUDED_APPS = "excluded_apps"

        private const val NOTIF_CH = "vpn_service"
        private const val NOTIF_ID = 1

        var statusListener: ((String) -> Unit)? = null
        @Volatile private var setupDone = false
    }

    private var boxService: BoxService? = null
    private var tunInterface: ParcelFileDescriptor? = null
    private var defaultNetwork: Network? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val config = intent.getStringExtra(EXTRA_CONFIG) ?: run {
                    stopSelf(); return START_NOT_STICKY
                }
                startForeground(NOTIF_ID, buildNotification())
                statusListener?.invoke("connecting")
                Thread {
                    runCatching { startBox(config) }.onFailure {
                        statusListener?.invoke("error: ${it.message}")
                        stopBox()
                    }
                }.start()
            }
            ACTION_DISCONNECT -> stopBox()
        }
        return START_STICKY
    }

    private fun startBox(config: String) {
        if (!setupDone) {
            val opts = SetupOptions()
            opts.basePath = filesDir.absolutePath
            opts.workingPath = filesDir.absolutePath
            opts.tempPath = cacheDir.absolutePath
            Libbox.setup(opts)
            Libbox.setMemoryLimit(true)
            setupDone = true
        }
        val service = Libbox.newService(config, this)
        service.start()
        boxService = service
        statusListener?.invoke("connected")
    }

    private fun stopBox() {
        runCatching { boxService?.close() }
        boxService = null
        runCatching { tunInterface?.close() }
        tunInterface = null
        statusListener?.invoke("disconnected")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() { stopBox(); super.onDestroy() }
    override fun onRevoke() { stopBox() }

    // ── PlatformInterface: построение TUN ───────────────────────────────────
    override fun openTun(options: TunOptions): Int {
        val builder = Builder().setSession("LightningMcQueen").setMtu(options.getMTU())

        val inet4 = options.getInet4Address()
        while (inet4.hasNext()) { val p = inet4.next(); builder.addAddress(p.address(), p.prefix()) }
        val inet6 = options.getInet6Address()
        while (inet6.hasNext()) { val p = inet6.next(); builder.addAddress(p.address(), p.prefix()) }

        if (options.getAutoRoute()) {
            runCatching { builder.addDnsServer(options.getDNSServerAddress().getValue()) }

            val r4 = options.getInet4RouteAddress()
            if (r4.hasNext()) {
                while (r4.hasNext()) { val p = r4.next(); builder.addRoute(p.address(), p.prefix()) }
            } else builder.addRoute("0.0.0.0", 0)
            val r6 = options.getInet6RouteAddress()
            while (r6.hasNext()) { val p = r6.next(); builder.addRoute(p.address(), p.prefix()) }

            val incl = options.getIncludePackage()
            while (incl.hasNext()) runCatching { builder.addAllowedApplication(incl.next()) }
            val excl = options.getExcludePackage()
            while (excl.hasNext()) runCatching { builder.addDisallowedApplication(excl.next()) }
        }

        builder.setBlocking(false)
        val pfd = builder.establish() ?: throw IllegalStateException("VpnService.establish() вернул null")
        tunInterface = pfd
        return pfd.fd
    }

    // ── PlatformInterface: защита сокетов libbox от петли через туннель ──────
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true
    override fun autoDetectInterfaceControl(fd: Int) { protect(fd) }

    // ── PlatformInterface: монитор интерфейса по умолчанию ──────────────────
    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val cm = getSystemService(ConnectivityManager::class.java)
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { updateDefault(network, listener) }
            override fun onLost(network: Network) {
                if (defaultNetwork == network) listener.updateDefaultInterface("", -1, false, false)
            }
        }
        networkCallback = cb
        cm.registerNetworkCallback(request, cb)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        networkCallback?.let {
            runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(it) }
        }
        networkCallback = null
    }

    private fun updateDefault(network: Network, listener: InterfaceUpdateListener) {
        defaultNetwork = network
        val cm = getSystemService(ConnectivityManager::class.java)
        val name = cm.getLinkProperties(network)?.interfaceName ?: return
        val index = runCatching { java.net.NetworkInterface.getByName(name).index }.getOrDefault(-1)
        listener.updateDefaultInterface(name, index, false, false)
    }

    // ── PlatformInterface: перечисление интерфейсов ─────────────────────────
    override fun getInterfaces(): NetworkInterfaceIterator {
        val list = java.net.NetworkInterface.getNetworkInterfaces().toList().map { ni ->
            io.nekohasekai.libbox.NetworkInterface().apply {
                setName(ni.name)
                setIndex(ni.index)
                runCatching { setMTU(ni.mtu) }
                setFlags(
                    (if (ni.isUp) OsConstants.IFF_UP else 0) or
                    (if (ni.isLoopback) OsConstants.IFF_LOOPBACK else 0) or
                    (if (ni.supportsMulticast()) OsConstants.IFF_MULTICAST else 0))
                setAddresses(StringArrayIterator(
                    ni.interfaceAddresses.mapNotNull { ia ->
                        ia.address.hostAddress?.let { "$it/${ia.networkPrefixLength}" }
                    }))
            }
        }
        return NetworkInterfaceArrayIterator(list)
    }

    // ── PlatformInterface: владелец соединения / пакеты ─────────────────────
    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun findConnectionOwner(
        ipProto: Int, srcIp: String, srcPort: Int, destIp: String, destPort: Int
    ): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) throw UnsupportedOperationException()
        return getSystemService(ConnectivityManager::class.java).getConnectionOwnerUid(
            ipProto, InetSocketAddress(srcIp, srcPort), InetSocketAddress(destIp, destPort))
    }

    override fun packageNameByUid(uid: Int): String =
        packageManager.getPackagesForUid(uid)?.firstOrNull() ?: ""

    override fun uidByPackageName(packageName: String): Int =
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                packageManager.getPackageUid(packageName, PackageManager.PackageInfoFlags.of(0))
            else @Suppress("DEPRECATION") packageManager.getPackageUid(packageName, 0)
        }.getOrDefault(-1)

    // ── PlatformInterface: остальное (минимально) ───────────────────────────
    override fun writeLog(message: String) { android.util.Log.i("libbox", message) }
    override fun clearDNSCache() {}
    override fun readWIFIState(): WIFIState? = null
    override fun systemCertificates(): StringIterator = StringArrayIterator(emptyList())
    override fun localDNSTransport(): LocalDNSTransport? = null
    override fun includeAllNetworks(): Boolean = false
    override fun underNetworkExtension(): Boolean = false
    override fun sendNotification(notification: io.nekohasekai.libbox.Notification) {}

    // ── вспомогательные итераторы для libbox ────────────────────────────────
    private class StringArrayIterator(private val items: List<String>) : StringIterator {
        private var i = 0
        override fun hasNext(): Boolean = i < items.size
        override fun next(): String = items[i++]
        override fun len(): Int = items.size
    }

    private class NetworkInterfaceArrayIterator(
        private val items: List<io.nekohasekai.libbox.NetworkInterface>
    ) : NetworkInterfaceIterator {
        private var i = 0
        override fun hasNext(): Boolean = i < items.size
        override fun next(): io.nekohasekai.libbox.NetworkInterface = items[i++]
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(NOTIF_CH, "VPN", NotificationManager.IMPORTANCE_LOW))
        }
        return NotificationCompat.Builder(this, NOTIF_CH)
            .setContentTitle("LightningMcQueen")
            .setContentText("VPN активен")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .build()
    }
}
