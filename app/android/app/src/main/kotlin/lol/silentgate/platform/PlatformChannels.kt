package lol.silentgate.platform

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel
import lol.silentgate.cores.libbox.Libbox
import lol.silentgate.cores.libXray.LibXray
import lol.silentgate.cores.libXray.LibXrayInvokeRequest
import lol.silentgate.cores.libXray.PingRequest
import java.io.ByteArrayOutputStream

/**
 * Нативная сторона каналов, которые объявлены в Dart
 * (`core/platform/device_id_android.dart`, `app_launcher_android.dart`).
 *
 * Без этих обработчиков вызовы падали с `MissingPluginException`, а Dart молча
 * уходил в запасные значения — в отчёте поддержки появлялись «Модель: unknown»,
 * «HWID: unknown» и строка прошивки вместо версии Android, а кнопки перехода в
 * поддержку не делали ничего.
 */
object PlatformChannels {

    const val DEVICE_CHANNEL = "lol.silentgate/device"
    const val LAUNCHER_CHANNEL = "lol.silentgate/launcher"
    const val APPS_CHANNEL = "lol.silentgate/apps"
    const val PROBE_CHANNEL = "lol.silentgate/probe"

    /**
     * Пинг сервера ОТДЕЛЬНЫМ экземпляром Xray.
     *
     * ⚠️ Это не противоречит «VpnService в приложении один»: `LibXray.ping`
     * поднимает СВОЙ `core.New` и гасит его в defer, не трогая глобальный
     * инстанс, занятый живым туннелем. Именно поэтому на Android возможен
     * настоящий харнесс, а не только проба по уже поднятому каналу.
     *
     * Без этого hysteria2 и панельные профили «Авто» не пингуются вовсе: TCP у
     * них нет (QUIC / балансировщик по десяткам узлов), а вторая фаза проверки
     * требовала харнесса, которого на Android «не было».
     *
     * Возвращает задержку в мс либо null. Коды libXray: 10000 — ошибка,
     * 11000 — таймаут; наружу отдаём null, чтобы не выдавать их за секунды.
     */
    fun handleProbe(
        method: String,
        configPath: String?,
        timeoutSec: Int,
        url: String?,
        proxy: String?,
        result: MethodChannel.Result,
    ) {
        when (method) {
            "ping" -> {
                val path = configPath?.trim().orEmpty()
                if (path.isEmpty()) { result.success(null); return }
                val delay = runCatching {
                    val req = PingRequest().apply {
                        this.configPath = path
                        this.timeout = timeoutSec.toLong()
                        this.url = url?.trim().orEmpty().ifEmpty {
                            "https://www.gstatic.com/generate_204"
                        }
                        this.proxy = proxy?.trim().orEmpty().ifEmpty { "socks5://127.0.0.1:0" }
                    }
                    val raw = LibXray.invoke(jsonOf(req))
                    // ⚠️ Ответ ядра ОБЯЗАН попадать в лог. Раньше он молча
                    // проглатывался, и «все серверы мёртвые» выглядело как
                    // необъяснимое поведение: наружу отдавался null, а почему —
                    // узнать было негде.
                    val parsed = parseDelay(raw)
                    if (parsed == null) {
                        android.util.Log.w("SilentGateProbe", "ping: $raw")
                    }
                    parsed
                }.onFailure {
                    android.util.Log.w("SilentGateProbe", "ping упал: $it")
                }.getOrNull()
                result.success(delay)
            }
            else -> result.notImplemented()
        }
    }

    /** Задержка из ответа libXray; служебные коды 10000/11000 → null. */
    private fun parseDelay(raw: String?): Long? {
        val body = raw ?: return null
        val m = Regex("""\"delay\"\s*:\s*(-?\d+)""").find(body) ?: return null
        val v = m.groupValues[1].toLongOrNull() ?: return null
        // 10000 — ошибка, 11000 — таймаут: наружу их отдавать нельзя, иначе
        // «недоступен» покажется как честные 10 секунд.
        return if (v <= 0 || v >= 10000) null else v
    }

    /** Запрос в формате `LibXray.invoke`. */
    private fun jsonOf(req: PingRequest): String {
        val path = req.configPath.replace("\\", "/")
        val payload = """{"configPath":"$path","timeout":${req.timeout},""" +
            """"url":"${req.url}","proxy":"${req.proxy}"}"""
        return """{"apiVersion":1,"method":"ping","payload":$payload}"""
    }

