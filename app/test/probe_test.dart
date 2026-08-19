import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show TextDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silentgate/core/models/subscription_info.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/device_id.dart';
import 'package:silentgate/core/platform/network_watcher.dart';
import 'package:silentgate/engine/windows/app_icon_windows.dart';
import 'package:silentgate/core/probe/auto_config_engine.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/net/speed_test.dart';
import 'package:silentgate/core/net/ip_info.dart';
import 'package:silentgate/core/models/subscription_profile.dart';
import 'package:silentgate/ui/widgets/subscription_avatar.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/i18n/app_locales.dart';
import 'package:silentgate/core/i18n/text_direction.dart';
import 'package:silentgate/core/util/server_search.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/xray/panel_direct_reroute.dart';
import 'package:silentgate/core/singbox/tun_autotune.dart';
import 'package:silentgate/core/subscription/subscription_logo.dart';
import 'package:silentgate/core/subscription/xray_json_subscription.dart';
import 'package:silentgate/core/xray/xray_outbound_factory.dart';
import 'package:silentgate/core/xray/harness_config_builder.dart';
import 'package:silentgate/core/xray/outbound_variant.dart';
import 'package:silentgate/core/xray/override_normalizer.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';

const _reality =
    'vless://11111111-2222-3333-4444-555555555555@example.com:443'
    '?type=tcp&security=reality&pbk=K&sni=a.com&sid=ab&flow=xtls-rprx-vision'
    '&encryption=none#S';

