package lol.silentgate.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
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
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.RoutePrefix
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import lol.silentgate.MainActivity
import lol.silentgate.R
import java.net.Inet6Address
import java.net.InetSocketAddress
import java.net.InterfaceAddress
import java.net.NetworkInterface as JavaNetworkInterface

/**
 * VPN-сервис SilentGate: поднимает туннель через `libbox` (sing-box) и отдаёт
 * ему файловый дескриптор от [VpnService].
 *
 * ## Кто кем командует
 *
 * Дескриптор передаётся НЕ «сверху вниз»: ядро само зовёт [openTun], а мы по
 * пришедшим [TunOptions] строим `VpnService.Builder`, вызываем `establish()` и
 * возвращаем fd. Это инверсия управления, и другого поддерживаемого пути у
 * libbox нет — так устроен и официальный клиент sing-box.
 *
 * ## Порядок работы (API sing-box 1.13, выяснено по исходникам)
 *
 * `Libbox.setup` → `newCommandServer` → `start()` → `startOrReloadService(json)`.
 * Классов `BoxService`/`newService` из старых примеров в 1.13 уже нет.
 *
 * Подробности и рецепт сборки ядер — `tools/build-android-cores.md`.
 */
class SilentGateVpnService : VpnService(), PlatformInterface, CommandServerHandler {

    companion object {
        const val ACTION_START = "lol.silentgate.action.START"
        const val ACTION_STOP = "lol.silentgate.action.STOP"
        const val EXTRA_CONFIG = "config"

        private const val CHANNEL_ID = "silentgate_vpn"
        private const val NOTIFICATION_ID = 1

        /** Состояние для Dart-стороны; сервис живёт дольше UI. */
        @Volatile
        var running: Boolean = false
            private set

        @Volatile
        var lastError: String? = null
            private set

        /** Слушатель состояния — им выступает мост к Flutter. */
        @Volatile
        var stateListener: ((running: Boolean, error: String?) -> Unit)? = null

        private fun notifyState() {
            stateListener?.invoke(running, lastError)
        }
    }

