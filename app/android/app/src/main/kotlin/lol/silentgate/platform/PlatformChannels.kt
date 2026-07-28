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
            "list" -> result.success(runCatching { listApps(context) }.getOrDefault(emptyList()))
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
            else -> handleDeviceRest(context, method, result)
        }
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
}