void main() {
  test('fragment добавляет freedom-outbound с dialerProxy', () {
    final s = ShareLinkParser.tryParse(_reality)!;
    final map = const XrayConfigBuilder()
        .buildMap(s, variant: const OutboundVariant(fragment: true));
    final outs = (map['outbounds'] as List).cast<Map>();
    final proxy = outs.firstWhere((o) => o['tag'] == 'proxy');
    final sockopt =
        (proxy['streamSettings'] as Map)['sockopt'] as Map<String, dynamic>;
    expect(sockopt['dialerProxy'], 'frag-proxy');
    expect(
      outs.any((o) => o['tag'] == 'frag-proxy' && o['protocol'] == 'freedom'),
      isTrue,
    );
  });

  test('harness: N http-inbound → N outbound + routing', () {
    final s = ShareLinkParser.tryParse(_reality)!;
    const b = HarnessConfigBuilder();
    final map = b.buildMap([
      HarnessEntry(key: 'a', server: s),
      HarnessEntry(key: 'b', server: s, variant: const OutboundVariant(fragment: true)),
    ]);
    final inbounds = map['inbounds'] as List;
    expect(inbounds.length, 2);
    expect(inbounds[0]['protocol'], 'http');
    expect(b.portFor(0), 21000);
    expect(b.portFor(1), 21001);

    final rules = (map['routing'] as Map)['rules'] as List;
    expect(rules.length, 2);
    expect(rules[0]['inboundTag'], ['in-0']);
    expect(rules[0]['outboundTag'], 'out-0');

    final outs = (map['outbounds'] as List).cast<Map>();
    expect(outs.any((o) => o['tag'] == 'frag-out-1'), isTrue);
  });

  // ⚠️ ЭТОТ ТЕСТ РАНЬШЕ СТЕРЁГ ДЕФЕКТ. Он требовал `rules[0].balancerTag ==
  // 'balancer'` и `burstObservatory != null` — то есть буквально «проба идёт
  // через балансировщик, у которого в харнессе нет и не может быть данных
  // наблюдателя». Разбор — в [HarnessConfigBuilder.probeExitTag].
  test('#8.2 harness override: полный JSON → один http-inbound на КОНКРЕТНЫЙ узел',
      () {
    const burst = '''
{
  "inbounds": [
    {"tag": "socks-in", "port": 10808, "protocol": "socks", "listen": "127.0.0.1"},
    {"tag": "http-in", "port": 10809, "protocol": "http", "listen": "127.0.0.1"}
  ],
  "outbounds": [
    {"tag": "proxy-0", "protocol": "vless", "settings": {"vnext": []}},
    {"tag": "proxy-1", "protocol": "vless", "settings": {"vnext": []}},
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "balancers": [{"tag": "balancer", "selector": ["proxy"]}],
    "rules": [{"type": "field", "inboundTag": ["socks-in", "http-in"], "balancerTag": "balancer"}]
  },
  "burstObservatory": {"subjectSelector": ["proxy"]},
  "stats": {},
  "policy": {}
}
''';
    final s = ShareLinkParser.tryParse(_reality)!.copyWith(rawJsonOverride: burst);
    const b = HarnessConfigBuilder();
    final map = b.buildMap([HarnessEntry(key: 'ov', server: s)]);

    // ⚠️ ИНБАУНДОВ СТОЛЬКО, СКОЛЬКО КАНДИДАТОВ (19.08.2026). Здесь узлов два —
    // значит два порта подряд от базового. Мерить один узел балансировщика
    // значит объявлять профиль мёртвым всякий раз, когда мёртв именно он.
    final inbounds = (map['inbounds'] as List).cast<Map>();
    expect(inbounds.length, 2);
    for (var i = 0; i < inbounds.length; i++) {
      expect(inbounds[i]['protocol'], 'http');
      expect(inbounds[i]['port'], b.portFor(i));
    }

    // Роутинг заменён на правила на КОНКРЕТНЫЕ узлы из selector'а.
    final rules = (map['routing'] as Map)['rules'] as List;
    expect(rules.length, 2);
    expect(rules[0]['inboundTag'], ['in-0']);
    expect(rules[0]['outboundTag'], 'proxy-0');
    expect(rules[1]['outboundTag'], 'proxy-1');
    for (final r in rules) {
      expect(r.containsKey('balancerTag'), isFalse,
          reason: 'балансировщику в харнессе неоткуда взять задержки узлов');
    }

    // Outbounds сохранены; балансировщик, наблюдатель и api/stats/policy — нет.
    final outs = (map['outbounds'] as List).cast<Map>();
    expect(outs.any((o) => o['tag'] == 'proxy-0'), isTrue);
    expect((map['routing'] as Map).containsKey('balancers'), isFalse);
    expect(map.containsKey('burstObservatory'), isFalse);
    expect(map.containsKey('stats'), isFalse);
    expect(map.containsKey('policy'), isFalse);
  });

  test('#2 логотип подписки: <img alt="logo"> со страницы', () {
    const html = '''
<html><body>
<img class="icon" alt="bg" src="https://cdn.example/bg.png">
<img class="m_9e117634 mantine-Image-root" alt="logo"
     src="https://i.postimg.cc/m2cnxWX6/SilentGateIcon.jpg"
     style="--image-object-fit: contain; width: 32px; height: 32px;">
</body></html>
''';
    expect(
      SubscriptionLogo.extractLogoUrl(html),
      'https://i.postimg.cc/m2cnxWX6/SilentGateIcon.jpg',
    );

    // Относительный src разрешается от адреса страницы подписки.
    expect(
      SubscriptionLogo.extractLogoUrl('<img alt="logo" src="/img/l.png">',
          base: Uri.parse('https://sub.silentgate.lol/sub/ABC')),
      'https://sub.silentgate.lol/img/l.png',
    );

    // Нет подходящего тега — null (карточка оставит иконку-заглушку).
    expect(SubscriptionLogo.extractLogoUrl('<img alt="x" src="a.jpg">'), isNull);

    // SPA-страница без <img>: берём apple-touch-icon, затем png-favicon (#1.1).
    const spa = '''
<link rel="icon" type="image/svg+xml" href="/assets/favicon.svg">
<link rel="icon" sizes="32x32" type="image/png" href="/assets/favicon-32x32.png">
<link rel="apple-touch-icon" sizes="180x180" href="/assets/favicon-180x180.png">
''';
    expect(
      SubscriptionLogo.extractLogoUrl(spa,
          base: Uri.parse('https://sub.silentgate.lol/sub/ABC')),
      'https://sub.silentgate.lol/assets/favicon-180x180.png',
    );
    expect(
      SubscriptionLogo.extractLogoUrl(
          '<link rel="icon" type="image/png" href="/assets/favicon-32x32.png">',
          base: Uri.parse('https://sub.silentgate.lol/sub/ABC')),
      'https://sub.silentgate.lol/assets/favicon-32x32.png',
    );
  });

  test('override: порты socks/http подгоняются под захват (фикс блэкхола)', () {
    const raw = '''
{"inbounds":[
  {"tag":"socks-in","port":2080,"listen":"0.0.0.0","protocol":"socks"},
  {"tag":"http-in","port":2081,"protocol":"http"}
],"outbounds":[{"tag":"p","protocol":"freedom"}]}
''';
    final n = normalizeOverridePorts(raw, socksPort: 10808, httpPort: 10809);
    expect(n.hasSocks, isTrue);
    expect(n.hasHttp, isTrue);
    final cfg = jsonDecode(n.json) as Map;
    final ins = (cfg['inbounds'] as List).cast<Map>();
    expect(ins[0]['port'], 10808);
    expect(ins[0]['listen'], '127.0.0.1');
    expect(ins[0]['tag'], 'socks-in'); // теги не трогаем — роутинг живёт
    expect(ins[1]['port'], 10809);

    // Конфиг без http-inbound: недостающий дописывается (профили «Авто» от панели
    // содержат только socks — раньше подключение падало с ошибкой).
    final none = normalizeOverridePorts(
        '{"inbounds":[{"protocol":"socks","port":1}]}',
        socksPort: 1080, httpPort: 1081);
    expect(none.hasSocks, isTrue);
    expect(none.hasHttp, isTrue);
    expect(none.addedInbounds, ['sg-http-in']);

    // Мусор не роняет: возвращается как есть.
    final bad = normalizeOverridePorts('не json', socksPort: 1, httpPort: 2);
    expect(bad.json, 'не json');
  });

  test('split «по пути» → process_path_regex с (?i) (регистронезависимо)', () {
    const split = SplitTunnelConfig(
      mode: SplitMode.onlySelected,
      apps: [AppRule(r'C:\Program Files (x86)\App\game.exe')],
    );
    final map = const SingboxConfigBuilder().buildMap(split);
    final rules = ((map['route'] as Map)['rules'] as List).cast<Map>();
    final rule = rules.firstWhere((r) => r.containsKey('process_path_regex'));
    final rx = (rule['process_path_regex'] as List).first as String;
    expect(rx, startsWith('(?i)^'));
    expect(rx, endsWith(r'\.exe$'));
    // Скобки и точки экранированы, обратные слэши удвоены.
    expect(rx, contains(r'\(x86\)'));
    expect(rx, contains(r'C:\\Program Files'));
    // Регэксп валиден и матчит путь в любом регистре (RE2-совместимое подмножество).
    final re = RegExp(rx.replaceFirst('(?i)', ''), caseSensitive: false);
    expect(re.hasMatch(r'c:\program files (x86)\app\GAME.EXE'), isTrue);
    expect(re.hasMatch(r'C:\Program Files (x86)\App\game.exe'), isTrue);
    expect(re.hasMatch(r'C:\Other\game.exe'), isFalse);
  });

  test('#3.1 sing-box: стек пробрасывается, auto — поле не пишется', () {
    const split = SplitTunnelConfig(mode: SplitMode.all);
    final auto = const SingboxConfigBuilder().buildMap(split);
    final tunAuto = (auto['inbounds'] as List).first as Map;
    expect(tunAuto.containsKey('stack'), isFalse);

    final gvisor = const SingboxConfigBuilder(
            options: TunOptions(stack: 'gvisor'))
        .buildMap(split);
    final tunGvisor = (gvisor['inbounds'] as List).first as Map;
    expect(tunGvisor['stack'], 'gvisor');

    expect(TunStack.auto.singboxValue, isNull);
    expect(TunStack.mixed.singboxValue, 'mixed');
    expect(TunStack.system.singboxValue, 'system');
    expect(TunStack.gvisor.singboxValue, 'gvisor');
  });

  group('v0.8.0 TUN', () {
    const split = SplitTunnelConfig(mode: SplitMode.all);
    List<Map> rulesOf(Map cfg) =>
        ((cfg['route'] as Map)['rules'] as List).cast<Map>();
    Map tunOf(Map cfg) => (cfg['inbounds'] as List).first as Map;

    test('IP сервера уводится мимо туннеля ПЕРВЫМ правилом (защита от петли)', () {
      final cfg = const SingboxConfigBuilder(
        options: TunOptions(serverIps: ['203.0.113.7', '2001:db8::1']),
      ).buildMap(split);
      // Ищем правило исключения сервера и правило по процессам.
      final rules = rulesOf(cfg);
      final serverIdx = rules.indexWhere((r) =>
          (r['ip_cidr'] as List?)?.contains('203.0.113.7/32') == true);
      final procIdx = rules.indexWhere((r) => r['process_name'] != null);
      expect(serverIdx, greaterThanOrEqualTo(0), reason: 'нет правила по IP сервера');
      expect(serverIdx, lessThan(procIdx), reason: 'сервер должен идти до процессов');
      expect(rules[serverIdx]['outbound'], 'direct');
      // IPv6 сервера → /128.
      expect((rules[serverIdx]['ip_cidr'] as List), contains('2001:db8::1/128'));
    });

    test('DNS: во ВСЕХ режимах есть секция и перехват; отличается только апстрим', () {
      final vpn = const SingboxConfigBuilder(
        options: TunOptions(dnsMode: DnsMode.vpn),
      ).buildMap(split);
      final dns = vpn['dns'] as Map;
      final servers = (dns['servers'] as List).cast<Map>();
      expect(servers.any((s) => s['detour'] == 'proxy'), isTrue);
      expect(servers.any((s) => s['address'] == 'local'), isTrue);
      // Режим «весь трафик» → финальный резолвер через туннель.
      expect(dns['final'], 'dns-proxy');
      expect(rulesOf(vpn).any((r) => r['action'] == 'hijack-dns'), isTrue);

      // ⚠️ Прежнее ожидание («system — без секции и без перехвата») ОТМЕНЕНО:
      // именно оно и описывало поломку. Туннель в любом режиме объявляет себя
      // DNS-сервером адаптера, и без перехвата запросы уходили на 172.19.0.2,
      // где никто не слушает, — не резолвилось ничего. Подробности и проверка
      // порядка правил — в dns_system_mode_test.dart.
      final sys = const SingboxConfigBuilder(
        options: TunOptions(dnsMode: DnsMode.system),
      ).buildMap(split);
      expect(sys.containsKey('dns'), isTrue);
      expect(rulesOf(sys).any((r) => r['action'] == 'hijack-dns'), isTrue);
      // «Системный» = резолв апстримом системы, а не через туннель.
      expect((sys['dns'] as Map)['final'], 'dns-local');

      final custom = const SingboxConfigBuilder(
        options: TunOptions(dnsMode: DnsMode.custom, dnsServer: '9.9.9.9'),
      ).buildMap(split);
      final cs = ((custom['dns'] as Map)['servers'] as List).cast<Map>();
      expect(cs.first['address'], 'tcp://9.9.9.9');
    });

    test('IPv6 / strict_route / EIN / исключения попадают в tun-inbound', () {
      final on = const SingboxConfigBuilder(
        options: TunOptions(excludeCidrs: ['10.8.0.0/24']),
      ).buildMap(split);
      final tun = tunOf(on);
      expect((tun['address'] as List).length, 2); // IPv4 + IPv6
      expect(tun['strict_route'], isTrue);
      expect(tun['endpoint_independent_nat'], isTrue);
      expect(tun['route_exclude_address'], ['10.8.0.0/24']);

      final off = const SingboxConfigBuilder(
        options: TunOptions(ipv6: false, strictRoute: false, endpointIndependentNat: false),
      ).buildMap(split);
      final tunOff = tunOf(off);
      // ⚠️ Адрес IPv6 у туннеля теперь есть ВСЕГДА. Раньше при выключенном IPv6
      // его не было — а значит не было и маршрута ::/0 в туннель, и такой
      // трафик уходил мимо VPN под реальным адресом. Выключенная настройка
      // означает не «не захватывать», а «захватить и отказать» (правило
      // ip_version: 6 → reject ниже).
      expect((tunOff['address'] as List),
          ['172.19.0.1/30', 'fdfe:dcba:9876::1/126']);
      expect(
        (off['route']['rules'] as List)
            .cast<Map<String, dynamic>>()
            .any((r) => r['ip_version'] == 6 && r['action'] == 'reject'),
        isTrue,
        reason: 'захват без отказа означал бы, что IPv6 просто ходит в туннель',
      );
      expect(tunOff['strict_route'], isFalse);
      expect(tunOff['endpoint_independent_nat'], isFalse);
      expect(tunOff.containsKey('route_exclude_address'), isFalse);
    });

    test('правила используют action: route (legacy outbound устарел в 1.11)', () {
      final cfg = const SingboxConfigBuilder().buildMap(
          const SplitTunnelConfig(mode: SplitMode.onlySelected, apps: [AppRule(r'C:\a.exe')]));
      for (final r in rulesOf(cfg)) {
        if (r.containsKey('outbound')) {
          expect(r['action'], 'route', reason: 'правило без action: $r');
        }
      }
    });

    test('bypassLan выключается настройкой', () {
      final off = const SingboxConfigBuilder(options: TunOptions(bypassLan: false))
          .buildMap(split);
      expect(rulesOf(off).any((r) => r['ip_is_private'] == true), isFalse);
      final on = const SingboxConfigBuilder().buildMap(split);
      expect(rulesOf(on).any((r) => r['ip_is_private'] == true), isTrue);
    });

    test('TunOptions.fromSettings переносит все настройки', () {
      const s = AppSettings(
        tunStack: TunStack.gvisor,
        tunMtu: 1400,
        tunStrictRoute: false,
        tunIpv6: false,
        tunEndpointIndependentNat: false,
        tunBypassLan: false,
        tunExcludeCidrs: ['192.168.50.0/24'],
        dnsMode: DnsMode.custom,
        dnsCustomServer: '8.8.4.4',
        dnsStrategy: DnsStrategy.ipv4Only,
        singboxLogLevel: SingboxLogLevel.debug,
      );
      final o = TunOptions.fromSettings(s, serverIps: ['1.2.3.4']);
      expect(o.stack, 'gvisor');
      expect(o.mtu, 1400);
      expect(o.strictRoute, isFalse);
      expect(o.ipv6, isFalse);
      expect(o.endpointIndependentNat, isFalse);
      expect(o.bypassLan, isFalse);
      expect(o.excludeCidrs, ['192.168.50.0/24']);
      expect(o.dnsMode, DnsMode.custom);
      expect(o.dnsServer, '8.8.4.4');
      expect(o.dnsStrategy.singboxValue, 'ipv4_only');
      expect(o.logLevel, 'debug');
      expect(o.serverIps, ['1.2.3.4']);
    });
  });

  test('#1 PNG-энкодер иконок: валидная сигнатура и размеры чанков', () {
    // 2×2 непрозрачных красных пикселя.
    final rgba = Uint8List.fromList(
        List.generate(2 * 2 * 4, (i) => i % 4 == 0 ? 255 : (i % 4 == 3 ? 255 : 0)));
    final png = AppIconWindows.encodePng(2, 2, rgba);
    // Сигнатура PNG.
    expect(png.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    // IHDR: длина 13, ширина/высота 2.
    expect(png.sublist(8, 16),
        [0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
    expect(png.sublist(16, 24), [0, 0, 0, 2, 0, 0, 0, 2]);
    // IEND-чанк в конце: длина 0 + тип + CRC (последние 12 байт).
    expect(png.sublist(png.length - 12, png.length - 8), [0, 0, 0, 0]);
    expect(String.fromCharCodes(png.sublist(png.length - 8, png.length - 4)),
        'IEND');
  });

  test('#5 SubscriptionInfo round-trip (персист карточки)', () {
    final info = SubscriptionInfo(
      title: 'SilentGate',
      uploadBytes: 10,
      downloadBytes: 20,
      totalBytes: 100,
      expiresAt: DateTime(2027, 1, 2),
      updateIntervalHours: 12,
      announce: 'привет',
      supportUrl: 'https://t.me/x',
    );
    final r = SubscriptionInfo.fromJson(info.toJson());
    expect(r.title, 'SilentGate');
    expect(r.usedBytes, 30);
    expect(r.totalBytes, 100);
    expect(r.expiresAt, DateTime(2027, 1, 2));
    expect(r.updateIntervalHours, 12);
    expect(r.announce, 'привет');
    expect(r.supportUrl, 'https://t.me/x');
  });

  test('заголовки устройства: локализованная версия Windows не ломает запрос', () {
    // На русской Windows Platform.operatingSystemVersion содержит кириллицу и кавычки —
    // http отвергал такой заголовок, и импорт/обновление подписки падали целиком.
    expect(
      DeviceHeaders.headerSafe(
          '"Майкрософт Windows 11 Корпоративная" 10.0 (Build 26100)'),
      'Windows 11 10.0 (Build 26100)',
    );
    expect(DeviceHeaders.headerSafe('Только кириллица'), 'unknown');
    expect(DeviceHeaders.headerSafe('10.0 (Build 26100)'), '10.0 (Build 26100)');
  });

  _xrayJsonSubscriptionTests();
  _panelProfileTests();
  _searchAndReliabilityTests();
  _networkWatcherTests();
  _serverInfoTests();
  _subscriptionsAndUpdateTests();
  _tunAutotuneTests();

  test('AppSettings round-trip', () {
    const s = AppSettings(
      pingPrimary: PingMethod.icmp,
      tryFragment: false,
      autoConfigServices: {ProbeService.youtube, ProbeService.telegram},
    );
    final r = AppSettings.fromJson(s.toJson());
    expect(r.pingPrimary, PingMethod.icmp);
    expect(r.tryFragment, false);
    expect(r.autoConfigServices, {ProbeService.youtube, ProbeService.telegram});
    expect(r.pingFallback, PingMethod.proxyGet);
    expect(r.requiredServices, 2);
  });

  test('миграция старых настроек пинга на новую схему фаз', () {
    // Настройки пользователя до 0.8.4: смысл фаз был обратный.
    final old = {
      'verifyViaProxyFirst': false,
      'latencyMethod': 'icmp',
      'proxyCheckMethod': 'proxyHead',
    };
    final r = AppSettings.fromJson(old);
    expect(r.pingTwoPhase, isFalse, reason: 'галочка переносится по смыслу');
    expect(r.pingPrimary, PingMethod.icmp, reason: 'метод задержки стал основным');
    expect(r.pingFallback, PingMethod.proxyHead,
        reason: 'проверка через прокси стала запасной');
  });

  test('PingResult round-trip (сохранение)', () {
    final r = PingResult(
      outcome: PingOutcome.ok,
      latencyMs: 42,
      latencyMethod: PingMethod.tcp,
      reachableViaProxy: true,
      working: false,
      measuredAt: DateTime(2026, 1, 1),
    );
    final r2 = PingResult.fromJson(r.toJson());
    expect(r2.outcome, PingOutcome.ok);
    expect(r2.latencyMs, 42);
    expect(r2.latencyMethod, PingMethod.tcp);
    expect(r2.reachableViaProxy, true);
    expect(r2.working, false, reason: 'флаг «рабочий» переживает сохранение');
  });

  test('PingResult: рабочий = достижим И прошёл проверку', () {
    // TCP ответил, но GET/HEAD не прошёл — достижим, но НЕ рабочий.
    const reachable =
        PingResult(outcome: PingOutcome.ok, latencyMs: 30, working: false);
    expect(reachable.isOk, isTrue);
    expect(reachable.isWorking, isFalse);

    const working =
        PingResult(outcome: PingOutcome.ok, latencyMs: 30, working: true);
    expect(working.isWorking, isTrue);

    // Мёртвый (нет TCP) — ни то, ни другое.
    const dead = PingResult(outcome: PingOutcome.failed);
    expect(dead.isOk, isFalse);
    expect(dead.isWorking, isFalse);
  });

  test('PingResult: старые записи без флага working считаются рабочими', () {
    final legacy = PingResult.fromJson({
      'outcome': 'ok',
      'latencyMs': 55,
      'latencyMethod': 'tcp',
    });
    expect(legacy.working, isTrue, reason: 'обратная совместимость');
    expect(legacy.isWorking, isTrue);
  });

  test('AutoConfigResult round-trip (сохранение)', () {
    final s = ShareLinkParser.tryParse(_reality)!;
    final detail = CandidateResult(
      server: s,
      variant: const OutboundVariant(fragment: true),
      passed: {ProbeService.youtube: true, ProbeService.discord: false},
      avgLatencyMs: 120,
    );
    final r = AutoConfigResult(
      server: s,
      variant: const OutboundVariant(fragment: true),
      detail: detail,
      measuredAt: DateTime(2026, 1, 1),
    );
    final r2 = AutoConfigResult.fromJson(r.toJson())!;
    expect(r2.server.address, 'example.com');
    expect(r2.variant.fragment, true);
    expect(r2.detail.passed[ProbeService.youtube], true);
    expect(r2.detail.passed[ProbeService.discord], false);
    expect(r2.detail.avgLatencyMs, 120);
  });

  group('SingboxConfigBuilder (TUN)', () {
    Map rt(Map<String, dynamic> cfg) => cfg['route'] as Map;
    List<Map> rules(Map<String, dynamic> cfg) =>
        (rt(cfg)['rules'] as List).cast<Map>();

    test('loop-avoidance ядра всегда direct', () {
      final cfg = const SingboxConfigBuilder()
          .buildMap(const SplitTunnelConfig(mode: SplitMode.all));
      expect(rt(cfg)['final'], 'proxy');
      expect(
        rules(cfg).any((r) =>
            (r['process_name'] as List?)?.contains('xray.exe') == true &&
            r['outbound'] == 'direct'),
        isTrue,
      );
    });

    test('onlySelected: «Туннель»-приложение → proxy, домены → proxy, final direct', () {
      final cfg = const SingboxConfigBuilder().buildMap(const SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        apps: [AppRule(r'C:\a.exe', action: AppAction.tunnel)],
        sites: [SiteRule('x.com', action: AppAction.tunnel)],
      ));
      expect(rt(cfg)['final'], 'direct');
      expect(
          rules(cfg).any((r) =>
              r['process_path_regex'] != null && r['outbound'] == 'proxy'),
          isTrue);
      expect(
          rules(cfg).any((r) =>
              r['domain_suffix'] != null && r['outbound'] == 'proxy'),
          isTrue);
    });

    // ⚠️ Тест ПЕРЕПИСАН. Раньше он закреплял обратное: в режиме «всё через VPN»
    // правило «Прямо» попадало в конфиг и прорезало дыру в туннеле. Интерфейс
    // при этом прячет списки со словами «исключений нет» — то есть тест
    // фиксировал расхождение конфига с обещанием интерфейса, а не требование.
    // Проверка ФОРМЫ правил переехала ниже, на exceptSelected.
    test('all: правило «Прямо» НЕ применяется, база — proxy', () {
      final cfg = const SingboxConfigBuilder().buildMap(const SplitTunnelConfig(
        mode: SplitMode.all,
        apps: [AppRule(r'C:\a.exe', action: AppAction.direct)],
      ));
      expect(rt(cfg)['final'], 'proxy');
      expect(rules(cfg).any((r) => r['process_path_regex'] != null), isFalse);
    });

    test('exceptSelected: «Прямо»-приложение → direct, база proxy', () {
      final cfg = const SingboxConfigBuilder().buildMap(const SplitTunnelConfig(
        mode: SplitMode.exceptSelected,
        apps: [AppRule(r'C:\a.exe', action: AppAction.direct)],
      ));
      expect(rt(cfg)['final'], 'proxy');
      expect(
          rules(cfg).any((r) =>
              r['process_path_regex'] != null && r['outbound'] == 'direct'),
          isTrue);
    });

    test('«Блок»-приложение → action: reject (без outbound)', () {
      final cfg = const SingboxConfigBuilder().buildMap(const SplitTunnelConfig(
        mode: SplitMode.exceptSelected,
        apps: [
          AppRule(r'C:\ads.exe', byName: true, action: AppAction.block),
          AppRule(r'C:\vpn.exe', byName: true, action: AppAction.tunnel),
        ],
      ));
      final reject = rules(cfg).firstWhere((r) => r['action'] == 'reject');
      expect((reject['process_name'] as List), contains('ads.exe'));
      expect(reject.containsKey('outbound'), isFalse);
      // Туннель-приложение не попало в reject.
      expect((reject['process_name'] as List).contains('vpn.exe'), isFalse);
    });

    test('exceptSelected: отмеченные «Прямо» → direct, final proxy', () {
      final cfg = const SingboxConfigBuilder().buildMap(const SplitTunnelConfig(
        mode: SplitMode.exceptSelected,
        apps: [AppRule(r'C:\a.exe', action: AppAction.direct)],
      ));
      expect(rt(cfg)['final'], 'proxy');
      expect(
          rules(cfg).any((r) =>
              r['process_path_regex'] != null && r['outbound'] == 'direct'),
          isTrue);
    });

    test('сайт «Блок» → domain_suffix + action reject', () {
      final cfg = const SingboxConfigBuilder().buildMap(const SplitTunnelConfig(
        mode: SplitMode.exceptSelected,
        sites: [SiteRule('ads.com', action: AppAction.block)],
      ));
      final r = rules(cfg).firstWhere(
          (x) => x['action'] == 'reject' && x.containsKey('domain_suffix'));
      expect((r['domain_suffix'] as List), contains('ads.com'));
    });

    test('выключенное правило приложения не применяется в конфиге', () {
      final cfg = const SingboxConfigBuilder().buildMap(const SplitTunnelConfig(
        mode: SplitMode.exceptSelected,
        apps: [
          AppRule(r'C:\on.exe', byName: true, action: AppAction.direct),
          AppRule(r'C:\off.exe',
              byName: true, action: AppAction.direct, enabled: false),
        ],
      ));
      final names = rules(cfg)
          .where((r) => r['process_name'] != null)
          .expand((r) => (r['process_name'] as List))
          .toList();
      expect(names, contains('on.exe'));
      expect(names, isNot(contains('off.exe')));
    });

    test('normalizeDomain убирает схему/путь/www/порт', () {
      expect(normalizeDomain('https://www.EXAMPLE.com/lk?x=1'), 'example.com');
      expect(normalizeDomain('  HTTP://Steam.com/ '), 'steam.com');
      expect(normalizeDomain('sub.example.com'), 'sub.example.com');
      // Порт теперь живёт отдельным полем — из домена он убирается.
      expect(normalizeDomain('example.com:8443/path'), 'example.com');
    });

    test('extractPort достаёт порт из строки, валидирует диапазон', () {
      expect(extractPort('example.com:8443/path'), 8443);
      expect(extractPort('https://example.com:443'), 443);
      expect(extractPort('example.com'), isNull); // порта нет
      expect(extractPort('example.com:0'), isNull); // вне диапазона
      expect(extractPort('example.com:70000'), isNull); // вне диапазона
      expect(extractPort('example.com:abc'), isNull); // не число
    });

    test('baseDomain определяет корень для дерева поддоменов', () {
      expect(baseDomain('sub.example.com'), 'example.com');
      expect(baseDomain('example.com'), 'example.com');
      expect(baseDomain('a.b.c.example.com'), 'example.com');
      // Двухуровневый публичный суффикс: корень — три метки.
      expect(baseDomain('www.bbc.co.uk'), 'bbc.co.uk');
      expect(baseDomain('bbc.co.uk'), 'bbc.co.uk');
    });

    test('сайт с портом → правило domain_suffix + port', () {
      final cfg = const SingboxConfigBuilder().buildMap(const SplitTunnelConfig(
        mode: SplitMode.exceptSelected,
        sites: [
          SiteRule('example.com', port: 8443, action: AppAction.direct),
          SiteRule('plain.com', action: AppAction.direct),
        ],
      ));
      // Домен с портом — отдельное правило (домен И порт вместе).
      final withPort = rules(cfg).firstWhere((r) =>
          r['domain_suffix'] != null && r.containsKey('port'));
      expect((withPort['domain_suffix'] as List), contains('example.com'));
      expect((withPort['port'] as List), contains(8443));
      expect(withPort['outbound'], 'direct');
      // Домен без порта — правило без ключа port.
      final noPort = rules(cfg).firstWhere((r) =>
          r['domain_suffix'] != null && !r.containsKey('port'));
      expect((noPort['domain_suffix'] as List), contains('plain.com'));
    });

    test('SiteRule с портом переживает JSON, containsSite учитывает порт', () {
      const cfg = SplitTunnelConfig(sites: [
        SiteRule('example.com', port: 8443, action: AppAction.tunnel),
        SiteRule('example.com', action: AppAction.direct), // тот же домен, без порта
      ]);
      final round = SplitTunnelConfig.fromJson(cfg.toJson());
      expect(round.sites.length, 2);
      expect(round.sites.first.port, 8443);
      expect(round.sites.first.label, 'example.com:8443');
      expect(round.containsSite('example.com', port: 8443), isTrue);
      expect(round.containsSite('example.com'), isTrue); // без порта — тоже есть
      expect(round.containsSite('example.com', port: 9999), isFalse);
    });

    test('onlySelected: DNS затуннелированного приложения идёт через туннель', () {
      // ⚠️ Раньше здесь проверялся `dns.final == dns-proxy`, и тест был зелёным
      // только потому, что умолчание `tunnelDnsForAll` в билдере расходилось с
      // настройками приложения (true против false). У пользователя `final`
      // был `dns-local`, а правил про приложения в DNS не было вовсе — имя
      // затуннелированному приложению резолвил провайдер.
      //
      // Теперь утечку закрывает ЯВНОЕ правило, а не `final`, и проверять надо
      // именно его: оно верно при любом значении `tunnelDnsForAll`.
      final cfg = SingboxConfigBuilder(
        options: const TunOptions(serverIps: ['203.0.113.10']),
      ).buildMap(const SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        apps: [AppRule('chrome.exe', byName: true, action: AppAction.tunnel)],
      ));
      final dns = ((cfg['dns'] as Map)['rules'] as List).cast<Map>();
      final rule = dns.firstWhere(
          (r) => (r['process_name'] as List?)?.contains('chrome.exe') == true,
          orElse: () => <String, dynamic>{});
      expect(rule['server'], 'dns-proxy',
          reason: 'иначе имя резолвит провайдер, и приложение идёт через '
              'туннель на подменённый адрес');
    });

    test('битые exclude-CIDR отбрасываются, конфиг остаётся валидным', () {
      final cfg = SingboxConfigBuilder(
        options: const TunOptions(excludeCidrs: [
          '10.0.0.0/8', // ок
          '192.168.0.0/33', // битый префикс (>32)
          '999.0.0.0/8', // битый адрес
          'foo/bar', // мусор
          '2001:db8::/32', // ок IPv6
        ]),
      ).buildMap(const SplitTunnelConfig());
      final rules = (cfg['route'] as Map)['rules'] as List;
      final cidrRule = rules.cast<Map>().firstWhere(
          (r) => r['ip_cidr'] != null && r['outbound'] == 'direct',
          orElse: () => <String, dynamic>{});
      final cidrs = (cidrRule['ip_cidr'] as List).cast<String>();
      expect(cidrs, containsAll(['10.0.0.0/8', '2001:db8::/32']));
      expect(cidrs, hasLength(2)); // битые ушли
      // В tun-inbound route_exclude_address — тоже только валидные.
      final tun = (cfg['inbounds'] as List).first as Map;
      expect((tun['route_exclude_address'] as List),
          containsAll(['10.0.0.0/8', '2001:db8::/32']));
    });

    test('пустой/битый custom DNS → фолбэк tcp://1.1.1.1, схема срезается', () {
      String proxyAddr(String server) {
        final cfg = SingboxConfigBuilder(
          options: TunOptions(dnsMode: DnsMode.custom, dnsServer: server),
        ).buildMap(const SplitTunnelConfig());
        final servers = ((cfg['dns'] as Map)['servers'] as List).cast<Map>();
        return servers.firstWhere((x) => x['tag'] == 'dns-proxy')['address']
            as String;
      }

      expect(proxyAddr('   '), 'tcp://1.1.1.1'); // пусто → фолбэк
      expect(proxyAddr('https://dns.google/dns-query'), 'tcp://dns.google');
      expect(proxyAddr('8.8.8.8'), 'tcp://8.8.8.8');
    });

    test('#3.5 БЛОК сайта важнее «Туннель»-приложения (порядок правил)', () {
      final cfg = const SingboxConfigBuilder().buildMap(const SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        apps: [AppRule(r'C:\chrome.exe', byName: true, action: AppAction.tunnel)],
        sites: [SiteRule('site.com', action: AppAction.block)],
      ));
      final r = rules(cfg);
      final blockIdx = r.indexWhere((x) =>
          x['action'] == 'reject' &&
          (x['domain_suffix'] as List?)?.contains('site.com') == true);
      final tunIdx = r.indexWhere((x) =>
          x['process_name'] != null && x['outbound'] == 'proxy');
      expect(blockIdx, greaterThanOrEqualTo(0));
      expect(tunIdx, greaterThanOrEqualTo(0));
      expect(blockIdx, lessThan(tunIdx),
          reason: 'блок должен идти РАНЬШЕ туннель-приложения');
    });

    // Раньше noRealIp переписывал КАЖДОЕ «Прямо» в proxy, и управлять сайтами
    // по отдельности было нельзя: пользователь помечал example.org «Прямо», а сайт
    // всё равно уходил в туннель. Теперь явное правило сильнее глобальной
    // настройки, а вернуть конкретное правило под защиту можно галочкой.
    test('noRealIp: явное «Прямо» остаётся direct, снятая галочка — через VPN',
        () {
      final cfg = SingboxConfigBuilder(
        options: const TunOptions(noRealIp: true, serverIps: ['1.2.3.4']),
      ).buildMap(const SplitTunnelConfig(
        mode: SplitMode.exceptSelected,
        apps: [
          // Явное разрешение — единственный способ выйти напрямую при
          // включённой защите: она стоит выше всех правил и не перебивается.
          AppRule(r'C:\a.exe',
              byName: true, action: AppAction.direct, allowRealIp: true),
          AppRule(r'C:\b.exe', byName: true, action: AppAction.direct),
        ],
        sites: [
          SiteRule('example.com', action: AppAction.direct, allowRealIp: true),
          SiteRule('bank.ru', action: AppAction.direct),
        ],
      ));
      final r = rules(cfg);
      bool routed(String key, String value, String outbound) => r.any((x) =>
          (x[key] as List?)?.contains(value) == true &&
          x['outbound'] == outbound);

      // Явные правила пользователя действительно идут мимо VPN.
      expect(routed('process_name', 'a.exe', 'direct'), isTrue);
      expect(routed('domain_suffix', 'example.com', 'direct'), isTrue);
      // Снятая галочка «разрешить реальный IP» возвращает правило под защиту.
      expect(routed('process_name', 'b.exe', 'proxy'), isTrue);
      expect(routed('domain_suffix', 'bank.ru', 'proxy'), isTrue);
      // Инфраструктурный direct (IP сервера) остаётся direct.
      expect(
          r.any((x) =>
              (x['ip_cidr'] as List?)?.any((c) => '$c'.startsWith('1.2.3.4')) ==
                  true &&
              x['outbound'] == 'direct'),
          isTrue);
    });

    test('noRealIp выключен: галочка ничего не меняет', () {
      final cfg = SingboxConfigBuilder(
        options: const TunOptions(serverIps: ['1.2.3.4']),
      ).buildMap(const SplitTunnelConfig(
        mode: SplitMode.exceptSelected,
        sites: [
          SiteRule('bank.ru', action: AppAction.direct, allowRealIp: false),
        ],
      ));
      expect(
          rules(cfg).any((x) =>
              (x['domain_suffix'] as List?)?.contains('bank.ru') == true &&
              x['outbound'] == 'direct'),
          isTrue,
          reason: 'без noRealIp «Прямо» всегда прямое');
    });

    // DNS должен повторять маршруты: иначе домен, идущий мимо VPN, всё равно
    // резолвится резолвером выходного узла — и запрос утекает в туннель, а CDN
    // отдаёт адрес в стране VPN.
    test('DNS зеркалит правила сайтов', () {
      final cfg = SingboxConfigBuilder(
        options: const TunOptions(noRealIp: true),
      ).buildMap(const SplitTunnelConfig(
        mode: SplitMode.exceptSelected,
        sites: [
          // Явное разрешение: только оно даёт прямой резолв при включённой
          // защите — она стоит выше всех правил и не перебивается.
          SiteRule('example.com', action: AppAction.direct, allowRealIp: true),
          SiteRule('bank.ru', action: AppAction.direct),
          SiteRule('netflix.com', action: AppAction.tunnel),
          SiteRule('ads.example', action: AppAction.block),
        ],
      ));
      final dns = (cfg['dns'] as Map)['rules'] as List;
      Map<String, dynamic>? ruleFor(String domain) {
        for (final x in dns.cast<Map<String, dynamic>>()) {
          if ((x['domain_suffix'] as List?)?.contains(domain) == true) return x;
        }
        return null;
      }

      expect(ruleFor('example.com')?['server'], 'dns-local');
      expect(ruleFor('bank.ru')?['server'], 'dns-proxy');
      expect(ruleFor('netflix.com')?['server'], 'dns-proxy');
      expect(ruleFor('ads.example')?['action'], 'reject');
      // Блок обязан стоять выше остальных: заблокированный домен не резолвится.
      expect(dns.indexOf(ruleFor('ads.example')), 0);
    });

    // Правило с портом в DNS-зеркало попадать НЕ должно: резолв идёт до выбора
    // порта, и «блок example.com:8443» убил бы резолв ВСЕГО домена.
    test('DNS-зеркало игнорирует правила с портом', () {
      final cfg = SingboxConfigBuilder().buildMap(const SplitTunnelConfig(
        mode: SplitMode.exceptSelected,
        sites: [
          SiteRule('example.com', port: 8443, action: AppAction.block),
          SiteRule('shop.ru', port: 443, action: AppAction.direct),
        ],
      ));
      final dns = (cfg['dns'] as Map)['rules'] as List;
      for (final r in dns.cast<Map<String, dynamic>>()) {
        final d = r['domain_suffix'] as List?;
        expect(d?.contains('example.com'), isNot(isTrue),
            reason: 'блок одного порта не должен убивать резолв всего домена');
        expect(d?.contains('shop.ru'), isNot(isTrue));
      }
      // При этом МАРШРУТ по порту остаётся точным.
      expect(
          rules(cfg).any((x) =>
              (x['domain_suffix'] as List?)?.contains('example.com') == true &&
              (x['port'] as List?)?.contains(8443) == true),
          isTrue);
    });


    test('миграция: старые apps/domains без action, действие из режима', () {
      final cfg = SplitTunnelConfig.fromJson({
        'mode': 'exceptSelected',
        'apps': [
          {'path': r'C:\a.exe', 'byName': true}
        ],
        'domains': ['old.com'],
      });
      // exceptSelected остаётся собой, а старые записи получают «Прямо».
      expect(cfg.mode, SplitMode.exceptSelected);
      expect(cfg.apps.single.action, AppAction.direct);
      expect(cfg.sites.single.domain, 'old.com');
      expect(cfg.sites.single.action, AppAction.direct);
    });
  });

  // Панель может прислать очень длинные title/announce (Remnawave не задаёт
  // жёсткого лимита символов — практический потолок это размер HTTP-заголовка,
  // обычно ~8–16 КБ на заголовок; announce base64 в заголовке `announce`).
  // Проверяем, что модель не режет и не ломается на большом тексте.
  group('SubscriptionInfo: огромный текст', () {
    String b64(String s) => base64.encode(utf8.encode(s));

    test('длинные title/announce парсятся целиком и переживают JSON', () {
      final bigTitle = 'Очень длинное название ' * 200; // ~4600 символов
      final bigAnn = 'Объявление про VPN 🚀 ' * 500; // ~10000 символов, с эмодзи
      final info = SubscriptionInfo.fromHeaders({
        'profile-title': 'base64:${b64(bigTitle)}',
        'announce': 'base64:${b64(bigAnn)}',
        'support-url': 'https://t.me/help',
      });
      expect(info.title, bigTitle);
      expect(info.announce, bigAnn);
      expect(info.title!.length, greaterThan(4000));
      expect(info.announce!.length, greaterThan(9000));

      // Сохранение/загрузка не теряет и не обрезает текст.
      final again = SubscriptionInfo.fromJson(info.toJson());
      expect(again.title, bigTitle);
      expect(again.announce, bigAnn);
      expect(again.supportUrl, 'https://t.me/help');
    });

    test('битый base64 в заголовке не роняет разбор', () {
      final info = SubscriptionInfo.fromHeaders({
        'profile-title': 'base64:%%%невалидно%%%',
        'announce': 'base64:zzz!!!',
      });
      // Не исключение, а исходная строка (fallback).
      expect(info.title, isNotNull);
      expect(info.announce, isNotNull);
    });
  });

  test('VpnServer buildShareLink round-trip (редактор)', () {
    final s = ShareLinkParser.tryParse(_reality)!;
    final edited = s.copyWith(remark: 'Изменён', sni: 'new.example.com');
    final s2 = ShareLinkParser.tryParse(edited.copyWith(rawLink: edited.buildShareLink()).rawLink)!;
    expect(s2.address, s.address);
    expect(s2.port, s.port);
    expect(s2.id, s.id);
    expect(s2.security, 'reality');
    expect(s2.publicKey, s.publicKey);
    expect(s2.flow, s.flow);
    expect(s2.sni, 'new.example.com');
    expect(s2.remark, 'Изменён');
  });
}

