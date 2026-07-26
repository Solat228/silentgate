/// Идентификация приложения в сети. Держать версию синхронно с `pubspec.yaml`.
class AppInfo {
  static const name = 'SilentGate';
  static const version = '1.0.0';

  /// User-Agent запроса подписки: всегда «Имя/версия (платформа)».
  /// Панель (Remnawave) по нему выбирает формат ответа — правило в разделе
  /// Templates → Response Rules сопоставляет имя и отдаёт XRAY_JSON.
  static const userAgent = '$name/$version (Windows)';
}
