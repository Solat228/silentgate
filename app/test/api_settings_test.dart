import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';

/// Настройки локального API.
///
/// ⚠️ Класс багов, ради которого этот тест существует: поле пишется в toJson,
/// но не читается в fromJson (или наоборот) — и молча сбрасывается при каждом
/// запуске. Компилятор такое не ловит, потому что toJson и fromJson независимы.
void main() {
  group('Умолчания', () {
    test('API выключен, токена нет, серверов нет', () {
      const s = AppSettings();
      expect(s.apiEnabled, isFalse, reason: 'API обязан быть ВЫКЛ по умолчанию');
      expect(s.apiToken, isEmpty);
      expect(s.apiExitServerKeys, isEmpty);
    });
  });

  group('Переживают диск', () {
    test('все поля API (включая расширенные 1.18.7) возвращаются как есть', () {
      const s = AppSettings(
        apiEnabled: true,
        apiToken: 'abc123',
        apiExitServerKeys: ['vless://a', 'vless://b'],
        apiAssignedPorts: {'vless://a': 10825},
        apiAutoIncludeAutoProfiles: true,
        apiKeepAliveWhenDisconnected: true,
        apiProxyAuthMode: ApiProxyAuthMode.custom,
        apiProxyCustomUser: 'bot',
        apiProxyCustomPassword: 'pw',
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.apiEnabled, isTrue);
      expect(back.apiToken, 'abc123');
      expect(back.apiExitServerKeys, ['vless://a', 'vless://b']);
      expect(back.apiAssignedPorts, {'vless://a': 10825});
      expect(back.apiAutoIncludeAutoProfiles, isTrue);
      expect(back.apiKeepAliveWhenDisconnected, isTrue);
      expect(back.apiProxyAuthMode, ApiProxyAuthMode.custom);
      expect(back.apiProxyCustomUser, 'bot');
      expect(back.apiProxyCustomPassword, 'pw');
    });

    test('старый файл без полей читается умолчаниями', () {
      final back = AppSettings.fromJson({'captureMode': 'tun'});
      expect(back.apiEnabled, isFalse);
      expect(back.apiToken, isEmpty);
      expect(back.apiExitServerKeys, isEmpty);
      expect(back.apiAutoPortEnabled, isTrue);
      expect(back.apiProxyAuthMode, ApiProxyAuthMode.apiToken);
    });
  });

  group('copyWith не теряет поля', () {
    test('правка соседнего поля не сбрасывает настройки API', () {
      const s = AppSettings(
          apiEnabled: true, apiToken: 't', apiExitServerKeys: ['k']);
      final next = s.copyWith(killSwitch: true);
      expect(next.apiEnabled, isTrue);
      expect(next.apiToken, 't');
      expect(next.apiExitServerKeys, ['k']);
    });
  });

  group('Требуют переподключения', () {
    // С версии 1.18.7 порты выходов поднимаются во ВСЕХ режимах захвата
    // (`tun`, `proxyOnly`, `systemProxy` через параллельный `ExitRouter`),
    // поэтому правка настроек портов API требует перезапуска сессии во всех трёх.
    test('все поля портов API названы в reconnectReasons во всех режимах захвата', () {
      for (final mode in CaptureMode.values) {
        final cfg = AppSettings(captureMode: mode);
        expect(cfg.reconnectReasons(cfg.copyWith(apiEnabled: true)),
            contains('API для автоматизации'),
            reason: 'режим $mode');
        expect(cfg.reconnectReasons(cfg.copyWith(apiToken: 'x')),
            contains('токен API'),
            reason: 'режим $mode');
        expect(cfg.reconnectReasons(cfg.copyWith(apiExitServerKeys: ['k'])),
            contains('серверы с отдельным портом'),
            reason: 'режим $mode');
      }
    });

    test('смена самого способа захвата переподключение требует', () {
      const sp = AppSettings(captureMode: CaptureMode.systemProxy);
      expect(sp.reconnectReasons(sp.copyWith(captureMode: CaptureMode.tun)),
          contains('способ захвата'));
    });
  });

  group('apiSettingsChanged — гейт перезапуска локального API '
      '(раунд ревью 1, находка 4)', () {
    // ⚠️ НАРОЧНО НЕ requiresReconnect. Тот триггерится ЛЮБЫМ полем конфига
    // ядра (MTU, DNS, стек, правила...) — использовать его же для решения
    // «перезапускать ли API-сокет» значило бы гасить и поднимать его заново
    // на каждую не связанную с API правку, обрывая тех, кто через него в
    // этот момент работает (`main.dart`, `_ApiSettingsLink.applyIfChanged`).
    const a = AppSettings();

    test('apiEnabled — считается изменением', () {
      expect(a.apiSettingsChanged(a.copyWith(apiEnabled: true)), isTrue);
    });

    test('apiToken — считается изменением', () {
      expect(a.apiSettingsChanged(a.copyWith(apiToken: 'x')), isTrue);
    });

    test('apiExitServerKeys — считается изменением', () {
      expect(
          a.apiSettingsChanged(a.copyWith(apiExitServerKeys: ['k'])), isTrue);
    });

    test('одинаковые настройки — не изменение', () {
      expect(a.apiSettingsChanged(a.copyWith()), isFalse);
    });

    test('⚠️ НЕ связанные с API поля (MTU, тема, правила) — НЕ изменение '
        'для API, хотя requiresReconnect на них сработал бы', () {
      final withMtu = a.copyWith(tunMtu: 1280);
      expect(a.requiresReconnect(withMtu), isTrue,
          reason: 'MTU запекается в конфиг ядра — reconnectReasons обязан '
              'это заметить');
      expect(a.apiSettingsChanged(withMtu), isFalse,
          reason: 'но локальный API-сокет к MTU туннеля отношения не имеет');

      final withKillSwitch = a.copyWith(killSwitch: true);
      expect(a.apiSettingsChanged(withKillSwitch), isFalse);
    });
  });
}
