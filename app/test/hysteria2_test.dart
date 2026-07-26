import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/singbox/singbox_harness_config_builder.dart';
import 'package:silentgate/core/singbox/singbox_outbound_factory.dart';
import 'package:silentgate/core/singbox/singbox_proxy_config_builder.dart';
import 'package:silentgate/core/subscription/xray_json_subscription.dart';
import 'package:silentgate/core/xray/harness_config_builder.dart';

const _hy2 = 'hysteria2://p%40ss@hy.example.com:8443'
    '?sni=hy.example.com&alpn=h3&obfs=salamander&obfs-password=secret'
    '&insecure=1&mport=20000-21000#%F0%9F%87%B3%F0%9F%87%B1%20NL%20Hy2';

void main() {
  group('парсер hysteria2', () {
    test('полная ссылка разбирается со всеми параметрами', () {
      final s = ShareLinkParser.tryParse(_hy2)!;
      expect(s.protocol, 'hysteria2');
      expect(s.address, 'hy.example.com');
      expect(s.port, 8443);
      expect(s.id, 'p@ss'); // пароль был URL-кодирован
      expect(s.sni, 'hy.example.com');
      expect(s.alpn, 'h3');
      expect(s.obfs, 'salamander');
      expect(s.obfsPassword, 'secret');
      expect(s.allowInsecure, isTrue);
      expect(s.hopPorts, '20000-21000');
      expect(s.remark, contains('NL Hy2'));
      // Транспорт у hysteria2 всегда QUIC поверх TLS — фиксируем это в модели.
      expect(s.network, 'quic');
      expect(s.security, 'tls');
    });

    test('короткая схема hy2:// и порт по умолчанию', () {
      final s = ShareLinkParser.tryParse('hy2://pwd@1.2.3.4#Node')!;
      expect(s.protocol, 'hysteria2');
      expect(s.port, 443);
      expect(s.allowInsecure, isFalse);
      expect(s.obfs, isNull);
    });

    test('такой сервер поднимает sing-box, обычный — Xray', () {
      expect(ShareLinkParser.tryParse(_hy2)!.core, ProxyCore.singbox);
      final vless = ShareLinkParser.tryParse(
          'vless://id@a.com:443?type=tcp&security=tls#V')!;
      expect(vless.core, ProxyCore.xray);
    });

    test('IPv6-адрес переживает пересборку ссылки', () {
      // Uri.host отдаёт IPv6 БЕЗ скобок; без обратного обрамления ссылка
      // переставала парситься, и отредактированный сервер исчезал навсегда.
      final s = ShareLinkParser.tryParse('hysteria2://pass@[2001:db8::1]:443#V6')!;
      expect(s.address, '2001:db8::1');
      final again = ShareLinkParser.tryParse(s.buildShareLink());
      expect(again, isNotNull);
      expect(again!.address, '2001:db8::1');
      expect(again.port, 443);
    });

    test('ссылка собирается обратно без потери параметров', () {
      final s = ShareLinkParser.tryParse(_hy2)!;
      final again = ShareLinkParser.tryParse(s.buildShareLink())!;
      expect(again.id, s.id);
      expect(again.address, s.address);
      expect(again.port, s.port);
      expect(again.obfsPassword, s.obfsPassword);
      expect(again.allowInsecure, isTrue);
      expect(again.hopPorts, s.hopPorts);
    });
  });

  group('outbound sing-box', () {
    test('hysteria2 → tls + obfs + порт-хоппинг в формате sing-box', () {
      final s = ShareLinkParser.tryParse(_hy2)!;
      final out = SingboxOutboundFactory.build(s, tag: 'proxy');
      expect(out['type'], 'hysteria2');
      expect(out['server'], 'hy.example.com');
      // При хоппинге server_port должен ОТСУТСТВОВАТЬ — иначе ядро ругается.
      expect(out.containsKey('server_port'), isFalse);
      expect(out['server_ports'], ['20000:21000']);
      expect(out['password'], 'p@ss');
      expect((out['obfs'] as Map)['type'], 'salamander');
      final tls = out['tls'] as Map;
      expect(tls['enabled'], isTrue);
      expect(tls['insecure'], isTrue);
      expect(tls['alpn'], ['h3']);
    });

    test('без хоппинга остаётся обычный server_port', () {
      final s = ShareLinkParser.tryParse('hy2://pwd@1.2.3.4:9000#N')!;
      final out = SingboxOutboundFactory.build(s);
      expect(out['server_port'], 9000);
      expect(out.containsKey('server_ports'), isFalse);
      expect(out.containsKey('obfs'), isFalse);
    });

    // Ядро валит ВЕСЬ конфиг из-за одного плохого поля, поэтому чистим на входе.
    test('обфускация без пароля и obfs=none выбрасываются, а не ломают конфиг', () {
      final noPass =
          ShareLinkParser.tryParse('hy2://pwd@a.com:443?obfs=salamander#A')!;
      expect(SingboxOutboundFactory.build(noPass).containsKey('obfs'), isFalse);

      final none = ShareLinkParser.tryParse(
          'hy2://pwd@a.com:443?obfs=none&obfs-password=x#A')!;
      expect(SingboxOutboundFactory.build(none).containsKey('obfs'), isFalse);

      final ok = ShareLinkParser.tryParse(
          'hy2://pwd@a.com:443?obfs=Salamander&obfs-password=s#A')!;
      expect((SingboxOutboundFactory.build(ok)['obfs'] as Map)['type'],
          'salamander');
    });

    test('порты вне диапазона отбрасываются, перевёрнутый разворачивается', () {
      final bad = ShareLinkParser.tryParse('hy2://p@a.com:443?mport=1000-70000#A')!;
      final outBad = SingboxOutboundFactory.build(bad);
      expect(outBad.containsKey('server_ports'), isFalse);
      expect(outBad['server_port'], 443); // откат на обычный порт

      final rev = ShareLinkParser.tryParse('hy2://p@a.com:443?mport=2000-1000#A')!;
      expect(SingboxOutboundFactory.build(rev)['server_ports'], ['1000:2000']);
    });
  });

  group('прокси-конфиг sing-box', () {
    test('один сервер: mixed-инбаунды на тех же портах, что у Xray', () {
      final s = ShareLinkParser.tryParse(_hy2)!;
      final map = const SingboxProxyConfigBuilder().buildMap([s]);
      final inbounds = (map['inbounds'] as List).cast<Map>();
      expect(inbounds.map((i) => i['listen_port']), [10808, 10809]);
      expect(inbounds.every((i) => i['type'] == 'mixed'), isTrue);
      expect(inbounds.every((i) => i['listen'] == '127.0.0.1'), isTrue);

      final outs = (map['outbounds'] as List).cast<Map>();
      expect(outs.first['tag'], 'proxy');
      expect(outs.last['type'], 'direct');
      expect((map['route'] as Map)['final'], 'proxy');
      // Счётчики трафика читаются из Clash API.
      final api = ((map['experimental'] as Map)['clash_api'] as Map);
      expect(api['external_controller'], '127.0.0.1:10085');
    });

    test('Clash API закрыт паролем, когда он задан', () {
      final s = ShareLinkParser.tryParse(_hy2)!;
      final open = const SingboxProxyConfigBuilder().buildMap([s]);
      final api = (open['experimental'] as Map)['clash_api'] as Map;
      expect(api.containsKey('secret'), isFalse); // по умолчанию поля нет

      final closed =
          const SingboxProxyConfigBuilder(apiSecret: 'deadbeef').buildMap([s]);
      final api2 = (closed['experimental'] as Map)['clash_api'] as Map;
      expect(api2['secret'], 'deadbeef');
    });

    test('несколько серверов → urltest выбирает лучший', () {
      final a = ShareLinkParser.tryParse('hy2://p@a.com:443#A')!;
      final b = ShareLinkParser.tryParse('hy2://p@b.com:443#B')!;
      final map = const SingboxProxyConfigBuilder().buildMap([a, b]);
      final outs = (map['outbounds'] as List).cast<Map>();
      final group = outs.firstWhere((o) => o['type'] == 'urltest');
      expect(group['tag'], 'proxy');
      expect(group['outbounds'], ['node-0', 'node-1']);
    });
  });

  test('харнесс sing-box: свой inbound и своё правило на каждого кандидата', () {
    final a = ShareLinkParser.tryParse('hy2://p@a.com:443#A')!;
    final b = ShareLinkParser.tryParse('hy2://p@b.com:443#B')!;
    const builder = SingboxHarnessConfigBuilder(ports: HarnessPorts(base: 21500));
    final map = builder.buildMap([
      HarnessEntry(key: a.key, server: a),
      HarnessEntry(key: b.key, server: b),
    ]);
    final inbounds = (map['inbounds'] as List).cast<Map>();
    expect(inbounds.map((i) => i['listen_port']), [21500, 21501]);
    final rules = ((map['route'] as Map)['rules'] as List).cast<Map>();
    expect(rules[0]['inbound'], ['in-0']);
    expect(rules[0]['outbound'], 'out-0');
    expect(rules[1]['outbound'], 'out-1');
    // Харнесс не должен ничего захватывать глобально.
    expect(map.containsKey('experimental'), isFalse);
    expect((map['route'] as Map)['final'], 'direct');
  });

  group('XRAY_JSON: hysteria2 от панели (Remnawave отдаёт как protocol "hysteria")', () {
    // Реальная структура из silentgate.lol: protocol "hysteria", version 2,
    // адрес/порт в settings, auth — в streamSettings.hysteriaSettings.
    const panelHy = '''{
      "remarks":"🇵🇱🚀Польша 1.6 Hysteria2🎮",
      "outbounds":[
        {"tag":"proxy","protocol":"hysteria",
         "settings":{"address":"pol.silentgate.lol","port":443,"version":2},
         "streamSettings":{"network":"hysteria",
           "hysteriaSettings":{"version":2,"auth":"71bcca74-329d-491e-955c-40e1f37d081d"},
           "security":"tls",
           "tlsSettings":{"serverName":"pol.silentgate.lol","fingerprint":"chrome","alpn":["h3"]}}},
        {"tag":"direct","protocol":"freedom"},
        {"tag":"block","protocol":"blackhole"}
      ]
    }''';

    test('узел больше НЕ выбрасывается — парсится как hysteria2', () {
      final servers = XrayJsonSubscription.parse('[$panelHy]');
      expect(servers.length, 1, reason: 'hysteria2-узел терялся до фикса');
      final s = servers.first;
      expect(s.protocol, 'hysteria2');
      expect(s.address, 'pol.silentgate.lol');
      expect(s.port, 443);
      expect(s.id, '71bcca74-329d-491e-955c-40e1f37d081d'); // auth
      expect(s.sni, 'pol.silentgate.lol');
      expect(s.alpn, 'h3');
      expect(s.core, ProxyCore.singbox); // поднимается sing-box, не Xray
    });

    test('sing-box собирает рабочий outbound из такого узла', () {
      final s = XrayJsonSubscription.parse('[$panelHy]').first;
      final ob = SingboxOutboundFactory.build(s, tag: 'proxy');
      expect(ob['type'], 'hysteria2');
      expect(ob['server'], 'pol.silentgate.lol');
      expect(ob['server_port'], 443);
      expect(ob['password'], '71bcca74-329d-491e-955c-40e1f37d081d');
    });

    test('обычный vless-узел по-прежнему разбирается (не сломали)', () {
      const vless = '''{"remarks":"NL","outbounds":[
        {"tag":"proxy","protocol":"vless","settings":{"vnext":[
          {"address":"1.2.3.4","port":443,"users":[{"id":"uuid-1","flow":"xtls-rprx-vision"}]}]},
         "streamSettings":{"network":"tcp","security":"reality",
           "realitySettings":{"serverName":"a.com","publicKey":"pk","shortId":"ab"}}}]}''';
      final s = XrayJsonSubscription.parse('[$vless]').first;
      expect(s.protocol, 'vless');
      expect(s.address, '1.2.3.4');
      expect(s.core, ProxyCore.xray);
    });
  });
}
