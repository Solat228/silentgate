package lol.silentgate.vpn

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Process
import android.util.Log
import lol.silentgate.BuildConfig
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Контроллер режима `ROOT-Stealth` (сборка `--flavor stealth`, пакет `lol.silentgate.stealth`).
 *
 * Закрывает все 5 векторов детекта VPN российскими приложениями (Госуслуги, Ozon,
 * Wildberries, MAX, банки, АЗС):
 *  1. **Полноценный прозрачный перехват через `su` без `VpnService` (`Root Redirect`):**
 *     Заменяет `tun`-инбаунд `sing-box` на локальный `redirect` (`127.0.0.1:10851`) +
 *     `direct` DNS (`127.0.0.1:10853`) и поднимает сервис [SilentGateStealthService]
 *     без вызова `VpnService.prepare` / `establish()`. В системе нет интерфейса `tun0`,
 *     нет флага `NetworkCapabilities.TRANSPORT_VPN`, нет иконки ключа в статус-баре,
 *     а `SilentGateVpnService` остаётся `android:enabled="false"` даже во время работы.
 *  2. **Поприложенная маршрутизация по UID в `iptables` / `ip6tables`:**
 *     Правила `onlySelected` и `allExcept` применяются прямо на уровне ядра Linux
 *     через `-m owner --uid-owner <uid>` (исключённые банки/Госуслуги/маркетплейсы
 *     идут напрямую через физический `wlan0`/`rmnet` без касания прокси).
 *  3. **Блокировка сканирования локальных портов (`127.0.0.1:10808..10999`):**
 *     Чужие UID получают мгновенный `TCP RST`, как от закрытого порта.
 *  4. **Безопасный автоматический откат без root:**
 *     Если `su` недоступен или пользователь отказал в доступе суперпользователя,
 *     клиент автоматически переключается на классический `SilentGateVpnService`
 *     с динамическим скрытием компонента после остановки.
 */
object RootStealthController {
    private const val TAG = "SilentGateStealth"
    private const val LOCAL_PORT_RANGE = "10808:10999"
    const val REDIRECT_PORT = 10851
    const val DNS_REDIRECT_PORT = 10853

    data class RedirectSessionPlan(
        val configJson: String,
        val includePackages: List<String>,
        val excludePackages: List<String>,
        val bypassLan: Boolean,
    )

    val isStealthFlavor: Boolean
        get() = BuildConfig.FLAVOR == "stealth"

    private val SU_CANDIDATES = listOf(
        "su",
        "/system/bin/su",
        "/system/xbin/su",
        "/sbin/su",
        "/debug_ramdisk/su",
        "/data/adb/ksu/bin/su",
        "/data/adb/ap/bin/su",
    )

    @Volatile
    private var resolvedSuBin: String = "su"

    @Volatile
    var rootAvailableCached: Boolean? = null
        private set

    /**
     * Проверить наличие рабочего `su` (с окном до 15 с на интерактивный диалог
     * выдачи прав в Magisk / KernelSU / APatch при первом обращении).
     * Отрицательный результат навсегда не кэшируется, чтобы включение root в
     * менеджере подхватывалось при следующем нажатии Connect без перезапуска.
     */
    fun checkRootAvailable(forceRefresh: Boolean = false): Boolean {
        if (!forceRefresh && rootAvailableCached == true) {
            return true
        }
        for (candidate in SU_CANDIDATES) {
            if (candidate.startsWith("/") && !java.io.File(candidate).exists()) {
                continue
            }
            val ok = runCatching {
                val proc = ProcessBuilder(candidate, "-c", "id -u")
                    .redirectErrorStream(true)
                    .start()
                val finished = proc.waitFor(15_000, TimeUnit.MILLISECONDS)
                if (!finished) {
                    proc.destroyForcibly()
                    false
                } else {
                    val out = proc.inputStream.bufferedReader().readText().trim()
                    proc.exitValue() == 0 && out.lines().any { it.trim() == "0" }
                }
            }.getOrDefault(false)
            if (ok) {
                resolvedSuBin = candidate
                rootAvailableCached = true
                return true
            }
        }
        rootAvailableCached = false
        return false
    }

