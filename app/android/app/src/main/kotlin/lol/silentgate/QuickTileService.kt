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

    override fun onStartListening() {
        super.onStartListening()
        refresh()
    }

    override fun onClick() {
        super.onClick()
        if (SilentGateVpnService.running) {
            // Выключение не требует интерфейса — гасим сервис напрямую.
            startService(
                Intent(this, SilentGateVpnService::class.java)
                    .setAction(SilentGateVpnService.ACTION_STOP)
            )
            refresh()
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
