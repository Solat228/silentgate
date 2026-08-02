package lol.silentgate

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.Manifest
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import lol.silentgate.platform.PlatformChannels
import lol.silentgate.vpn.SilentGateVpnService

/**
 * Единственная Activity приложения плюс мост к VPN-сервису.
 *
 * ⚠️ По решению 4а (`docs/platforms/ANDROID.md`) Activity обязана
 * переиспользовать КЭШИРОВАННЫЙ `FlutterEngine`, а не создавать свой: иначе
 * появится второй Dart-изолят, а с ним гонка записи в хранилища и смерть
 * автопереподключения при свайпе UI. Сейчас изолят один (его создаёт Flutter),
 * кэширование включается вместе с работой сервиса при закрытом интерфейсе.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "lol.silentgate/vpn"
        private const val LINKS_CHANNEL = "lol.silentgate/links"
        private const val EVENT_CHANNEL = "lol.silentgate/vpn_events"
        private const val REQ_PREPARE = 1001
        private const val REQ_NOTIFICATIONS = 1002

        /// Схемы, которые приложение понимает. Держать согласованными с
        /// intent-фильтрами манифеста и с `ShareLinkParser` на стороне Dart:
        /// список нужен, чтобы выудить ссылку из ТЕКСТА, присланного через
        /// «Поделиться», — там вокруг неё обычно есть слова.
        private val SCHEMES = listOf(
            "silentgate", "vless", "vmess", "trojan", "ss", "hysteria2", "hy2",
        )
    }

    private var events: EventChannel.EventSink? = null

    /** Канал входящих ссылок silentgate:// / vless:// и прочих схем. */
    private var links: MethodChannel? = null

    /**
     * Ссылка, пришедшая до того, как Dart-сторона успела подписаться.
     *
     * Холодный старт по ссылке — самый частый случай (человек нажал ссылку в
     * Telegram, приложение ещё не запущено), и именно в нём канал появляется
     * ПОЗЖЕ интента. Без этой очереди первая ссылка терялась бы, а
     * пользователь видел бы пустой экран импорта.
     */
    private var pendingLink: String? = null

    /** Конфиги, ждущие согласия пользователя на VPN. */
    private var pendingConfig: String? = null
    private var pendingXrayConfig: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        links = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LINKS_CHANNEL)
            .also { ch ->
                ch.setMethodCallHandler { call, result ->
                    when (call.method) {
                        // Dart подписался и забирает ссылку холодного старта.
                        "consumeInitial" -> {
                            result.success(pendingLink)
                            pendingLink = null
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        ensureNotificationPermission()

        // Ссылка, с которой приложение запустили.
        //
        // ⚠️ ТОЛЬКО ПРИ НАСТОЯЩЕМ ЗАПУСКЕ ПО ССЫЛКЕ, НЕ ПРИ ВОЗВРАТЕ ИЗ НЕДАВНИХ.
        //
        // Задача, созданная VIEW-интентом, хранит его как baseIntent
        // (launchMode=singleTask), и система пересоздаёт Activity С ТЕМ ЖЕ
        // интентом после смерти процесса. Без проверки флага человек, однажды
        // запустивший приложение ссылкой `silentgate://toggle`, через час
        // открывал его из недавних — и туннель ВЫКЛЮЧАЛСЯ сам собой. Для
        // `import?url=` это был ещё и повторный сетевой импорт при каждом
        // восстановлении задачи.
        val fromHistory =
            (intent?.flags ?: 0) and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        if (!fromHistory) {
            linkFrom(intent)?.let { pendingLink = it }
            // Интент отработан: гасим ссылку в задаче, чтобы следующее
            // пересоздание Activity не подобрало её снова.
            intent?.data = null
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // prepare() возвращает Intent, если согласия ещё нет.
                    "isPrepared" -> result.success(VpnService.prepare(this) == null)

                    "start" -> {
                        val config = call.argument<String>("config")
                        if (config.isNullOrBlank()) {
                            result.error("empty_config", "Пустой конфиг", null)
                        } else {
                            // Второй конфиг есть только у панельных профилей
                            // «Авто»: их поднимает Xray, а туннель заворачивает
                            // трафик в его локальный SOCKS.
                            startWithConsent(
                                config, call.argument<String>("xray_config"), result)
                        }
                    }

                    "stop" -> {
                        startService(
                            Intent(this, SilentGateVpnService::class.java)
                                .setAction(SilentGateVpnService.ACTION_STOP)
                        )
                        result.success(null)
                    }

                    "isRunning" -> result.success(SilentGateVpnService.running)

                    // Kill switch держит трафик: сказать об этом в шторке.
                    // Приложение при этом обычно закрыто — другого способа
                    // объяснить пропавший интернет у нас нет.
                    "showBlocked" -> {
                        SilentGateVpnService.instance?.showBlocked()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }

        // Сведения об устройстве: без этого обработчика Dart уходил в
        // запасные значения, и в отчёте поддержки стояли «unknown».
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
                PlatformChannels.DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                PlatformChannels.handleDevice(applicationContext, call.method, result)
            }

        // Открытие ссылок (Telegram-поддержка, страница обновления). Без него
        // кнопки перехода в поддержку просто ничего не делали.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
                PlatformChannels.LAUNCHER_CHANNEL)
            .setMethodCallHandler { call, result ->
                PlatformChannels.handleLauncher(
                    this, call.method, call.argument<String>("url"), result)
            }

        // Каталог установленных приложений и их иконки. Без него раздельное
        // туннелирование на Android недоступно целиком: правило задаётся именем
        // пакета, а взять его пользователю было неоткуда — «выбрать файл», как
        // на Windows, здесь невозможно.
        //
        // Список строится тяжело (тысяча пакетов + чтение меток), поэтому
        // выполняем НЕ в главном потоке: иначе экран правил открывался бы с
        // заметной задержкой, а на слабом устройстве ловил ANR.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
                PlatformChannels.APPS_CHANNEL)
            .setMethodCallHandler { call, result ->
                val arg = call.argument<String>("package")
                Thread {
                    PlatformChannels.handleApps(
                        applicationContext, call.method, arg,
                        MainThreadResult(this, result),
                    )
                }.start()
            }

        // Пинг сервера отдельным экземпляром Xray. Работает и при поднятом
        // туннеле: LibXray.ping создаёт СВОЙ core.New и гасит его в defer, не
        // трогая глобальный инстанс. Уводим в фоновый поток — замер идёт
        // секундами и заморозил бы интерфейс.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
                PlatformChannels.PROBE_CHANNEL)
            .setMethodCallHandler { call, result ->
                val cfg = call.argument<String>("configPath")
                val timeout = call.argument<Int>("timeout") ?: 5
                val url = call.argument<String>("url")
                val proxy = call.argument<String>("proxy")
                Thread {
                    PlatformChannels.handleProbe(
                        call.method, cfg, timeout, url, proxy,
                        MainThreadResult(this, result),
                    )
                }.start()
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    events = sink
                    SilentGateVpnService.stateListener = { running, error, byUser ->
                        runOnUiThread {
                            events?.success(
                                mapOf(
                                    "running" to running,
                                    "error" to error,
                                    // Отличает «нажали Отключить в шторке» от
                                    // «ядро упало»: без этого Dart уходил в
                                    // автопереподключение и включал VPN обратно.
                                    "byUser" to byUser,
                                )
                            )
                        }
                    }
                    // Сразу отдаём текущее состояние: интерфейс мог быть
                    // перезапущен при живом туннеле.
                    sink?.success(
                        mapOf(
                            "running" to SilentGateVpnService.running,
                            "error" to SilentGateVpnService.lastError,
                            "byUser" to SilentGateVpnService.stoppedByUser,
                        )
                    )
                }

                override fun onCancel(arguments: Any?) {
                    SilentGateVpnService.stateListener = null
                    events = null
                }
            })
    }

    /**
     * Согласие на VPN спрашивается в момент первого подключения, а не на
     * старте приложения — так же, как на Windows UAC просят только при
     * подъёме туннеля.
     */
    private fun startWithConsent(
        config: String,
        xrayConfig: String?,
        result: MethodChannel.Result,
    ) {
        val consent = VpnService.prepare(this)
        if (consent != null) {
            pendingConfig = config
            pendingXrayConfig = xrayConfig
            pendingResult = result
            startActivityForResult(consent, REQ_PREPARE)
            return
        }
        launchService(config, xrayConfig)
        result.success(null)
    }

    private fun launchService(config: String, xrayConfig: String?) {
        val intent = Intent(this, SilentGateVpnService::class.java)
            .setAction(SilentGateVpnService.ACTION_START)
            .putExtra(SilentGateVpnService.EXTRA_CONFIG, config)
            .putExtra(SilentGateVpnService.EXTRA_XRAY_CONFIG, xrayConfig)
        if (Build.VERSION.SDK_INT >= 26) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    @Deprecated("совместимость с FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PREPARE) return

        val config = pendingConfig
        val xrayConfig = pendingXrayConfig
        val result = pendingResult
        pendingConfig = null
        pendingXrayConfig = null
        pendingResult = null

        if (resultCode == Activity.RESULT_OK && config != null) {
            launchService(config, xrayConfig)
            result?.success(null)
        } else {
            // Отказ от согласия — отдельный путь ошибки, которого нет на Windows.
            result?.error("consent_denied", "Пользователь не разрешил VPN", null)
        }
    }
    /**
     * Приложение уже живо, пришла новая ссылка.
     *
     * ⚠️ `setIntent` обязателен: без него `getIntent()` продолжает отдавать
     * интент запуска, и следующая проверка возьмёт устаревшую ссылку.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val url = linkFrom(intent) ?: return
        // Канал есть — отдаём сразу; нет (движок ещё поднимается) — придержим.
        if (links == null) pendingLink = url else links?.invokeMethod("link", url)
    }

    /**
     * Ссылка из интента — из адреса ИЛИ из текста «Поделиться».
     *
     * ⚠️ Манифест объявляет `ACTION_SEND` + `text/plain`, поэтому SilentGate
     * появляется в системном меню «Поделиться» — а читался только
     * `intent.dataString`, которого у `ACTION_SEND` нет: данные лежат в
     * `EXTRA_TEXT`. Пункт меню открывал приложение и не импортировал ничего.
     * Ровно тот класс контролов-обманок, который вычищали с экранов в 1.0.3.
     *
     * Из присланного текста берём первую строку, похожую на ссылку: делятся
     * обычно не голым URL, а сообщением вокруг него.
     */
    private fun linkFrom(intent: Intent?): String? {
        intent?.dataString?.let { return it }
        val text = intent?.getStringExtra(Intent.EXTRA_TEXT) ?: return null
        return text.split(Regex("""\s+""")).firstOrNull { candidate ->
            SCHEMES.any { candidate.startsWith("$it://", ignoreCase = true) }
        }
    }


    /**
     * ⚠️ БЕЗ ЭТОГО НА ANDROID 13+ УВЕДОМЛЕНИЯ СЕРВИСА НЕТ ВООБЩЕ.
     *
     * `POST_NOTIFICATIONS` объявлено в манифесте, но с API 33 оно выдаётся
     * только по запросу в рантайме, а запроса не было нигде — ни в Kotlin, ни
     * в Dart. Сервис при этом стартует и туннель работает, а пользователь
     * теряет и постоянную индикацию «VPN включён», и кнопку «Отключить» —
     * единственный способ снять туннель при закрытом окне приложения.
     *
     * Живой прогон шёл на Android 11, где ограничения нет, — поэтому дефект и
     * не всплыл.
     *
     * Спрашиваем ОДИН раз при старте и молча: отказ ничего не ломает, туннель
     * поднимается всё равно, просто без уведомления. Просить повторно и
     * объяснять — хуже: разрешение не критично для работы.
     */
    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) return
        runCatching {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATIONS)
        }
    }

}


/**
 * Обёртка, возвращающая ответ канала в главный поток.
 *
 * `MethodChannel.Result` обязан вызываться на главном потоке, а тяжёлые вызовы
 * (перечисление пакетов, отрисовка иконок) мы уводим в фоновый — иначе экран
 * правил открывается с задержкой, а на слабом устройстве это ANR.
 */
private class MainThreadResult(
    private val activity: Activity,
    private val inner: MethodChannel.Result,
) : MethodChannel.Result {
    override fun success(value: Any?) = activity.runOnUiThread { inner.success(value) }

    override fun error(code: String, message: String?, details: Any?) =
        activity.runOnUiThread { inner.error(code, message, details) }

    override fun notImplemented() = activity.runOnUiThread { inner.notImplemented() }
}