    /** Доступен ли полноценный Root-режим без `VpnService` и `tun0`. */
    fun canUseRootRedirect(rootStealthEnabled: Boolean): Boolean {
        if (!isStealthFlavor || !rootStealthEnabled) return false
        return checkRootAvailable()
    }

    /** Динамически включить или скрыть [SilentGateVpnService] в `PackageManager`. */
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
     * Преобразовать TUN-конфиг `sing-box` в без-TUN конфиг `redirect` + `direct` DNS
     * с сохранением всех правил маршрутизации, выходов Xray/Hysteria2/Whitelist и Clash API.
     */
    fun convertTunConfigToRedirect(
        rawConfigJson: String,
        bypassLanDefault: Boolean = true,
    ): RedirectSessionPlan {
        val root = JSONObject(rawConfigJson)
        val includePkgs = mutableListOf<String>()
        val excludePkgs = mutableListOf<String>()

        val oldInbounds = root.optJSONArray("inbounds") ?: JSONArray()
        val newInbounds = JSONArray()
        var replacedTun = false

        for (i in 0 until oldInbounds.length()) {
            val item = oldInbounds.optJSONObject(i) ?: continue
            if (item.optString("type") == "tun") {
                item.optJSONArray("include_package")?.let { arr ->
                    for (j in 0 until arr.length()) {
                        val p = arr.optString(j).trim()
                        if (p.isNotEmpty()) includePkgs.add(p)
                    }
                }
                item.optJSONArray("exclude_package")?.let { arr ->
                    for (j in 0 until arr.length()) {
                        val p = arr.optString(j).trim()
                        if (p.isNotEmpty()) excludePkgs.add(p)
                    }
                }
                val tag = item.optString("tag").ifEmpty { "tun-in" }
                newInbounds.put(
                    JSONObject()
                        .put("type", "redirect")
                        .put("tag", tag)
                        .put("listen", "127.0.0.1")
                        .put("listen_port", REDIRECT_PORT)
                )
                newInbounds.put(
                    JSONObject()
                        .put("type", "direct")
                        .put("tag", "dns-redir-udp")
                        .put("listen", "127.0.0.1")
                        .put("listen_port", DNS_REDIRECT_PORT)
                        .put("network", "udp")
                )
                newInbounds.put(
                    JSONObject()
                        .put("type", "direct")
                        .put("tag", "dns-redir-tcp")
                        .put("listen", "127.0.0.1")
                        .put("listen_port", DNS_REDIRECT_PORT)
                        .put("network", "tcp")
                )
                replacedTun = true
            } else {
                newInbounds.put(item)
            }
        }

        if (!replacedTun) {
            newInbounds.put(
                JSONObject()
                    .put("type", "redirect")
                    .put("tag", "tun-in")
                    .put("listen", "127.0.0.1")
                    .put("listen_port", REDIRECT_PORT)
            )
            newInbounds.put(
                JSONObject()
                    .put("type", "direct")
                    .put("tag", "dns-redir-udp")
                    .put("listen", "127.0.0.1")
                    .put("listen_port", DNS_REDIRECT_PORT)
                    .put("network", "udp")
            )
            newInbounds.put(
                JSONObject()
                    .put("type", "direct")
                    .put("tag", "dns-redir-tcp")
                    .put("listen", "127.0.0.1")
                    .put("listen_port", DNS_REDIRECT_PORT)
                    .put("network", "tcp")
            )
        }
        root.put("inbounds", newInbounds)

        val route = root.optJSONObject("route") ?: JSONObject().also { root.put("route", it) }
        // Сокеты нашего процесса исключены из перехвата по UID в iptables,
        // поэтому auto_detect_interface через VpnService.protect() не нужен.
        route.put("auto_detect_interface", false)

        val oldRules = route.optJSONArray("rules") ?: JSONArray()
        val newRules = JSONArray()
        var dnsHijackInserted = false
        val dnsHijackRule = JSONObject()
            .put("inbound", JSONArray().put("dns-redir-udp").put("dns-redir-tcp"))
            .put("action", "hijack-dns")

        for (i in 0 until oldRules.length()) {
            val r = oldRules.optJSONObject(i) ?: continue
            newRules.put(r)
            if (!dnsHijackInserted && r.optString("action") == "sniff") {
                newRules.put(dnsHijackRule)
                dnsHijackInserted = true
            }
        }
        if (!dnsHijackInserted) {
            val prepended = JSONArray()
            prepended.put(dnsHijackRule)
            for (i in 0 until newRules.length()) {
                prepended.put(newRules.get(i))
            }
            route.put("rules", prepended)
        } else {
            route.put("rules", newRules)
        }

        return RedirectSessionPlan(
            configJson = root.toString(),
            includePackages = includePkgs,
            excludePackages = excludePkgs,
            bypassLan = bypassLanDefault,
        )
    }

