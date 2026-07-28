package lol.silentgate.platform

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

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

    fun handleDevice(context: Context, method: String, result: MethodChannel.Result) {
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