    private var commandServer: CommandServer? = null
    private var coreLog: java.io.File? = null
    private var tunFd: ParcelFileDescriptor? = null
    private var interfaceListener: InterfaceUpdateListener? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    private val connectivity: ConnectivityManager
        get() = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopTunnel()
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                val config = intent?.getStringExtra(EXTRA_CONFIG)
                if (config.isNullOrBlank()) {
                    lastError = "Пустой конфиг"
                    notifyState()
                    stopSelf()
                    return START_NOT_STICKY
                }
                startTunnel(config)
            }
        }
        return START_STICKY
    }

    private fun startTunnel(configJson: String) {
        try {
            // Нотификация ДО подъёма ядра: foreground-сервис обязан её показать
            // сразу, иначе система убьёт его за нарушение контракта.
            startForeground(NOTIFICATION_ID, buildNotification(getString(R.string.vpn_connecting)))

            // Весь вывод ядра и, главное, паники Go уходят в файл: без этого
            // причина падения не видна нигде — ни в логах приложения, ни на
            // экране. Файл читает экран «Логи».
            coreLog = filesDir.resolve("singbox.log")
            runCatching { Libbox.redirectStderr(coreLog!!.absolutePath) }

            Libbox.setup(SetupOptions().apply {
                basePath = filesDir.absolutePath
                workingPath = filesDir.resolve("sing-box").also { it.mkdirs() }.absolutePath
                tempPath = cacheDir.absolutePath
                // На Android нужен обход особенности стека Go — иначе часть
                // соединений не поднимается.
                fixAndroidStack = true
            })

            val server = CommandServer(this, this)
            server.start()
            // ⚠️ Вторым аргументом НЕЛЬЗЯ передавать null: Go-сторона
            // разыменовывает указатель сразу (`options.AutoRedirect` в
            // CommandServer.StartOrReloadService), и nil даёт панику Go —
            // то есть SIGSEGV и смерть процесса, а не Java-исключение.
            // Именно так выглядел «VPN вылетает без следа в логах».
            //
            // Сами списки пакетов оставляем пустыми: единственный источник
            // правды — конфиг (include_package/exclude_package в TUN-инбаунде),
            // и дублировать их здесь значило бы иметь два несогласованных места.
            server.startOrReloadService(configJson, OverrideOptions())
            commandServer = server

            running = true
            lastError = null
            notifyState()
            updateNotification(getString(R.string.vpn_connected))
        } catch (e: Throwable) {
            // Имя класса обязательно: у UnsatisfiedLinkError (не загрузилась
            // libbox.so) и у ошибок конфига message бывает пустым, и без типа
            // сообщение выглядело бы как «ядро не запустилось» без причины.
            val cause = generateSequence(e) { it.cause }.last()
            lastError = buildString {
                append(e::class.java.simpleName)
                e.message?.takeIf { it.isNotBlank() }?.let { append(": ").append(it) }
                if (cause !== e) {
                    append(" <- ").append(cause::class.java.simpleName)
                    cause.message?.takeIf { it.isNotBlank() }?.let { append(": ").append(it) }
                }
                tailOfCoreLog()?.let { append("\n\n").append(it) }
            }
            running = false
            notifyState()
            stopTunnel()
            stopSelf()
        }
    }

    /// Хвост лога ядра — в него попадают и паники Go, перехваченные
    /// redirectStderr.
    private fun tailOfCoreLog(): String? {
        val f = coreLog ?: return null
        return runCatching {
            val lines = f.readLines()
            if (lines.isEmpty()) null
            else lines.takeLast(12).joinToString("\n")
        }.getOrNull()
    }

    private fun stopTunnel() {
        try {
            commandServer?.closeService()
        } catch (_: Throwable) {
        }
        try {
            commandServer?.close()
        } catch (_: Throwable) {
        }
        commandServer = null

        networkCallback?.let {
            try {
                connectivity.unregisterNetworkCallback(it)
            } catch (_: Throwable) {
            }
        }
        networkCallback = null
        interfaceListener = null

        try {
            tunFd?.close()
        } catch (_: Throwable) {
        }
        tunFd = null

        running = false
        notifyState()
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }

    /**
     * Система или пользователь отобрали туннель (включили другой VPN, выключили
     * в шторке). Кода-аналога на Windows нет вовсе — это обязательный путь.
     */
    override fun onRevoke() {
        lastError = getString(R.string.vpn_revoked)
        stopTunnel()
        stopSelf()
        super.onRevoke()
    }

    // ── PlatformInterface: сердце интеграции ──────────────────────────────────

    /**
     * Ядро просит туннель. Строим [Builder] по [TunOptions] и отдаём fd.
     *
     * Каждый `addAllowedApplication`/`addDisallowedApplication` обёрнут в
     * try/catch: пакет мог быть удалён после того, как правило создали, и без
     * защиты VPN просто перестал бы подключаться.
     */
    override fun openTun(options: TunOptions): Int {
        val builder = Builder()
            .setSession("SilentGate")
            .setMtu(options.mtu)

        options.inet4Address.forEach { builder.addAddress(it.address(), it.prefix()) }
        options.inet6Address.forEach { builder.addAddress(it.address(), it.prefix()) }

        if (options.autoRoute) {
            options.inet4RouteAddress.let { routes ->
                if (routes.hasNext()) {
                    routes.forEach { builder.addRoute(it.address(), it.prefix()) }
                } else {
                    builder.addRoute("0.0.0.0", 0)
                }
            }
            options.inet6RouteAddress.let { routes ->
                if (routes.hasNext()) {
                    routes.forEach { builder.addRoute(it.address(), it.prefix()) }
                } else if (options.inet6Address.hasNext()) {
                    builder.addRoute("::", 0)
                }
            }
            // Исключения из маршрутов доступны только с API 33; ниже ядро само
            // раскладывает их в набор покрывающих префиксов.
            if (Build.VERSION.SDK_INT >= 33) {
                options.inet4RouteExcludeAddress.forEach {
                    builder.excludeRoute(android.net.IpPrefix(java.net.InetAddress.getByName(it.address()), it.prefix()))
                }
                options.inet6RouteExcludeAddress.forEach {
                    builder.excludeRoute(android.net.IpPrefix(java.net.InetAddress.getByName(it.address()), it.prefix()))
                }
            }
        }

        try {
            builder.addDnsServer(options.dnsServerAddress.value)
        } catch (_: Throwable) {
            // Без DNS-сервера приложения пойдут в системный резолвер мимо
            // туннеля — ровно та утечка, которую чинили на Windows.
        }

        // include и exclude НЕЛЬЗЯ смешивать: наличие хотя бы одного allowed
        // уводит всё остальное мимо VPN.
        var perAppApplied = false
        options.includePackage.forEach { pkg ->
            try {
                builder.addAllowedApplication(pkg)
                perAppApplied = true
            } catch (_: PackageManager.NameNotFoundException) {
            }
        }
        if (!perAppApplied) {
            options.excludePackage.forEach { pkg ->
                try {
                    builder.addDisallowedApplication(pkg)
                } catch (_: PackageManager.NameNotFoundException) {
                }
            }
        }
        // Себя из туннеля исключаем всегда: иначе пинг, загрузка подписки и
        // сокеты ядра пойдут в собственный туннель — петля и ложные цифры.
        try {
            builder.addDisallowedApplication(packageName)
        } catch (_: PackageManager.NameNotFoundException) {
        }

        if (Build.VERSION.SDK_INT >= 29) builder.setMetered(false)

        val pfd = builder.establish() ?: throw IllegalStateException("establish() вернул null")
        tunFd = pfd
        return pfd.fd
    }

    /** `protect(fd)` — анти-петля для сокетов ядра. */
    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    /** С Android 10 `/proc` закрыт — матчинг по процессам только через систему. */
    override fun useProcFS(): Boolean = false

    /**
     * Владелец соединения по uid. Без этого НЕ работают `package_name`-правила,
     * то есть блокировка приложений. Доступно с API 29.
     */
    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        if (Build.VERSION.SDK_INT < 29) throw UnsupportedOperationException("нужен Android 10+")
        val uid = connectivity.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
        if (uid == -1) throw IllegalStateException("владелец соединения не найден")
        val owner = ConnectionOwner()
        owner.userId = uid
        // Список пакетов, а не один: у приложений с общим UID их несколько —
        // ядро само выберет совпадение с правилом.
        val packages = packageManager.getPackagesForUid(uid)?.toList().orEmpty()
        owner.setAndroidPackageNames(StringArray(packages))
        return owner
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val active = connectivity.activeNetwork
        val activeCaps = active?.let { connectivity.getNetworkCapabilities(it) }
        // На Android 11+ перечисление интерфейсов ограничено и может вернуть
        // null; необработанный NPE здесь уходит через JNI в Go и роняет процесс.
        val ifaces = runCatching { JavaNetworkInterface.getNetworkInterfaces() }
            .getOrNull() ?: return InterfaceArray(emptyList())
        val list = ifaces.toList().map { iface ->
            LibboxNetworkInterface().apply {
                name = iface.name
                index = iface.index
                mtu = runCatching { iface.mtu }.getOrDefault(1500)
                addresses = StringArray(iface.interfaceAddresses.map { it.cidr() })
                flags = 0
                type = when {
                    activeCaps == null -> Libbox.InterfaceTypeOther
                    activeCaps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                    activeCaps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                    activeCaps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                    else -> Libbox.InterfaceTypeOther
                }
                metered = activeCaps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)?.not() ?: false
                dnsServer = StringArray(emptyList())
            }
        }
        return InterfaceArray(list)
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        interfaceListener = listener
        // NOT_VPN обязателен: без него подъём СВОЕГО туннеля прилетает как
        // «сменилась сеть» и запускает вечный цикл переподключений — грабли,
        // которые на Windows чинили трижды.
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = update(network)
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = update(network)
            override fun onLost(network: Network) {
                listener.updateDefaultInterface("", -1, false, false)
            }

            private fun update(network: Network) {
                val caps = connectivity.getNetworkCapabilities(network) ?: return
                val link = connectivity.getLinkProperties(network) ?: return
                val name = link.interfaceName ?: return
                val index = runCatching { JavaNetworkInterface.getByName(name)?.index ?: -1 }.getOrDefault(-1)
                listener.updateDefaultInterface(
                    name,
                    index,
                    !caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                        !caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET),
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED).not(),
                )
            }
        }
        networkCallback = cb
        connectivity.registerNetworkCallback(request, cb)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        networkCallback?.let {
            runCatching { connectivity.unregisterNetworkCallback(it) }
        }
        networkCallback = null
        interfaceListener = null
    }

    override fun underNetworkExtension(): Boolean = false
    override fun includeAllNetworks(): Boolean = false
    override fun clearDNSCache() {}
    // Пустое состояние вместо null: значение уходит в Go через JNI, и null там
    // разыменовывается без проверки.
    override fun readWIFIState(): WIFIState = WIFIState("", "")
    override fun systemCertificates(): StringIterator = StringArray(emptyList())
    override fun localDNSTransport(): LocalDNSTransport? = null
    override fun sendNotification(notification: io.nekohasekai.libbox.Notification) {}

    // ── CommandServerHandler ──────────────────────────────────────────────────

    override fun serviceStop() {
        stopTunnel()
        stopSelf()
    }

    override fun serviceReload() {}
    override fun getSystemProxyStatus(): SystemProxyStatus = SystemProxyStatus().apply {
        available = false
        enabled = false
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) {}
    override fun writeDebugMessage(message: String) {}

    // ── Нотификация ───────────────────────────────────────────────────────────

    private fun buildNotification(text: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, getString(R.string.vpn_channel_name), NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, SilentGateVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_vpn)
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, getString(R.string.vpn_disconnect), stop).build())
            .build()
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }
}

// ── Мелкие адаптеры между Java-коллекциями и итераторами libbox ──────────────

private class StringArray(private val items: List<String>) : StringIterator {
    private var i = 0
    override fun hasNext() = i < items.size
    override fun next() = items[i++]
    override fun len() = items.size
}

private class InterfaceArray(private val items: List<LibboxNetworkInterface>) : NetworkInterfaceIterator {
    private var i = 0
    override fun hasNext() = i < items.size
    override fun next() = items[i++]
}

private fun InterfaceAddress.cidr(): String {
    val addr = address.hostAddress ?: ""
    return "$addr/$networkPrefixLength"
}

private inline fun io.nekohasekai.libbox.RoutePrefixIterator.forEach(action: (RoutePrefix) -> Unit) {
    while (hasNext()) action(next())
}

private inline fun StringIterator.forEach(action: (String) -> Unit) {
    while (hasNext()) action(next())
}