    private fun resolvePackageUids(context: Context, packages: Collection<String>): Set<Int> {
        val pm = context.packageManager
        val myPkg = context.packageName
        val out = LinkedHashSet<Int>()
        for (pkg in packages) {
            if (pkg.isBlank() || pkg == myPkg) continue
            runCatching {
                @Suppress("DEPRECATION")
                val info = pm.getApplicationInfo(pkg, 0)
                if (info.uid > 0) out.add(info.uid)
            }
        }
        return out
    }

    /**
     * Атомарно применить правила прозрачного перехвата `iptables`/`ip6tables` для Root-режима.
     */
    fun applyRootTransparentRules(context: Context, plan: RedirectSessionPlan): Boolean {
        val myUid = Process.myUid()
        val includeUids = resolvePackageUids(context, plan.includePackages)
        val excludeUids = resolvePackageUids(context, plan.excludePackages)

        val sb = StringBuilder()
        sb.appendLine("set -e")
        // 1. Сначала гарантированно убираем хвосты прошлых сессий.
        sb.appendLine(cleanupScriptBody(myUid))

        // 2. Цепочка NAT OUTPUT -> SG_STEALTH_NAT -> SG_STEALTH_DO
        sb.appendLine("iptables -w 2 -t nat -N SG_STEALTH_DO 2>/dev/null || iptables -w 2 -t nat -F SG_STEALTH_DO")
        sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_DO -p udp --dport 53 -j REDIRECT --to-ports $DNS_REDIRECT_PORT")
        sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_DO -p tcp --dport 53 -j REDIRECT --to-ports $DNS_REDIRECT_PORT")
        sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_DO -d 127.0.0.0/8 -j RETURN")
        sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_DO -d 169.254.0.0/16 -j RETURN")
        sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_DO -d 224.0.0.0/4 -j RETURN")
        sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_DO -d 255.255.255.255/32 -j RETURN")
        if (plan.bypassLan) {
            sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_DO -d 10.0.0.0/8 -j RETURN")
            sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_DO -d 172.16.0.0/12 -j RETURN")
            sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_DO -d 192.168.0.0/16 -j RETURN")
        }
        sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_DO -p tcp -j REDIRECT --to-ports $REDIRECT_PORT")

        sb.appendLine("iptables -w 2 -t nat -N SG_STEALTH_NAT 2>/dev/null || iptables -w 2 -t nat -F SG_STEALTH_NAT")
        sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_NAT -m owner --uid-owner $myUid -j RETURN")
        sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_NAT -m owner --uid-owner 0 -j RETURN")
        // Системный резолвер netd (UID 1051 = dns / AID_DNS) тоже заворачиваем на порт 53,
        // если не включён строгий список только выбранных приложений.
        if (plan.includePackages.isNotEmpty()) {
            for (uid in includeUids) {
                sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_NAT -m owner --uid-owner $uid -j SG_STEALTH_DO")
            }
            sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_NAT -j RETURN")
        } else {
            for (uid in excludeUids) {
                sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_NAT -m owner --uid-owner $uid -j RETURN")
            }
            sb.appendLine("iptables -w 2 -t nat -A SG_STEALTH_NAT -j SG_STEALTH_DO")
        }
        sb.appendLine("iptables -w 2 -t nat -I OUTPUT 1 -j SG_STEALTH_NAT")

        // 3. Цепочка FILTER OUTPUT (защита локальных портов + отказ QUIC UDP:443 и DoT :853).
        sb.appendLine("iptables -w 2 -t filter -N SG_STEALTH_FLT_DO 2>/dev/null || iptables -w 2 -t filter -F SG_STEALTH_FLT_DO")
        sb.appendLine("iptables -w 2 -t filter -A SG_STEALTH_FLT_DO -p udp --dport 443 -j REJECT")
        sb.appendLine("iptables -w 2 -t filter -A SG_STEALTH_FLT_DO -p udp --dport 853 -j REJECT")
        sb.appendLine("iptables -w 2 -t filter -A SG_STEALTH_FLT_DO -p tcp --dport 853 -j REJECT --reject-with tcp-reset")

        sb.appendLine("iptables -w 2 -t filter -N SG_STEALTH_FLT 2>/dev/null || iptables -w 2 -t filter -F SG_STEALTH_FLT")
        sb.appendLine("iptables -w 2 -t filter -A SG_STEALTH_FLT -o lo -p tcp --dport $LOCAL_PORT_RANGE -m owner ! --uid-owner $myUid -j REJECT --reject-with tcp-reset")
        sb.appendLine("iptables -w 2 -t filter -A SG_STEALTH_FLT -m owner --uid-owner $myUid -j RETURN")
        sb.appendLine("iptables -w 2 -t filter -A SG_STEALTH_FLT -m owner --uid-owner 0 -j RETURN")
        if (plan.includePackages.isNotEmpty()) {
            for (uid in includeUids) {
                sb.appendLine("iptables -w 2 -t filter -A SG_STEALTH_FLT -m owner --uid-owner $uid -j SG_STEALTH_FLT_DO")
            }
        } else {
            for (uid in excludeUids) {
                sb.appendLine("iptables -w 2 -t filter -A SG_STEALTH_FLT -m owner --uid-owner $uid -j RETURN")
            }
            sb.appendLine("iptables -w 2 -t filter -A SG_STEALTH_FLT -j SG_STEALTH_FLT_DO")
        }
        sb.appendLine("iptables -w 2 -t filter -I OUTPUT 1 -j SG_STEALTH_FLT")

        // 4. IPv6: защита портов lo и блокировка утечки IPv6 для туннелируемых UID.
        sb.appendLine("ip6tables -w 2 -t filter -N SG_STEALTH6_DO 2>/dev/null || ip6tables -w 2 -t filter -F SG_STEALTH6_DO")
        sb.appendLine("ip6tables -w 2 -t filter -A SG_STEALTH6_DO -o lo -j RETURN")
        sb.appendLine("ip6tables -w 2 -t filter -A SG_STEALTH6_DO -d fe80::/10 -j RETURN")
        sb.appendLine("ip6tables -w 2 -t filter -A SG_STEALTH6_DO -j REJECT")

        sb.appendLine("ip6tables -w 2 -t filter -N SG_STEALTH6_FLT 2>/dev/null || ip6tables -w 2 -t filter -F SG_STEALTH6_FLT")
        sb.appendLine("ip6tables -w 2 -t filter -A SG_STEALTH6_FLT -o lo -p tcp --dport $LOCAL_PORT_RANGE -m owner ! --uid-owner $myUid -j REJECT --reject-with tcp-reset")
        sb.appendLine("ip6tables -w 2 -t filter -A SG_STEALTH6_FLT -m owner --uid-owner $myUid -j RETURN")
        sb.appendLine("ip6tables -w 2 -t filter -A SG_STEALTH6_FLT -m owner --uid-owner 0 -j RETURN")
        if (plan.includePackages.isNotEmpty()) {
            for (uid in includeUids) {
                sb.appendLine("ip6tables -w 2 -t filter -A SG_STEALTH6_FLT -m owner --uid-owner $uid -j SG_STEALTH6_DO")
            }
        } else {
            for (uid in excludeUids) {
                sb.appendLine("ip6tables -w 2 -t filter -A SG_STEALTH6_FLT -m owner --uid-owner $uid -j RETURN")
            }
            sb.appendLine("ip6tables -w 2 -t filter -A SG_STEALTH6_FLT -j SG_STEALTH6_DO")
        }
        sb.appendLine("ip6tables -w 2 -t filter -I OUTPUT 1 -j SG_STEALTH6_FLT")

        return execRootScript(sb.toString(), timeoutMs = 5000)
    }