// ── XRAY_JSON подписка (формат, который Remnawave отдаёт Happ/v2rayNG) ────────
void _xrayJsonSubscriptionTests() {
  // Реальная структура ответа панели: массив полных конфигов, по одному на сервер.
  const body = '''
[{"dns":{"servers":["1.1.1.1"]},"routing":{"rules":[]},
  "inbounds":[{"tag":"socks","port":10808,"protocol":"socks"}],
  "outbounds":[
    {"tag":"proxy","protocol":"vless","settings":{"vnext":[{"address":"ru1.example.com","port":443,
      "users":[{"id":"11111111-2222-3333-4444-555555555555","encryption":"none","flow":"xtls-rprx-vision"}]}]},
     "streamSettings":{"network":"tcp","security":"reality",
       "realitySettings":{"serverName":"www.microsoft.com","fingerprint":"chrome",
         "publicKey":"jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0","shortId":"6ba85179e30d4fc2","spiderX":"/"}}},
    {"tag":"direct","protocol":"freedom"},{"tag":"block","protocol":"blackhole"}],
  "remarks":"🇷🇺 Москва"}]
''';

  test('XRAY_JSON: сервер разбирается и сохраняет авторитетный outbound', () {
    expect(XrayJsonSubscription.looksLikeJson(body), isTrue);
    final servers = XrayJsonSubscription.parse(body);
    expect(servers, hasLength(1));
    final s = servers.first;
    expect(s.remark, '🇷🇺 Москва');
    expect(s.address, 'ru1.example.com');
    expect(s.port, 443);
    expect(s.security, 'reality');
    expect(s.flow, 'xtls-rprx-vision');
    expect(s.publicKey, 'jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0');
    expect(s.rawOutboundJson, isNotNull);
    // Ключ стабильный и совместим с share-ссылками (пины/override переживают).
    expect(s.key, startsWith('vless://'));
  });

  test('outbound панели используется как есть (в т.ч. в balancer/burstObservatory)', () {
    final s = XrayJsonSubscription.parse(body).first;

    // Одиночный outbound.
    final built = XrayOutboundFactory.build(s, tag: 'proxy-0');
    expect(built.first['tag'], 'proxy-0');
    final stream = built.first['streamSettings'] as Map;
    // spiderX из панели сохранён — пересборка из ссылки его теряла.
    expect((stream['realitySettings'] as Map)['spiderX'], '/');

    // Конфиг автовыбора: outbound'ы реальные, burstObservatory их видит.
    final cfg = const XrayConfigBuilder().buildBalancerMap([s]);
    final outs = (cfg['outbounds'] as List).cast<Map>();
    final proxy0 = outs.firstWhere((o) => o['tag'] == 'proxy-0');
    expect(((proxy0['streamSettings'] as Map)['realitySettings'] as Map)['spiderX'], '/');
    expect((cfg['burstObservatory'] as Map)['subjectSelector'], ['proxy']);
  });

  test('вариация автонастройки накладывается поверх outbound панели', () {
    final s = XrayJsonSubscription.parse(body).first;
    final built = XrayOutboundFactory.build(s,
        tag: 'proxy', variant: const OutboundVariant(fingerprint: 'firefox', fragment: true));
    final proxy = built.firstWhere((o) => o['tag'] == 'proxy');
    final stream = proxy['streamSettings'] as Map;
    expect((stream['realitySettings'] as Map)['fingerprint'], 'firefox');
    expect((stream['sockopt'] as Map)['dialerProxy'], 'frag-proxy');
    expect(built.any((o) => o['tag'] == 'frag-proxy'), isTrue);
  });
}

