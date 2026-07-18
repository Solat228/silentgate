import 'dart:io';

/// Переменные окружения для запуска изолированной копии приложения (отладка/диагностика),
/// чтобы она не мешала уже установленной рабочей копии.
///
/// * `APPDATA` — задаёт папку данных (`%APPDATA%\SilentGate`), см. [AppPaths].
/// * `SILENTGATE_PORT_OFFSET` — сдвиг локальных портов (single-instance, проброс-харнесс),
///   чтобы копии не конкурировали за порты.
/// * `SILENTGATE_NO_SCHEME=1` — не регистрировать url-схему `silentgate://` в реестре
///   (иначе копия перехватила бы ссылки у установленной версии).
class AppEnv {
  static int get portOffset {
    final v = Platform.environment['SILENTGATE_PORT_OFFSET'];
    return int.tryParse(v ?? '') ?? 0;
  }

  static bool get skipSchemeRegistration =>
      Platform.environment['SILENTGATE_NO_SCHEME'] == '1';

  /// Пометка в UI/логах, что это изолированная копия.
  static bool get isIsolatedCopy => portOffset != 0 || skipSchemeRegistration;
}
