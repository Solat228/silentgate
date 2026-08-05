package lol.silentgate

import android.app.Application
import android.system.Os
import android.util.Log
import java.io.File

/**
 * Приложение целиком. Существует ради ОДНОЙ вещи — переменной окружения,
 * которую надо выставить раньше всего остального.
 *
 * ⚠️ ПОЧЕМУ НЕ В МОМЕНТ ЗАПУСКА ЯДРА. Сначала так и было сделано:
 * `Os.setenv("XRAY_LOCATION_ASSET", …)` прямо перед `LibXray.invoke`. На
 * эмуляторе это НЕ СРАБОТАЛО — базы скачаны, лежат на месте, а ядро всё равно
 * падало с
 *
 * ```
 * common/geodata: failed to open geoip.dat
 *   > stat /system/bin/geoip.dat: no such file or directory
 * ```
 *
 * Причина в устройстве Go: его рантайм копирует окружение процесса ОДИН РАЗ,
 * при инициализации — то есть при загрузке `libbox`/`libXray`. Всё, что
 * выставлено через libc `setenv` позже, попадает в окружение процесса, но в
 * копию Go уже не попадает, и `os.Getenv` внутри ядра этого не видит.
 *
 * Поэтому переменная ставится здесь: `Application.onCreate` выполняется раньше,
 * чем что-либо коснётся классов ядра, а значит раньше, чем нативная библиотека
 * будет загружена. Тем же приёмом пользуется v2rayNG.
 *
 * ⚠️ Не переносить обратно «поближе к использованию»: там она смотрится
 * логичнее и не работает.
 */
class SilentGateApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        runCatching {
            // Тот же каталог, куда кладёт файлы Dart-сторона (`GeoAssets.dir()`).
            // Создаём заранее: пустой каталог ядру не мешает, а его отсутствие
            // добавило бы к разбору лишний слой «а туда ли вообще смотрели».
            val geo = File(filesDir, "SilentGate/geo")
            if (!geo.exists()) geo.mkdirs()
            Os.setenv("XRAY_LOCATION_ASSET", geo.absolutePath, true)
        }.onFailure {
            Log.w("SilentGateApp", "Не удалось указать каталог гео-баз: ${it.message}")
        }
    }
}
