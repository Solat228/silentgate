package lol.silentgate.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import lol.silentgate.MainActivity
import lol.silentgate.R

/// РАЗОВОЕ УВЕДОМЛЕНИЕ О СОБЫТИИ, ТРЕБУЮЩЕМ ВНИМАНИЯ (обрыв связи и провал
/// восстановления).
///
/// ## Зачем оно понадобилось
///
/// На Windows такое уведомление появилось в 1.3.0, и повод был прямой: сторож
/// канала честно отработал, туннель переподнялся за шесть секунд, карточка в
/// приложении показалась — а владелец написал «на пк я не заметил увед от
/// VPNa». Окно было свёрнуто в трей.
///
/// На телефоне то же самое, только хуже: приложение свёрнуто не «почти
/// всегда», а всегда. До 20.08.2026 обрыв на Android не был виден НИГДЕ, кроме
/// открытого приложения, — `DesktopNotice.show` на не-Windows просто писал
/// строку в журнал. Проверено живьём в эмуляторе: журнал показывал «Системное
/// уведомление показать нечем на этой платформе» ровно в момент разрыва.
///
/// ## ⚠️ ПОЧЕМУ ОТДЕЛЬНЫЙ КАНАЛ, А НЕ ПОСТОЯННОЕ УВЕДОМЛЕНИЕ СЕРВИСА
///
/// Постоянное живёт в канале `silentgate_vpn` с `IMPORTANCE_LOW` — без звука и
/// всплытия, и это НЕ недосмотр: там раз в секунду переписывается строка
/// скорости, и всплывай оно каждый раз, телефон стал бы невыносимым. Понизить
/// важность нельзя (сообщение утонет), повысить нельзя (звук раз в секунду).
/// Поэтому канал второй, с другим идентификатором уведомления.
///
/// ## ⚠️ ПОЧЕМУ ЭТО НЕ МЕТОД СЕРВИСА
///
/// «Восстановить связь не удалось» приходит как раз тогда, когда сервис уже
/// погашен, — то есть в самый важный момент постить было бы некому. Отсюда
/// объект, которому достаточно любого контекста: живой сервис зовёт его собой,
/// `MainActivity` — собой.
object AlertNotice {
    /// ⚠️ ДРУГОЙ КАНАЛ, ЧЕМ У ПОСТОЯННОГО УВЕДОМЛЕНИЯ (`silentgate_vpn`).
    private const val CHANNEL_ID = "silentgate_alerts"

    /// ⚠️ ДРУГОЙ ИДЕНТИФИКАТОР, ЧЕМ У ПОСТОЯННОГО (там 1). С одинаковым наше
    /// сообщение подменило бы строку состояния сервиса — и было бы стёрто
    /// следующим же тактом счётчиков, то есть меньше чем через секунду.
    private const val NOTIFICATION_ID = 2

    /// Язык, под который канал уже заведён. `null` — ещё ни разу.
    /// Пересоздавать канал на каждое уведомление незачем: имя меняется только
    /// вместе с языком.
    private var channelLang: String? = null

    /// Показать. Ошибки глотаются намеренно: уведомление — не то, ради чего
    /// стоит рушить подключение или обработчик канала.
    ///
    /// Тексты приходят из движка готовой строкой — на Android они собираются
    /// там же, где на Windows, и уже переведены не будут (движок не переводит).
    /// Локализуется только ИМЯ КАНАЛА, потому что его показывает система в
    /// настройках уведомлений.
    fun post(context: Context, title: String, body: String) {
        try {
            val app = context.applicationContext
            val manager =
                app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val res = NativePrefs.localized(app)

            if (Build.VERSION.SDK_INT >= 26) {
                val lang = res.resources.configuration.locales.toLanguageTags()
                if (channelLang != lang) {
                    manager.createNotificationChannel(
                        NotificationChannel(
                            CHANNEL_ID,
                            res.getString(R.string.alerts_channel_name),
                            NotificationManager.IMPORTANCE_HIGH,
                        )
                    )
                    channelLang = lang
                }
            }

            // ⚠️ Код запроса 3: 0 и 1 заняты «открыть» и «отключить» у
            // постоянного уведомления, 2 — кнопкой сворачивания. Совпади он —
            // Android вернул бы ЧУЖОЙ PendingIntent, и нажатие на сообщение об
            // обрыве отключало бы VPN.
            val open = PendingIntent.getActivity(
                app, 3, Intent(app, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

            val builder = if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(app, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(app).setPriority(Notification.PRIORITY_HIGH)
            }
            val n = builder
                .setSmallIcon(R.drawable.ic_stat_vpn)
                .setContentTitle(title)
                .setContentText(body)
                // Длинный текст обрезается одной строкой — а у нас там причина
                // обрыва, ради которой уведомление и посылается.
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setContentIntent(open)
                // Разовое: прочитали — исчезло. Иначе шторка копила бы историю
                // всех обрывов за сутки.
                .setAutoCancel(true)
                .build()
            manager.notify(NOTIFICATION_ID, n)
        } catch (_: Throwable) {
            // Нет разрешения на уведомления (Android 13+ и человек отказался),
            // канал заблокирован пользователем, экзотическая прошивка — всё это
            // законные исходы. Молчим: звать логгер отсюда некуда, а падать
            // ради уведомления нельзя.
        }
    }
}
