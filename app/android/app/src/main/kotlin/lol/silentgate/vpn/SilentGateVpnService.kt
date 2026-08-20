package lol.silentgate.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.SystemClock
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.system.OsConstants
import android.util.Log
import lol.silentgate.cores.libbox.CommandServer
import lol.silentgate.cores.libbox.CommandServerHandler
import lol.silentgate.cores.libbox.ConnectionOwner
import lol.silentgate.cores.libbox.InterfaceUpdateListener
import lol.silentgate.cores.libbox.Libbox
import lol.silentgate.cores.libbox.LocalDNSTransport
import lol.silentgate.cores.libbox.NetworkInterface as LibboxNetworkInterface
import lol.silentgate.cores.libbox.NetworkInterfaceIterator
import lol.silentgate.cores.libbox.OverrideOptions
import lol.silentgate.cores.libbox.PlatformInterface
import lol.silentgate.cores.libbox.RoutePrefix
import lol.silentgate.cores.libbox.SetupOptions
import lol.silentgate.cores.libbox.StringIterator
import lol.silentgate.cores.libbox.SystemProxyStatus
import lol.silentgate.cores.libbox.TunOptions
import lol.silentgate.cores.libbox.WIFIState
import lol.silentgate.cores.libXray.DialerController
import lol.silentgate.cores.libXray.LibXray
import org.json.JSONObject
import lol.silentgate.MainActivity
import lol.silentgate.R
import java.net.Inet6Address
import java.net.InetSocketAddress
import java.net.InterfaceAddress
import java.net.NetworkInterface as JavaNetworkInterface

/**
 * VPN-сервис SilentGate: поднимает туннель через `libbox` (sing-box) и отдаёт
 * ему файловый дескриптор от [VpnService].
 *
 * ## Кто кем командует
 *
 * Дескриптор передаётся НЕ «сверху вниз»: ядро само зовёт [openTun], а мы по
 * пришедшим [TunOptions] строим `VpnService.Builder`, вызываем `establish()` и
 * возвращаем fd. Это инверсия управления, и другого поддерживаемого пути у
 * libbox нет — так устроен и официальный клиент sing-box.
 *
 * ## Порядок работы (API sing-box 1.13, выяснено по исходникам)
 *
 * `Libbox.setup` → `newCommandServer` → `start()` → `startOrReloadService(json)`.
 * Классов `BoxService`/`newService` из старых примеров в 1.13 уже нет.
 *
 * Подробности и рецепт сборки ядер — `tools/build-android-cores.md`.
 */
class SilentGateVpnService : VpnService(), PlatformInterface, CommandServerHandler {
    private val logTag = "SilentGateVpn"


    companion object {
        const val ACTION_START = "lol.silentgate.action.START"
        const val ACTION_STOP = "lol.silentgate.action.STOP"

        /// ⚠️ КТО ИМЕННО ПРОСИТ ОСТАНОВКУ — ЧЕЛОВЕК ИЛИ МЫ САМИ.
        ///
        /// Без этого признака остановка была неразличима, и своё же
        /// переподключение читалось как нажатие кнопки в шторке: сторож канала
        /// решал восстановить связь, гасил ядро своей же командой `stop`,
        /// сервис помечал остановку пользовательской, Dart видел `byUser` и
        /// ОТМЕНЯЛ запланированное восстановление. Туннель после этого не
        /// возвращался. Поймано живым прогоном на эмуляторе 19.08.2026:
        /// «Автопереподключение: попытка 1 через 800 мс» и «Туннель снят
        /// пользователем из уведомления» стоят в журнале в одну секунду.
        ///
        /// ⚠️ Ставить обязаны ВСЕ отправители `ACTION_STOP`, их ровно три:
        /// кнопка в шторке и плитка быстрых настроек — `true`, канал из Dart —
        /// `false` (там намерение пользователя знает сама Dart-сторона, у неё
        /// для этого есть `_userStopped`). Страж — `test/android_stop_reason_test.dart`.
        const val EXTRA_BY_USER = "by_user"

        /** Свернуть/развернуть уведомление прямо из шторки. */
        const val ACTION_TOGGLE_COMPACT = "lol.silentgate.action.TOGGLE_COMPACT"

        const val EXTRA_CONFIG = "config"

        /// Конфиг Xray для панельных профилей «Авто».
        ///
        /// Когда он задан, поднимаются ОБА ядра: Xray держит сам профиль
        /// (balancers/burstObservatory — sing-box такое не разбирает) и слушает
        /// локальный SOCKS, а sing-box делает туннель и заворачивает трафик
        /// туда. Ровно как на Windows.
        const val EXTRA_XRAY_CONFIG = "xray_config"

        /// ⚠️ Имя хранилища и ключ языка переехали в [NativePrefs] — их читает
        /// не только сервис. Здесь их больше нет намеренно: копия константы
        /// рядом с общей быстро начинает жить своей жизнью.

        private const val CHANNEL_ID = "silentgate_vpn"

        /// ⚠️ ЗАНЯТО ПОСТОЯННЫМ УВЕДОМЛЕНИЕМ. Разовые сообщения об обрыве
        /// берут другой номер — см. `AlertNotice.NOTIFICATION_ID`.
        private const val NOTIFICATION_ID = 1

        /** Состояние для Dart-стороны; сервис живёт дольше UI. */
        @Volatile
        var running: Boolean = false
            private set

        @Volatile
        var lastError: String? = null
            private set

        /**
         * ⚠️ ТУННЕЛЬ СНЯТ ПО ПРОСЬБЕ ПОЛЬЗОВАТЕЛЯ, А НЕ УПАЛ САМ.
         *
         * Без этого признака остановка по кнопке «Отключить» в шторке выглядела
         * снаружи ровно как смерть ядра: `running=false`, `error=null` — то же
         * самое, что при внезапном падении. Dart честно шёл в `onCoreDied`, а
         * оттуда — в автопереподключение, включённое по умолчанию. Итог: самый
         * привычный способ выключить VPN (шторка, приложение свёрнуто) включал
         * его обратно через 0,8 с. При выключенном автоповторе вместо этого
         * показывалась ложная ошибка «Ядро остановилось (код 0)».
         *
         * На эмуляторном прогоне дефект не показался: там отключали через
         * `silentgate://disconnect`, то есть по другому пути.
         */
        @Volatile
        var stoppedByUser: Boolean = false
            private set

        /// Живой экземпляр сервиса. Нужен, чтобы Dart мог поменять текст
        /// уведомления, не пересоздавая туннель (kill switch держит трафик, и
        /// перезапуск сервиса ради надписи открыл бы окно утечки).
        @Volatile
        var instance: SilentGateVpnService? = null

        /** Слушатель состояния — им выступает мост к Flutter. */
        @Volatile
        var stateListener: ((running: Boolean, error: String?, byUser: Boolean) -> Unit)? = null

        /// Слушатель раскладки уведомления.
        ///
        /// ⚠️ ОБЯЗАТЕЛЕН, А НЕ «ПРИЯТНОЕ ДОПОЛНЕНИЕ». Раскладку задаёт Dart и
        /// присылает её с КАЖДЫМ обновлением счётчиков, то есть раз в секунду.
        /// Без обратной связи кнопка на уведомлении отработала бы ровно до
        /// следующего такта, и со стороны это выглядело бы как «кнопка не
        /// нажимается».
        @Volatile
        var layoutListener: ((compact: Boolean) -> Unit)? = null

        private fun notifyState() {
            stateListener?.invoke(running, lastError, stoppedByUser)
            // Плитка в шторке узнаёт о состоянии ТОЛЬКО пока система её слушает,
            // а слушает она в основном при открытой шторке. Без этой строки
            // туннель, поднятый или снятый из приложения, оставлял плитку в
            // прежнем виде до следующего открытия шторки.
            lol.silentgate.QuickTileService.requestRefresh()
        }
    }

    /// Строки уведомления. Раскладка задана владельцем:
    ///   обычная  — [значок + подписка] / сервер / скорость, с кнопками;
    ///   короткая — [значок + приложение + подписка] / сервер,
    ///              без скорости и без кнопок.
    /// Первая строка уведомления Android — это `subText` рядом со значком, и
    /// имя приложения система дописывает туда сама, поэтому подписка едет
    /// именно в subText: в короткой раскладке это и даёт «приложение · подписка».
    private var noteSub: String? = null
    private var noteServer: String? = null
    private var noteNow: String? = null
    private var noteTotal: String? = null
    private var noteCompact = false

