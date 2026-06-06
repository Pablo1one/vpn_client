package lightningmcqueen.proxy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import androidx.core.app.NotificationCompat
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.InetSocketAddress

// vpn-сервис на libbox (sing-box, форк amnezia-box 1.13). В 1.13 движок гоняется через
// CommandServer (startOrReloadService/closeService) + CommandServerHandler, а не BoxService.
// Реализуем PlatformInterface (openTun из TunOptions, монитор) и CommandServerHandler.
class SingBoxVpnService : VpnService(), PlatformInterface, CommandServerHandler {

    companion object {
        const val ACTION_CONNECT    = "lightningmcqueen.proxy.CONNECT"
        const val ACTION_DISCONNECT = "lightningmcqueen.proxy.DISCONNECT"
        const val EXTRA_CONFIG      = "config"
        const val EXTRA_EXCLUDED_APPS = "excluded_apps"
        const val EXTRA_PROTOCOL    = "protocol"
        const val EXTRA_COUNTRY     = "country"

        private const val NOTIF_CH = "vpn_service"
        private const val NOTIF_ID = 1

        var statusListener: ((String) -> Unit)? = null
        // последний статус — чтобы при пересоздании активити (тап по уведомлению)
        // заново подписавшийся UI сразу узнал, что коннект жив (иначе кнопка серая)
        @Volatile var currentStatus: String = "disconnected"
        @Volatile private var setupDone = false
    }

    private var commandServer: CommandServer? = null
    private var tunInterface: ParcelFileDescriptor? = null
    private var defaultNetwork: Network? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var stopping = false

