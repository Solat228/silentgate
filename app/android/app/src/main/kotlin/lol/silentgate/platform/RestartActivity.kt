package lol.silentgate.platform

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Process
import android.os.SystemClock
import java.io.File

/**
 * Перезапуск приложения после импорта настроек (P11).
 *
 * ⚠️ ЗАПУСТИТЬ MAINACTIVITY И ВЫЙТИ ИЗ ПРОЦЕССА — НЕ РАБОТАЕТ. Новая Activity
 * встаёт в ТОТ ЖЕ процесс и умирает вместе с ним: экран гаснет, человек
 * оказывается на рабочем столе, а импорт ждёт, пока приложение откроют руками
 * (живьём в эмуляторе 20.10.2026). А запланировать запуск будильником после
 * выхода нельзя: с Android 10 приложение без видимого окна Activity не
 * запускает.
 *
 * Поэтому — как ProcessPhoenix: эта прозрачная Activity живёт в ОТДЕЛЬНОМ
 * процессе (`:restart` в манифесте). Главный процесс запускает её и выходит;
 * она дожидается его смерти и уже из своего, видимого, процесса открывает
 * приложение заново.
 */
class RestartActivity : Activity() {

    companion object {
        private const val EXTRA_PID = "lol.silentgate.restart.pid"

        /** Сколько ждать, пока главный процесс выйдет сам, прежде чем добить. */
        private const val WAIT_MS = 3_000L

        /** Главный процесс: открыть перезапуск. Выходить — вызывающему. */
        fun start(context: Context): Boolean = try {
            context.startActivity(
                Intent(context, RestartActivity::class.java)
                    .putExtra(EXTRA_PID, Process.myPid())
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (_: Throwable) {
            false
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pid = intent.getIntExtra(EXTRA_PID, -1)
        Thread {
            if (pid > 0) {
                val until = SystemClock.elapsedRealtime() + WAIT_MS
                while (File("/proc/$pid").exists() && SystemClock.elapsedRealtime() < until) {
                    SystemClock.sleep(50)
                }
                // Не вышел сам — добиваем: новая копия рядом со старой делила
                // бы с ней файлы данных.
                if (File("/proc/$pid").exists()) Process.killProcess(pid)
            }
            runOnUiThread {
                packageManager.getLaunchIntentForPackage(packageName)?.let {
                    startActivity(
                        it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                    )
                }
                finish()
                Runtime.getRuntime().exit(0)
            }
        }.start()
    }
}
