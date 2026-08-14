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

    companion object {
        /**
         * Контекст приложения для тех мест, где своего нет.
         *
         * ⚠️ Нужен ровно одному потребителю — обновлению плитки быстрых настроек
         * из статического [lol.silentgate.vpn.SilentGateVpnService.notifyState].
         * Там смена состояния объявляется из companion object, а экземпляр
         * сервиса к тому моменту уже может быть снят, поэтому брать контекст у
         * него нельзя. Контекст ПРИЛОЖЕНИЯ живёт столько же, сколько процесс, и
         * утечки активности здесь не бывает.
         */
        @Volatile
        var appContext: android.content.Context? = null
            private set
    }

    override fun onCreate() {
        super.onCreate()
        appContext = applicationContext
        runCatching {
            // Тот же каталог, куда кладёт файлы Dart-сторона (`GeoAssets.dir()`).
            // Создаём заранее: пустой каталог ядру не мешает, а его отсутствие
            // добавило бы к разбору лишний слой «а туда ли вообще смотрели».
            val geo = File(filesDir, "SilentGate/geo")
            if (!geo.exists()) geo.mkdirs()
            Os.setenv("XRAY_LOCATION_ASSET", geo.absolutePath, true)
            // ⚠️ ЗАГРУЖАЕМ ЯДРО ПРЯМО ЗДЕСЬ, СРАЗУ ПОСЛЕ setenv. Без этого
            // порядок не задан ничем: класс `LibXray` подтягивается лениво —
            // тем, кто первым его коснётся, — и Go-рантайм успевал стартовать
            // ДО нашей переменной. Тогда `os.Getenv` внутри ядра её не видел, и
            // оно шло искать базы по умолчанию:
            //
            //   common/geodata: illegal ip rule: geoip:private
            //     > failed to open geoip.dat
            //     > stat /system/bin/geoip.dat: no such file or directory
            //
            // Владелец получил это на живом телефоне 15.08.2026: базы лежали на
            // месте, а VPN не поднимался вовсе. Обращение к классу заставляет
            // `System.loadLibrary` отработать в известный момент — после
            // setenv, — и Go копирует окружение уже с нашей переменной.
            //
            // Читаем обратно и пишем в лог: «поставили» и «ядро увидело» — два
            // разных утверждения, и до этой правки они расходились молча.
            Class.forName("lol.silentgate.cores.libXray.LibXray")
            Log.i("SilentGateApp", "Каталог гео-баз: ${Os.getenv("XRAY_LOCATION_ASSET")}")
        }.onFailure {
            Log.w("SilentGateApp", "Не удалось указать каталог гео-баз: ${it.message}")
        }
    }
}
