package lol.silentgate.platform

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.LuminanceSource
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.client.android.Intents
import com.google.zxing.common.GlobalHistogramBinarizer
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import com.journeyapps.barcodescanner.CaptureActivity
import io.flutter.plugin.common.MethodChannel

/**
 * QR-код подписки: с камеры и с картинки из галереи (ANDROID.md п.60а).
 *
 * Страница подписки Remnawave штатно показывает «Get Link (Show QR)», то есть
 * провайдер выдаёт QR, а клиент до 1.15.0 его не читал. Картинка — не менее
 * важный путь, чем камера: человек чаще сохраняет скриншот, чем держит рядом
 * второй экран.
 *
 * Распознавание — ZXing (Apache-2.0, совместима с GPL-3.0): камера через
 * готовую `CaptureActivity` из zxing-android-embedded, картинка — ядром ZXing
 * прямо здесь. ML Kit не взят сознательно: это закрытый бинарь Google и
 * зависимость от сервисов Google Play, которых на части телефонов нет.
 *
 * Что делать с текстом, решает Dart (`importSource`) — второй логики разбора
 * ссылок здесь нет и быть не должно.
 *
 * Ответы канала:
 *  - строка — распознанный текст;
 *  - `null` — человек отменил (назад на камере, ничего не выбрал в галерее);
 *  - ошибка `camera_denied` / `no_qr` / `read_failed` / `busy`.
 */
class QrScanner(private val activity: Activity) {

    companion object {
        const val CHANNEL = "lol.silentgate/qr"
        const val REQ_SCAN = 1101
        const val REQ_IMAGE = 1102

        /**
         * Предел пикселей картинки для разбора. Скриншот телефона — до ~4,6 млн
         * (1440×3200); больше — уменьшаем вдвое, пока не влезет: QR на скриншоте
         * крупный и уменьшение переживает, а массив пикселей на 16 млн точек —
         * 64 МБ в памяти процесса, где работает VPN.
         */
        private const val MAX_PIXELS = 4_000_000

        /**
         * Вызов Dart, ждущий ответа сканера.
         *
         * ⚠️ В COMPANION, А НЕ В ЭКЗЕМПЛЯРЕ. Пока открыт сканер, система вправе
         * снять нашу Activity, и ответ сканера получит уже НОВАЯ — со своим
         * [QrScanner]. Будь ожидание полем экземпляра, новый сканер его бы не
         * знал, а Dart ждал бы вечно: камера распознавала код, импорта не было
         * (телефон владельца, 13.10.2026). Движок живёт дольше Activity
         * (`MainActivity.provideFlutterEngine`), поэтому ответ по-прежнему есть
         * кому принять.
         */
        private var pending: MethodChannel.Result? = null
    }

    private val main = Handler(Looper.getMainLooper())

    fun handle(method: String, prompt: String?, result: MethodChannel.Result) {
        when (method) {
            "hasCamera" -> result.success(
                activity.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
            )
            "cameraGranted" -> result.success(
                activity.checkSelfPermission(Manifest.permission.CAMERA) ==
                    PackageManager.PERMISSION_GRANTED
            )
            "scanCamera" -> {
                if (!take(result)) return
                // Разрешение на камеру спрашивает сама CaptureActivity; отказ
                // возвращается флагом MISSING_CAMERA_PERMISSION в ответе.
                val intent = Intent(activity, CaptureActivity::class.java)
                    .setAction(Intents.Scan.ACTION)
                    .putExtra(Intents.Scan.FORMATS, BarcodeFormat.QR_CODE.name)
                    .putExtra(Intents.Scan.PROMPT_MESSAGE, prompt ?: "")
                    .putExtra(Intents.Scan.BEEP_ENABLED, false)
                    // Портрет — так держат телефон; по умолчанию у библиотеки
                    // альбомная ориентация (переопределено в манифесте).
                    .putExtra(Intents.Scan.ORIENTATION_LOCKED, false)
                startOrFail(intent, REQ_SCAN)
            }
            "scanImage" -> {
                if (!take(result)) return
                // ACTION_GET_CONTENT не требует разрешения на чтение файлов:
                // доступ к одной выбранной картинке выдаёт система.
                val intent = Intent(Intent.ACTION_GET_CONTENT)
                    .setType("image/*")
                    .addCategory(Intent.CATEGORY_OPENABLE)
                startOrFail(intent, REQ_IMAGE)
            }
            else -> result.notImplemented()
        }
    }

