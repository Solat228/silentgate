package lol.silentgate.platform

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Выбор текстового файла системным окном — для импорта настроек (P11).
 *
 * ⚠️ ПОЧЕМУ НЕ `file_selector`. Плагин ждёт ответа окна выбора на той
 * Activity, которая окно открыла. Пока окно открыто, система вправе снять нашу
 * Activity — «Не сохранять действия» в параметрах разработчика, агрессивные
 * прошивки, нехватка памяти, — и ответ получает уже НОВАЯ. Плагин на новой
 * Activity создаёт себя заново и про ожидание не знает: файл выбран, окно
 * закрылось, а Dart ждёт вечно, без ответа и без ошибки (живьём в эмуляторе
 * 20.10.2026, и именно так настроен телефон владельца). Та же беда уже была у
 * QR-сканера — см. [QrScanner]; лечение то же: ожидание в companion object,
 * движок Flutter живёт дольше Activity.
 *
 * Ответы канала:
 *  - `{name, text}` — имя файла и его содержимое (UTF-8);
 *  - `null` — человек ничего не выбрал;
 *  - ошибка `busy` / `too_big` / `read_failed`.
 */
class TextFilePicker(private val activity: Activity) {

    companion object {
        const val CHANNEL = "lol.silentgate/files"
        const val REQ_PICK = 1103

        /** Предел по умолчанию, если Dart его не прислал. */
        private const val DEFAULT_MAX_BYTES = 32 * 1024 * 1024

        /** Вызов Dart, ждущий ответа окна выбора. В companion — см. описание класса. */
        private var pending: MethodChannel.Result? = null
        private var pendingMax: Int = DEFAULT_MAX_BYTES
    }

    private val main = Handler(Looper.getMainLooper())

    fun handle(method: String, maxBytes: Int?, result: MethodChannel.Result) {
        when (method) {
            "pickText" -> {
                if (pending != null) {
                    result.error("busy", "Выбор файла: предыдущий запрос ещё не завершён", null)
                    return
                }
                pending = result
                pendingMax = maxBytes?.takeIf { it > 0 } ?: DEFAULT_MAX_BYTES
                // Без фильтра типов: расширение `.sgsettings` система не знает,
                // и с фильтром файл в окне просто не показался бы.
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("*/*")
                try {
                    @Suppress("DEPRECATION")
                    activity.startActivityForResult(intent, REQ_PICK)
                } catch (e: Exception) {
                    finishError("read_failed", e.toString())
                }
            }
            else -> result.notImplemented()
        }
    }

    /** `true` — запрос наш и обработан. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK) return false
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            finish(null)
            return true
        }
        val max = pendingMax
        // Чтение — не на главном потоке: поставщик файла бывает сетевым
        // (облачный диск), и ответ от него приходит не сразу.
        Thread {
            val outcome = runCatching { read(uri, max) }
            main.post {
                outcome.fold(
                    onSuccess = { finish(it) },
                    onFailure = {
                        android.util.Log.w("SilentGateFiles", "выбор файла: ошибка $it")
                        if (it is TooBig) finishError("too_big", "файл больше $max Б")
                        else finishError("read_failed", it.toString())
                    },
                )
            }
        }.start()
        return true
    }

    private class TooBig : Exception()

    private fun read(uri: Uri, max: Int): Map<String, Any?> {
        val resolver = activity.contentResolver
        val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
            ?: uri.lastPathSegment
            ?: ""
        val input = resolver.openInputStream(uri)
            ?: throw IllegalStateException("файл не открылся")
        val out = ByteArrayOutputStream()
        input.use {
            val buf = ByteArray(64 * 1024)
            while (true) {
                val n = it.read(buf)
                if (n < 0) break
                out.write(buf, 0, n)
                // Предел проверяется по ходу чтения, а не по размеру от
                // поставщика: размер он вправе не сообщить.
                if (out.size() > max) throw TooBig()
            }
        }
        return mapOf("name" to name, "text" to out.toString(Charsets.UTF_8.name()))
    }

    private fun finish(value: Any?) {
        val r = pending ?: return
        pending = null
        r.success(value)
    }

    private fun finishError(code: String, message: String) {
        val r = pending ?: return
        pending = null
        r.error(code, message, null)
    }
}
