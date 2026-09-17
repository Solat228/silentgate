import 'dart:io';

/// Идентификация приложения в сети. Держать версию синхронно с `pubspec.yaml`
/// (и с `versionName` в Gradle, когда появится Android-сборка) — паритет
/// стережёт тест `test/app_info_test.dart`.
class AppInfo {
  static const name = 'SilentGate';
  static const version = '1.13.1';

  /// Канал СБОРКИ — свойство конкретного exe/apk, а не то, что можно
  /// прочитать из настроек или манифеста обновлений.
  ///
  /// ⚠️ ПОЧЕМУ ИМЕННО ТАК. Признак беты у уже установленной сборки нельзя
  /// решить полем ответа сервера: манифест приходит уже ПОСЛЕ того, как
  /// человек эту бету поставил, а «О программе» должно честно говорить,
  /// что у него за файл, даже без единого сетевого запроса и даже если
  /// человек ни разу не открывал раздел обновлений. Задаётся на сборке
  /// (`build-exe.bat`/`build-apk.bat` → `--dart-define=SILENTGATE_CHANNEL=beta`),
  /// обычная сборка канал не задаёт вовсе — `String.fromEnvironment` тогда
  /// даёт пустую строку, и `isBeta` остаётся `false`.
  static const channel =
      String.fromEnvironment('SILENTGATE_CHANNEL', defaultValue: '');

  /// Это бета-сборка (см. [channel]).
  static bool get isBeta => channel == 'beta';

  /// Метка платформы в User-Agent. Панель Remnawave сопоставляет только ИМЯ
  /// (правило `user-agent CONTAINS SilentGate`), поэтому суффикс на выбор
  /// формата ответа не влияет — он нужен для аналитики и отчётов поддержки.
  static String get platformTag {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  /// User-Agent запроса подписки: всегда «Имя/версия (платформа)».
  /// Панель (Remnawave) по нему выбирает формат ответа — правило в разделе
  /// Templates → Response Rules сопоставляет имя и отдаёт XRAY_JSON.
  ///
  /// ⚠️ Формат «Имя/версия» обязателен, сверка на панели регистрозависимая:
  /// при отклонении от него придёт base64 вместо XRAY_JSON, и клиент молча
  /// потеряет профили «Авто» и hysteria2-узлы.
  static String get userAgent => '$name/$version ($platformTag)';
}