    /** Один вызов за раз: второй ответ к первому не прицепить. */
    private fun take(result: MethodChannel.Result): Boolean {
        if (pending != null) {
            result.error("busy", "QR: предыдущий запрос ещё не завершён", null)
            return false
        }
        pending = result
        return true
    }

    private fun startOrFail(intent: Intent, code: Int) {
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, code)
        } catch (e: Exception) {
            finishError("read_failed", e.toString())
        }
    }

    /** `true` — запрос наш и обработан. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        when (requestCode) {
            REQ_SCAN -> {
                val text = data?.getStringExtra(Intents.Scan.RESULT)
                when {
                    resultCode == Activity.RESULT_OK && !text.isNullOrEmpty() -> finish(text)
                    data?.getBooleanExtra(Intents.Scan.MISSING_CAMERA_PERMISSION, false) == true ->
                        finishError("camera_denied", "Нет разрешения на камеру")
                    else -> finish(null)
                }
            }
            REQ_IMAGE -> {
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    finish(null)
                    return true
                }
                // Разбор картинки — не на главном потоке: на нём живут касания
                // и vsync Flutter, а TRY_HARDER по большой картинке — секунды.
                Thread {
                    val outcome = runCatching { decodeUri(uri) }
                    main.post {
                        // Исход — в logcat: без этой строки отказ разбора на
                        // устройстве не отличить от потерянного ответа.
                        // Распознанный текст не пишется — в нём ссылка-подписка.
                        outcome.fold(
                            onSuccess = { text ->
                                android.util.Log.w("SilentGateQr",
                                    if (text == null) "картинка: QR не найден"
                                    else "картинка: QR прочитан, ${text.length} симв.")
                                if (text == null) finishError("no_qr", "QR не найден")
                                else finish(text)
                            },
                            onFailure = {
                                android.util.Log.w("SilentGateQr", "картинка: ошибка $it")
                                finishError("read_failed", it.toString())
                            },
                        )
                    }
                }.start()
            }
            else -> return false
        }
        return true
    }

    private fun finish(text: String?) {
        val r = pending ?: return
        pending = null
        r.success(text)
    }

    private fun finishError(code: String, message: String) {
        val r = pending ?: return
        pending = null
        r.error(code, message, null)
    }

    private fun decodeUri(uri: Uri): String? {
        val resolver = activity.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        // ⚠️ С inJustDecodeBounds `decodeStream` ВСЕГДА возвращает null — размеры
        // приходят в `bounds`. Проверка `?: throw` по его результату отвергала
        // любую картинку (живой прогон на эмуляторе 10.10.2026), поэтому на null
        // проверяется только сам поток.
        val stream = resolver.openInputStream(uri)
            ?: throw IllegalStateException("картинка не открылась")
        stream.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw IllegalStateException("не картинка")
        }
        var sample = 1
        while ((bounds.outWidth / sample).toLong() * (bounds.outHeight / sample) > MAX_PIXELS) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        val bmp = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
            ?: throw IllegalStateException("картинка не декодировалась")
        try {
            return decodeBitmap(bmp)
        } finally {
            bmp.recycle()
        }
    }

    /**
     * Перебор: прямое и инвертированное изображение (светлый QR на тёмном фоне
     * — тёмная тема страницы подписки), два бинаризатора — гибридный хорош на
     * фото, глобальный — на ровных скриншотах.
     */
    private fun decodeBitmap(bmp: Bitmap): String? {
        val w = bmp.width
        val h = bmp.height
        val px = IntArray(w * h)
        bmp.getPixels(px, 0, w, 0, 0, w, h)
        val source: LuminanceSource = RGBLuminanceSource(w, h, px)
        val hints = mapOf(
            DecodeHintType.TRY_HARDER to true,
            DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
            // Кодировка по умолчанию для QR без ECI: в названиях бывает кириллица.
            DecodeHintType.CHARACTER_SET to "UTF-8",
        )
        val reader = QRCodeReader()
        for (s in listOf(source, source.invert())) {
            for (bin in listOf(HybridBinarizer(s), GlobalHistogramBinarizer(s))) {
                try {
                    return reader.decode(BinaryBitmap(bin), hints).text
                } catch (_: ReaderException) {
                    reader.reset()
                }
            }
        }
        return null
    }
}
