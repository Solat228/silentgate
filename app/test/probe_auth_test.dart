import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/probe/proxy_probe.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/xray/override_normalizer.dart';

/// Страж против отраслевой дыры: локальный инбаунд проб без пароля.
///
/// Loopback на Android НЕ изолирован между приложениями — к 127.0.0.1:10811
/// подключается любое установленное. А правило `probe-in → proxy` стоит выше
/// пользовательских, включая блок-правила: чужое приложение получало наш VPN
/// целиком, вместе с обходом раздельного туннелирования.
///
/// Второй тест здесь важнее первого: он стережёт ВТОРОЙ конец. У v2rayNG
/// (#5549) аутентификацию включили, а в потребителя прокинуть забыли — вышло
/// «подключено, интернета нет». Поэтому оба конца проверяются вместе.
void main() {
  Map<String, dynamic> tunInbound({String user = '', String password = ''}) {
    final cfg = SingboxConfigBuilder(
      probePort: 10811,
      probeUser: user,
      probePassword: password,
      options: const TunOptions(platformTun: true),
    ).buildMap(const SplitTunnelConfig());
    return (cfg['inbounds'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((i) => i['tag'] == 'probe-in');
  }

  group('Инбаунд проб закрыт паролем', () {
    test('с кредами в конфиг попадает users', () {
      final users = tunInbound(user: 'sg', password: 'secret')['users'] as List;
      expect(users, hasLength(1));
      expect((users.first as Map)['username'], 'sg');
      expect((users.first as Map)['password'], 'secret');
    });

    test('без кред users нет вовсе — иначе ядро отвергнет пустой список', () {
      expect(tunInbound()['users'], isNull);
    });

    test('порт по-прежнему только на петле', () {
      expect(tunInbound(user: 'sg', password: 'x')['listen'], '127.0.0.1');
    });
  });

  group('Клиент проб предъявляет те же креды', () {
    tearDown(() {
      ProxyProbe.user = '';
      ProxyProbe.password = '';
    });

    test('заголовок собирается по схеме Basic', () {
      ProxyProbe.user = 'sg';
      ProxyProbe.password = 'secret';
      final header = ProxyProbe.authHeader;
      expect(header, isNotNull);
      expect(header, startsWith('Basic '));
      final decoded =
          utf8.decode(base64Decode(header!.substring('Basic '.length)));
      expect(decoded, 'sg:secret');
    });

    test('без пароля заголовка нет — на Windows инбаунд открыт намеренно', () {
      expect(ProxyProbe.authHeader, isNull);
    });

    test('непустой пароль без имени заголовка не даёт', () {
      ProxyProbe.password = 'secret';
      expect(ProxyProbe.authHeader, isNull,
          reason: 'признак включённой аутентификации — имя пользователя');
    });
  });

  group('Локальные инбаунды Xray закрыты тем же паролем', () {
    // 10808/10809 поднимаются при панельных профилях «Авто». Без пароля они
    // открыты любому приложению устройства ровно так же, как порт проб.
    String norm({String user = '', String pass = ''}) =>
        normalizeOverridePorts('{"outbounds":[{"protocol":"freedom"}]}',
                socksPort: 10808,
                httpPort: 10809,
                socksUser: user,
                socksPassword: pass)
            .json;

    test('с кредами у socks появляется auth: password и аккаунт', () {
      final cfg = jsonDecode(norm(user: 'sg', pass: 'secret')) as Map;
      final socks = (cfg['inbounds'] as List)
          .cast<Map>()
          .firstWhere((i) => i['protocol'] == 'socks');
      final st = socks['settings'] as Map;
      expect(st['auth'], 'password');
      expect((st['accounts'] as List).first, {'user': 'sg', 'pass': 'secret'});
    });

    test('без кред остаётся noauth — Windows ломать нельзя', () {
      final cfg = jsonDecode(norm()) as Map;
      final socks = (cfg['inbounds'] as List)
          .cast<Map>()
          .firstWhere((i) => i['protocol'] == 'socks');
      expect((socks['settings'] as Map)['auth'], 'noauth');
      expect((socks['settings'] as Map)['accounts'], isNull);
    });

    test('туннель идёт в Xray С ТЕМ ЖЕ паролем — иначе трафик встанет', () {
      final cfg = SingboxConfigBuilder(
        xraySocksPort: 10808,
        xraySocksUser: 'sg',
        xraySocksPassword: 'secret',
        options: const TunOptions(platformTun: true),
      ).buildMap(const SplitTunnelConfig());
      final proxy = (cfg['outbounds'] as List)
          .cast<Map>()
          .firstWhere((o) => o['tag'] == 'proxy');
      expect(proxy['username'], 'sg');
      expect(proxy['password'], 'secret');
    });

    test('без кред socks-outbound их не пишет', () {
      final cfg = SingboxConfigBuilder(
        xraySocksPort: 10808,
        options: const TunOptions(platformTun: true),
      ).buildMap(const SplitTunnelConfig());
      final proxy = (cfg['outbounds'] as List)
          .cast<Map>()
          .firstWhere((o) => o['tag'] == 'proxy');
      expect(proxy.containsKey('username'), isFalse);
    });
  });
}