    /**
     * Список приложений, между которыми можно делить трафик.
     *
     * Без него раздельное туннелирование на Android недоступно ЦЕЛИКОМ: правило
     * задаётся именем пакета, а взять его пользователю неоткуда — «выбрать файл»
     * на Android невозможно, в отличие от Windows.
     *
     * Отдаём только то, что имеет смысл разделять:
     *  - у приложения есть доступ в интернет (иначе правило бессмысленно);
     *  - оно запускаемое (есть LAUNCHER-активность) ЛИБО не системное. Системные
     *    без экрана — это сервисы вроде `com.android.providers.*`, они забивают
     *    список сотней строк, среди которых пользователю нечего выбирать.
     *
     * ⚠️ Требует `<queries>` в манифесте: с Android 11 без него
     * `getInstalledApplications` вернёт почти пустой список — приложение видит
     * только себя.
     */
    fun handleApps(context: Context, method: String, arg: String?, result: MethodChannel.Result) {
        when (method) {
            // ⚠️ Отказ НЕ выдаём за «приложений нет».
            //
            // Раньше здесь стоял getOrDefault(emptyList()): любое исключение
            // превращалось в пустой список, и экран правил показывал «пусто»
            // без единого слова о причине. Пользователь видел бы то же самое,
            // что при честном отсутствии приложений, и чинить было бы нечего.
            // Та же болезнь, что лечили в автонастройке через AutoConfigUnsupported.
            "list" -> runCatching { listApps(context) }.fold(
                onSuccess = { result.success(it) },
                onFailure = { result.error("apps_unavailable", it.message ?: it::class.java.simpleName, null) },
            )
            "icon" -> {
                val pkg = arg?.trim().orEmpty()
                if (pkg.isEmpty()) result.success(null)
                else result.success(runCatching { iconPng(context, pkg) }.getOrNull())
            }
            else -> result.notImplemented()
        }
    }

    private fun listApps(context: Context): List<Map<String, Any?>> {
        val pm = context.packageManager
        val launchable = runCatching {
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            pm.queryIntentActivities(intent, 0).mapNotNull { it.activityInfo?.packageName }.toSet()
        }.getOrDefault(emptySet())

        return pm.getInstalledApplications(0)
            .asSequence()
            .filter { info ->
                // Интернет-доступ: без него правило ничего не значит.
                pm.checkPermission(android.Manifest.permission.INTERNET, info.packageName) ==
                    PackageManager.PERMISSION_GRANTED
            }
            .filter { info ->
                val system = (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                !system || launchable.contains(info.packageName)
            }
            .map { info ->
                mapOf(
                    "package" to info.packageName,
                    "name" to runCatching { pm.getApplicationLabel(info).toString() }
                        .getOrDefault(info.packageName),
                    "system" to ((info.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                )
            }
            // Сортируем здесь: на стороне Dart это была бы вторая сортировка
            // тысячи строк на каждом открытии экрана.
            .sortedBy { (it["name"] as String).lowercase() }
            .toList()
    }

    /** Иконка приложения в PNG. `null` — пакета нет или иконку не отрисовать. */
    private fun iconPng(context: Context, pkg: String): ByteArray? {
        val pm = context.packageManager
        val drawable: Drawable = runCatching { pm.getApplicationIcon(pkg) }.getOrNull() ?: return null
        // 96 px хватает для списка на любой плотности и не раздувает канал:
        // адаптивные иконки рисуются в векторе и могут отдать 512×512.
        val size = 96
        val bmp = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)
        } else {
            Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also { out ->
                val canvas = Canvas(out)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
            }
        }
        val stream = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }

    fun handleDevice(context: Context, method: String, result: MethodChannel.Result) {
        when (method) {
            // Версии ядер. Раньше здесь стояла заглушка «н/д» с комментарием
            // «придёт, когда AAR появится в сборке» — AAR давно в сборке, а
            // заглушка осталась: пользователь видел прочерк вместо версии.
            "coreVersions" -> result.success(
                mapOf(
                    "singbox" to runCatching { Libbox.version() }.getOrNull(),
                    // ⚠️ Версию Xray libXray отдаёт только через конверт
                    // Invoke(json) — отдельный метод `xrayVersion()` в биндинге
                    // отсутствует. Пока не разобран формат ответа, честно не
                    // выдумываем: пустое значение интерфейс покажет как прочерк.
                    "xray" to null,
                )
            )

            // DNS ФИЗИЧЕСКОЙ сети — для доменов с правилом «Прямо».
            //
            // ⚠️ Без него ядро оставляет резолвер `local`, и такие домены не
            // резолвятся ВООБЩЕ: проверено живым запуском — сайт «Туннель»
            // открывался, «Блок» блокировался, а «Прямо» отвечал
            // «No address associated with hostname». Ровно тот же дефект, что
            // чинили на Windows: `local` уходит в системный резолвер, чей
            // трафик возвращается в туннель.
            //
            // Берём сеть БЕЗ признака VPN, иначе получим адрес самого туннеля.
            "directDns" -> result.success(directDns(context))
            // Иконка САМОГО приложения — в рантайме, а не файлом в assets.
            //
            // Владелец предупредил, что бренд может смениться; зашитая картинка
            // пережила бы ребрендинг и осталась старой. Здесь берём ту, что
            // реально установлена в системе.
            "appIcon" -> result.success(appIconPng(context))
            // Системный Always-on VPN + «блокировать соединения без VPN».
            //
            // Это надёжнее любого нашего kill switch: система держит блокировку
            // даже когда приложение убито, обновляется или ещё не запустилось
            // после перезагрузки. Наш собственный kill switch закрывает окно
            // между попытками переподключения, системный — всё остальное.
            //
            // Прямого экрана «Always-on для приложения X» в Android нет:
            // открываем общий раздел VPN, дальше пользователь выбирает нас.
            "openVpnSettings" -> result.success(
                startAction(context, Settings.ACTION_VPN_SETTINGS)
            )
            else -> handleDeviceRest(context, method, result)
        }
    }

    /// Иконка приложения в PNG.
    ///
    /// `getApplicationIcon` возвращает Drawable — у адаптивных иконок это не
    /// BitmapDrawable, поэтому рисуем на холст сами, иначе на всех современных
    /// сборках вернулся бы null.
    private fun appIconPng(context: Context): ByteArray? = try {
        val d = context.packageManager.getApplicationIcon(context.packageName)
        val size = if (d.intrinsicWidth > 0) minOf(d.intrinsicWidth, 192) else 128
        val bmp = android.graphics.Bitmap.createBitmap(
            size, size, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bmp)
        d.setBounds(0, 0, size, size)
        d.draw(canvas)
        val out = java.io.ByteArrayOutputStream()
        bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
        bmp.recycle()
        out.toByteArray()
    } catch (e: Throwable) {
        null
    }

    private fun directDns(context: Context): String? = runCatching {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.allNetworks
            .asSequence()
            .mapNotNull { net ->
                val caps = cm.getNetworkCapabilities(net) ?: return@mapNotNull null
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return@mapNotNull null
                if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                    return@mapNotNull null
                }
                cm.getLinkProperties(net)?.dnsServers
            }
            .flatten()
            // IPv4 предпочтительнее: адрес уходит в `udp://<addr>`, а
            // link-local IPv6 там потребовал бы зону интерфейса.
            .sortedBy { if (it is java.net.Inet4Address) 0 else 1 }
            .firstOrNull { it.hostAddress?.isNotEmpty() == true }
            ?.hostAddress
            ?.substringBefore('%')
    }.getOrNull()

