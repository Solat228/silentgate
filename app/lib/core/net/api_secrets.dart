import 'dart:convert';

import '../geo/sha256.dart';

/// Поля, которых в ответах локального API быть НЕ ДОЛЖНО.
///
/// ⚠️ Явный список, а не «по умолчанию не отдаём». Креды локального прокси
/// лежат в глобальных статиках процесса, а последний сегмент URL подписки у
/// Remnawave — это секрет: «отдать состояние» без списка означало бы отдать
/// ключ от туннеля и от подписки одним GET-запросом.
///
/// ⚠️ Живёт в `core/net/`, а не в `state/api_handlers.dart` (где список был
/// раньше), НАРОЧНО: барьер обязан стоять там, где ответ реально уходит в
/// сокет (`LocalApiServer._write`), иначе он проверяет только то, что сам
/// обработчик СОБРАЛСЯ отдать, а не то, что ушло по факту — и новый эндпоинт,
/// забытый в обработчике, обошёл бы проверку молча (раунд ревью 1, находка 1:
/// список раньше вызывался ТОЛЬКО из теста, ни разу — из рантайма).
const apiSecretMarkers = <String>[
  'apiToken',
  'localProxyPassword',
  'localProxyUser',
  'subscriptionUrl',
  'rawJsonOverride',
  'rawPanelConfig',
];

/// Схемы ключей сервера. Ключ — share-ссылка с адресом и кредами (uuid,
/// пароль), в ответ API он не уходит НИКОГДА (аудит 25.10.2026, F).
const apiServerKeySchemes = <String>[
  'vless://',
  'vmess://',
  'trojan://',
  'ss://',
  'hysteria2://',
  'hy2://',
  'tuic://',
  'panel://',
  'json://',
];

/// Непрозрачный устойчивый id сервера для API вместо его ключа.
///
/// Тот же ключ — тот же id, поэтому скрипт может запомнить его между
/// запусками. Обратно из id ключ не восстановить.
String apiServerId(String key) =>
    'srv-${Sha256.ofBytes(utf8.encode(key)).substring(0, 16)}';

/// Бросает [StateError], если в сериализованном ответе встретилось запрещённое.
void assertNoSecrets(String json) {
  for (final m in apiSecretMarkers) {
    if (json.contains(m)) {
      throw StateError('В ответе API запрещённое поле: $m');
    }
  }
  for (final m in apiServerKeySchemes) {
    if (json.contains(m)) {
      throw StateError('В ответе API ключ сервера ($m…)');
    }
  }
}
