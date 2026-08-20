package lol.silentgate.vpn

import android.content.Context

/// НАСТРОЙКИ, КОТОРЫЕ НУЖНЫ НАТИВНОМУ СЛОЮ БЕЗ ЖИВОГО DART.
///
/// ⚠️ ЗАЧЕМ ОТДЕЛЬНЫЙ ФАЙЛ. Имя хранилища `silentgate_native` было записано
/// ДВАЖДЫ — константой в сервисе и строковым литералом в `MainActivity`. Пока
/// строки совпадают, всё работает; разъедься они на одну букву — язык молча
/// перестал бы доезжать до уведомления, и заметить это можно было бы только
/// глазами на телефоне с непривычным языком системы. Один источник правды
/// дешевле любой проверки.
object NativePrefs {
    private const val FILE = "silentgate_native"
    private const val LANG = "language_code"

    fun languageCode(context: Context): String =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getString(LANG, "").orEmpty()

    fun setLanguageCode(context: Context, code: String) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
            .putString(LANG, code)
            .apply()
    }

    /// Контекст, у которого `getString` отвечает на языке ПРИЛОЖЕНИЯ.
    ///
    /// ⚠️ ПОЧЕМУ НЕ ПРОСТО `getString`. Он берёт локаль СИСТЕМЫ, а язык
    /// приложения человек выбирает отдельно. Русский интерфейс на англоязычном
    /// телефоне давал бы английское уведомление — то есть единственное место,
    /// которое видно при закрытом приложении, говорило бы не на том языке.
    ///
    /// Пусто — язык системы, ровно как в самом приложении. Ошибка разбора кода
    /// тоже даёт язык системы: уведомление на неродном языке хуже, чем нужное,
    /// но неизмеримо лучше, чем упавшая ветка уведомления.
    fun localized(context: Context): Context {
        val code = languageCode(context)
        if (code.isBlank()) return context
        return runCatching {
            val cfg = android.content.res.Configuration(context.resources.configuration)
            cfg.setLocale(java.util.Locale.forLanguageTag(code))
            context.createConfigurationContext(cfg)
        }.getOrDefault(context)
    }
}