// ── Профили «Авто …» от панели: конфиг применяется ЦЕЛИКОМ ───────────────────
void _panelProfileTests() {
  // Урезанная копия реального профиля: балансировщик + burstObservatory + 3 сервера,
  // и ТОЛЬКО socks-inbound (как присылает Remnawave).
  const autoProfile = '''
[{"dns":{"servers":["1.1.1.1"]},
  "inbounds":[{"tag":"socks","port":10808,"listen":"127.0.0.1","protocol":"socks",
    "settings":{"udp":true,"auth":"noauth"}}],
  "outbounds":[
    {"tag":"proxy","protocol":"vless","settings":{"vnext":[{"address":"a.example.com","port":443,
      "users":[{"id":"11111111-2222-3333-4444-555555555555","encryption":"none","flow":"xtls-rprx-vision"}]}]},
     "streamSettings":{"network":"tcp","security":"reality",
       "realitySettings":{"serverName":"st.ozone.ru","publicKey":"KEY","shortId":"ab","fingerprint":"firefox"}}},
    {"tag":"proxy-2","protocol":"vless","settings":{"vnext":[{"address":"b.example.com","port":443,
      "users":[{"id":"11111111-2222-3333-4444-555555555555","encryption":"none"}]}]},
     "streamSettings":{"network":"tcp","security":"reality",
       "realitySettings":{"serverName":"st.ozone.ru","publicKey":"KEY","shortId":"ab"}}},
    {"tag":"proxy-3","protocol":"vless","settings":{"vnext":[{"address":"c.example.com","port":443,
      "users":[{"id":"11111111-2222-3333-4444-555555555555","encryption":"none"}]}]},
     "streamSettings":{"network":"tcp","security":"reality",
       "realitySettings":{"serverName":"st.ozone.ru","publicKey":"KEY","shortId":"ab"}}},
    {"tag":"direct","protocol":"freedom"},{"tag":"block","protocol":"blackhole"}],
  "routing":{"rules":[{"type":"field","network":"tcp,udp","balancerTag":"yt_auto"}],
    "balancers":[{"tag":"yt_auto","selector":["proxy"],
      "strategy":{"type":"leastPing","settings":{"maxRTT":"15s"}},"fallbackTag":"direct"}]},
  "burstObservatory":{"subjectSelector":["proxy"],
    "pingConfig":{"destination":"https://www.youtube.com/generate_204","interval":"120s"}},
  "remarks":"🎬 Авто (YouTube)"}]
''';

  test('профиль «Авто» сохраняется ЦЕЛИКОМ, а не одним outbound', () {
    final servers = XrayJsonSubscription.parse(autoProfile);
    expect(servers, hasLength(1));
    final s = servers.first;

    expect(s.isPanelProfile, isTrue, reason: 'профиль с балансировщиком не распознан');
    expect(s.remark, '🎬 Авто (YouTube)');
    // Ключ стабилен и не зависит от состава серверов внутри профиля. С 1.4.2 в
    // нём есть ещё и отпечаток подписки — иначе одноимённые профили разных
    // подписок делили бы данные (см. test/panel_profile_key_test.dart).
    expect(s.key, startsWith(XrayJsonSubscription.panelKey('🎬 Авто (YouTube)')));
    expect(
        s.key,
        XrayJsonSubscription.panelKeyOf(
            (jsonDecode(autoProfile) as List).first as Map<String, dynamic>));

    // Главное: сохранены ВСЕ outbound'ы, балансировщик и burstObservatory.
    final cfg = jsonDecode(s.rawPanelConfig!) as Map;
    expect((cfg['outbounds'] as List), hasLength(5));
    expect(((cfg['routing'] as Map)['balancers'] as List).first['tag'], 'yt_auto');
    expect((cfg['burstObservatory'] as Map)['subjectSelector'], ['proxy']);
  });

  test('обычный сервер профилем не считается (нужен для общего balancer)', () {
    const single = '''
[{"inbounds":[{"tag":"socks","port":10808,"protocol":"socks"}],
  "outbounds":[{"tag":"proxy","protocol":"vless","settings":{"vnext":[{"address":"x.example.com",
    "port":443,"users":[{"id":"11111111-2222-3333-4444-555555555555","encryption":"none"}]}]},
    "streamSettings":{"network":"tcp","security":"none"}},
   {"tag":"direct","protocol":"freedom"},{"tag":"block","protocol":"blackhole"}],
  "remarks":"🇵🇱 Польша 1.2"}]
''';
    final s = XrayJsonSubscription.parse(single).first;
    expect(s.isPanelProfile, isFalse);
    expect(s.rawOutboundJson, isNotNull);
    expect(s.key, startsWith('vless://')); // совместимость с пинами
  });

  test('недостающий http-inbound дописывается (у профиля только socks)', () {
    final s = XrayJsonSubscription.parse(autoProfile).first;
    final norm = normalizeOverridePorts(s.rawPanelConfig!,
        socksPort: 10808, httpPort: 10809);
    expect(norm.hasSocks, isTrue);
    expect(norm.hasHttp, isTrue, reason: 'http-inbound должен быть дописан');
    expect(norm.addedInbounds, contains('sg-http-in'));

    final cfg = jsonDecode(norm.json) as Map;
    final ins = (cfg['inbounds'] as List).cast<Map>();
    expect(ins, hasLength(2));
    expect(ins.firstWhere((i) => i['protocol'] == 'socks')['port'], 10808);
    expect(ins.firstWhere((i) => i['protocol'] == 'http')['port'], 10809);
    // Балансировщик и burstObservatory не тронуты.
    expect((cfg['burstObservatory'] as Map), isNotNull);
    expect(((cfg['routing'] as Map)['balancers'] as List), hasLength(1));
  });

  // ⚠️ ЭТОТ ТЕСТ ТОЖЕ СТЕРЁГ ДЕФЕКТ — и назывался «идёт через его собственный
  // балансировщик». Балансировщик профиля в харнессе выбрать не может: его
  // стратегия `leastPing` берёт задержки у `burstObservatory`, а тот успевает
  // обойти узлы за секунды, тогда как харнесс живёт один замер. Xray отдавал
  // пустой выбор в `fallbackTag` (у панели это `direct`) — то есть проба
  // мерила ПРЯМОЙ канал пользователя. Подробности —
  // `HarnessConfigBuilder.probeExitTag`, разбор — `panel_profile_probe_test`.
  test('пинг-харнесс профиля идёт на конкретный узел, а не на балансировщик',
      () {
    final s = XrayJsonSubscription.parse(autoProfile).first;
    const b = HarnessConfigBuilder();
    final map = b.buildMap([HarnessEntry(key: s.key, server: s)]);

    // ⚠️ Инбаунд на каждого кандидата, порты подряд от базового (19.08.2026):
    // профиль — балансировщик, и один узел за него не отвечает.
    final inbounds = (map['inbounds'] as List).cast<Map>();
    expect(inbounds, isNotEmpty);
    for (var i = 0; i < inbounds.length; i++) {
      expect(inbounds[i]['port'], b.portFor(i));
    }

    final rules = (map['routing'] as Map)['rules'] as List;
    expect(rules, hasLength(inbounds.length));
    for (final r in rules) {
      expect(r.containsKey('balancerTag'), isFalse);
    }
    expect(rules.first['outboundTag'], 'proxy');
    // Узлы профиля остаются на месте — режем только выбор выхода.
    expect((map['outbounds'] as List), hasLength(5));
    expect(map.containsKey('burstObservatory'), isFalse,
        reason: 'наблюдатель шлёт свою пробу через КАЖДЫЙ узел ровно во время '
            'замера — цифра получалась про эту бурю');
  });
}