    /** Полная очистка всех цепочек `SG_STEALTH*` и снятие блокировки loopback. */
    fun clearRootTransparentRules() {
        if (rootAvailableCached != true) return
        val myUid = Process.myUid()
        execRootScript(cleanupScriptBody(myUid), timeoutMs = 4000)
    }

    private fun cleanupScriptBody(myUid: Int): String = """
        iptables -w 2 -t nat -D OUTPUT -j SG_STEALTH_NAT 2>/dev/null || true
        iptables -w 2 -t nat -F SG_STEALTH_NAT 2>/dev/null || true
        iptables -w 2 -t nat -X SG_STEALTH_NAT 2>/dev/null || true
        iptables -w 2 -t nat -F SG_STEALTH_DO 2>/dev/null || true
        iptables -w 2 -t nat -X SG_STEALTH_DO 2>/dev/null || true
        iptables -w 2 -t filter -D OUTPUT -j SG_STEALTH_FLT 2>/dev/null || true
        iptables -w 2 -t filter -F SG_STEALTH_FLT 2>/dev/null || true
        iptables -w 2 -t filter -X SG_STEALTH_FLT 2>/dev/null || true
        iptables -w 2 -t filter -F SG_STEALTH_FLT_DO 2>/dev/null || true
        iptables -w 2 -t filter -X SG_STEALTH_FLT_DO 2>/dev/null || true
        ip6tables -w 2 -t filter -D OUTPUT -j SG_STEALTH6_FLT 2>/dev/null || true
        ip6tables -w 2 -t filter -F SG_STEALTH6_FLT 2>/dev/null || true
        ip6tables -w 2 -t filter -X SG_STEALTH6_FLT 2>/dev/null || true
        ip6tables -w 2 -t filter -F SG_STEALTH6_DO 2>/dev/null || true
        ip6tables -w 2 -t filter -X SG_STEALTH6_DO 2>/dev/null || true
        for bin in iptables ip6tables; do
          ${'$'}bin -w 2 -D OUTPUT -o lo -p tcp --dport $LOCAL_PORT_RANGE -m owner ! --uid-owner $myUid -j REJECT --reject-with tcp-reset 2>/dev/null || true
        done
    """.trimIndent()

