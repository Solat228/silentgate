package lol.silentgate

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
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

    /** Конфиг, ждущий согласия пользователя на VPN. */
    private var pendingConfig: String? = null
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
                            startWithConsent(config, result)
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
    private fun startWithConsent(config: String, result: MethodChannel.Result) {
        val consent = VpnService.prepare(this)
        if (consent != null) {
            pendingConfig = config
            pendingResult = result
            startActivityForResult(consent, REQ_PREPARE)
            return
        }
        launchService(config)
        result.success(null)
    }

    private fun launchService(config: String) {
        val intent = Intent(this, SilentGateVpnService::class.java)
            .setAction(SilentGateVpnService.ACTION_START)
            .putExtra(SilentGateVpnService.EXTRA_CONFIG, config)
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
        val result = pendingResult
        pendingConfig = null
        pendingResult = null

        if (resultCode == Activity.RESULT_OK && config != null) {
            launchService(config)
            result?.success(null)
        } else {
            // Отказ от согласия — отдельный путь ошибки, которого нет на Windows.
            result?.error("consent_denied", "Пользователь не разрешил VPN", null)
        }
    }
}