// ── Поиск по серверам и настройки надёжности ─────────────────────────────────
void _searchAndReliabilityTests() {
  VpnServer srv(String remark, {String addr = 'a.example.com', String net = 'tcp'}) =>
      VpnServer(
        protocol: 'vless',
        remark: remark,
        address: addr,
        port: 443,
        id: 'id',
        network: net,
        security: 'reality',
        rawLink: 'vless://id@$addr:443#$remark',
      );

  test('поиск: свободный текст, регистр, флаги и код страны', () {
    final list = [
      srv('🇳🇱 Нидерланды 1.2'),
      srv('🇷🇺🏳️🚀Москва 1.6', addr: 'msk.example.com'),
      srv('🇩🇪🚀Германия 1. GRPC', net: 'grpc'),
      srv('🇺🇸🚀USA xhttp', net: 'xhttp'),
    ];

    // Подстрока в имени, регистр не важен.
    expect(ServerSearch.matchIndices(list, 'москва'), [1]);
    expect(ServerSearch.matchIndices(list, 'МОСКВА'), [1]);
    // Имя ищется и без флаг-эмодзи.
    expect(ServerSearch.matchIndices(list, 'нидерланды'), [0]);
    // Код страны из флага.
    expect(ServerSearch.matchIndices(list, 'us'), [3]);
    // По адресу.
    expect(ServerSearch.matchIndices(list, 'msk.example'), [1]);
    // Несколько слов = И: «германия grpc» находит только немецкий GRPC.
    expect(ServerSearch.matchIndices(list, 'германия grpc'), [2]);
    // По транспорту из тегов конфига.
    expect(ServerSearch.matchIndices(list, 'xhttp'), [3]);
    // Пустой запрос — весь список по порядку.
    expect(ServerSearch.matchIndices(list, '  '), [0, 1, 2, 3]);
    // Нет совпадений.
    expect(ServerSearch.matchIndices(list, 'зимбабве'), isEmpty);
  });

  test('поиск возвращает ИСХОДНЫЕ индексы (иначе выбор уедет на соседа)', () {
    final list = [srv('Первый'), srv('Второй'), srv('Третий')];
    final found = ServerSearch.matchIndices(list, 'третий');
    expect(found, [2]);
    expect(list[found.first].remark, 'Третий');
  });

  test('поиск находит профили «Авто» по слову «авто»', () {
    final profile = srv('🎬 Авто (YouTube)').copyWith(
        rawPanelConfig: '{"outbounds":[]}', rawLink: 'panel://auto-yt');
    final found = ServerSearch.matchIndices([srv('Польша'), profile], 'авто');
    expect(found, [1]);
  });

  test('настройки надёжности: умолчания и round-trip', () {
    const d = AppSettings.defaults;
    expect(d.autoReconnect, isTrue, reason: 'восстановление нужно по умолчанию');
    expect(d.killSwitch, isFalse, reason: 'kill switch — осознанный выбор');

    final s = d.copyWith(autoReconnect: true, killSwitch: true);
    final r = AppSettings.fromJson(s.toJson());
    expect(r.autoReconnect, isTrue);
    expect(r.killSwitch, isTrue);
  });
}

