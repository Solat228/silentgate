import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/probe/auto_config_engine.dart';
import 'package:silentgate/core/settings/app_settings.dart';

void main() {
  group('Каталог сервисов (#6.1)', () {
    test('у всех сервисов есть проба доступности (endpointFor)', () {
      for (final s in ProbeService.values) {
        expect(AutoConfigCatalog.endpointFor(s), isNotNull,
            reason: 'нет endpoint для ${s.name}');
      }
    });

    test('гео-проба только у ИИ-сервисов (geoGated)', () {
      for (final s in ProbeService.values) {
        final geo = AutoConfigCatalog.geoEndpointFor(s);
        expect(geo != null, s.geoGated,
            reason: 'geoGated и наличие гео-пробы разошлись у ${s.name}');
      }
    });

    test('у каждого сервиса есть домен и имя', () {
      for (final s in ProbeService.values) {
        expect(s.label, isNotEmpty);
        expect(s.domain, contains('.'));
      }
    });
  });

  group('Гео-валидаторы', () {
    test('OpenAI: заблокирован только по маркеру unsupported_country', () {
      final geo = AutoConfigCatalog.geoEndpointFor(ProbeService.chatgpt)!;
      expect(geo.blocked(403, '{"error":"unsupported_country"}'), isTrue);
      expect(geo.blocked(200, '{"error":"unsupported_country"}'), isTrue);
      expect(geo.blocked(200, '{"ok":true}'), isFalse);
      // Голый 403 (Cloudflare/WAF/бот-челлендж на доступном регионе) — НЕ гео-блок.
      expect(geo.blocked(403, 'Just a moment... attention required'), isFalse);
    });

    test('Claude/Gemini: 451 или текст, но не голый 403', () {
      final geo = AutoConfigCatalog.geoEndpointFor(ProbeService.claude)!;
      expect(geo.blocked(451, ''), isTrue); // юридический гео-блок
      expect(geo.blocked(200, 'Claude is not available in your country'), isTrue);
      expect(geo.blocked(200, "This app isn't available here"), isTrue);
      expect(geo.blocked(200, 'Welcome to Claude'), isFalse);
      // Голый 403 (rate-limit/челлендж) на доступном регионе — НЕ гео-блок.
      expect(geo.blocked(403, 'cloudflare rate limited'), isFalse);
    });

    test('Gemini: типографская апострофа U+2019 в «isn’t available» ловится', () {
      // Google/Anthropic ставят фигурную апострофу — раньше ASCII-шаблон её не брал.
      final geo = AutoConfigCatalog.geoEndpointFor(ProbeService.gemini)!;
      expect(geo.blocked(200, 'Gemini isn’t available in your country yet'),
          isTrue);
    });
  });

  group('Дефолтный набор сервисов автонастройки (#6.3.1)', () {
    test('по умолчанию — YouTube, ChatGPT, Telegram', () {
      expect(AppSettings.defaults.autoConfigServices, {
        ProbeService.youtube,
        ProbeService.chatgpt,
        ProbeService.telegram,
      });
    });
  });
}