    /// Значок подписки в шторке и путь, из которого он прочитан.
    ///
    /// ⚠️ Держим РАСПАКОВАННУЮ картинку и путь рядом: такт статистики идёт раз
    /// в секунду, и читать файл с диска на каждом обновлении уведомления
    /// значило бы декодировать JPEG шестьдесят раз в минуту впустую.
    private var noteLogo: android.graphics.Bitmap? = null
    private var noteLogoPath: String? = null

    /// Прочитать логотип подписки, если путь изменился.
    ///
    /// Картинка уже лежит на диске (её скачал и закэшировал Dart), поэтому сюда
    /// приходит путь, а не байты: гонять десятки килобайт через канал каждую
    /// секунду незачем.
    private fun setLogo(path: String?) {
        val p = path?.takeIf { it.isNotBlank() }
        if (p == noteLogoPath) return
        noteLogoPath = p
        noteLogo = null
        if (p == null) return
        try {
            // ⚠️ Уменьшаем при чтении. Логотип подписки бывает и 1024×1024, а в
            // шторке он показывается размером с ноготь: полноразмерный Bitmap
            // здесь — это мегабайты в памяти сервиса, который обязан жить
            // сутками.
            val bounds = android.graphics.BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            android.graphics.BitmapFactory.decodeFile(p, bounds)
            val want = 128
            var scale = 1
            while (bounds.outWidth / (scale * 2) >= want &&
                   bounds.outHeight / (scale * 2) >= want) {
                scale *= 2
            }
            val opts = android.graphics.BitmapFactory.Options().apply {
                inSampleSize = scale
            }
            noteLogo = android.graphics.BitmapFactory.decodeFile(p, opts)
        } catch (e: Throwable) {
            // Битый или недочитанный файл не должен мешать уведомлению: без
            // значка оно остаётся полностью рабочим.
            Log.w(logTag, "Логотип подписки не прочитан: $e")
            noteLogo = null
        }
    }

    /**
     * ⚠️ ЭКРАН ПОГАС — ЯДРО МОЖНО ПРИТОРМОЗИТЬ, А НЕ ПЕРЕПОДКЛЮЧАТЬ.
     *
     * У libbox есть `pause()`/`wake()` ровно для этого: при уходе устройства в
     * Doze ядро сворачивает фоновую активность, а при пробуждении
     * восстанавливается САМО — без пересоздания туннеля. Официальный клиент
     * sing-box делает так же.
     *
     * Чего этим избегаем: NekoBox без такой обработки ловит «двадцать секунд
     * переподключения после разблокировки» (их issue #898, закрыт «not
     * planned»), а WireGuard в sing-box отваливался через три минуты после
     * гашения экрана (#3546). То есть без паузы система душит ядро сама, и
     * выглядит это как обрыв связи.
     *
     * Заодно гасим обновление уведомления: такт статистики раз в секунду, а
     * шторку при выключенном экране всё равно никто не видит.
     */
    @Volatile
    private var screenOn = true

