import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/xray/override_normalizer.dart';

/// Доезжают ли креды локального прокси ДО КОНФИГА — а не только до полей движка.
///
/// ⚠️ ЗАЧЕМ ПРОВЕРЯТЬ ИМЕННО СОБРАННЫЙ КОНФИГ.
///
/// Пароль на локальных инбаундах включили по умолчанию, и появился целый выводок
/// дефектов одного вида: движок креды выдал, а потребитель их не запросил.
/// Каждый раз это выглядело одинаково — «Подключено» и НОЛЬ трафика, потому что
/// ядро отвечает `407`, а наверх это никак не всплывает.
///
/// Нашлись сразу четыре: туннель на Windows шёл в SOCKS Xray без пароля;
/// запасной DNS-форвардер — тоже; сквозная проверка канала получала 407 и
/// объявляла исправный туннель мёртвым; `ProxyProbe` на Windows вовсе не
/// получал кредов, и сервис-чипы упирались в 407 молча.
///
/// Проверка «поле движка заполнено» ни одного из них не поймала бы: поле-то
/// заполнено. Ловит только вопрос «а что в итоговом JSON».
void main() {
  Map<String, dynamic> decode(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  List<Map<String, dynamic>> outbounds(Map<String, dynamic> cfg) =>
      (cfg['outbounds'] as List).cast<Map<String, dynamic>>();

  group('Туннель → SOCKS Xray', () {
    test('с кредами outbound proxy несёт логин и пароль', () {
      // Именно тот дефект, что ломал панельные профили на Windows: конфиг
      // туннеля собирался без кредов, и весь трафик упирался в 407.
      final cfg = decode(const SingboxConfigBuilder(
        xraySocksPort: 10808,
        xraySocksUser: 'sg',
        xraySocksPassword: 'secret',
      ).buildJson(const SplitTunnelConfig(mode: SplitMode.all)));

      final proxy = outbounds(cfg).firstWhere((o) => o['tag'] == 'proxy');
      expect(proxy['type'], 'socks');
      expect(proxy['username'], 'sg',
          reason: 'без логина ядро ответит 407, а туннель будет выглядеть живым');
      expect(proxy['password'], 'secret');
    });

    test('без кредов полей нет вовсе — а не пустые строки', () {
      // Пустые username/password ядро трактует как попытку аутентификации и
      // отвергает соединение: «пусто» и «нет поля» тут не одно и то же.
      final cfg = decode(const SingboxConfigBuilder(xraySocksPort: 10808)
          .buildJson(const SplitTunnelConfig(mode: SplitMode.all)));
      final proxy = outbounds(cfg).firstWhere((o) => o['tag'] == 'proxy');
      expect(proxy.containsKey('username'), isFalse);
      expect(proxy.containsKey('password'), isFalse);
    });
  });

  group('Инбаунды панельного профиля', () {
    String panel() => jsonEncode({
          'inbounds': [
            {
              'tag': 'socks',
              'protocol': 'socks',
              'port': 1080,
              'listen': '127.0.0.1',
              'settings': {'auth': 'noauth'},
            },
            {
              'tag': 'http',
              'protocol': 'http',
              'port': 1081,
              'listen': '127.0.0.1',
              'settings': const <String, dynamic>{},
            },
          ],
          'outbounds': [
            {'tag': 'proxy', 'protocol': 'freedom'},
          ],
        });

    test('оба инбаунда закрываются паролем', () {
      final norm = normalizeOverridePorts(panel(),
          socksPort: 10808,
          httpPort: 10809,
          socksUser: 'sg',
          socksPassword: 'secret');
      final ins =
          (decode(norm.json)['inbounds'] as List).cast<Map<String, dynamic>>();
      for (final i in ins) {
        final proto = i['protocol'];
        if (proto != 'socks' && proto != 'http') continue;
        final st = (i['settings'] as Map?) ?? const {};
        final accounts = (st['accounts'] as List?) ?? const [];
        expect(accounts, isNotEmpty,
            reason: 'инбаунд ${i['tag']} остался открытым: его увидит и '
                'использует любой локальный процесс');
        expect((accounts.first as Map)['user'], 'sg');
      }
    });

    test('у socks снимается auth: noauth', () {
      // Иначе ядро принимает и то и другое: пароль стоит, но не обязателен —
      // защита, которой на самом деле нет.
      final norm = normalizeOverridePorts(panel(),
          socksPort: 10808,
          httpPort: 10809,
          socksUser: 'sg',
          socksPassword: 'secret');
      final socks = (decode(norm.json)['inbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((i) => i['protocol'] == 'socks');
      expect((socks['settings'] as Map)['auth'], isNot('noauth'));
    });

    test('без кредов инбаунды остаются открытыми — путь системного прокси', () {
      // На Windows в них смотрит WinINET, а он кредов не передаёт: пароль там
      // означал бы 407 на каждый запрос. Фиксируем разницу, чтобы её не
      // «починили» случайно.
      final norm =
          normalizeOverridePorts(panel(), socksPort: 10808, httpPort: 10809);
      final socks = (decode(norm.json)['inbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((i) => i['protocol'] == 'socks');
      final st = (socks['settings'] as Map?) ?? const {};
      expect(st['accounts'], anyOf(isNull, isEmpty));
    });
  });
}