    /**
     * Вызывается перед стартом классического `VpnService` (когда Root Redirect не используется):
     * включает компонент `SilentGateVpnService` и при наличии root закрывает порты `lo`.
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
     * Вызывается при остановке VPN: чистит правила `iptables`, а при наличии
     * root держит `SilentGateVpnService` скрытым (`disabled`). На устройствах
     * без root компонент остаётся включённым, чтобы Android VpnManager не
     * сбрасывал выданное пользователем системное согласие при каждом реконнекте.
     */
    fun afterVpnStop(context: Context) {
        if (isStealthFlavor && rootAvailableCached == true) {
            setVpnComponentEnabled(context, false)
        }
        Thread {
            if (rootAvailableCached == true) {
                clearRootTransparentRules()
            }
        }.start()
    }

    private fun applyLoopbackPortLockdown(uid: Int, enable: Boolean) {
        val cmd = if (enable) {
            """
            for bin in iptables ip6tables; do
              ${'$'}bin -w 2 -C OUTPUT -o lo -p tcp --dport $LOCAL_PORT_RANGE -m owner ! --uid-owner $uid -j REJECT --reject-with tcp-reset 2>/dev/null || \
              ${'$'}bin -w 2 -I OUTPUT 1 -o lo -p tcp --dport $LOCAL_PORT_RANGE -m owner ! --uid-owner $uid -j REJECT --reject-with tcp-reset 2>/dev/null
            done
            """.trimIndent()
        } else {
            cleanupScriptBody(uid)
        }
        execRootScript(cmd, timeoutMs = 3000)
    }

    private fun execRootScript(script: String, timeoutMs: Long): Boolean {
        return runCatching {
            val proc = ProcessBuilder(resolvedSuBin, "-c", script)
                .redirectErrorStream(true)
                .start()
            if (!proc.waitFor(timeoutMs, TimeUnit.MILLISECONDS)) {
                proc.destroyForcibly()
                Log.w(TAG, "Root script timed out after ${timeoutMs}ms")
                false
            } else {
                val ok = proc.exitValue() == 0
                if (!ok) {
                    val out = runCatching { proc.inputStream.bufferedReader().readText() }.getOrDefault("")
                    Log.w(TAG, "Root script exited ${proc.exitValue()}: $out")
                }
                ok
            }
        }.onFailure {
            Log.w(TAG, "execRootScript failed: $it")
        }.getOrDefault(false)
    }
}
