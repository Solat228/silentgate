import '../app_store.dart';
import '../settings/app_settings.dart';

/// Согласие на отправку данных устройства провайдеру подписки.
///
/// Что уходит: заголовки `X-HWID` (на Android — ANDROID_ID), `X-Device-OS`,
/// `X-Ver-OS`, `X-Device-Model` при каждом запросе подписки
/// (`core/platform/device_id.dart`). Панели по ним считают устройства
/// (device-limit Remnawave); без них часть провайдеров подписку не отдаст.
///
/// ⚠️ СПРАШИВАЕМ ТОЛЬКО В СБОРКЕ ИЗ GOOGLE PLAY (решение владельца 14.10.2026).
/// Правила Play о данных требуют заметного раскрытия и согласия ДО отправки
/// идентификатора устройства. Пока ответа нет ([AppSettings.deviceInfoConsent]
/// == `null`), заголовки НЕ уходят: подписка, которую обновили на старте до
/// ответа, не должна унести то, на что человек ещё не согласился.
/// Сборка GitHub шлёт заголовки, как раньше.
abstract final class DeviceInfoConsent {
  /// Показать окно согласия: сборка Play, а ответа ещё нет.
  static bool needsAsking(AppSettings s, {AppStore? store}) =>
      (store ?? AppStoreInfo.current) == AppStore.play &&
      s.deviceInfoConsent == null;

  /// Можно ли отправлять данные устройства.
  static bool allowed(AppSettings s, {AppStore? store}) =>
      (store ?? AppStoreInfo.current) != AppStore.play ||
      s.deviceInfoConsent == true;

  /// Заголовки устройства, которые нельзя отправлять без согласия.
  static const Set<String> gatedHeaders = {
    'X-HWID',
    'X-Device-OS',
    'X-Ver-OS',
    'X-Device-Model',
  };

  /// Убрать из [headers] всё, что требует согласия, если его нет.
  static Map<String, String> filter(Map<String, String> headers,
      {required bool allowed}) {
    if (allowed) return headers;
    return {
      for (final e in headers.entries)
        if (!gatedHeaders.contains(e.key)) e.key: e.value,
    };
  }
}