    private val lifecycleReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    screenOn = false
                    runCatching { commandServer?.pause() }
                }
                Intent.ACTION_SCREEN_ON -> {
                    screenOn = true
                    runCatching { commandServer?.wake() }
                }
                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    if (Build.VERSION.SDK_INT >= 23 && pm.isDeviceIdleMode) {
                        runCatching { commandServer?.pause() }
                    } else {
                        runCatching { commandServer?.wake() }
                    }
                }
            }
        }
    }
    private var lifecycleRegistered = false

    /**
     * ⚠️ ПОДЪЁМ ЯДЕР ИДЁТ ЗДЕСЬ, А НЕ НА ГЛАВНОМ ПОТОКЕ, И ЭТО НЕ ОПТИМИЗАЦИЯ.
     *
     * `onStartCommand` система вызывает НА ГЛАВНОМ ПОТОКЕ приложения, а внутри
     * него раньше выполнялось всё: `Libbox.setup`, полный старт Xray
     * (`LibXray.invoke(runXrayFromJson)`), полный старт sing-box
     * (`startOrReloadService` → `openTun` → `establish()`) и повторы с
     * `Thread.sleep` до 2,5 с суммарно.
     *
     * Чем это платится ровно в нашем случае. Flutter ждёт vsync через
     * `Choreographer` ГЛАВНОГО потока Android и через него же получает касания:
     * пока главный поток занят, интерфейс не перерисовывается и не реагирует —
     * снаружи это ровно «приложение зависло». Плюс ANR, если в это время
     * пришло событие ввода.
     *
     * И с 1.5.0 эта работа стала заметно дороже: конфиг уходит ядру ВМЕСТЕ со
     * ссылками на гео-базы (до 1.5.0 они вычищались, потому что ядро их всё
     * равно не открывало), а значит Xray на старте разбирает `geoip.dat`
     * (22,5 МБ) и `geosite.dat` (2,2 МБ). На бюджетном телефоне это секунды —
     * и не единожды: каждая смена сети при включённом kill switch присылает
     * ДВА `start` подряд (заглушка и живой конфиг).
     *
     * Поток ОДИН и намеренно: он сохраняет прежний порядок команд. Разложи мы
     * их по пулу — заглушка kill switch могла бы приехать после живого конфига
     * и погасить только что поднятый туннель.
     */
    private val work = java.util.concurrent.Executors.newSingleThreadExecutor { r ->
        Thread(r, "silentgate-vpn").apply { isDaemon = true }
    }

    /**
     * Взаимное исключение подъёма и уборки.
     *
     * Раньше его роль играл сам главный поток: `onStartCommand` и `onDestroy`
     * приходят на него и не могли пересечься. Теперь подъём идёт на [work], а
     * `onDestroy`/`onRevoke` по-прежнему на главном — без замка они разошлись
     * бы посреди `startOrReloadService`.
     */
    private val lifecycleLock = Any()

    private var commandServer: CommandServer? = null
    private var coreLog: java.io.File? = null
    private var xrayRunning = false
    private var tunFd: ParcelFileDescriptor? = null
    private var interfaceListener: InterfaceUpdateListener? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    private val connectivity: ConnectivityManager
        get() = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            // ⚠️ РАСКЛАДКУ МЕНЯЕМ, НЕ ТРОГАЯ ТУННЕЛЬ. Это ровно кнопка на самом
            // уведомлении: на телефоне оно всплывает поверх экрана и закрывает
            // заголовок — из настроек до тумблера в этот момент не добраться,
            // потому что уведомление закрывает и настройки тоже.
            //
            // Выбор запоминаем там же, где остальные настройки Flutter, чтобы
            // он совпал с тумблером в приложении и пережил перезапуск.
            ACTION_TOGGLE_COMPACT -> {
                noteCompact = !noteCompact
                updateNotification(strings().getString(R.string.vpn_connected))
                layoutListener?.invoke(noteCompact)
                return START_STICKY
            }
            ACTION_STOP -> {
                // ⚠️ В ту же очередь, что и подъём: иначе «Отключить» из шторки
                // могло бы обогнать ещё не доработавший старт и снять туннель,
                // который через миг поднимется заново.
                // ⚠️ ПРИЗНАК БЕРЁМ ИЗ ИНТЕНТА, А НЕ СТАВИМ БЕЗУСЛОВНО.
                // Раньше здесь стояло `stoppedByUser = true` — и любая наша
                // собственная остановка (переподключение после обрыва, смена
                // сервера, правка настроек) выдавала себя за нажатие кнопки в
                // шторке. Dart на такое честно отменял восстановление.
                val byUser = intent?.getBooleanExtra(EXTRA_BY_USER, false) ?: false
                work.execute {
                    // Пометить ДО остановки: `stopTunnel` шлёт состояние наружу,
                    // и признак должен уехать вместе с ним.
                    stoppedByUser = byUser
                    stopTunnel()
                    stopSelf()
                }
                return START_NOT_STICKY
            }
            else -> {
                // ⚠️ ПУСТОЙ КОНФИГ — ЭТО НОРМАЛЬНЫЙ СТАРТ ОТ СИСТЕМЫ, А НЕ ОШИБКА.
                //
                // При включённой «Постоянной VPN» Android поднимает сервис сам:
                // после перезагрузки, до разблокировки экрана, и конфига в
                // интенте нет по определению — система его не знает. Раньше
                // ветка ниже просто гасила сервис с «Пустой конфиг», то есть
                // постоянная VPN не работала ВООБЩЕ. А приложение при этом само
                // предлагает её включить; с галочкой «блокировать без VPN»
                // телефон оставался без интернета после каждой перезагрузки —
                // и починить это можно было только руками, из настроек системы.
                var config = intent?.getStringExtra(EXTRA_CONFIG)
                var xrayRestored: String? = null
                if (config.isNullOrBlank()) {
                    val saved = loadSessionForAlwaysOn()
                    if (saved != null) {
                        config = saved.first
                        xrayRestored = saved.second
                        Log.i(logTag, "Постоянная VPN: поднимаю сессию из сохранённого конфига")
                    }
                }
                if (config.isNullOrBlank()) {
                    // Сохранённой сессии нет — значит успешного подключения на
                    // этом устройстве ещё не было. Восстанавливать нечего.
                    //
                    // ⚠️ УВЕДОМЛЕНИЕ ПОКАЗЫВАЕМ ДАЖЕ РАДИ НЕМЕДЛЕННОЙ ОСТАНОВКИ.
                    // Система запускает нас через `startForegroundService`, и
                    // контракт требует показать уведомление в первые секунды —
                    // ИНАЧЕ ANDROID УБИВАЕТ ПРОЦЕСС с
                    // `RemoteServiceException: Context.startForegroundService()
                    // did not then call Service.startForeground()`. Поймано
                    // прогоном на эмуляторе 18.08.2026: ветка отказа звала
                    // `stopSelf()` напрямую, и вместо понятного сообщения
                    // пользователь получал падение приложения — при этом ровно
                    // в том случае, когда постоянная VPN включена, а сессии
                    // ещё нет, то есть после первой же перезагрузки телефона.
                    runCatching {
                        startForeground(
                            NOTIFICATION_ID,
                            buildNotification(
                                strings().getString(R.string.vpn_always_on_no_session)),
                        )
                    }
                    lastError = "Постоянная VPN: нет сохранённой сессии — подключитесь один раз вручную"
                    notifyState()
                    // Снимаем уведомление вместе с сервисом: висящее «нет
                    // сессии» после ухода сервиса — мусор в шторке.
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    return START_NOT_STICKY
                }
                // ⚠️ УВЕДОМЛЕНИЕ ПУБЛИКУЕМ СИНХРОННО, НА ГЛАВНОМ ПОТОКЕ.
                // `startForegroundService` обязывает показать его в первые
                // секунды, иначе система убьёт процесс
                // (ForegroundServiceDidNotStartInTimeException). Это дешёвая
                // операция — в отличие от подъёма ядер ниже.
                //
                // Условие повторяет развилку в [startTunnel]: перезагрузка
                // живого туннеля (заглушка kill switch) уведомление не трогает,
                // иначе в шторке на миг появлялось бы «Подключение…» вместо
                // «Трафик заблокирован».
                if (!running || commandServer == null) {
                    runCatching {
                        startForeground(
                            NOTIFICATION_ID,
                            buildNotification(strings().getString(R.string.vpn_connecting)),
                        )
                    }
                }
                val xray = intent?.getStringExtra(EXTRA_XRAY_CONFIG) ?: xrayRestored
                work.execute {
                    // ⚠️ СБРОС ЗДЕСЬ, А НЕ ТОЛЬКО В УСПЕШНОЙ ВЕТКЕ startTunnel.
                    //
                    // Признак «остановлено пользователем» ставится на ACTION_STOP,
                    // а снимался лишь тогда, когда туннель ПОДНЯЛСЯ. При неудачном
                    // старте catch звал notifyState() со старым `true`, и
                    // Dart-сторона (проверка byUser стоит выше вывода ошибки)
                    // выбрасывала настоящий текст, подменяя его на «Туннель снят
                    // пользователем из уведомления». Дефект самоподдерживающийся:
                    // любая ошибка в Dart заканчивается cleanup() → 'stop' →
                    // ACTION_STOP, который снова взводит флаг.
                    //
                    // В журнале владельца это выглядело как череда «Подключение по
                    // команде пользователя» → «Туннель снят пользователем», без
                    // единой ошибки, — то есть диагностика велась по логу, из
                    // которого отказы были стёрты.
                    //
                    // ⚠️ Сброс обязан идти В ТОЙ ЖЕ ОЧЕРЕДИ, что и подъём: оставь
                    // мы его на главном потоке, он обогнал бы уже поставленную в
                    // очередь остановку и снял бы её признак.
                    stoppedByUser = false
                    startTunnel(config, xray)
                }
            }
        }
        return START_STICKY
    }

    /**
     * Сказать пользователю, что kill switch держит трафик.
     *
     * ⚠️ Без этого пропавший интернет выглядит поломкой, и самое естественное
     * действие человека — выключить VPN, то есть ровно то, от чего защита и
     * оберегала. Уведомление живёт в шторке и видно при закрытом приложении —
     * именно тогда, когда объяснить некому.
     */
    /// Обновить подпись в шторке (сервер + трафик). Зовётся из Dart.
    fun setDetail(
        sub: String?,
        server: String?,
        nowDown: String?,
        nowUp: String?,
        totalDown: String?,
        totalUp: String?,
        compact: Boolean,
        logoPath: String?,
    ) {
        if (!running) return
        // Экран выключен — обновлять нечего и некому.
        if (!screenOn) return
        noteSub = sub?.takeIf { it.isNotBlank() }
        noteServer = server?.takeIf { it.isNotBlank() }
        // ⚠️ Признак приходит ОТДЕЛЬНЫМ полем, а не выводится из пустой
        // подписки. Прежняя догадка «нет подписки — значит короткая» ломалась
        // сама собой: у подписки без имени обычная раскладка молча становилась
        // короткой, и пользователь терял строку, которую не выключал.
        noteCompact = compact
        setLogo(logoPath)
        // ⚠️ Подписи и стрелки берутся из строковых ресурсов, а не приходят из
        // Dart: только так они следуют выбранному в приложении языку (сервис
        // переживает смерть изолята) и лежат в одном месте, если шрифт
        // устройства снова начнёт рисовать стрелки мусором.
        val res = strings()
        noteNow = if (nowDown != null && nowUp != null)
            res.getString(R.string.vpn_traffic_now, nowDown, nowUp) else null
        noteTotal = if (totalDown != null && totalUp != null)
            res.getString(R.string.vpn_traffic_total, totalDown, totalUp) else null
        // ⚠️ СЧЁТЧИК НЕ ЗАТИРАЕТ СООБЩЕНИЕ О БЛОКИРОВКЕ.
        //
        // Раньше здесь стояла безусловная строка «Подключено», а счётчик трафика
        // тикает раз в секунду — поэтому уведомление «сайт заблокирован» жило
        // меньше секунды и человек его не успевал прочитать. Механизм был, а
        // сообщения не было: ровно тот случай, когда код работает, а
        // пользователь этого не видит.
        updateNotification(noticeTextNow(res))
    }

    /**
     * Что писать в уведомлении прямо сейчас: свежая пометка о блокировке важнее
     * дежурного «Подключено».
     */
    private fun noticeTextNow(ctx: Context): String =
        if (SystemClock.elapsedRealtime() < blockedUntil)
            ctx.getString(R.string.vpn_blocked)
        else
            ctx.getString(R.string.vpn_connected)

    /**
     * До какого момента показывать «сайт заблокирован».
     *
     * ⚠️ Именно СРОК, а не флаг: счётчик трафика обновляет уведомление каждую
     * секунду, и без срока пометку пришлось бы снимать вручную — а снимать её
     * некому, событие блокировки одноразовое.
     */
    private var blockedUntil = 0L

    fun showBlocked() {
        if (!running) return
        // Пять секунд: меньше — не успеть прочитать, больше — пометка переживёт
        // сам повод и будет висеть над уже открывшимся сайтом.
        blockedUntil = SystemClock.elapsedRealtime() + 5_000
        updateNotification(strings().getString(R.string.vpn_blocked))
    }

    /**
     * Состояние СИСТЕМНОЙ защиты: «Постоянная VPN» и «Блокировать соединения без VPN».
     *
     * ⚠️ ЗАЧЕМ ЭТО СПРАШИВАТЬ, ЕСЛИ У НАС ЕСТЬ СВОЙ KILL SWITCH.
     *
     * Наш kill switch перезагружает ядро конфигом-заглушкой: туннель остаётся
     * поднятым, а трафик умирает в `reject`. Это настоящая блокировка — но она
     * держится, ПОКА ЖИВ НАШ СЕРВИС. Стоит системе убить процесс (нехватка
     * памяти, Doze, пользователь смахнул приложение из недавних), и защиты нет
     * вовсе: туннель снимается вместе с сервисом, трафик идёт открыто.
     *
     * Закрывает этот случай только сама Android — «Блокировать соединения без
     * VPN» в системных настройках. Включить её из приложения НЕЛЬЗЯ (это
     * намеренное ограничение платформы: иначе любое приложение могло бы
     * запереть весь трафик устройства). Зато СПРОСИТЬ состояние можно, начиная
     * с Android 10, — и мы обязаны это делать, чтобы не обещать защиту, которой
     * нет.
     *
     * До Android 10 узнать нельзя вовсе: возвращаем `supported = false`, и
     * интерфейс честно говорит «проверить не могу», а не рисует зелёную птицу.
     */
    fun lockdownState(): Map<String, Any> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return mapOf("supported" to false, "alwaysOn" to false, "lockdown" to false)
        }
        return try {
            mapOf(
                "supported" to true,
                "alwaysOn" to isAlwaysOn,
                "lockdown" to isLockdownEnabled,
            )
        } catch (e: Throwable) {
            // На части прошивок геттеры бросают. Молча соврать «включено» здесь
            // было бы худшим из вариантов.
            Log.w(logTag, "Не удалось узнать состояние системной защиты: $e")
            mapOf("supported" to false, "alwaysOn" to false, "lockdown" to false)
        }
    }

    // ── Постоянная VPN: сохранённая сессия ────────────────────────────────────
    //
    // ⚠️ ЗАЧЕМ ВООБЩЕ ХРАНИТЬ КОНФИГ НА ДИСКЕ. При always-on систему не волнует
    // наше приложение: она стартует VpnService сама, после перезагрузки и до
    // разблокировки экрана. Спросить конфиг у Flutter в этот момент нельзя —
    // изолята нет, а поднимать его ради этого значит тянуть весь UI-движок в
    // фон на старте телефона. Файл рядом с остальными данными приложения
    // дешевле и надёжнее.
    //
    // ⚠️ ЭТО СЕКРЕТ. Внутри — учётные данные серверов и пароль локального
    // прокси. Кладём в приватный каталог приложения (`filesDir`), который
    // песочница Android закрывает от других программ, — туда же, где уже лежат
    // подписки. Наружу (в кэш, на общий накопитель, в резервную копию) не
    // выносим.
    private fun alwaysOnDir() = filesDir.resolve("always_on").also { it.mkdirs() }

    private fun saveSessionForAlwaysOn(configJson: String, xrayConfigJson: String?) {
        runCatching {
            val dir = alwaysOnDir()
            dir.resolve("session.json").writeText(configJson)
            val xrayFile = dir.resolve("xray.json")
            // ⚠️ ОТСУТСТВИЕ Xray — ЭТО ТОЖЕ СОСТОЯНИЕ, И ЕГО НАДО ЗАПИСАТЬ.
            // Обычный VLESS поднимает только sing-box, и файла быть не должно.
            // Оставить прошлый — значит на следующей загрузке поднять ядро от
            // ДРУГОГО сервера: сессия сборная, туннель ведёт не туда, куда
            // показывает интерфейс.
            if (xrayConfigJson.isNullOrBlank()) {
                if (xrayFile.exists()) xrayFile.delete()
            } else {
                xrayFile.writeText(xrayConfigJson)
            }
        }.onFailure { Log.w(logTag, "Не удалось сохранить сессию для постоянной VPN: $it") }
    }

    /// Конфиг последней УСПЕШНОЙ сессии и конфиг Xray к нему (или null).
    private fun loadSessionForAlwaysOn(): Pair<String, String?>? = runCatching {
        val dir = alwaysOnDir()
        val session = dir.resolve("session.json")
        if (!session.exists()) return@runCatching null
        val text = session.readText()
        if (text.isBlank()) return@runCatching null
        val xrayFile = dir.resolve("xray.json")
        val xray = if (xrayFile.exists()) xrayFile.readText().takeIf { it.isNotBlank() } else null
        Pair(text, xray)
    }.getOrElse {
        Log.w(logTag, "Не удалось прочитать сохранённую сессию: $it")
        null
    }

    private fun startTunnel(configJson: String, xrayConfigJson: String?) =
        synchronized(lifecycleLock) { startTunnelLocked(configJson, xrayConfigJson) }

    private fun startTunnelLocked(configJson: String, xrayConfigJson: String?) {
        // ⚠️ ПОВТОРНЫЙ start ПОВЕРХ ЖИВОГО СЕРВИСА — это ПЕРЕЗАГРУЗКА, а не
        // второй запуск. Так приходит заглушка kill switch: Dart шлёт `start` с
        // blackhole-конфигом, чтобы туннель ОСТАЛСЯ поднятым, а трафик умирал в
        // reject.
        //
        // Раньше здесь безусловно создавался ВТОРОЙ CommandServer поверх
        // работающего: старый не закрывался (ссылка на него просто затиралась),
        // его clash_api продолжал держать порт, новый бинд падал с «address
        // already in use», исключение уходило в catch — а catch снимает туннель
        // целиком. То есть kill switch делал ровно обратное обещанному: Dart
        // писал в лог «туннель удержан, трафик блокируется», а трафик в этот
        // момент шёл открыто, и цепочка попыток обрывалась.
        if (running && commandServer != null) {
            reloadTunnelLocked(configJson, xrayConfigJson)
            return
        }
        try {
            // ⚠️ `startForeground` ЗДЕСЬ БОЛЬШЕ НЕТ — он переехал в
            // `onStartCommand`, на главный поток. Контракт foreground-сервиса
            // требует показать уведомление в первые секунды после
            // `startForegroundService`, а этот код теперь исполняется в очереди
            // [work] и может начаться позже. Развилка в `onStartCommand`
            // повторяет условие выше: перезагрузку живого туннеля уведомление
            // не трогает.

            // Весь вывод ядра и, главное, паники Go уходят в файл: без этого
            // причина падения не видна нигде — ни в логах приложения, ни на
            // экране. Файл читает экран «Логи».
            // ⚠️ Каталог "SilentGate" обязателен. Dart-сторона (экран «Логи» и
            // отчёт поддержки) читает getApplicationSupportDirectory()/SilentGate,
            // а писали мы уровнем выше — в filesDir. Из-за этого лог ядра не
            // видели НИ экран логов, НИ отчёт: причина падения существовала на
            // диске, но до пользователя не доходила никогда.
            coreLog = filesDir.resolve("SilentGate")
                .also { it.mkdirs() }
                .resolve("singbox.log")
            runCatching { Libbox.redirectStderr(coreLog!!.absolutePath) }

            Libbox.setup(SetupOptions().apply {
                basePath = filesDir.absolutePath
                workingPath = filesDir.resolve("sing-box").also { it.mkdirs() }.absolutePath
                tempPath = cacheDir.absolutePath
                // На Android нужен обход особенности стека Go — иначе часть
                // соединений не поднимается.
                fixAndroidStack = true
            })

            // Панельный профиль «Авто» — это готовый конфиг Xray. Поднимаем
            // его ПЕРЕД туннелем: sing-box сразу начнёт слать трафик в SOCKS,
            // и если Xray там ещё не слушает, первые соединения отвалятся.
            if (!xrayConfigJson.isNullOrBlank()) startXray(xrayConfigJson)

            val server = CommandServer(this, this)
            server.start()
            // ⚠️ Вторым аргументом НЕЛЬЗЯ передавать null: Go-сторона
            // разыменовывает указатель сразу (`options.AutoRedirect` в
            // CommandServer.StartOrReloadService), и nil даёт панику Go —
            // то есть SIGSEGV и смерть процесса, а не Java-исключение.
            // Именно так выглядел «VPN вылетает без следа в логах».
            //
            // Сами списки пакетов оставляем пустыми: единственный источник
            // правды — конфиг (include_package/exclude_package в TUN-инбаунде),
            // и дублировать их здесь значило бы иметь два несогласованных места.
            startOrReloadWithRetry(server, configJson)
            commandServer = server

            running = true
            lastError = null
            // ⚠️ КОНФИГ СОХРАНЯЕМ ПОСЛЕ УСПЕХА — ради «Постоянной VPN».
            // Систему интересует не наше приложение: при always-on она стартует
            // сервис САМА (после перезагрузки, до разблокировки экрана) и НЕ
            // передаёт конфиг. Без сохранённой копии восстанавливать нечего.
            // Пишем только то, что реально поднялось: сохранять заведомо битый
            // конфиг значит обречь каждую загрузку телефона на ту же ошибку.
            saveSessionForAlwaysOn(configJson, xrayConfigJson)
            // Новая сессия — признак прошлой остановки сбрасываем, иначе
            // следующее падение ядра выдало бы себя за нажатие пользователя.
            stoppedByUser = false
            notifyState()
            updateNotification(strings().getString(R.string.vpn_connected))
        } catch (e: Throwable) {
            // Имя класса обязательно: у UnsatisfiedLinkError (не загрузилась
            // libbox.so) и у ошибок конфига message бывает пустым, и без типа
            // сообщение выглядело бы как «ядро не запустилось» без причины.
            val cause = generateSequence(e) { it.cause }.last()
            lastError = buildString {
                append(e::class.java.simpleName)
                e.message?.takeIf { it.isNotBlank() }?.let { append(": ").append(it) }
                if (cause !== e) {
                    append(" <- ").append(cause::class.java.simpleName)
                    cause.message?.takeIf { it.isNotBlank() }?.let { append(": ").append(it) }
                }
                tailOfCoreLog()?.let { append("\n\n").append(it) }
            }
            running = false
            // ⚠️ УБИРАЕМ УВЕДОМЛЕНИЕ ПЕРВЫМ ДЕЙСТВИЕМ. Оно уже опубликовано —
            // `startForeground` обязан отработать в первые секунды
            // `onStartCommand`, иначе система убьёт процесс с
            // ForegroundServiceDidNotStartInTimeException. Значит «не показывать
            // до успеха» не вариант, и остаётся честно снять его при провале.
            // Иначе в шторке висит уведомление о работающем VPN, которого нет, и
            // смахнуть его нельзя: у него setOngoing(true).
            cancelNotification()
            runCatching { notifyState() }
            stopTunnel()
            stopSelf()
        }
    }

    /// Перезагрузка ядра БЕЗ пересоздания сервиса.
    ///
    /// Нотификация, networkCallback и подписка на состояние остаются на месте —
    /// пересоздавать их незачем. Сам tun-интерфейс система заменяет при
    /// повторном `establish()` внутри `openTun`, и делает это без разрыва.
    ///
    /// Xray переподнимается только если конфиг пришёл: заглушка kill switch
    /// присылает один sing-box, и держать при ней живое соединение с VPN-сервером
    /// не нужно.
    /**
     * `startOrReloadService` с повтором на «порт занят».
     *
     * ⚠️ ЗАЧЕМ. Перезагрузка ядра поднимает НОВЫЕ инбаунды раньше, чем ядро
     * успевает отпустить сокеты прежнего экземпляра. Чаще всего спотыкается
     * `probe-in` (10811) — служебный инбаунд для проверки сервисов у кнопки
     * Connect. В журнале владельца это выглядело так:
     *
     *   proxyerror: start inbound/mixed[probe-in]:
     *   listen tcp 127.0.0.1:10811: bind: address already in use
     *
     * и на этом **весь VPN-сервис останавливался** — то есть диагностическое
     * удобство роняло туннель. Цена ожидания в пару сотен миллисекунд
     * несопоставима с ценой обрыва связи, поэтому просто ждём и повторяем.
     *
     * Повторяем ТОЛЬКО на ошибку связывания порта: всё остальное (битый конфиг,
     * недоступное ядро) повтором не лечится, и молчаливые попытки там лишь
     * оттянули бы честный отказ.
     */
    private fun startOrReloadWithRetry(server: CommandServer, configJson: String) {
        var attempt = 0
        while (true) {
            try {
                server.startOrReloadService(configJson, OverrideOptions())
                if (attempt > 0) {
                    Log.i(logTag, "Ядро поднялось с попытки ${attempt + 1}: порт был занят прошлым экземпляром")
                }
                return
            } catch (e: Throwable) {
                val text = generateSequence(e) { it.cause }
                    .mapNotNull { it.message }.joinToString(" | ")
                val portBusy = text.contains("address already in use", ignoreCase = true)
                if (!portBusy || attempt >= 4) throw e
                attempt++
                Thread.sleep(250L * attempt)
            }
        }
    }

    private fun reloadTunnelLocked(configJson: String, xrayConfigJson: String?) {
        try {
            stopXray()
            if (!xrayConfigJson.isNullOrBlank()) startXray(xrayConfigJson)
            commandServer?.let { startOrReloadWithRetry(it, configJson) }
            running = true
            lastError = null
            // Новая сессия — признак прошлой остановки сбрасываем, иначе
            // следующее падение ядра выдало бы себя за нажатие пользователя.
            stoppedByUser = false
            notifyState()
        } catch (e: Throwable) {
            // Неизвестное состояние опаснее честного отказа: туннель мог бы
            // остаться жить со СТАРЫМ конфигом, а Dart считал бы, что применён
            // новый.
            val cause = generateSequence(e) { it.cause }.last()
            lastError = buildString {
                append("Перезагрузка ядра: ").append(e::class.java.simpleName)
                e.message?.takeIf { it.isNotBlank() }?.let { append(": ").append(it) }
                if (cause !== e) append(" <- ").append(cause::class.java.simpleName)
                tailOfCoreLog()?.let { append("\n\n").append(it) }
            }
            running = false
            notifyState()
            stopTunnel()
            stopSelf()
        }
    }

    /// Запускает Xray на локальном SOCKS. Единственный вход в libXray —
    /// `invoke(json)`, ответ приходит JSON-ом с полем success.
    private fun startXray(configJson: String) {
        // Где ядро ищет гео-базы — задаётся в `SilentGateApplication.onCreate`,
        // и только там: рантайм Go копирует окружение процесса ОДИН РАЗ, при
        // загрузке нативной библиотеки. Попытка выставить переменную здесь
        // выглядела правильнее, компилировалась, ничего не ломала — и не
        // работала: ядро продолжало искать базы в /system/bin. Проверено на
        // эмуляторе, не переносить обратно.

        // protect() для сокетов ядра: без него трафик Xray к VPN-серверу
        // вернётся в собственный туннель — петля и мёртвая сеть.
        LibXray.registerDialerController(object : DialerController {
            override fun protectFd(fd: Long): Boolean = protect(fd.toInt())
        })
        val request = JSONObject()
            .put("apiVersion", 1)
            .put("method", "runXrayFromJson")
            .put("payload", JSONObject().put("configJson", configJson))
            .toString()
        val answer = JSONObject(LibXray.invoke(request))
        if (!answer.optBoolean("success", false)) {
            throw IllegalStateException(
                "Xray не запустился: ${answer.optString("error", "без причины")}")
        }
        xrayRunning = true
    }

    private fun stopXray() {
        if (!xrayRunning) return
        xrayRunning = false
        runCatching {
            LibXray.invoke(JSONObject()
                .put("apiVersion", 1)
                .put("method", "stopXray")
                .toString())
        }
    }

    /// Хвост лога ядра — в него попадают и паники Go, перехваченные
    /// redirectStderr.
    /**
     * Хвост лога ядра для текста ошибки.
     *
     * ⚠️ ОГРАНИЧЕНИЙ БЫЛО НЕДОСТАТОЧНО. Раньше читался ВЕСЬ файл
     * (`readLines()`) и брались последние 12 строк — по числу строк, но не по
     * их длине. Ядро умеет писать очень длинные строки, а в логе попадаются и
     * непечатаемые байты: у владельца это дало сплошной блок нечитаемых
     * символов на тысячи знаков. Он уезжал в отчёт поддержки, заслонял всё
     * остальное и раздувал отчёт до десятков сообщений в чате.
     *
     * Теперь читаем только конец файла, режем по длине и вычищаем управляющие
     * символы вместе с ANSI-раскраской.
     */
    private fun tailOfCoreLog(): String? {
        val f = coreLog ?: return null
        return runCatching {
            val maxBytes = 16 * 1024L
            val raw = java.io.RandomAccessFile(f, "r").use { raf ->
                val from = (raf.length() - maxBytes).coerceAtLeast(0L)
                raf.seek(from)
                val buf = ByteArray((raf.length() - from).toInt())
                raf.readFully(buf)
                Pair(String(buf, Charsets.UTF_8), from > 0)
            }
            val ansi = Regex("\\[[0-9;]*[a-zA-Z]")
            val lines = raw.first.lines()
                // Первая строка после смещения почти наверняка обрезана посередине.
                .let { if (raw.second && it.size > 1) it.drop(1) else it }
                .takeLast(12)
                .map { line ->
                    ansi.replace(line, "")
                        .filter { it == '\t' || it.code >= 0x20 }
                        .take(400)
                }
                .filter { it.isNotBlank() }
            if (lines.isEmpty()) null else lines.joinToString("\n").take(4000)
        }.getOrNull()
    }

    /// ⚠️ Под тем же замком, что и подъём: `onDestroy`/`onRevoke` приходят на
    /// ГЛАВНЫЙ поток, а подъём с 1.5.1 идёт в очереди [work] — без замка уборка
    /// разошлась бы с ним посреди `startOrReloadService`.
    private fun stopTunnel() = synchronized(lifecycleLock) { stopTunnelLocked() }

    private fun stopTunnelLocked() {
        try {
            commandServer?.closeService()
        } catch (_: Throwable) {
        }
        try {
            commandServer?.close()
        } catch (_: Throwable) {
        }
        commandServer = null
        stopXray()

        networkCallback?.let {
            try {
                connectivity.unregisterNetworkCallback(it)
            } catch (_: Throwable) {
            }
        }
        networkCallback = null
        if (lifecycleRegistered) {
            runCatching { unregisterReceiver(lifecycleReceiver) }
            lifecycleRegistered = false
        }
        interfaceListener = null

        try {
            tunFd?.close()
        } catch (_: Throwable) {
        }
        tunFd = null

        running = false
        // Уведомление снимаем ПОСЛЕ закрытия commandServer, но ДО notifyState:
        // раньше — рискуем потерять foreground-статус на середине уборки ядра и
        // быть убитыми системой; позже — исключение из notifyState отменило бы
        // снятие вовсе.
        cancelNotification()
        runCatching { notifyState() }
    }

    /**
     * Убрать уведомление ГАРАНТИРОВАННО.
     *
     * ⚠️ Публикуется оно двумя путями — `startForeground` (через системный
     * менеджер сервисов) и `manager.notify` в [updateNotification], — а
     * снималось одним: `stopForeground`. Пережившее уведомление пользователь не
     * может даже смахнуть, потому что у него `setOngoing(true)`. Отсюда жалоба
     * «даже если произошла ошибка включения, он попадает в шторку».
     *
     * Отменять надо оба пути, поэтому здесь и `stopForeground`, и явный
     * `cancel`.
     */
    private fun cancelNotification() {
        runCatching { stopForeground(STOP_FOREGROUND_REMOVE) }
        runCatching {
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(NOTIFICATION_ID)
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        // ⚠️ ЗДЕСЬ ЖДЁМ ЗАМОК НА ГЛАВНОМ ПОТОКЕ, И ЭТО ОСОЗНАННО. Уборка обязана
        // случиться до того, как экземпляр перестанет существовать: недоснятый
        // `CommandServer` держит порты и tun-fd. Хуже от переезда подъёма в
        // очередь [work] не стало — до него ровно эта работа ВСЕГДА шла на
        // главном потоке.
        stopTunnel()
        runCatching { work.shutdown() }
        // Снимаем ссылку ТОЛЬКО если она наша: при быстром пересоздании сервиса
        // новый экземпляр успевает записаться раньше, чем умрёт старый, и
        // безусловное обнуление стёрло бы живой.
        if (instance === this) instance = null
        super.onDestroy()
    }

    /**
     * Система или пользователь отобрали туннель (включили другой VPN, выключили
     * в шторке). Кода-аналога на Windows нет вовсе — это обязательный путь.
     */
    override fun onRevoke() {
        lastError = getString(R.string.vpn_revoked)
        stopTunnel()
        stopSelf()
        super.onRevoke()
    }

    // ── PlatformInterface: сердце интеграции ──────────────────────────────────

    /**
     * Ядро просит туннель. Строим [Builder] по [TunOptions] и отдаём fd.
     *
     * Каждый `addAllowedApplication`/`addDisallowedApplication` обёрнут в
     * try/catch: пакет мог быть удалён после того, как правило создали, и без
     * защиты VPN просто перестал бы подключаться.
     */
    override fun openTun(options: TunOptions): Int {
        val builder = Builder()
            .setSession("SilentGate")
            .setMtu(options.mtu)

        options.inet4Address.forEach { builder.addAddress(it.address(), it.prefix()) }
        options.inet6Address.forEach { builder.addAddress(it.address(), it.prefix()) }

        // ⚠️ Маршруты ставим ВСЕГДА, не глядя на options.autoRoute.
        //
        // `auto_route` в конфиге означает «ядро само правит таблицу маршрутов
        // ОС» — это про Windows/Linux. На Android таблицей владеет система, и
        // мы намеренно не пишем это поле (ядро 1.13 отвергает его для
        // платформенного туннеля). Значит здесь оно ВСЕГДА false — и вся
        // установка маршрутов молча пропускалась.
        //
        // Что это давало вживую: tun0 поднимался, система показывала VPN
        // CONNECTED, свой uid корректно исключался, — но в таблице оставались
        // только собственные подсети туннеля (172.19.0.0/30 и fdfe:…/126).
        // Дефолтного маршрута не было, поэтому В ТУННЕЛЬ НЕ ШЛО НИЧЕГО:
        // запросы уходили напрямую, мимо VPN, а пользователь видел «Подключено».
        // Поймано живым запуском в эмуляторе (`dumpsys connectivity`).
        options.inet4RouteAddress.let { routes ->
            if (routes.hasNext()) {
                routes.forEach { builder.addRoute(it.address(), it.prefix()) }
            } else {
                builder.addRoute("0.0.0.0", 0)
            }
        }
        options.inet6RouteAddress.let { routes ->
            if (routes.hasNext()) {
                routes.forEach { builder.addRoute(it.address(), it.prefix()) }
            } else if (options.inet6Address.hasNext()) {
                builder.addRoute("::", 0)
            }
        }
        // Исключения из маршрутов доступны только с API 33; ниже ядро само
        // раскладывает их в набор покрывающих префиксов.
        if (Build.VERSION.SDK_INT >= 33) {
            options.inet4RouteExcludeAddress.forEach {
                builder.excludeRoute(android.net.IpPrefix(java.net.InetAddress.getByName(it.address()), it.prefix()))
            }
            options.inet6RouteExcludeAddress.forEach {
                builder.excludeRoute(android.net.IpPrefix(java.net.InetAddress.getByName(it.address()), it.prefix()))
            }
        }

        try {
            builder.addDnsServer(options.dnsServerAddress.value)
        } catch (_: Throwable) {
            // Без DNS-сервера приложения пойдут в системный резолвер мимо
            // туннеля — ровно та утечка, которую чинили на Windows.
        }

        // include и exclude НЕЛЬЗЯ смешивать: наличие хотя бы одного allowed
        // уводит всё остальное мимо VPN.
        var perAppApplied = false
        var includeWanted = false
        options.includePackage.forEach { pkg ->
            // Свой пакет в allowed-список не пускаем: он увёл бы трафик самого
            // приложения в собственный туннель (петля и ложные цифры проб).
            if (pkg == packageName) return@forEach
            includeWanted = true
            try {
                builder.addAllowedApplication(pkg)
                perAppApplied = true
            } catch (_: PackageManager.NameNotFoundException) {
            }
        }
        // ⚠️ Список был задан, но НИ ОДИН пакет не установлен (удалили после
        // создания правила, либо он из другого профиля пользователя).
        // Молча уйти в ветку exclude нельзя: политика перевернётся с «в туннель
        // идут только выбранные» на «в туннель идёт ВСЁ, кроме нас» — причём с
        // DNS всей системы через VPN. Это прямо противоположно тому, что просил
        // пользователь, и заметить подмену нечем.
        if (includeWanted && !perAppApplied) {
            throw IllegalStateException(
                "Выбранные приложения не установлены — режим «только выбранные» применить не к чему"
            )
        }
        if (!perAppApplied) {
            // Себя исключаем ТОЛЬКО в этой ветке. Раньше вызов стоял ниже и
            // выполнялся всегда — а addDisallowedApplication после
            // addAllowedApplication бросает UnsupportedOperationException,
            // который здесь не ловился: исключение уходило наверх, openTun
            // не доходил до establish(), и в режиме «только выбранные»
            // туннель не поднимался вообще.
            //
            // При allowed-списке исключать себя и не нужно: в туннель идут
            // ТОЛЬКО перечисленные приложения, все прочие и так снаружи.
            // excludePackage — итератор libbox, не коллекция: сначала собираем.
            val excludes = LinkedHashSet<String>()
            options.excludePackage.forEach { excludes.add(it) }
            excludes.add(packageName)
            excludes.forEach { pkg ->
                try {
                    builder.addDisallowedApplication(pkg)
                } catch (_: PackageManager.NameNotFoundException) {
                } catch (_: UnsupportedOperationException) {
                }
            }
        }

        if (Build.VERSION.SDK_INT >= 29) builder.setMetered(false)

        val pfd = builder.establish() ?: throw IllegalStateException("establish() вернул null")
        // ⚠️ Прежний дескриптор закрываем ПОСЛЕ establish(), а не до. При
        // перезагрузке ядра (заглушка kill switch) openTun вызывается повторно;
        // систему просят заменить интерфейс, и она делает это без разрыва.
        // Закрыть старый ДО establish() значило бы снять туннель на этот миг —
        // то есть открыть ровно то окно утечки, которое kill switch закрывает.
        // Не закрывать вовсе — оставить дескриптор висеть до смерти процесса.
        val previous = tunFd
        tunFd = pfd
        if (previous !== pfd) runCatching { previous?.close() }
        return pfd.fd
    }

    /** `protect(fd)` — анти-петля для сокетов ядра. */
    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    /// До Android 10 `/proc/net` читается, с Android 10 — закрыт.
    ///
    /// ⚠️ Здесь стояло безусловное `false`, и на Android 7-9 правила приложений
    /// не работали ВООБЩЕ: `getConnectionOwnerUid` появился только в API 29, то
    /// есть `findConnectionOwner` ниже на этих версиях бросает исключение, а
    /// запасного пути через `/proc` мы не разрешали. Владельца соединения
    /// определить было нечем — «Блок» молча пропускал трафик, «Прямо» и
    /// «Туннель» не различались. Это четверть поддерживаемого диапазона версий
    /// (minSdk 24).
    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    /**
     * Владелец соединения по uid. Без этого НЕ работают `package_name`-правила,
     * то есть блокировка приложений. Доступно с API 29.
     */
    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        if (Build.VERSION.SDK_INT < 29) throw UnsupportedOperationException("нужен Android 10+")
        val uid = connectivity.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
        if (uid == -1) throw IllegalStateException("владелец соединения не найден")
        val owner = ConnectionOwner()
        owner.userId = uid
        // Список пакетов, а не один: у приложений с общим UID их несколько —
        // ядро само выберет совпадение с правилом.
        val packages = packageManager.getPackagesForUid(uid)?.toList().orEmpty()
        owner.setAndroidPackageNames(StringArray(packages))
        return owner
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val active = connectivity.activeNetwork
        val activeCaps = active?.let { connectivity.getNetworkCapabilities(it) }
        // На Android 11+ перечисление интерфейсов ограничено и может вернуть
        // null; необработанный NPE здесь уходит через JNI в Go и роняет процесс.
        val ifaces = runCatching { JavaNetworkInterface.getNetworkInterfaces() }
            .getOrNull() ?: return InterfaceArray(emptyList())
        val list = ifaces.toList().map { iface ->
            LibboxNetworkInterface().apply {
                name = iface.name
                index = iface.index
                mtu = runCatching { iface.mtu }.getOrDefault(1500)
                // mapNotNull, а не map: непригодная запись отбрасывается, иначе
                // netip.MustParsePrefix на той стороне убьёт процесс.
                addresses = StringArray(iface.interfaceAddresses.mapNotNull { it.cidr() })
                // ⚠️ Здесь стоял `flags = 0`, и это ломало ВЕСЬ исходящий трафик.
                //
                // Поле читает Go как `net.Flags`, где нулевое значение означает
                // «интерфейс административно выключен». sing-box отбирает
                // интерфейсы по флагу up, не находил ни одного и отвечал на
                // каждое соединение:
                //   dial TCP connection: no available network interface
                // Снаружи: туннель поднят, маршруты верные, а наружу не уходит
                // ничего — даже DNS. Поймано живым запуском в эмуляторе, статикой
                // не видно: ошибка появляется только когда ядро реально дозванивается.
                //
                // ⚠️ Биты — СЫРЫЕ линуксовые IFF_*, а НЕ значения Go net.Flags.
                // libbox прогоняет это поле через linkFlags() (копию
                // net.linkFlags), которая сама переводит IFF_* в net.Flags.
                // Отдавать ей уже переведённые значения — значит соврать:
                // совпадает только бит up (0x1), а дальше 4 читается как
                // IFF_DEBUG вместо loopback, 8 — как IFF_LOOPBACK вместо
                // point-to-point (то есть ppp0/rmnet мобильного интернета
                // объявляются петлёй), 16 — как IFF_POINTOPOINT вместо
                // multicast (wlan0 выдаётся за point-to-point).
                // Живой тест этого не поймал: он шёл по wlan0, где случайно
                // совпал единственный бит, который и требовался.
                flags = runCatching {
                    var f = 0
                    if (iface.isUp) f = f or OsConstants.IFF_UP or OsConstants.IFF_RUNNING
                    if (iface.isLoopback) f = f or OsConstants.IFF_LOOPBACK
                    if (iface.isPointToPoint) f = f or OsConstants.IFF_POINTOPOINT
                    if (iface.supportsMulticast()) f = f or OsConstants.IFF_MULTICAST
                    f
                }.getOrDefault(OsConstants.IFF_UP or OsConstants.IFF_RUNNING)
                type = when {
                    activeCaps == null -> Libbox.InterfaceTypeOther
                    activeCaps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                    activeCaps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                    activeCaps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                    else -> Libbox.InterfaceTypeOther
                }
                metered = activeCaps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)?.not() ?: false
                dnsServer = StringArray(emptyList())
            }
        }
        return InterfaceArray(list)
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        interfaceListener = listener
        // NOT_VPN обязателен: без него подъём СВОЕГО туннеля прилетает как
        // «сменилась сеть» и запускает вечный цикл переподключений — грабли,
        // которые на Windows чинили трижды.
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = update(network)
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = update(network)
            override fun onLost(network: Network) {
                listener.updateDefaultInterface("", -1, false, false)
            }

            private fun update(network: Network) {
                val caps = connectivity.getNetworkCapabilities(network) ?: return
                val link = connectivity.getLinkProperties(network) ?: return
                val name = link.interfaceName ?: return
                val index = runCatching { JavaNetworkInterface.getByName(name)?.index ?: -1 }.getOrDefault(-1)
                listener.updateDefaultInterface(
                    name,
                    index,
                    !caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                        !caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET),
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED).not(),
                )
            }
        }
        networkCallback = cb
        if (!lifecycleRegistered) {
            val f = android.content.IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
                if (Build.VERSION.SDK_INT >= 23) {
                    addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
                }
            }
            runCatching { registerReceiver(lifecycleReceiver, f) }
                .onSuccess { lifecycleRegistered = true }
        }
        connectivity.registerNetworkCallback(request, cb)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        networkCallback?.let {
            runCatching { connectivity.unregisterNetworkCallback(it) }
        }
        networkCallback = null
        interfaceListener = null
    }

    override fun underNetworkExtension(): Boolean = false
    override fun includeAllNetworks(): Boolean = false
    override fun clearDNSCache() {}
    // Пустое состояние вместо null: значение уходит в Go через JNI, и null там
    // разыменовывается без проверки.
    override fun readWIFIState(): WIFIState = WIFIState("", "")
    override fun systemCertificates(): StringIterator = StringArray(emptyList())
    override fun localDNSTransport(): LocalDNSTransport? = null
    override fun sendNotification(notification: lol.silentgate.cores.libbox.Notification) {}

    // ── CommandServerHandler ──────────────────────────────────────────────────

    override fun serviceStop() {
        stopTunnel()
        stopSelf()
    }

    override fun serviceReload() {}
    override fun getSystemProxyStatus(): SystemProxyStatus = SystemProxyStatus().apply {
        available = false
        enabled = false
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) {}
    override fun writeDebugMessage(message: String) {}

    // ── Нотификация ───────────────────────────────────────────────────────────

    /**
     * ⚠️ СТРОКИ ШТОРКИ ОБЯЗАНЫ СЛЕДОВАТЬ ЯЗЫКУ ПРИЛОЖЕНИЯ, А НЕ ЯЗЫКУ СИСТЕМЫ.
     *
     * Весь интерфейс переведён на десять языков и выбор языка живёт в настройках
     * приложения. А `getString()` в сервисе берёт локаль СИСТЕМЫ — значит
     * человек, поставивший в приложении русский на англоязычном телефоне,
     * получал бы английское уведомление. Это и есть «выпасть из
     * десятиязычности»: единственное место, которое видно при закрытом
     * приложении, говорило бы не на том языке.
     *
     * Код языка приходит из Dart и ПЕРСИСТИТСЯ: сервис переживает смерть
     * изолята, и в момент обновления уведомления спросить Dart может быть уже
     * не у кого. Пусто — язык системы, как и в самом приложении.
     */
    /// ⚠️ КЭШ, А НЕ МИКРООПТИМИЗАЦИЯ. `strings()` зовётся дважды на каждое
    /// обновление шторки, а обновление идёт РАЗ В СЕКУНДУ, пока идёт трафик и
    /// включён экран. Каждый несохранённый вызов — чтение SharedPreferences плюс
    /// `createConfigurationContext`, то есть новый объект `Resources`. На
    /// бюджетном телефоне это заметная доля главного потока впустую.
    /// Ключ — код языка: сменился язык, пересоберём.
    private var stringsCache: Pair<String, Context>? = null

    /// ⚠️ РАЗБОР ЯЗЫКА ЖИВЁТ В [NativePrefs], А НЕ ЗДЕСЬ. Тот же код нужен
    /// разовому уведомлению об обрыве ([AlertNotice]), которое постится в том
    /// числе БЕЗ сервиса. Две копии одного разбора разошлись бы молча — и
    /// уведомления заговорили бы на разных языках.
    private fun strings(): Context {
        val code = NativePrefs.languageCode(this)
        stringsCache?.let { (cached, ctx) -> if (cached == code) return ctx }
        val ctx = NativePrefs.localized(this)
        stringsCache = code to ctx
        return ctx
    }

    /// Язык, под который канал уведомлений уже заведён. `null` — ещё ни разу.
    ///
    /// ⚠️ Канал пересоздавался на КАЖДОМ обновлении шторки, то есть раз в
    /// секунду: лишний вызов в системный сервис через binder ради имени, которое
    /// меняется только вместе с языком.
    private var channelLang: String? = null

    private fun buildNotification(text: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val res = strings()
        if (Build.VERSION.SDK_INT >= 26) {
            val lang = res.resources.configuration.locales.toLanguageTags()
            if (channelLang != lang) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, res.getString(R.string.vpn_channel_name), NotificationManager.IMPORTANCE_LOW)
                )
                channelLang = lang
            }
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, SilentGateVpnService::class.java)
                .setAction(ACTION_STOP)
                // Настоящее нажатие человека — единственный случай, когда
                // автовосстановление отменять НАДО.
                .putExtra(EXTRA_BY_USER, true),
            // FLAG_UPDATE_CURRENT здесь обязателен и по второй причине: без него
            // Android вернул бы ранее созданный PendingIntent со старыми
            // extras, и признак не доехал бы вовсе.
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        // ⚠️ Код запроса ДРУГОЙ (2, не 1). С одинаковым кодом Android вернул бы
        // тот же PendingIntent, и кнопка сворачивания отключала бы VPN.
        val toggle = PendingIntent.getService(
            this, 2,
            Intent(this, SilentGateVpnService::class.java).setAction(ACTION_TOGGLE_COMPACT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, CHANNEL_ID)
            // Имя берём из ресурсов, а не литералом: бренд ещё может смениться.
            // ⚠️ РАСКЛАДКА ЗАДАНА ВЛАДЕЛЬЦЕМ — не менять «как красивее».
            //
            // Обычная:  [значок + имя подписки] / имя сервера / скорость
            // Короткая: [значок + имя сервера]  / скорость
            //
            // В Android верхняя строка уведомления — это `subText` рядом со
            // значком приложения, а НЕ заголовок. Поэтому подписка (или сервер
            // в короткой раскладке) ставится через setSubText, иначе она
            // оказалась бы второй строкой, а не первой.
            //
            // Пока трафика нет (только подключились), заголовок падает обратно
            // на статус — пустая строка выглядела бы как сломанное уведомление.
            .also { b ->
                // Верхняя строка уведомления Android — это `subText` рядом со
                // значком, причём имя приложения система дописывает туда САМА.
                // Поэтому подписка едет именно в subText: в короткой раскладке
                // это и даёт требуемое «приложение · подписка».
                if (noteSub != null) b.setSubText(noteSub)
                if (noteCompact) {
                    // КОРОТКАЯ: [значок + приложение + подписка] / сервер.
                    // Ни скорости, ни кнопок — так решил владелец: уведомление
                    // должно отвечать на один вопрос «через что я сейчас», а не
                    // быть панелью управления.
                    b.setContentTitle(noteServer ?: res.getString(R.string.app_name))
                } else {
                    // ОБЫЧНАЯ: [значок + подписка] / сервер / скорость.
                    // Пока трафика нет (только подключились), заголовок падает
                    // обратно на статус — пустая строка выглядела бы как
                    // сломанное уведомление.
                    b.setContentTitle(noteServer ?: res.getString(R.string.app_name))
                    // Две строки трафика: «Текущ» и «Всего». В свёрнутом виде
                    // Android показывает одну — поэтому первой идёт текущая
                    // скорость, ради неё в шторку и смотрят.
                    val lines = listOfNotNull(noteNow, noteTotal)
                        .filter { it.isNotBlank() }
                    if (lines.isEmpty()) {
                        b.setContentText(text)
                    } else {
                        b.setContentText(lines.first())
                        if (lines.size > 1) {
                            b.setStyle(Notification.BigTextStyle()
                                .bigText(lines.joinToString(System.lineSeparator())))
                        }
                    }
                }
            }
            .setSmallIcon(R.drawable.ic_stat_vpn)
            // Значок подписки — крупной картинкой справа. Маленький значок
            // остаётся нашим: он живёт в статус-баре и обязан быть
            // одноцветным силуэтом.
            .also { b -> noteLogo?.let { b.setLargeIcon(it) } }
            .setContentIntent(open)
            .setOngoing(true)
            // ⚠️ Кнопки — ТОЛЬКО в обычной раскладке. В короткой владелец
            // просил их убрать: нажатие на само уведомление по-прежнему
            // открывает приложение, а отключить VPN можно плиткой в шторке.
            .also { b ->
                // ⚠️ ЭТА КНОПКА ЕСТЬ В ОБЕИХ РАСКЛАДКАХ, включая короткую, где
                // остальных кнопок нет. Иначе сворачивание было бы дорогой в
                // один конец: свернул — и развернуть уже нечем, кнопки-то
                // убраны. Одна кнопка на переключение туда и обратно.
                b.addAction(Notification.Action.Builder(
                    null,
                    res.getString(
                        if (noteCompact) R.string.vpn_expand else R.string.vpn_collapse),
                    toggle).build())
                if (!noteCompact) {
                    b.addAction(Notification.Action.Builder(
                        null, res.getString(R.string.vpn_disconnect), stop).build())
                    // Вторая кнопка — открыть приложение. Нажатие на само
                    // уведомление делает то же, но кнопка заметнее: на
                    // Android 13+ тело уведомления часто свёрнуто, и виден
                    // только ряд кнопок.
                    b.addAction(Notification.Action.Builder(
                        null, res.getString(R.string.vpn_open), open).build())
                }
            }
            .build()
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }
}