    private fun handleDeviceRest(
        context: Context,
        method: String,
        result: MethodChannel.Result,
    ) {
        when (method) {
            // ANDROID_ID: стабилен для пары «устройство + подпись приложения»,
            // но меняется при сбросе к заводским настройкам — для device-limit
            // панели такое устройство станет новым. Это осознанно.
            "hwid" -> result.success(androidId(context))
            // Именно версия ОС («11»), а не Build.FINGERPRINT: dart:io отдаёт
            // здесь строку прошивки, которая в отчёте выглядела мусором.
            "osVersion" -> result.success(Build.VERSION.RELEASE ?: "")
            "model" -> result.success(model())
            else -> result.notImplemented()
        }
    }

    @SuppressLint("HardwareIds")
    private fun androidId(context: Context): String =
        runCatching {
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID) ?: ""
        }.getOrDefault("")

    private fun model(): String {
        val brand = (Build.MANUFACTURER ?: "").trim()
        val model = (Build.MODEL ?: "").trim()
        // Производитель часто уже входит в модель («Redmi Note 12») — не дублируем.
        return when {
            model.isEmpty() -> brand
            brand.isEmpty() || model.startsWith(brand, ignoreCase = true) -> model
            else -> "$brand $model"
        }
    }

    fun handleLauncher(context: Context, method: String, url: String?, result: MethodChannel.Result) {
        val target = url?.trim().orEmpty()
        if (target.isEmpty()) {
            result.success(false)
            return
        }
        when (method) {
            "open" -> {
                result.success(startView(context, target))
            }
            // Для tg://-ссылок: открываем ТОЛЬКО если есть чем. Иначе Dart
            // уходит в браузер, и пользователь не видит системного «нет
            // приложения для этого действия».
            "openIfHandled" -> {
                val intent = viewIntent(target)
                val canHandle = intent.resolveActivity(context.packageManager) != null
                result.success(if (canHandle) startView(context, target) else false)
            }
            else -> result.notImplemented()
        }
    }

    private fun viewIntent(url: String): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            // Запуск из Activity-контекста возможен и без флага, но канал могут
            // дёрнуть, когда Activity уже не на переднем плане.
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    private fun startView(context: Context, url: String): Boolean = runCatching {
        context.startActivity(viewIntent(url))
        true
    }.getOrDefault(false)

    /** Открыть системный экран настроек по action. `false` — экрана нет. */
    private fun startAction(context: Context, action: String): Boolean =
        runCatching {
            context.startActivity(
                Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        }.getOrDefault(false)
}
