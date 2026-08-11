import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/xray/override_normalizer.dart';

/// Что мы открываем на loopback — и с чем.
///
/// ⚠️ ЗАЧЕМ ЭТО СТЕРЕЖЁТСЯ ОТДЕЛЬНО. На Android loopback между приложениями НЕ
/// изолирован: `127.0.0.1:<порт>` виден любому установленному приложению.
/// Детекторы VPN (например RKNHardering) прямо ищут там прокси БЕЗ
/// аутентификации и gRPC API Xray — это отдельные модули проверки. Каждый
/// открытый порт без пароля даёт им попадание, а нам — ничего.
///
/// Ловушка в том, что такой порт ничего не ломает: туннель поднимается,
/// трафик идёт, тесты зелёные. Заметить его можно только специально.
void main() {
  /// Панельный профиль без своей секции статистики — самый частый случай.
  String panelConfig() => jsonEncode({
        'inbounds': [
          {
            'tag': 'socks',
            'protocol': 'socks',
            'port': 10808,
            'listen': '127.0.0.1',
            'settings': {'auth': 'noauth'},
          },
        ],
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'freedom'},
        ],
      });

  List<Map<String, dynamic>> inbounds(String raw) =>
      ((jsonDecode(raw) as Map)['inbounds'] as List).cast<Map<String, dynamic>>();

  group('api-инбаунд Xray', () {
    test('добавляется, когда счётчики оттуда читают (Windows)', () {
      final out = ensureXrayStats(panelConfig(), apiPort: 10085);
      final api = inbounds(out).where((i) => i['tag'] == 'api').toList();
      expect(api, hasLength(1),
          reason: 'без него трафик панельного профиля показывался бы нулём');
      expect(api.single['port'], 10085);
    });

    test('⚠️ он БЕЗ аутентификации — это свойство Xray, а не наша забывчивость',
        () {
      // Зафиксировано намеренно: Xray не поддерживает креды на `api`, поэтому
      // единственная защита — не открывать порт там, где его не читают.
      // Если в будущем Xray научится паролю, этот тест напомнит, что можно
      // перестать гасить инбаунд на Android.
      final out = ensureXrayStats(panelConfig(), apiPort: 10085);
      final api = inbounds(out).firstWhere((i) => i['tag'] == 'api');
      final settings = (api['settings'] as Map?) ?? const {};
      expect(settings.containsKey('accounts'), isFalse);
      expect(settings.containsKey('auth'), isFalse);
    });

    test('повторный вызов не плодит второй инбаунд', () {
      final once = ensureXrayStats(panelConfig(), apiPort: 10085);
      final twice = ensureXrayStats(once, apiPort: 10085);
      expect(inbounds(twice).where((i) => i['tag'] == 'api'), hasLength(1));
    });

    test('занятый порт не отбирается у чужого инбаунда', () {
      // Инбаунд пользователя уже стоит на 10085 — дописывать поверх нельзя,
      // ядро не поднимется вовсе.
      final raw = jsonEncode({
        'inbounds': [
          {'tag': 'mine', 'protocol': 'dokodemo-door', 'port': 10085},
        ],
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'freedom'},
        ],
      });
      final out = ensureXrayStats(raw, apiPort: 10085);
      expect(inbounds(out).where((i) => i['port'] == 10085), hasLength(1));
    });
  });

  group('Локальные инбаунды закрыты кредами', () {
    test('socks и http получают логин с паролем, когда они заданы', () {
      // На Android это единственное, что отделяет наш прокси от любого
      // приложения на телефоне. Детектор засчитывает ТОЛЬКО прокси без
      // аутентификации — то есть по этому признаку мы невидимы, пока креды
      // доезжают.
      final norm = normalizeOverridePorts(
        panelConfig(),
        socksPort: 10808,
        httpPort: 10809,
        socksUser: 'sg',
        socksPassword: 'secret',
      );
      final list = inbounds(norm.json);
      for (final i in list) {
        final proto = i['protocol'];
        if (proto != 'socks' && proto != 'http') continue;
        final s = (i['settings'] as Map?) ?? const {};
        expect(s['accounts'], isNotNull,
            reason: 'инбаунд ${i['tag']} открыт без пароля — на Android его '
                'увидит и использует любое приложение');
      }
    });

    test('без кредов инбаунды остаются открытыми — это путь Windows', () {
      // На Windows в них ходит системный прокси, а WinINET кредов не несёт.
      // Фиксируем разницу явно, чтобы её не «починили» случайно.
      final norm = normalizeOverridePorts(panelConfig(),
          socksPort: 10808, httpPort: 10809);
      final socks =
          inbounds(norm.json).firstWhere((i) => i['protocol'] == 'socks');
      final s = (socks['settings'] as Map?) ?? const {};
      expect(s['accounts'], isNull);
    });
  });
}
