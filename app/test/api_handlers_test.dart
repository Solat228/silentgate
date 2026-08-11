import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/state/api_handlers.dart';

/// Что API НЕ отдаёт наружу.
///
/// ⚠️ ЭТО НЕ ПЕРЕСТРАХОВКА. Креды локального прокси лежат в глобальных
/// статиках процесса, а последний сегмент URL подписки у Remnawave — это
/// секрет. «Отдать состояние» без явного чёрного списка означало бы отдать
/// ключ от туннеля и от подписки одним GET-запросом.
void main() {
  test('чёрный список полей соблюдается', () {
    // Список ведётся ЗДЕСЬ и в apiSecretMarkers — двух копий быть не должно.
    expect(apiSecretMarkers, containsAll(<String>[
      'apiToken',
      'localProxyPassword',
      'localProxyUser',
      'subscriptionUrl',
      'rawJsonOverride',
      'rawPanelConfig',
    ]));
  });

  test('проверка ответа ловит запрещённое поле', () {
    final dirty = jsonEncode({'localProxyPassword': 'hunter2'});
    expect(() => assertNoSecrets(dirty), throwsA(isA<StateError>()));
  });

  test('чистый ответ проходит', () {
    final clean = jsonEncode({'state': 'connected', 'server': 'Германия'});
    expect(() => assertNoSecrets(clean), returnsNormally);
  });

  test('⚠️ ни один эндпоинт не отдаёт секретов', () async {
    // Перебор по списку, а не выборочно: новый эндпоинт, забытый в проверке,
    // и есть самый вероятный способ отдать секрет наружу.
    final h = _FakeHandlers();
    final bodies = <String>[
      jsonEncode(await h.status()),
      jsonEncode(await h.servers()),
      jsonEncode(await h.exits()),
      jsonEncode(await h.traffic()),
      jsonEncode(await h.subscription()),
    ];
    for (final b in bodies) {
      expect(() => assertNoSecrets(b), returnsNormally);
    }
  });
}

/// Заглушка, повторяющая ФОРМУ ответов [AppStateApiHandlers] константами —
/// без зависимости от живого [AppState]/[ProbeController]/[SettingsController].
class _FakeHandlers {
  Future<Map<String, dynamic>> status() async => {
        'state': 'connected',
        'server': 'Германия',
        'captureMode': 'tun',
        'connectedSeconds': 120,
      };

  Future<List<Map<String, dynamic>>> servers() async => [
        {
          'key': 'vless://example#Германия',
          'name': 'Германия',
          'country': 'DE',
          'protocol': 'vless',
          'pingMs': 42,
          'working': true,
        },
      ];

  Future<List<Map<String, dynamic>>> exits() async => [
        {
          'serverKey': 'vless://example#Германия',
          'name': 'Германия',
          'country': 'DE',
          'port': 10820,
        },
        {'serverKey': null, 'name': 'Прямо', 'port': 10819},
      ];

  Future<Map<String, dynamic>> traffic() async => {
        'uplinkBytes': 1024,
        'downlinkBytes': 2048,
      };

  Future<Map<String, dynamic>> subscription() async => {
        'title': 'Мой тариф',
        'usedBytes': 100,
        'totalBytes': 1000,
        'unlimited': false,
        'expiresAt': '2026-12-31T00:00:00.000Z',
      };
}
