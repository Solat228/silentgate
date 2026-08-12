import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/singbox/singbox_harness_config_builder.dart';
import 'package:silentgate/core/singbox/singbox_proxy_config_builder.dart';
import 'package:silentgate/core/xray/harness_config_builder.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';

/// Локальные порты ядра закрыты паролем НА ВСЕХ ПУТЯХ.
///
/// ⚠️ ЧТО ЗДЕСЬ СТЕРЕЖЁТСЯ И ПОЧЕМУ ЭТО НЕ ПРИДИРКА. Порт 10808/10809 на
/// 127.0.0.1 — это полноценный вход в VPN пользователя: выходной IP, квота
/// подписки и обход его же правил, включая приложения с действием «Блок».
/// Настройка «Пароль на локальный прокси» включена по умолчанию и обещает,
/// что порт закрыт.
///
/// Обещание держалось не везде. Пароль выдавался и уходил ТУННЕЛЮ, а
/// построитель конфига Xray умел только `auth: noauth` — по этому пути идут
/// ВСЕ обычные серверы подписки и режим «Авто (лучший сервер)», то есть
/// подавляющее большинство подключений. Прокси-ядро sing-box (hysteria2) не
/// умело кредов вовсе. Снаружи всё выглядело исправным: подключение проходит,
/// тумблер включён, — а порт открыт любому процессу машины.
///
/// ⚠️ И ТОТ ЖЕ УРОК ПОВТОРИЛСЯ. В 1.3.0 закрыли ДВА пути сборки конфига из
/// ЧЕТЫРЁХ, а этот файл проверял ровно те же два. Про ХАРНЕСС — отдельный
/// экземпляр ядра, который поднимается на время пинга и подбора, — забыли, и
/// его порт 21000+/21500+ оставался открытым входом в туннель весь прогон.
/// Нашлось только ревью, спустя две версии.
///
/// Поэтому ниже проверяются ВСЕ ЧЕТЫРЕ построителя. Появится пятый — добавить
/// его сюда, а не надеяться, что «этот путь не такой».
void main() {
  const vless = VpnServer(
    protocol: 'vless',
    remark: 'srv',
    address: 'example.com',
    port: 443,
    id: '00000000-0000-0000-0000-000000000000',
    rawLink: 'vless://00000000-0000-0000-0000-000000000000@example.com:443#srv',
  );
  const hy2 = VpnServer(
    protocol: 'hysteria2',
    remark: 'hy',
    address: 'hy.example.com',
    port: 443,
    id: 'pass',
    rawLink: 'hysteria2://pass@hy.example.com:443#hy',
  );

  Map<String, dynamic> inboundByTag(Map<String, dynamic> cfg, String tag) =>
      (cfg['inbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((i) => i['tag'] == tag);

  group('Xray: обычный сервер', () {
    test('с кредами socks требует пароль', () {
      final cfg = const XrayConfigBuilder()
          .withAuth('sg', 'secret')
          .buildMap(vless);
      final socks = inboundByTag(cfg, 'socks')['settings'] as Map;
      expect(socks['auth'], 'password');
      expect(socks['accounts'], [
        {'user': 'sg', 'pass': 'secret'}
      ]);
    });

    test('с кредами http требует пароль', () {
      final cfg = const XrayConfigBuilder()
          .withAuth('sg', 'secret')
          .buildMap(vless);
      final http = inboundByTag(cfg, 'http')['settings'] as Map;
      expect(http['accounts'], [
        {'user': 'sg', 'pass': 'secret'}
      ]);
    });

    test('БЕЗ кредов остаётся noauth — это режим системного прокси', () {
      // Не забыть и обратное: в режиме системного прокси пароль ставить
      // НЕЛЬЗЯ. WinINET креденшелов не передаёт, и весь интернет получил бы
      // 407 — то есть «защита» уронила бы связь целиком.
      final cfg = const XrayConfigBuilder().buildMap(vless);
      final socks = inboundByTag(cfg, 'socks')['settings'] as Map;
      expect(socks['auth'], 'noauth');
      expect(socks.containsKey('accounts'), isFalse);
      expect((inboundByTag(cfg, 'http')['settings'] as Map).isEmpty, isTrue);
    });

    test('пустой пароль при заданном логине паролем не считается', () {
      // Полумера опаснее отсутствия: инбаунд с `auth: password` и пустым
      // паролем пускал бы кого угодно, а в интерфейсе стояло бы «закрыт».
      final cfg =
          const XrayConfigBuilder().withAuth('sg', '').buildMap(vless);
      expect((inboundByTag(cfg, 'socks')['settings'] as Map)['auth'], 'noauth');
    });
  });

  group('Xray: «Авто (лучший сервер)»', () {
    test('балансировщик тоже закрывает оба инбаунда', () {
      // Отдельный путь сборки (`buildBalancerMap`), и он про креды не знал.
      final cfg = const XrayConfigBuilder()
          .withAuth('sg', 'secret')
          .buildBalancerMap([vless, vless]);
      expect((inboundByTag(cfg, 'socks')['settings'] as Map)['auth'],
          'password');
      expect((inboundByTag(cfg, 'http')['settings'] as Map)['accounts'], [
        {'user': 'sg', 'pass': 'secret'}
      ]);
    });
  });

  group('sing-box: прокси-ядро hysteria2', () {
    test('оба mixed-инбаунда требуют пароль', () {
      final cfg = const SingboxProxyConfigBuilder(
              user: 'sg', password: 'secret')
          .buildMap([hy2]);
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(ins, isNotEmpty);
      for (final i in ins) {
        expect(i['users'], [
          {'username': 'sg', 'password': 'secret'}
        ], reason: 'инбаунд ${i['tag']} остался без пароля');
      }
    });

    test('без кредов инбаунды открыты — режим системного прокси', () {
      final cfg = const SingboxProxyConfigBuilder().buildMap([hy2]);
      for (final i in (cfg['inbounds'] as List).cast<Map<String, dynamic>>()) {
        expect(i.containsKey('users'), isFalse);
      }
    });
  });

  group('Конфиг остаётся валидным JSON', () {
    test('Xray с кредами сериализуется', () {
      final json = const XrayConfigBuilder()
          .withAuth('sg', 'secret')
          .buildJson(vless);
      expect(() => jsonDecode(json), returnsNormally);
    });

    test('sing-box с кредами сериализуется', () {
      final json = const SingboxProxyConfigBuilder(
              user: 'sg', password: 'secret')
          .buildJson([hy2]);
      expect(() => jsonDecode(json), returnsNormally);
    });
  });

  // ── Харнесс: третий и четвёртый пути сборки конфига ───────────────────────
  //
  // Инбаунд харнесса живёт недолго — только пока идёт прогон пинга или подбора.
  // Но всё это время он ведёт В ТУННЕЛЬ кандидата, а «недолго» на машине с
  // чужим процессом ничем не лучше «всегда».
  const entry = HarnessEntry(key: 'k', server: vless);
  // Второй обычный сервер — чтобы проверить набор инбаундов, а не один.
  // ⚠️ hysteria2 сюда класть НЕЛЬЗЯ: Xray этого протокола не знает и падает на
  // сборке outbound'а. Разложение по ядрам делает MixedProbeHarness.
  const entry2 = HarnessEntry(key: 'k2', server: vless);
  const hy2Entry = HarnessEntry(key: 'k2', server: hy2);

  group('Харнесс Xray', () {
    test('с кредами каждый инбаунд требует пароль', () {
      final cfg = const HarnessConfigBuilder()
          .withAuth('sg', 'secret')
          .buildMap([entry, entry2]);
      final inbounds = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(inbounds, isNotEmpty);
      for (final i in inbounds) {
        final accounts = (i['settings'] as Map)['accounts'];
        expect(accounts, isNotNull,
            reason: 'открытый инбаунд харнесса = вход в туннель без пароля');
        expect((accounts as List).first, {'user': 'sg', 'pass': 'secret'});
      }
    });

    test('без кредов инбаунд открыт — так было до 1.4.1', () {
      final cfg = const HarnessConfigBuilder().buildMap([entry]);
      final i = (cfg['inbounds'] as List).first as Map<String, dynamic>;
      expect((i['settings'] as Map).containsKey('accounts'), isFalse);
    });

    test('с кредами сериализуется', () {
      final json =
          const HarnessConfigBuilder().withAuth('sg', 'secret').buildJson([entry]);
      expect(() => jsonDecode(json), returnsNormally);
    });
  });

  group('Харнесс sing-box', () {
    test('с кредами каждый инбаунд требует пароль', () {
      final cfg = const SingboxHarnessConfigBuilder()
          .withAuth('sg', 'secret')
          .buildMap([hy2Entry]);
      final inbounds = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(inbounds, isNotEmpty);
      for (final i in inbounds) {
        // ⚠️ У sing-box поле называется `users`, а не `accounts`, и ключи
        // внутри другие: построители решают одну задачу, но не взаимозаменяемы.
        final users = i['users'];
        expect(users, isNotNull);
        expect((users as List).first,
            {'username': 'sg', 'password': 'secret'});
      }
    });

    test('без кредов инбаунд открыт — так было до 1.4.1', () {
      final cfg = const SingboxHarnessConfigBuilder().buildMap([hy2Entry]);
      final i = (cfg['inbounds'] as List).first as Map<String, dynamic>;
      expect(i.containsKey('users'), isFalse);
    });

    test('с кредами сериализуется', () {
      final json = const SingboxHarnessConfigBuilder()
          .withAuth('sg', 'secret')
          .buildJson([hy2Entry]);
      expect(() => jsonDecode(json), returnsNormally);
    });
  });
}