    // данные для уведомления-виджета (протокол + флаг страны) и живой статус скорости
    private var notifProtocol = ""
    private var notifCountry = ""        // ISO-код страны (для эмодзи-флага)
    private var statusClient: CommandClient? = null
    @Volatile private var connectedNow = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val config = intent.getStringExtra(EXTRA_CONFIG) ?: run {
                    stopSelf(); return START_NOT_STICKY
                }
                notifProtocol = intent.getStringExtra(EXTRA_PROTOCOL) ?: ""
                notifCountry = intent.getStringExtra(EXTRA_COUNTRY) ?: ""
                connectedNow = false
                startForeground(NOTIF_ID, buildNotification(0, 0))
                notifyStatus("connecting")
                Thread {
                    runCatching { startBox(config) }.onFailure {
                        android.util.Log.e("SingBoxVpn", "startBox failed", it)
                        notifyStatus("error: ${it.message}")
                        stopBox()
                    }
                }.start()
            }
            ACTION_DISCONNECT -> {
                // кнопка «Отключить» в шторке — пользовательская остановка: сообщаем
                // Flutter ("userstop"), чтобы он сбросил _userWantsConnected и НЕ реконнектил
                notifyStatus("userstop")
                stopBox()
            }
        }
        return START_STICKY
    }

    // @Synchronized: двухфазный WARP делает два коннекта подряд из разных потоков —
    // без сериализации фаза 2 видит commandServer==null и поднимает второй движок
    // (конфликт на 127.0.0.1:9090). С синхронизацией фаза 2 ждёт фазу 1 → reload.
    @Synchronized
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
        val existing = commandServer
        if (existing != null) {
            // двухфазный WARP / переключение сервера: перезагружаем сервис на том же
            // CommandServer, иначе поднимется второй движок (конфликт tun0/clash_api)
            android.util.Log.i("SingBoxVpn", "reload service, config ${config.length} байт")
            existing.startOrReloadService(config, OverrideOptions())
            connectedNow = true
            updateNotification(0, 0)
            startStatusClient()
            notifyStatus("connected")
            return
        }
        android.util.Log.i("SingBoxVpn", "newCommandServer, config ${config.length} байт")
        val server = Libbox.newCommandServer(this, this)
        server.start()
        android.util.Log.i("SingBoxVpn", "startOrReloadService")
        server.startOrReloadService(config, OverrideOptions())
        commandServer = server
        android.util.Log.i("SingBoxVpn", "started OK")
        connectedNow = true
        updateNotification(0, 0)
        startStatusClient()
        notifyStatus("connected")
    }

    private fun notifyStatus(s: String) {
        currentStatus = s
        statusListener?.invoke(s)
    }

    private fun stopBox() {
        if (stopping) return
        stopping = true
        connectedNow = false
        stopStatusClient()
        runCatching { commandServer?.closeService() }
        runCatching { commandServer?.close() }
        commandServer = null
        runCatching { tunInterface?.close() }
        tunInterface = null
        notifyStatus("disconnected")
        runCatching { stopForeground(STOP_FOREGROUND_REMOVE) }
        stopSelf()
    }

    // ── status-клиент: живая скорость для уведомления-виджета ────────────────
    // Подключаемся к собственному CommandServer как клиент команды Status — libbox
    // раз в секунду присылает Uplink/Downlink (в т.ч. для AmneziaWG, трафик общий).
    @Synchronized
    private fun startStatusClient() {
        if (statusClient != null) return
        runCatching {
            val opts = CommandClientOptions()
            opts.addCommand(Libbox.CommandStatus)
            opts.addCommand(Libbox.CommandLog) // логи движка → logcat (тег boxlog) для диагностики
            opts.statusInterval = 1_000_000_000L // 1 c в наносекундах
            val client = Libbox.newCommandClient(StatusHandler(), opts)
            client.connect()
            statusClient = client
        }.onFailure { android.util.Log.e("SingBoxVpn", "status client failed", it) }
    }

    @Synchronized
    private fun stopStatusClient() {
        runCatching { statusClient?.disconnect() }
        statusClient = null
    }

    // libbox дёргает эти колбэки из своего потока; нам нужен только writeStatus
    // (скорость для уведомления), остальное интерфейс требует реализовать пустыми.
    private inner class StatusHandler : CommandClientHandler {
        override fun connected() {}
        override fun disconnected(message: String?) {}
        override fun clearLogs() {}
        override fun writeLogs(messageList: io.nekohasekai.libbox.LogIterator?) {
            if (messageList == null) return
            while (messageList.hasNext()) {
                runCatching { android.util.Log.i("boxlog", messageList.next().message) }
            }
        }
        override fun writeStatus(message: StatusMessage?) {
            if (message == null || !connectedNow) return
            updateNotification(message.downlink, message.uplink)
        }
        override fun writeGroups(message: OutboundGroupIterator?) {}
        override fun writeConnectionEvents(message: io.nekohasekai.libbox.ConnectionEvents?) {}
        override fun initializeClashMode(modeList: StringIterator?, currentMode: String?) {}
        override fun updateClashMode(newMode: String?) {}
        override fun setDefaultLogLevel(level: Int) {}
    }

    override fun onDestroy() { stopBox(); super.onDestroy() }
    override fun onRevoke() { stopBox() }

    // ── CommandServerHandler ────────────────────────────────────────────────
    override fun serviceReload() {}
    override fun serviceStop() { stopBox() }
    override fun getSystemProxyStatus(): SystemProxyStatus =
        SystemProxyStatus().apply { available = false; enabled = false }
    override fun setSystemProxyEnabled(isEnabled: Boolean) {}
    override fun writeDebugMessage(message: String) { android.util.Log.d("libbox", message) }

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
        android.util.Log.i("SingBoxVpn", "openTun: establish()")
        val pfd = builder.establish() ?: throw IllegalStateException("VpnService.establish() вернул null")
        tunInterface = pfd
        android.util.Log.i("SingBoxVpn", "openTun: fd=${pfd.fd}")
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
        // сразу сообщить текущий дефолт: AWG-endpoint биндит UDP-сокет синхронно на
        // старте и не может ждать асинхронного onAvailable (иначе падает с
        // "create ipv4 connection: no available network interface")
        runCatching { cm.activeNetwork?.let { updateDefault(it, listener) } }
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
                        // у IPv6 link-local hostAddress содержит зону (%dummy0) —
                        // sing-box её в префиксе не принимает (netip.ParsePrefix паникует), срезаем
                        ia.address.hostAddress?.substringBefore('%')?.let { "$it/${ia.networkPrefixLength}" }
                    }))
            }
        }
        return NetworkInterfaceArrayIterator(list)
    }

    // ── PlatformInterface: владелец соединения (в 1.13 возвращает объект) ────
    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun findConnectionOwner(
        ipProto: Int, srcIp: String, srcPort: Int, destIp: String, destPort: Int
    ): ConnectionOwner {
        val owner = ConnectionOwner()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            runCatching {
                val uid = getSystemService(ConnectivityManager::class.java).getConnectionOwnerUid(
                    ipProto, InetSocketAddress(srcIp, srcPort), InetSocketAddress(destIp, destPort))
                owner.userId = uid
                packageManager.getPackagesForUid(uid)?.let {
                    // геттер androidPackageNames() без get-префикса → property-синтаксис не работает
                    owner.setAndroidPackageNames(StringArrayIterator(it.toList()))
                }
            }
        }
        return owner
    }

    // ── PlatformInterface: остальное (минимально) ───────────────────────────
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

    private fun updateNotification(down: Long, up: Long) {
        if (stopping) return
        runCatching {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIF_ID, buildNotification(down, up))
        }
    }

    private fun buildNotification(down: Long, up: Long): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(NOTIF_CH, "VPN", NotificationManager.IMPORTANCE_LOW))
        }

        val flag = flagEmoji(notifCountry)
        val proto = if (notifProtocol.isNotEmpty()) notifProtocol else "VPN"
        val title = if (flag.isNotEmpty()) "$flag  $proto" else proto
        val text = if (connectedNow)
            "↓ ${fmtSpeed(down)}    ↑ ${fmtSpeed(up)}"
        else
            "Подключение…"

        // кнопка «Отключить» прямо в шторке → ACTION_DISCONNECT в сервис
        val stopIntent = Intent(this, SingBoxVpnService::class.java)
            .setAction(ACTION_DISCONNECT)
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_IMMUTABLE else 0
        val stopPi = PendingIntent.getService(this, 0, stopIntent, piFlags)

        // тап по уведомлению → открыть приложение
        val openPi = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 1, it, piFlags)
        }

        return NotificationCompat.Builder(this, NOTIF_CH)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(0xFFE10600.toInt()) // фирменный красный McQueen — подложка иконки
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .apply { openPi?.let { setContentIntent(it) } }
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Отключить", stopPi)
            .build()
    }

    // ISO-код страны (RU/NL/…) → эмодзи-флаг через regional indicator symbols
    private fun flagEmoji(cc: String): String {
        if (cc.length != 2 || !cc.all { it.isLetter() }) return ""
        val base = 0x1F1E6
        val a = base + (Character.toUpperCase(cc[0]) - 'A')
        val b = base + (Character.toUpperCase(cc[1]) - 'A')
        return String(Character.toChars(a)) + String(Character.toChars(b))
    }

    private fun fmtSpeed(bytesPerSec: Long): String {
        val b = bytesPerSec.toDouble()
        return when {
            b >= 1024 * 1024 -> String.format("%.1f МБ/с", b / 1024 / 1024)
            b >= 1024        -> String.format("%.0f КБ/с", b / 1024)
            else             -> "$bytesPerSec Б/с"
        }
    }
}
