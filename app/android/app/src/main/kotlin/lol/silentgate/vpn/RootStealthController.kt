package lol.silentgate.vpn

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Process
import android.util.Log
import lol.silentgate.BuildConfig
import java.util.concurrent.TimeUnit

/**
 * Контроллер режима `ROOT-Stealth` (сборка `--flavor stealth`).
 *
 * Решает три задачи антидетекта на Android:
 *  1. **Скрытие из `queryIntentServices("android.net.VpnService")`:**
 *     В манифесте `src/stealth/AndroidManifest.xml` компонент [SilentGateVpnService]
 *     по умолчанию выключен (`android:enabled="false"`), поэтому сканеры Ozon,
 *     Wildberries, MAX и банков при опросе `PackageManager.queryIntentServices`
 *     с флагами по умолчанию (`0`) не видят установленный VPN-сервис.
 *     Перед запуском туннеля без root (или в режиме совместимости) компонент
 *     включается динамически через [setVpnComponentEnabled], а после остановки
 *     снова выключается.
 *  2. **Блокировка сканирования локальных портов (`127.0.0.1:10808..10999`):**
 *     При наличии `su` выставляет правило `iptables` / `ip6tables` с модулем
 *     `-m owner ! --uid-owner <uid> -j REJECT --reject-with tcp-reset` на `lo`,
 *     чтобы любое стороннее приложение при прощупывании портов SOCKS5/HTTP/API
 *     получало мгновенный `TCP RST` (как от закрытого порта), тогда как сам
 *     процесс SilentGate общается со своими ядрами штатно.
 *  3. **Безопасный откат без root:**
 *     Если `su` недоступен или пользователь отказал в правах суперпользователя,
 *     приложение продолжает работать через штатный движок без падений.
 */
object RootStealthController {
    private const val TAG = "SilentGateStealth"
    private const val LOCAL_PORT_RANGE = "10808:10999"

    val isStealthFlavor: Boolean
        get() = BuildConfig.FLAVOR == "stealth"

    @Volatile
    var rootAvailableCached: Boolean? = null
        private set

    /** Проверить наличие рабочего `su` (не блокируя UI-поток надолго). */
    fun checkRootAvailable(): Boolean {
        rootAvailableCached?.let { return it }
        val ok = runCatching {
            val proc = ProcessBuilder("su", "-c", "id -u")
                .redirectErrorStream(true)
                .start()
            val finished = proc.waitFor(2500, TimeUnit.MILLISECONDS)
            if (!finished) {
                proc.destroyForcibly()
                false
            } else {
                val out = proc.inputStream.bufferedReader().readText().trim()
                proc.exitValue() == 0 && out.lines().any { it.trim() == "0" }
            }
        }.getOrDefault(false)
        rootAvailableCached = ok
        return ok
    }

    /**
     * Динамически включить или скрыть [SilentGateVpnService] в `PackageManager`.
     */
    fun setVpnComponentEnabled(context: Context, enabled: Boolean) {
        if (!isStealthFlavor) return
        runCatching {
            val cn = ComponentName(context, SilentGateVpnService::class.java)
            val targetState = if (enabled) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            val pm = context.packageManager
            if (pm.getComponentEnabledSetting(cn) != targetState) {
                pm.setComponentEnabledSetting(
                    cn,
                    targetState,
                    PackageManager.DONT_KILL_APP,
                )
            }
        }.onFailure {
            Log.w(TAG, "setVpnComponentEnabled($enabled) failed: $it")
        }
    }

    /**
     * Вызывается перед `VpnService.prepare` и стартом сервиса: включает
     * компонент `SilentGateVpnService` (чтобы отработал штатный запуск даже без root)
     * и в фоне ставит root-защиту локальных портов `127.0.0.1:10808..10999`, если
     * `su` доступен.
     */
    fun beforeVpnStart(context: Context) {
        if (isStealthFlavor) {
            setVpnComponentEnabled(context, true)
        }
        val uid = Process.myUid()
        Thread {
            if (checkRootAvailable()) {
                applyLoopbackPortLockdown(uid, enable = true)
            }
        }.start()
    }

    /**
     * Вызывается при остановке VPN: снимает правило `iptables` на `lo` и в сборке
     * `stealth` снова прячет компонент `SilentGateVpnService` от `queryIntentServices`.
     */
    fun afterVpnStop(context: Context) {
        if (isStealthFlavor) {
            setVpnComponentEnabled(context, false)
        }
        val uid = Process.myUid()
        Thread {
            if (rootAvailableCached == true) {
                applyLoopbackPortLockdown(uid, enable = false)
            }
        }.start()
    }

    /**
     * Закрыть локальные порты SilentGate (`10808:10999`) на интерфейсе `lo` от
     * всех чужих UID (`! --uid-owner <uid>`), возвращая `TCP RST`.
     */
    private fun applyLoopbackPortLockdown(uid: Int, enable: Boolean) {
        val cmd = if (enable) {
            """
            for bin in iptables ip6tables; do
              ${'$'}bin -C OUTPUT -o lo -p tcp --dport $LOCAL_PORT_RANGE -m owner ! --uid-owner $uid -j REJECT --reject-with tcp-reset 2>/dev/null || \
              ${'$'}bin -I OUTPUT 1 -o lo -p tcp --dport $LOCAL_PORT_RANGE -m owner ! --uid-owner $uid -j REJECT --reject-with tcp-reset 2>/dev/null
            done
            """.trimIndent()
        } else {
            """
            for bin in iptables ip6tables; do
              ${'$'}bin -D OUTPUT -o lo -p tcp --dport $LOCAL_PORT_RANGE -m owner ! --uid-owner $uid -j REJECT --reject-with tcp-reset 2>/dev/null || true
            done
            """.trimIndent()
        }
        runCatching {
            val proc = ProcessBuilder("su", "-c", cmd)
                .redirectErrorStream(true)
                .start()
            if (!proc.waitFor(3000, TimeUnit.MILLISECONDS)) {
                proc.destroyForcibly()
            }
        }.onFailure {
            Log.w(TAG, "applyLoopbackPortLockdown(enable=$enable) failed: $it")
        }
    }
}
