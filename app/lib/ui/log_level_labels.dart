import '../core/settings/app_settings.dart';
import '../l10n/gen/app_localizations.dart';

/// Подписи уровней журнала — ОДНИ на все экраны.
///
/// ⚠️ ОТДЕЛЬНЫЙ ФАЙЛ, А НЕ ФУНКЦИЯ В ЭКРАНЕ. Уровень ядра правится из двух
/// мест — настроек туннеля и раздела «О программе», — и они правят ОДНО поле.
/// Держи подписи в одном из экранов, и второму пришлось бы импортировать
/// первый (взаимный импорт) либо завести свои слова; второе и случилось бы,
/// а два одинаковых по смыслу переключателя с разными подписями читаются как
/// две разные настройки.
///
/// Слова, а не `warn`/`info`/`debug`: решение «включать ли подробности»
/// принимает тот, кто пришёл в настройки за помощью, и сырые имена уровней
/// ему не говорят ничего.
String appLogLevelLabel(AppLocalizations l, AppLogLevel v) => switch (v) {
      AppLogLevel.warn => l.logLevelWarnLabel,
      AppLogLevel.info => l.logLevelInfoLabel,
      AppLogLevel.debug => l.logLevelDebugLabel,
    };

/// То же для ядра: типы разные, подписи НАРОЧНО те же — это одна шкала.
String singboxLogLevelLabel(AppLocalizations l, SingboxLogLevel v) =>
    switch (v) {
      SingboxLogLevel.warn => l.logLevelWarnLabel,
      SingboxLogLevel.info => l.logLevelInfoLabel,
      SingboxLogLevel.debug => l.logLevelDebugLabel,
    };
