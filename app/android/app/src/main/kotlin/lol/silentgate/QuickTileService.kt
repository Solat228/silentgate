package lol.silentgate

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import lol.silentgate.vpn.SilentGateVpnService

/**
 * Плитка быстрых настроек: включить и выключить VPN из шторки.
 *
 * ⚠️ Зачем. Это самый частый способ управлять VPN на телефоне — он есть у всех
 * разобранных клиентов (v2rayNG, NekoBox, Hiddify, официальный sing-box), и его
 * отсутствие заметно сразу: чтобы выключить туннель, приходилось открывать
 * приложение целиком.
 *
 * ## Чего плитка НЕ делает — и почему
 *
 * Включить туннель отсюда напрямую нельзя: для этого нужен конфиг, а он живёт в
 * Dart-состоянии, которое при закрытом приложении не поднято. Поэтому включение
 * идёт через ту же `silentgate://connect`, что и остальное внешнее управление —
 * система сама поднимет приложение. Выключение работает и без интерфейса:
 * сервису достаточно ACTION_STOP.
 *
 * ⚠️ `unlockAndRun` обязателен: на заблокированном экране система не отдаёт
 * плитке право запускать активности, и без обёртки нажатие просто ничего не
 * делало бы — молча, что хуже отсутствия плитки.
 */
@RequiresApi(Build.VERSION_CODES.N)
class QuickTileService : TileService() {

    companion object {
        /**
         * Живой экземпляр, пока система слушает плитку (то есть пока открыта
         * шторка). Вне этого времени `null` — и это нормально.
         */
        @Volatile
        private var listening: QuickTileService? = null

        /**
         * Перерисовать плитку под текущее состояние туннеля.
         *
         * ⚠️ ДВА ПУТИ, И ОДНОГО НЕ ХВАТАЕТ. Плитка живёт не тогда, когда нам
         * удобно, а пока система её слушает ([onStartListening] при открытии
         * шторки, [onStopListening] при закрытии):
         *
         * * шторка ЗАКРЫТА — экземпляра нет, обновлять нечего и некому; нужен
         *   `requestListeningState`, чтобы система подняла сервис и спросила
         *   состояние заново;
         * * шторка ОТКРЫТА — сервис уже слушает, и `requestListeningState`
         *   оказывается пустышкой: повторного `onStartListening` не будет.
         *   Обновить может только сам живой экземпляр.
         *
         * Проверено на эмуляторе: с одним лишь `requestListeningState` плитка
         * после снятия туннеля так и висела «Connected» — при том, что
         * уведомление уже исчезло, а сервис был снят.
         *
         * Зовётся из единственной точки объявления состояния
         * ([lol.silentgate.vpn.SilentGateVpnService.notifyState]), поэтому новые
         * пути включения и выключения получают обновление плитки даром.
         */
        fun requestRefresh() {
            listening?.let { live ->
                // Плитка обновляется только из главного потока: notifyState()
                // прилетает из потока уборки ядра.
                runCatching {
                    android.os.Handler(android.os.Looper.getMainLooper()).post { live.refresh() }
                }
                return
            }
            val ctx = SilentGateApplication.appContext ?: return
            runCatching {
                requestListeningState(
                    ctx,
                    android.content.ComponentName(ctx, QuickTileService::class.java),
                )
            }
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        listening = this
        refresh()
    }

    override fun onStopListening() {
        // Ссылку снимаем обязательно: за неё цепляется сервис, а обновлять
        // плитку, которую система больше не показывает, нельзя — `qsTile` там
        // уже null, и попытка молча ничего не сделает.
        if (listening === this) listening = null
        super.onStopListening()
    }

    override fun onDestroy() {
        if (listening === this) listening = null
        super.onDestroy()
    }

    override fun onClick() {
        super.onClick()
        if (SilentGateVpnService.running) {
            // Выключение не требует интерфейса — гасим сервис напрямую.
            startService(
                Intent(this, SilentGateVpnService::class.java)
                    .setAction(SilentGateVpnService.ACTION_STOP)
            )
            // ⚠️ НЕ вызывать здесь refresh(): остановка асинхронная, и в этот миг
            // `running` ещё true — плитка перерисовалась бы во «включено» поверх
            // выключаемого туннеля. Настоящее состояние придёт из notifyState()
            // сервиса через requestRefresh(), когда туннель действительно снят.
            return
        }
        // Включение требует конфига, а он в Dart-состоянии: поднимаем приложение
        // той же ссылкой, которой пользуется внешнее управление.
        val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse("silentgate://connect"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        unlockAndRun {
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    startActivityAndCollapse(
                        android.app.PendingIntent.getActivity(
                            this, 0, intent,
                            android.app.PendingIntent.FLAG_IMMUTABLE or
                                android.app.PendingIntent.FLAG_UPDATE_CURRENT,
                        )
                    )
                } else {
                    @Suppress("DEPRECATION")
                    startActivityAndCollapse(intent)
                }
            }
        }
    }

    private fun refresh() {
        val tile = qsTile ?: return
        val on = SilentGateVpnService.running
        // ⚠️ Значок у плитки ОДИН на оба состояния и меняться не должен: разницу
        // рисует сама система — активная плитка получает заливку и цвет акцента,
        // неактивная остаётся приглушённой. Подменять здесь значок «на выключен»
        // означало бы драться с оформлением шторки, разным на каждой прошивке.
        // Это НЕ то же самое, что значок в статус-баре: там значка при
        // выключенном VPN нет вовсе, потому что нет и уведомления.
        tile.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(R.string.app_name)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = getString(
                if (on) R.string.vpn_connected else R.string.vpn_tile_off
            )
        }
        tile.updateTile()
    }
}
