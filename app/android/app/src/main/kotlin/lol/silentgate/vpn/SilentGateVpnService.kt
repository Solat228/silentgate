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
import lol.silentgate.cores.libbox.CommandServer
import lol.silentgate.cores.libbox.CommandServerHandler
import lol.silentgate.cores.libbox.ConnectionOwner
import lol.silentgate.cores.libbox.InterfaceUpdateListener
import lol.silentgate.cores.libbox.Libbox
import lol.silentgate.cores.libbox.LocalDNSTransport
import lol.silentgate.cores.libbox.NetworkInterface as LibboxNetworkInterface
import lol.silentgate.cores.libbox.NetworkInterfaceIterator
import lol.silentgate.cores.libbox.OverrideOptions
import lol.silentgate.cores.libbox.PlatformInterface
import lol.silentgate.cores.libbox.RoutePrefix
import lol.silentgate.cores.libbox.SetupOptions
import lol.silentgate.cores.libbox.StringIterator
import lol.silentgate.cores.libbox.SystemProxyStatus
import lol.silentgate.cores.libbox.TunOptions
import lol.silentgate.cores.libbox.WIFIState
import lol.silentgate.cores.libXray.DialerController
import lol.silentgate.cores.libXray.LibXray
import org.json.JSONObject
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

        /// Конфиг Xray для панельных профилей «Авто».
        ///
        /// Когда он задан, поднимаются ОБА ядра: Xray держит сам профиль
        /// (balancers/burstObservatory — sing-box такое не разбирает) и слушает
        /// локальный SOCKS, а sing-box делает туннель и заворачивает трафик
        /// туда. Ровно как на Windows.
        const val EXTRA_XRAY_CONFIG = "xray_config"

        private const val PREFS = "silentgate_native"
        private const val PREF_LANG = "language_code"

        private const val CHANNEL_ID = "silentgate_vpn"
        private const val NOTIFICATION_ID = 1

        /** Состояние для Dart-стороны; сервис живёт дольше UI. */
        @Volatile
        var running: Boolean = false
            private set

        @Volatile
        var lastError: String? = null
            private set

        /**
         * ⚠️ ТУННЕЛЬ СНЯТ ПО ПРОСЬБЕ ПОЛЬЗОВАТЕЛЯ, А НЕ УПАЛ САМ.
         *
         * Без этого признака остановка по кнопке «Отключить» в шторке выглядела
         * снаружи ровно как смерть ядра: `running=false`, `error=null` — то же
         * самое, что при внезапном падении. Dart честно шёл в `onCoreDied`, а
         * оттуда — в автопереподключение, включённое по умолчанию. Итог: самый
         * привычный способ выключить VPN (шторка, приложение свёрнуто) включал
         * его обратно через 0,8 с. При выключенном автоповторе вместо этого
         * показывалась ложная ошибка «Ядро остановилось (код 0)».
         *
         * На эмуляторном прогоне дефект не показался: там отключали через
         * `silentgate://disconnect`, то есть по другому пути.
         */
        @Volatile
        var stoppedByUser: Boolean = false
            private set

        /// Живой экземпляр сервиса. Нужен, чтобы Dart мог поменять текст
        /// уведомления, не пересоздавая туннель (kill switch держит трафик, и
        /// перезапуск сервиса ради надписи открыл бы окно утечки).
        @Volatile
        var instance: SilentGateVpnService? = null

        /** Слушатель состояния — им выступает мост к Flutter. */
        @Volatile
        var stateListener: ((running: Boolean, error: String?, byUser: Boolean) -> Unit)? = null

        private fun notifyState() {
            stateListener?.invoke(running, lastError, stoppedByUser)
        }
    }

    /// Подпись под статусом: сервер и трафик. null — показывать нечего.
    private var lastDetail: String? = null

    private var commandServer: CommandServer? = null
    private var coreLog: java.io.File? = null
    private var xrayRunning = false
    private var tunFd: ParcelFileDescriptor? = null
    private var interfaceListener: InterfaceUpdateListener? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    private val connectivity: ConnectivityManager
        get() = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                // Пометить ДО остановки: `stopTunnel` шлёт состояние наружу, и
                // признак должен уехать вместе с ним.
                stoppedByUser = true
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
                startTunnel(config, intent.getStringExtra(EXTRA_XRAY_CONFIG))
            }
        }
        return START_STICKY
    }

    /**
     * Сказать пользователю, что kill switch держит трафик.
     *
     * ⚠️ Без этого пропавший интернет выглядит поломкой, и самое естественное
     * действие человека — выключить VPN, то есть ровно то, от чего защита и
     * оберегала. Уведомление живёт в шторке и видно при закрытом приложении —
     * именно тогда, когда объяснить некому.
     */
    /// Обновить подпись в шторке (сервер + трафик). Зовётся из Dart.
    fun setDetail(detail: String?, status: String?) {
        if (!running) return
        lastDetail = detail?.takeIf { it.isNotBlank() }
        updateNotification(status?.takeIf { it.isNotBlank() }
            ?: strings().getString(R.string.vpn_connected))
    }

    fun showBlocked() {
        if (!running) return
        updateNotification(strings().getString(R.string.vpn_blocked))
    }

    private fun startTunnel(configJson: String, xrayConfigJson: String?) {
        // ⚠️ ПОВТОРНЫЙ start ПОВЕРХ ЖИВОГО СЕРВИСА — это ПЕРЕЗАГРУЗКА, а не
        // второй запуск. Так приходит заглушка kill switch: Dart шлёт `start` с
        // blackhole-конфигом, чтобы туннель ОСТАЛСЯ поднятым, а трафик умирал в
        // reject.
        //
        // Раньше здесь безусловно создавался ВТОРОЙ CommandServer поверх
        // работающего: старый не закрывался (ссылка на него просто затиралась),
        // его clash_api продолжал держать порт, новый бинд падал с «address
        // already in use», исключение уходило в catch — а catch снимает туннель
        // целиком. То есть kill switch делал ровно обратное обещанному: Dart
        // писал в лог «туннель удержан, трафик блокируется», а трафик в этот
        // момент шёл открыто, и цепочка попыток обрывалась.
        if (running && commandServer != null) {
            reloadTunnel(configJson, xrayConfigJson)
            return
        }
        try {
            // Нотификация ДО подъёма ядра: foreground-сервис обязан её показать
            // сразу, иначе система убьёт его за нарушение контракта.
            startForeground(NOTIFICATION_ID, buildNotification(strings().getString(R.string.vpn_connecting)))

            // Весь вывод ядра и, главное, паники Go уходят в файл: без этого
            // причина падения не видна нигде — ни в логах приложения, ни на
            // экране. Файл читает экран «Логи».
            // ⚠️ Каталог "SilentGate" обязателен. Dart-сторона (экран «Логи» и
            // отчёт поддержки) читает getApplicationSupportDirectory()/SilentGate,
            // а писали мы уровнем выше — в filesDir. Из-за этого лог ядра не
            // видели НИ экран логов, НИ отчёт: причина падения существовала на
            // диске, но до пользователя не доходила никогда.
            coreLog = filesDir.resolve("SilentGate")
                .also { it.mkdirs() }
                .resolve("singbox.log")
            runCatching { Libbox.redirectStderr(coreLog!!.absolutePath) }

            Libbox.setup(SetupOptions().apply {
                basePath = filesDir.absolutePath
                workingPath = filesDir.resolve("sing-box").also { it.mkdirs() }.absolutePath
                tempPath = cacheDir.absolutePath
                // На Android нужен обход особенности стека Go — иначе часть
                // соединений не поднимается.
                fixAndroidStack = true
            })

            // Панельный профиль «Авто» — это готовый конфиг Xray. Поднимаем
            // его ПЕРЕД туннелем: sing-box сразу начнёт слать трафик в SOCKS,
            // и если Xray там ещё не слушает, первые соединения отвалятся.
            if (!xrayConfigJson.isNullOrBlank()) startXray(xrayConfigJson)

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
            // Новая сессия — признак прошлой остановки сбрасываем, иначе
            // следующее падение ядра выдало бы себя за нажатие пользователя.
            stoppedByUser = false
            notifyState()
            updateNotification(strings().getString(R.string.vpn_connected))
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

    /// Перезагрузка ядра БЕЗ пересоздания сервиса.
    ///
    /// Нотификация, networkCallback и подписка на состояние остаются на месте —
    /// пересоздавать их незачем. Сам tun-интерфейс система заменяет при
    /// повторном `establish()` внутри `openTun`, и делает это без разрыва.
    ///
    /// Xray переподнимается только если конфиг пришёл: заглушка kill switch
    /// присылает один sing-box, и держать при ней живое соединение с VPN-сервером
    /// не нужно.
    private fun reloadTunnel(configJson: String, xrayConfigJson: String?) {
        try {
            stopXray()
            if (!xrayConfigJson.isNullOrBlank()) startXray(xrayConfigJson)
            commandServer?.startOrReloadService(configJson, OverrideOptions())
            running = true
            lastError = null
            // Новая сессия — признак прошлой остановки сбрасываем, иначе
            // следующее падение ядра выдало бы себя за нажатие пользователя.
            stoppedByUser = false
            notifyState()
        } catch (e: Throwable) {
            // Неизвестное состояние опаснее честного отказа: туннель мог бы
            // остаться жить со СТАРЫМ конфигом, а Dart считал бы, что применён
            // новый.
            val cause = generateSequence(e) { it.cause }.last()
            lastError = buildString {
                append("Перезагрузка ядра: ").append(e::class.java.simpleName)
                e.message?.takeIf { it.isNotBlank() }?.let { append(": ").append(it) }
                if (cause !== e) append(" <- ").append(cause::class.java.simpleName)
                tailOfCoreLog()?.let { append("\n\n").append(it) }
            }
            running = false
            notifyState()
            stopTunnel()
            stopSelf()
        }
    }

    /// Запускает Xray на локальном SOCKS. Единственный вход в libXray —
    /// `invoke(json)`, ответ приходит JSON-ом с полем success.
    private fun startXray(configJson: String) {
        // protect() для сокетов ядра: без него трафик Xray к VPN-серверу
        // вернётся в собственный туннель — петля и мёртвая сеть.
        LibXray.registerDialerController(object : DialerController {
            override fun protectFd(fd: Long): Boolean = protect(fd.toInt())
        })
        val request = JSONObject()
            .put("apiVersion", 1)
            .put("method", "runXrayFromJson")
            .put("payload", JSONObject().put("configJson", configJson))
            .toString()
        val answer = JSONObject(LibXray.invoke(request))
        if (!answer.optBoolean("success", false)) {
            throw IllegalStateException(
                "Xray не запустился: ${answer.optString("error", "без причины")}")
        }
        xrayRunning = true
    }

    private fun stopXray() {
        if (!xrayRunning) return
        xrayRunning = false
        runCatching {
            LibXray.invoke(JSONObject()
                .put("apiVersion", 1)
                .put("method", "stopXray")
                .toString())
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
        stopXray()

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

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        stopTunnel()
        // Снимаем ссылку ТОЛЬКО если она наша: при быстром пересоздании сервиса
        // новый экземпляр успевает записаться раньше, чем умрёт старый, и
        // безусловное обнуление стёрло бы живой.
        if (instance === this) instance = null
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

        // ⚠️ Маршруты ставим ВСЕГДА, не глядя на options.autoRoute.
        //
        // `auto_route` в конфиге означает «ядро само правит таблицу маршрутов
        // ОС» — это про Windows/Linux. На Android таблицей владеет система, и
        // мы намеренно не пишем это поле (ядро 1.13 отвергает его для
        // платформенного туннеля). Значит здесь оно ВСЕГДА false — и вся
        // установка маршрутов молча пропускалась.
        //
        // Что это давало вживую: tun0 поднимался, система показывала VPN
        // CONNECTED, свой uid корректно исключался, — но в таблице оставались
        // только собственные подсети туннеля (172.19.0.0/30 и fdfe:…/126).
        // Дефолтного маршрута не было, поэтому В ТУННЕЛЬ НЕ ШЛО НИЧЕГО:
        // запросы уходили напрямую, мимо VPN, а пользователь видел «Подключено».
        // Поймано живым запуском в эмуляторе (`dumpsys connectivity`).
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

        try {
            builder.addDnsServer(options.dnsServerAddress.value)
        } catch (_: Throwable) {
            // Без DNS-сервера приложения пойдут в системный резолвер мимо
            // туннеля — ровно та утечка, которую чинили на Windows.
        }

        // include и exclude НЕЛЬЗЯ смешивать: наличие хотя бы одного allowed
        // уводит всё остальное мимо VPN.
        var perAppApplied = false
        var includeWanted = false
        options.includePackage.forEach { pkg ->
            // Свой пакет в allowed-список не пускаем: он увёл бы трафик самого
            // приложения в собственный туннель (петля и ложные цифры проб).
            if (pkg == packageName) return@forEach
            includeWanted = true
            try {
                builder.addAllowedApplication(pkg)
                perAppApplied = true
            } catch (_: PackageManager.NameNotFoundException) {
            }
        }
        // ⚠️ Список был задан, но НИ ОДИН пакет не установлен (удалили после
        // создания правила, либо он из другого профиля пользователя).
        // Молча уйти в ветку exclude нельзя: политика перевернётся с «в туннель
        // идут только выбранные» на «в туннель идёт ВСЁ, кроме нас» — причём с
        // DNS всей системы через VPN. Это прямо противоположно тому, что просил
        // пользователь, и заметить подмену нечем.
        if (includeWanted && !perAppApplied) {
            throw IllegalStateException(
                "Выбранные приложения не установлены — режим «только выбранные» применить не к чему"
            )
        }
        if (!perAppApplied) {
            // Себя исключаем ТОЛЬКО в этой ветке. Раньше вызов стоял ниже и
            // выполнялся всегда — а addDisallowedApplication после
            // addAllowedApplication бросает UnsupportedOperationException,
            // который здесь не ловился: исключение уходило наверх, openTun
            // не доходил до establish(), и в режиме «только выбранные»
            // туннель не поднимался вообще.
            //
            // При allowed-списке исключать себя и не нужно: в туннель идут
            // ТОЛЬКО перечисленные приложения, все прочие и так снаружи.
            // excludePackage — итератор libbox, не коллекция: сначала собираем.
            val excludes = LinkedHashSet<String>()
            options.excludePackage.forEach { excludes.add(it) }
            excludes.add(packageName)
            excludes.forEach { pkg ->
                try {
                    builder.addDisallowedApplication(pkg)
                } catch (_: PackageManager.NameNotFoundException) {
                } catch (_: UnsupportedOperationException) {
                }
            }
        }

        if (Build.VERSION.SDK_INT >= 29) builder.setMetered(false)

        val pfd = builder.establish() ?: throw IllegalStateException("establish() вернул null")
        // ⚠️ Прежний дескриптор закрываем ПОСЛЕ establish(), а не до. При
        // перезагрузке ядра (заглушка kill switch) openTun вызывается повторно;
        // систему просят заменить интерфейс, и она делает это без разрыва.
        // Закрыть старый ДО establish() значило бы снять туннель на этот миг —
        // то есть открыть ровно то окно утечки, которое kill switch закрывает.
        // Не закрывать вовсе — оставить дескриптор висеть до смерти процесса.
        val previous = tunFd
        tunFd = pfd
        if (previous !== pfd) runCatching { previous?.close() }
        return pfd.fd
    }

    /** `protect(fd)` — анти-петля для сокетов ядра. */
    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    /// До Android 10 `/proc/net` читается, с Android 10 — закрыт.
    ///
    /// ⚠️ Здесь стояло безусловное `false`, и на Android 7-9 правила приложений
    /// не работали ВООБЩЕ: `getConnectionOwnerUid` появился только в API 29, то
    /// есть `findConnectionOwner` ниже на этих версиях бросает исключение, а
    /// запасного пути через `/proc` мы не разрешали. Владельца соединения
    /// определить было нечем — «Блок» молча пропускал трафик, «Прямо» и
    /// «Туннель» не различались. Это четверть поддерживаемого диапазона версий
    /// (minSdk 24).
    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

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
                // mapNotNull, а не map: непригодная запись отбрасывается, иначе
                // netip.MustParsePrefix на той стороне убьёт процесс.
                addresses = StringArray(iface.interfaceAddresses.mapNotNull { it.cidr() })
                // ⚠️ Здесь стоял `flags = 0`, и это ломало ВЕСЬ исходящий трафик.
                //
                // Поле читает Go как `net.Flags`, где нулевое значение означает
                // «интерфейс административно выключен». sing-box отбирает
                // интерфейсы по флагу up, не находил ни одного и отвечал на
                // каждое соединение:
                //   dial TCP connection: no available network interface
                // Снаружи: туннель поднят, маршруты верные, а наружу не уходит
                // ничего — даже DNS. Поймано живым запуском в эмуляторе, статикой
                // не видно: ошибка появляется только когда ядро реально дозванивается.
                //
                // ⚠️ Биты — СЫРЫЕ линуксовые IFF_*, а НЕ значения Go net.Flags.
                // libbox прогоняет это поле через linkFlags() (копию
                // net.linkFlags), которая сама переводит IFF_* в net.Flags.
                // Отдавать ей уже переведённые значения — значит соврать:
                // совпадает только бит up (0x1), а дальше 4 читается как
                // IFF_DEBUG вместо loopback, 8 — как IFF_LOOPBACK вместо
                // point-to-point (то есть ppp0/rmnet мобильного интернета
                // объявляются петлёй), 16 — как IFF_POINTOPOINT вместо
                // multicast (wlan0 выдаётся за point-to-point).
                // Живой тест этого не поймал: он шёл по wlan0, где случайно
                // совпал единственный бит, который и требовался.
                flags = runCatching {
                    var f = 0
                    if (iface.isUp) f = f or OsConstants.IFF_UP or OsConstants.IFF_RUNNING
                    if (iface.isLoopback) f = f or OsConstants.IFF_LOOPBACK
                    if (iface.isPointToPoint) f = f or OsConstants.IFF_POINTOPOINT
                    if (iface.supportsMulticast()) f = f or OsConstants.IFF_MULTICAST
                    f
                }.getOrDefault(OsConstants.IFF_UP or OsConstants.IFF_RUNNING)
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
    override fun sendNotification(notification: lol.silentgate.cores.libbox.Notification) {}

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

    /**
     * ⚠️ СТРОКИ ШТОРКИ ОБЯЗАНЫ СЛЕДОВАТЬ ЯЗЫКУ ПРИЛОЖЕНИЯ, А НЕ ЯЗЫКУ СИСТЕМЫ.
     *
     * Весь интерфейс переведён на десять языков и выбор языка живёт в настройках
     * приложения. А `getString()` в сервисе берёт локаль СИСТЕМЫ — значит
     * человек, поставивший в приложении русский на англоязычном телефоне,
     * получал бы английское уведомление. Это и есть «выпасть из
     * десятиязычности»: единственное место, которое видно при закрытом
     * приложении, говорило бы не на том языке.
     *
     * Код языка приходит из Dart и ПЕРСИСТИТСЯ: сервис переживает смерть
     * изолята, и в момент обновления уведомления спросить Dart может быть уже
     * не у кого. Пусто — язык системы, как и в самом приложении.
     */
    private fun strings(): Context {
        val code = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(PREF_LANG, "").orEmpty()
        if (code.isBlank()) return this
        return runCatching {
            val cfg = android.content.res.Configuration(resources.configuration)
            cfg.setLocale(java.util.Locale.forLanguageTag(code))
            createConfigurationContext(cfg)
        }.getOrDefault(this)
    }

    private fun buildNotification(text: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val res = strings()
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, res.getString(R.string.vpn_channel_name), NotificationManager.IMPORTANCE_LOW)
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
            // Имя берём из ресурсов, а не литералом: бренд ещё может смениться.
            .setContentTitle(res.getString(R.string.app_name))
            .setContentText(text)
            // Вторая строка — трафик. Раньше в шторке был только статус, и
            // человек, не открывая приложение, не знал ни сколько скачано, ни
            // через какой сервер он сидит.
            .also { b -> lastDetail?.let { b.setSubText(it) } }
            .setSmallIcon(R.drawable.ic_stat_vpn)
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(
                null, res.getString(R.string.vpn_disconnect), stop).build())
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

/// Адрес интерфейса в виде CIDR — БЕЗ зоны IPv6.
///
/// ⚠️ Здесь ядро падало, и вместе с ним всё приложение. `hostAddress` у
/// link-local IPv6 возвращает адрес с зоной (`fe80::ac1d:acff:fe78:b834%dummy0`),
/// а Go разбирает такую строку через `netip.MustParsePrefix`, который на зонах
/// делает panic:
///
///   panic: netip.ParsePrefix("fe80::…%dummy0/64"):
///          IPv6 zones cannot be present in a prefix
///
/// Паника из горутины libbox не ловится ничем на стороне Kotlin — процесс
/// убивается по SIGABRT. Симптом снаружи: нажал «Подключиться», tun0 на
/// мгновение создаётся и тут же исчезает, приложение пропадает с экрана.
/// Link-local IPv6 есть практически на каждом интерфейсе, поэтому VPN не
/// поднимался НИКОГДА. Подтверждено живым запуском в эмуляторе.
/// `null` — запись непригодна и должна быть ОТБРОШЕНА, а не отдана ядру.
///
/// Go разбирает каждый элемент через `netip.MustParsePrefix`, а `Must*` не
/// возвращает ошибку — он паникует, и паника из горутины libbox убивает
/// процесс целиком. Поэтому валидируем здесь, а не надеемся на ту сторону:
/// `hostAddress` бывает `null` (тогда получалась строка «/64»), а
/// `networkPrefixLength` на некоторых интерфейсах приходит 0 или −1.
private fun InterfaceAddress.cidr(): String? {
    val addr = (address.hostAddress ?: return null).substringBefore('%')
    if (addr.isEmpty()) return null
    val prefix = networkPrefixLength.toInt()
    if (prefix < 0 || prefix > 128) return null
    return "$addr/$prefix"
}

private inline fun lol.silentgate.cores.libbox.RoutePrefixIterator.forEach(action: (RoutePrefix) -> Unit) {
    while (hasNext()) action(next())
}

private inline fun StringIterator.forEach(action: (String) -> Unit) {
    while (hasNext()) action(next())
}