// ── Автоподбор TUN и защита от ложных «смен сети» ────────────────────────────
void _tunAutotuneTests() {
  test('автоподбор TUN: сначала стеки на текущем MTU, потом меньшие MTU', () {
    final combos = TunAutotune.combos(baseMtu: 1500);
    // Первыми — все стеки на 1500 (стек: самая частая причина).
    expect(combos.take(3).map((c) => c.stack), ['system', 'gvisor', 'mixed']);
    expect(combos.take(3).every((c) => c.mtu == 1500), isTrue);
    // Дальше — уменьшенные MTU.
    expect(combos.any((c) => c.mtu == 1400), isTrue);
    expect(combos.any((c) => c.mtu == 1280), isTrue);
    // MTU больше базового не пробуем.
    expect(combos.every((c) => c.mtu <= 1500), isTrue);
    // Дублей нет.
    expect(combos.toSet().length, combos.length);
  });

  test('запомненная рабочая комбинация идёт первой и не дублируется', () {
    const good = TunCombo('gvisor', 1400);
    final combos = TunAutotune.combos(preferred: good, baseMtu: 1500);
    expect(combos.first, good);
    expect(combos.where((c) => c == good).length, 1);
  });

  test('нестандартный базовый MTU: большие значения не подставляются', () {
    final combos = TunAutotune.combos(baseMtu: 1400);
    expect(combos.first, const TunCombo('system', 1400));
    expect(combos.any((c) => c.mtu == 1500), isFalse);
    expect(combos.any((c) => c.mtu == 1280), isTrue);
  });

  test('TunCombo round-trip (запоминание на диске)', () {
    const c = TunCombo('mixed', 1280);
    final r = TunCombo.fromJson(c.toJson());
    expect(r, c);
    expect(r.label, contains('mixed'));
  });
}

