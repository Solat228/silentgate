package lol.silentgate

import android.app.Activity
import android.content.Intent
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
        private const val EVENT_CHANNEL = "lol.silentgate/vpn_events"
        private const val REQ_PREPARE = 1001
    }

    private var events: EventChannel.EventSink? = null

    /** Конфиги, ждущие согласия пользователя на VPN. */
    private var pendingConfig: String? = null
    private var pendingXrayConfig: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    events = sink
                    SilentGateVpnService.stateListener = { running, error ->
                        runOnUiThread {
                            events?.success(mapOf("running" to running, "error" to error))
                        }
                    }
                    // Сразу отдаём текущее состояние: интерфейс мог быть
                    // перезапущен при живом туннеле.
                    sink?.success(
                        mapOf(
                            "running" to SilentGateVpnService.running,
                            "error" to SilentGateVpnService.lastError,
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
}