// ── Мелкие адаптеры между Java-коллекциями и итераторами libbox ──────────────

private class StringArray(private val items: List<String>) : StringIterator {
    private var i = 0
    override fun hasNext() = i < items.size
    override fun next() = items[i++]
    override fun len() = items.size
}

private class InterfaceArray(private val items: List<LibboxNetworkInterface>) : NetworkInterfaceIterator {
    private var i = 0
    override fun hasNext() = i < items.size
    override fun next() = items[i++]
}

/// Адрес интерфейса в виде CIDR — БЕЗ зоны IPv6.
///
/// ⚠️ Здесь ядро падало, и вместе с ним всё приложение. `hostAddress` у
/// link-local IPv6 возвращает адрес с зоной (`fe80::ac1d:acff:fe78:b834%dummy0`),
/// а Go разбирает такую строку через `netip.MustParsePrefix`, который на зонах
/// делает panic:
///
///   panic: netip.ParsePrefix("fe80::…%dummy0/64"):
///          IPv6 zones cannot be present in a prefix
///
/// Паника из горутины libbox не ловится ничем на стороне Kotlin — процесс
/// убивается по SIGABRT. Симптом снаружи: нажал «Подключиться», tun0 на
/// мгновение создаётся и тут же исчезает, приложение пропадает с экрана.
/// Link-local IPv6 есть практически на каждом интерфейсе, поэтому VPN не
/// поднимался НИКОГДА. Подтверждено живым запуском в эмуляторе.
/// `null` — запись непригодна и должна быть ОТБРОШЕНА, а не отдана ядру.
///
/// Go разбирает каждый элемент через `netip.MustParsePrefix`, а `Must*` не
/// возвращает ошибку — он паникует, и паника из горутины libbox убивает
/// процесс целиком. Поэтому валидируем здесь, а не надеемся на ту сторону:
/// `hostAddress` бывает `null` (тогда получалась строка «/64»), а
/// `networkPrefixLength` на некоторых интерфейсах приходит 0 или −1.
private fun InterfaceAddress.cidr(): String? {
    val addr = (address.hostAddress ?: return null).substringBefore('%')
    if (addr.isEmpty()) return null
    val prefix = networkPrefixLength.toInt()
    if (prefix < 0 || prefix > 128) return null
    return "$addr/$prefix"
}

private inline fun lol.silentgate.cores.libbox.RoutePrefixIterator.forEach(action: (RoutePrefix) -> Unit) {
    while (hasNext()) action(next())
}

private inline fun StringIterator.forEach(action: (String) -> Unit) {
    while (hasNext()) action(next())
}