// ── Отпечаток сети: не реагировать на временные IPv6 (регресс 0.8.2/0.8.3) ────
void _networkWatcherTests() {
  // Реальные адреса из лога пользователя: между двумя «сменами сети» отличались
  // ТОЛЬКО временные IPv6 и Teredo — сама сеть не менялась.
  const before = [
    '192.168.1.143', '192.168.1.222', '172.26.192.1', '26.237.2.100',
    '2001:0:4625:9800:3090:adb5:fad3:51da', // Teredo
    'fd6e:e701:c863:0:1033:ee1d:e2db:e776', // ULA / privacy extension
    'fd6e:e701:c863:0:5dc7:4ab:253e:329f',
    'fd6e:e701:c863::560',
    'fdfd::1aed:264',
    'fe80::1', // link-local
  ];
  const after = [
    '192.168.1.143', '192.168.1.222', '172.26.192.1', '26.237.2.100',
    'fd6e:e701:c863:0:1033:ee1d:e2db:e776',
    'fd6e:e701:c863:0:3cee:7346:d372:d4d8', // новый временный
    'fd6e:e701:c863::560',
    'fdfd::1aed:264',
  ];

  test('временные IPv6 и Teredo не меняют отпечаток сети', () {
    expect(NetworkWatcher.fingerprintOf(after),
        NetworkWatcher.fingerprintOf(before),
        reason: 'менялись только временные адреса — это не смена сети');
  });

  test('реальная смена сети (IPv4 адаптера) отпечаток меняет', () {
    final moved = [...after]
      ..remove('192.168.1.143')
      ..add('10.0.0.5'); // переехали на другую подсеть
    expect(NetworkWatcher.fingerprintOf(moved),
        isNot(NetworkWatcher.fingerprintOf(after)));
  });

  test('свой TUN-адрес и link-local в отпечаток не попадают', () {
    final withTun = [...after, '172.19.0.1', 'fdfe:dcba:9876::1', 'fe80::abcd'];
    expect(NetworkWatcher.fingerprintOf(withTun),
        NetworkWatcher.fingerprintOf(after),
        reason: 'подъём собственного туннеля — не смена сети');
  });

  test('глобальный IPv6 считается стабильным и учитывается', () {
    final withGlobal = [...after, '2a00:1450:4010:c07::64'];
    expect(NetworkWatcher.fingerprintOf(withGlobal),
        isNot(NetworkWatcher.fingerprintOf(after)));
  });

  test('privacy-ротация глобального IPv6 в том же /64 отпечаток НЕ меняет', () {
    // RFC 4941: Windows крутит младшие 64 бита того же префикса — не смена сети.
    final a = [...after, '2a00:1450:4010:c07:1111:2222:3333:4444'];
    final b = [...after, '2a00:1450:4010:c07:aaaa:bbbb:cccc:dddd'];
    expect(NetworkWatcher.fingerprintOf(a), NetworkWatcher.fingerprintOf(b),
        reason: 'тот же /64 — privacy-адрес, не смена сети');
  });

  test('смена /64-префикса глобального IPv6 отпечаток МЕНЯЕТ', () {
    final a = [...after, '2a00:1450:4010:c07:1::1'];
    final b = [...after, '2a00:1450:4010:d99:1::1']; // другой /64 = другая сеть
    expect(NetworkWatcher.fingerprintOf(a),
        isNot(NetworkWatcher.fingerprintOf(b)));
  });

  test('виртуальные адаптеры 172.16/12 (Docker/WSL/Hyper-V) не в отпечатке', () {
    // Старт/стоп Docker/WSL/Hyper-V больше не считается сменой сети.
    final withVirtual = [...after, '172.17.0.1', '172.28.240.1'];
    expect(NetworkWatcher.fingerprintOf(withVirtual),
        NetworkWatcher.fingerprintOf(after));
    // Реальные LAN (10.x/192.168.x) по-прежнему учитываются.
    expect(NetworkWatcher.fingerprintOf([...after, '10.8.0.2']),
        isNot(NetworkWatcher.fingerprintOf(after)));
  });
}

// ── Экран информации о сервере: скорость и гео ───────────────────────────────
void _serverInfoTests() {
  test('размер пробы: объём и подпись', () {
    expect(SpeedTestSize.full.bytes, 20000000);
    expect(SpeedTestSize.light.bytes, 5000000);
    expect(SpeedTestSize.full.label, '20 МБ');
    expect(SpeedTestSize.light.label, '5 МБ');
  });

  test('скорость показывается только в БАЙТАХ', () {
    // 87.4 Мбит/с — это 10.9 МБ/с; мегабиты не показываем нигде.
    const fast = SpeedResult(
        bitsPerSecond: 87400000, bytes: 20000000, elapsed: Duration(seconds: 2));
    expect(fast.label, '10.9 МБ/с');

    const slow = SpeedResult(
        bitsPerSecond: 940000, bytes: 100000, elapsed: Duration(seconds: 1));
    expect(slow.label, '118 КБ/с');

    const bad = SpeedResult.failed('нет связи');
    expect(bad.ok, isFalse);
    expect(bad.label, '—');
  });

  test('размер пробы переживает сохранение настроек', () {
    const s = AppSettings(speedTestSize: SpeedTestSize.light);
    expect(AppSettings.fromJson(s.toJson()).speedTestSize, SpeedTestSize.light);
    // Умолчание — точный режим.
    expect(AppSettings.defaults.speedTestSize, SpeedTestSize.light);
  });

  test('IpInfo: локация собирается из того, что есть', () {
    const full = IpInfo(
        ip: '1.2.3.4', city: 'Kemerovo', region: 'Kuzbass', country: 'Russia');
    expect(full.location, 'Kemerovo, Kuzbass, Russia');

    const onlyCountry = IpInfo(ip: '1.2.3.4', country: 'Germany');
    expect(onlyCountry.location, 'Germany');

    const nothing = IpInfo(ip: '1.2.3.4');
    expect(nothing.location, '—');
  });

  test('IpInfo round-trip', () {
    const info = IpInfo(
        ip: '5.6.7.8',
        country: 'Netherlands',
        countryCode: 'NL',
        city: 'Amsterdam',
        isp: 'Some ISP');
    final r = IpInfo.fromJson(info.toJson());
    expect(r.ip, '5.6.7.8');
    expect(r.countryCode, 'NL');
    expect(r.isp, 'Some ISP');
  });
}

// ── Мульти-подписки и обновление приложения ──────────────────────────────────
void _subscriptionsAndUpdateTests() {
  test('id подписки стабилен и не зависит от регистра/пробелов', () {
    const url = 'https://sub.silentgate.lol/sub/ABC';
    expect(SubscriptionProfile.idFor(url), SubscriptionProfile.idFor('  $url  '));
    expect(SubscriptionProfile.idFor(url),
        SubscriptionProfile.idFor(url.toUpperCase()));
    expect(SubscriptionProfile.idFor(url),
        isNot(SubscriptionProfile.idFor('https://sub.silentgate.lol/sub/XYZ')));
  });

  test('имя подписки: из панели, иначе узнаваемый кусок ссылки', () {
    const named = SubscriptionProfile(
      id: 'a',
      url: 'https://sub.silentgate.lol/sub/ABC',
      info: SubscriptionInfo(title: 'Silentgate VPN'),
    );
    expect(named.title, 'Silentgate VPN');

    const unnamed =
        SubscriptionProfile(id: 'b', url: 'https://sub.silentgate.lol/sub/ABC');
    expect(unnamed.title, contains('sub.silentgate.lol'));
    expect(unnamed.title, contains('ABC'));
  });

  test('профиль подписки round-trip', () {
    const p = SubscriptionProfile(
      id: 'sub_1',
      url: 'https://example.com/sub/1',
      info: SubscriptionInfo(title: 'Тест', totalBytes: 100),
      logoPath: r'C:\logo.png',
      serverLinks: ['vless://a@b:443#S1', 'vless://c@d:443#S2'],
    );
    final r = SubscriptionProfile.fromJson(p.toJson());
    expect(r.id, 'sub_1');
    expect(r.url, 'https://example.com/sub/1');
    expect(r.info.title, 'Тест');
    expect(r.serverLinks, hasLength(2));
    expect(r.logoPath, r'C:\logo.png');
  });

  test('сравнение версий приложения', () {
    expect(AppUpdate.isNewer('0.9.0', '0.8.4'), isTrue);
    expect(AppUpdate.isNewer('0.8.5', '0.8.4'), isTrue);
    expect(AppUpdate.isNewer('1.0.0', '0.9.9'), isTrue);
    // Та же или старее — не предлагаем.
    expect(AppUpdate.isNewer('0.8.4', '0.8.4'), isFalse);
    expect(AppUpdate.isNewer('0.8.3', '0.8.4'), isFalse);
    // Суффиксы и мусор не ломают сравнение.
    expect(AppUpdate.isNewer('0.9.0-beta', '0.8.4'), isTrue);
    expect(AppUpdate.isNewer('мусор', '0.8.4'), isFalse);
  });

  test('настройки обновления приложения round-trip', () {
    const s = AppSettings(appUpdateCheck: false);
    final r = AppSettings.fromJson(s.toJson());
    expect(r.appUpdateCheck, isFalse);
    expect(AppSettings.defaults.appUpdateCheck, isTrue);
  });

  // Логотип подписки: `/assets/*` отдаётся только с cookie `session`, которую
  // ставит страница подписки при браузерном UA (checkAssetsCookieMiddleware +
  // RootService.isBrowser). Гоняем весь флоу на MockClient — без сети.
  group('SubscriptionLogo: брендинг панели', () {
    const sub = 'https://panel.example.com/sub/ABC123';
    const logo = 'https://i.postimg.cc/m2cnxWX6/SilentGateIcon.jpg';
    const cfgV2 = '/assets/.app-config-v2.json';

    // Ответ страницы подписки с cookie (как у Remnawave: Max-Age 1800).
    http.Response pageWithCookie([String body = '<html><body></body></html>']) =>
        http.Response(body, 200, headers: {
          'content-type': 'text/html',
          'set-cookie': 'session=JWT.TOKEN.VAL; Path=/; Max-Age=1800; HttpOnly',
        });

    test('логотип берётся из brandingSettings.logoUrl по cookie', () async {
      final seen = <String, Map<String, String>>{};
      final client = MockClient((req) async {
        seen[req.url.path] = req.headers;
        if (req.url.path == '/sub/ABC123') return pageWithCookie();
        if (req.url.path == cfgV2) {
          return http.Response(
              jsonEncode({
                'brandingSettings': {'logoUrl': logo, 'title': 'SilentGate'}
              }),
              200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('', 502);
      });

      final found = await SubscriptionLogo(client: client).findUrl(sub);
      expect(found, logo);
      // Страницу дёрнули браузерным UA — иначе куки не будет.
      expect(seen['/sub/ABC123']!['User-Agent'], contains('Mozilla/5.0'));
      // Конфиг запрошен с добытой cookie.
      expect(seen[cfgV2]!['Cookie'], 'session=JWT.TOKEN.VAL');
    });

    test('нет cookie (webpageAllowed:false) → null, /assets не дёргается',
        () async {
      final paths = <String>[];
      final client = MockClient((req) async {
        paths.add(req.url.path);
        if (req.url.path == '/sub/ABC123') {
          return http.Response('<html></html>', 200,
              headers: {'content-type': 'text/html'}); // без Set-Cookie
        }
        return http.Response('', 502);
      });

      expect(await SubscriptionLogo(client: client).findUrl(sub), isNull);
      expect(paths.any((p) => p.startsWith('/assets')), isFalse);
    });

    test('v2 недоступен → фолбэк на /assets/app-config.json', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/sub/ABC123') return pageWithCookie();
        if (req.url.path == cfgV2) return http.Response('', 502);
        if (req.url.path == '/assets/app-config.json') {
          return http.Response(
              jsonEncode({
                'brandingSettings': {'logoUrl': logo}
              }),
              200);
        }
        return http.Response('', 404);
      });
      expect(await SubscriptionLogo(client: client).findUrl(sub), logo);
    });

    test('брендинг без логотипа → фолбэк на разбор HTML страницы', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/sub/ABC123') {
          return pageWithCookie(
              '<html><head><link rel="apple-touch-icon" href="/t.png">'
              '</head></html>');
        }
        if (req.url.path.startsWith('/assets')) {
          // Конфиг есть, но logoUrl пустой.
          return http.Response(
              jsonEncode({
                'brandingSettings': {'logoUrl': '  '}
              }),
              200);
        }
        return http.Response('', 404);
      });
      expect(await SubscriptionLogo(client: client).findUrl(sub),
          'https://panel.example.com/t.png');
    });

    test('битый JSON конфига не роняет поиск', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/sub/ABC123') return pageWithCookie();
        if (req.url.path.startsWith('/assets')) {
          return http.Response('<<not json>>', 200);
        }
        return http.Response('', 404);
      });
      expect(await SubscriptionLogo(client: client).findUrl(sub), isNull);
    });
  });

  group('Аватарка подписки: градиент по названию', () {
    test('детерминирован для одного названия', () {
      final a = SubscriptionAvatar.gradientFor('Silentgate VPN');
      final b = SubscriptionAvatar.gradientFor('Silentgate VPN');
      expect(a, b);
      expect(a.length, 2); // пара цветов для LinearGradient
    });

    test('разные названия дают разные цвета', () {
      final a = SubscriptionAvatar.gradientFor('Alpha');
      final b = SubscriptionAvatar.gradientFor('Beta');
      expect(a.first, isNot(b.first));
    });

    test('флаг в начале не влияет — цвет от буквы названия', () {
      // FlagUtil.strip убирает ведущий эмодзи-флаг, поэтому «🇳🇱 NL» и «NL» —
      // один и тот же вход для цвета.
      expect(SubscriptionAvatar.gradientFor('🇳🇱 NL'),
          SubscriptionAvatar.gradientFor('NL'));
    });

    test('пустое/null название — нейтральный серый, без падения', () {
      expect(SubscriptionAvatar.gradientFor(null).length, 2);
      expect(SubscriptionAvatar.gradientFor('   ').length, 2);
    });
  });

  group('Панель: реврайт direct→VPN + stats (#3/#5)', () {
    const panel = '''{
      "outbounds":[
        {"protocol":"vless","tag":"srv1"},
        {"protocol":"vless","tag":"srv2"},
        {"protocol":"freedom","tag":"direct"},
        {"protocol":"blackhole","tag":"block"}
      ],
      "routing":{
        "balancers":[{"tag":"bal","selector":["srv"]}],
        "rules":[
          {"type":"field","domain":["geosite:category-ru"],"outboundTag":"direct"},
          {"type":"field","ip":["geoip:private"],"outboundTag":"direct"},
          {"type":"field","protocol":["bittorrent"],"outboundTag":"block"},
          {"type":"field","network":"tcp,udp","balancerTag":"bal"}
        ]
      }
    }''';

    test('RU-direct уходит на балансер, LAN остаётся direct, block цел', () {
      final out = jsonDecode(rerouteDirectThroughVpn(panel)) as Map;
      final rs = ((out['routing'] as Map)['rules'] as List).cast<Map>();
      // RU-домены больше НЕ direct — уведены на балансер (VPN).
      final ruRule = rs.firstWhere((r) =>
          (r['domain'] as List?)?.contains('geosite:category-ru') == true);
      expect(ruRule['outboundTag'], isNull);
      expect(ruRule['balancerTag'], 'bal');
      // LAN (geoip:private) остался direct.
      expect(
          rs.any((r) =>
              (r['ip'] as List?)?.contains('geoip:private') == true &&
              r['outboundTag'] == 'direct'),
          isTrue);
      // block не тронут.
      expect(
          rs.any((r) =>
              (r['protocol'] as List?)?.contains('bittorrent') == true &&
              r['outboundTag'] == 'block'),
          isTrue);
    });

    test('нераспознанный/битый JSON возвращается как есть', () {
      expect(rerouteDirectThroughVpn('not json'), 'not json');
      expect(rerouteDirectThroughVpn('{"outbounds":[]}'),
          '{"outbounds":[]}'); // нет routing → без изменений
    });

    test('ensureXrayStats дописывает api/stats/policy и правило', () {
      final out = jsonDecode(ensureXrayStats(panel, apiPort: 10085)) as Map;
      expect((out['api'] as Map)['services'], contains('StatsService'));
      expect(out['stats'], isNotNull);
      expect(((out['policy'] as Map)['system'] as Map)['statsOutboundUplink'],
          isTrue);
      final ins = (out['inbounds'] as List).cast<Map>();
      expect(ins.any((i) => i['tag'] == 'api' && i['port'] == 10085), isTrue);
      final rs = ((out['routing'] as Map)['rules'] as List).cast<Map>();
      expect(rs.first['outboundTag'], 'api'); // api-правило первым
    });
  });

  group('autoTextDirection (RTL: имена/провайдерский текст)', () {
    test('латиница/имена серверов → LTR (не зеркалятся)', () {
      expect(autoTextDirection('SilentGate NL-01'), TextDirection.ltr);
      expect(autoTextDirection('🇳🇱 NL-Amsterdam'), TextDirection.ltr); // флаг пропущен
      expect(autoTextDirection('vless://abc@host:443'), TextDirection.ltr);
    });
    test('кириллица → LTR', () {
      expect(autoTextDirection('Сервер Москва'), TextDirection.ltr);
    });
    test('арабский/фарси → RTL', () {
      expect(autoTextDirection('العربية'), TextDirection.rtl);
      expect(autoTextDirection('فارسی'), TextDirection.rtl);
      expect(autoTextDirection('بعد الدفع اضغط'), TextDirection.rtl);
    });
    test('первый СИЛЬНЫЙ символ решает (ведущие цифры/эмодзи пропускаются)', () {
      expect(autoTextDirection('01 · Server'), TextDirection.ltr);
      expect(autoTextDirection('🔒 السلام'), TextDirection.rtl);
    });
    test('пусто/null → null (наследует локаль)', () {
      expect(autoTextDirection(''), isNull);
      expect(autoTextDirection('   '), isNull);
      expect(autoTextDirection(null), isNull);
    });
  });

  group('Локализация (i18n)', () {
    test('languageCode: по умолчанию пусто (как в системе), переживает JSON', () {
      expect(AppSettings.defaults.languageCode, '');
      const s = AppSettings(languageCode: 'en');
      final r = AppSettings.fromJson(s.toJson());
      expect(r.languageCode, 'en');
    });

    test('старые настройки без languageCode → пусто (следуем системе)', () {
      final r = AppSettings.fromJson({'themeMode': 'dark'});
      expect(r.languageCode, '');
    });

    test('поддерживаемые языки: ru (база), en, es с флагами', () {
      expect(supportedLanguages.first.code, 'ru'); // база — первая
      final codes = supportedLanguages.map((l) => l.code).toList();
      expect(codes, containsAll(['ru', 'en', 'es']));
      // У каждого языка есть самоназвание и ISO-код флага.
      for (final l in supportedLanguages) {
        expect(l.endonym.trim(), isNotEmpty);
        expect(l.flag.length, 2);
        expect(l.locale.languageCode, l.code);
      }
    });

    test('languageByCode находит язык и возвращает null для неизвестного', () {
      expect(languageByCode('en')?.endonym, 'English');
      expect(languageByCode('ru')?.flag, 'RU');
      expect(languageByCode('xx'), isNull);
    });

    test('меню языков отсортировано по алфавиту (английские названия)', () {
      final names = languagesSortedByName.map((l) => l.englishName).toList();
      final sorted = [...names]..sort();
      expect(names, sorted); // уже отсортировано
      expect(names.first, 'Arabic');
      expect(names.last, 'Turkish');
      // все языки на месте (ничего не потеряли при сортировке)
      expect(languagesSortedByName.length, supportedLanguages.length);
    });
  });

  group('SubscriptionProfile: logoUrl', () {
    test('logoUrl переживает JSON round-trip', () {
      const p = SubscriptionProfile(
        id: 'sub_1',
        url: 'https://x/sub/1',
        logoPath: r'C:\cache\sub_logo_sub_1.png',
        logoUrl: 'https://i.postimg.cc/logo.jpg',
      );
      final r = SubscriptionProfile.fromJson(p.toJson());
      expect(r.logoPath, p.logoPath);
      expect(r.logoUrl, p.logoUrl);
    });

    test('clearLogo снимает и путь, и источник', () {
      const p = SubscriptionProfile(
        id: 'sub_1',
        url: 'https://x/sub/1',
        logoPath: r'C:\cache\a.png',
        logoUrl: 'https://x/a.png',
      );
      final cleared = p.copyWith(clearLogo: true);
      expect(cleared.logoPath, isNull);
      expect(cleared.logoUrl, isNull);
    });
  });
}
