import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/exit_outbounds.dart';
import 'package:silentgate/core/singbox/exit_tags.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/singbox/singbox_outbound_factory.dart';
import 'package:silentgate/core/xray/balancer_pick.dart';
import 'package:silentgate/core/xray/override_normalizer.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';
import 'package:silentgate/core/xray/xray_exit_bridge.dart';

/// Реалистичный панельный конфиг «🎬 Авто (YouTube)» по шаблону `ytjson.txt`
/// после инъекции узлов `proxy-*` и запасного `zslow-*` со стороны Remnawave:
/// содержит внутренние правила `.ru -> direct`, `youtube -> yt_auto`,
/// `UDP:443 -> block` и финальное `network: "tcp,udp" -> direct`, а также
/// `fallbackTag: "zslow"` (префикс!) и `burstObservatory`.
String _buildExpandedYtAutoJson({bool includeZslow = true}) => jsonEncode({
      'dns': {
        'queryStrategy': 'UseIPv4',
        'servers': ['https://cloudflare-dns.com/dns-query'],
      },
      'routing': {
        'domainMatcher': 'hybrid',
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          {
            'type': 'field',
            'domain': ['regexp:.*\\.ru\$'],
            'ruleTag': 'ru-direct',
            'outboundTag': 'direct',
          },
          {
            'type': 'field',
            'domain': ['domain:youtube.com', 'domain:googlevideo.com'],
            'balancerTag': 'yt_auto',
          },
          {
            'port': '443',
            'type': 'field',
            'network': 'udp',
            'ruleTag': 'block-quic',
            'outboundTag': 'block',
          },
          {
            'type': 'field',
            'network': 'tcp,udp',
            'outboundTag': 'direct',
          },
        ],
        'balancers': [
          {
            'tag': 'yt_auto',
            'selector': ['proxy'],
            'strategy': {
              'type': 'leastPing',
              'settings': {'maxRTT': '15s'},
            },
            'fallbackTag': 'zslow',
          },
        ],
      },
      'inbounds': [
        {
          'tag': 'socks',
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {'udp': true, 'auth': 'noauth'},
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
          },
        },
      ],
      'outbounds': [
        {
          'tag': 'proxy-1',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': 'nl.yt.example',
                'port': 443,
                'users': [
                  {
                    'id': '11111111-1111-1111-1111-111111111111',
                    'encryption': 'none',
                  },
                ],
              },
            ],
          },
          'streamSettings': {
            'network': 'xhttp',
            'security': 'tls',
            'tlsSettings': {'serverName': 'nl.yt.example'},
            'xhttpSettings': {'path': '/xhttp', 'mode': 'auto'},
          },
        },
        {
          'tag': 'proxy-2',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': 'de.yt.example',
                'port': 443,
                'users': [
                  {
                    'id': '22222222-2222-2222-2222-222222222222',
                    'encryption': 'none',
                  },
                ],
              },
            ],
          },
          'streamSettings': {
            'network': 'tcp',
            'security': 'tls',
            'tlsSettings': {'serverName': 'de.yt.example'},
          },
        },
        if (includeZslow)
          {
            'tag': 'zslow-1',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {
                  'address': 'gcp-it.yt.example',
                  'port': 443,
                  'users': [
                    {
                      'id': '33333333-3333-3333-3333-333333333333',
                      'encryption': 'none',
                    },
                  ],
                },
              ],
            },
            'streamSettings': {
              'network': 'tcp',
              'security': 'tls',
              'tlsSettings': {'serverName': 'gcp-it.yt.example'},
            },
          },
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'block', 'protocol': 'blackhole'},
      ],
      'burstObservatory': {
        'pingConfig': {
          'timeout': '10s',
          'interval': '120s',
          'sampling': 1,
          'destination': 'https://www.youtube.com/generate_204',
        },
        'subjectSelector': ['proxy'],
      },
    });

void main() {
  final ytAutoServer = VpnServer(
    protocol: 'vless',
    remark: '🎬 Авто (YouTube)',
    address: 'nl.yt.example',
    port: 443,
    id: '11111111-1111-1111-1111-111111111111',
    rawLink: 'panel://🎬 Авто (YouTube)?sub=main',
    rawPanelConfig: _buildExpandedYtAutoJson(),
  );

  const xhttpServer = VpnServer(
    protocol: 'vless',
    remark: '🇳🇱 Нидерланды 1.3 xhttp',
    address: 'nl-xhttp.example',
    port: 443,
    id: '44444444-4444-4444-4444-444444444444',
    network: 'xhttp',
    security: 'tls',
    sni: 'nl-xhttp.example',
    path: '/split',
    rawLink: 'vless://44444444-4444-4444-4444-444444444444@nl-xhttp.example:443'
        '?type=xhttp&security=tls&sni=nl-xhttp.example&path=%2Fsplit#NL-XHTTP',
  );

  const mainVlessServer = VpnServer(
    protocol: 'vless',
    remark: '🇫🇮 Финляндия 1.1',
    address: 'fi.main.example',
    port: 443,
    id: '55555555-5555-5555-5555-555555555555',
    network: 'tcp',
    security: 'tls',
    sni: 'fi.main.example',
    rawLink: 'vless://55555555-5555-5555-5555-555555555555@fi.main.example:443'
        '?type=tcp&security=tls&sni=fi.main.example#FI',
  );

  const brokenEmptyPanel = VpnServer(
    protocol: 'vless',
    remark: 'Пустой Авто',
    address: '0.0.0.0',
    port: 443,
    id: '66666666-6666-6666-6666-666666666666',
    rawLink: 'panel://Пустой Авто?sub=main',
    rawPanelConfig: '{"outbounds":[{"protocol":"freedom","tag":"direct"}]}',
  );

  group('Предикаты пригодности Xray-моста для «Через сервер»', () {
    test('Авто (YouTube) и VLESS+XHTTP принимаются через мост, а пустой шаблон отклоняется', () {
      expect(SingboxOutboundFactory.supports(xhttpServer), isFalse,
          reason: 'sing-box не поддерживает транспорт XHTTP напрямую');
      expect(needsXrayExitBridge(xhttpServer), isTrue);
      expect(canBeExitServer(xhttpServer), isTrue);

      expect(needsXrayExitBridge(ytAutoServer), isTrue);
      expect(canBeExitServer(ytAutoServer), isTrue);

      expect(needsXrayExitBridge(mainVlessServer), isFalse,
          reason: 'обычный VLESS+TCP поднимается напрямую в sing-box без лишнего хопа');
      expect(canBeExitServer(mainVlessServer), isTrue);

      expect(needsXrayExitBridge(brokenEmptyPanel), isFalse);
      expect(canBeExitServer(brokenEmptyPanel), isFalse);
    });
  });

  group('Изоляция мостов Xray и защита от утечки в direct из ytjson.txt', () {
    test('трафик in-exit-<hash> уходит строго в exit-<hash>-yt_auto и не течёт в direct', () {
      final exits = <String, VpnServer>{
        ytAutoServer.key: ytAutoServer,
        xhttpServer.key: xhttpServer,
      };
      final bridgePorts = assignXrayExitBridgePorts(exits);
      expect(bridgePorts.length, 2);
      expect(bridgePorts.values.toSet(), {10910, 10911});

      final baseJson = const XrayConfigBuilder().buildJson(mainVlessServer);
      final mergedJson = injectXrayExitBridges(
        baseJson,
        exitServers: exits,
        bridgePorts: bridgePorts,
        resolvedIps: const {
          'nl.yt.example': '198.51.100.132',
          'de.yt.example': '203.0.113.22',
          'gcp-it.yt.example': '203.0.113.230',
          'nl-xhttp.example': '198.51.100.63',
        },
        socksUser: 'sg-user',
        socksPassword: 'sg-secret-password',
      );
      final cfg = jsonDecode(mergedJson) as Map<String, dynamic>;

      // 1. Основной одиночный сервер не приобрёл ложного главного балансировщика:
      // BalancerPick обязан игнорировать `exit-*` балансировщики вторичных правил!
      expect(BalancerPick.hasBalancer(cfg), isFalse);
      expect(BalancerPick.mainBalancerTag(cfg), isNull);

      // 2. Если же основным тоже стоит профиль с балансировщиком — его тег сохраняется.
      final mainAutoNormalized = ensureXrayStats(
        normalizeOverridePorts(
          _buildExpandedYtAutoJson(),
          socksPort: 10808,
          httpPort: 10809,
        ).json,
        apiPort: 10085,
      );
      final mergedWithMainAuto = jsonDecode(injectXrayExitBridges(
        mainAutoNormalized,
        exitServers: {xhttpServer.key: xhttpServer},
        bridgePorts: {xhttpServer.key: 10910},
      )) as Map<String, dynamic>;
      expect(BalancerPick.mainBalancerTag(mergedWithMainAuto), 'yt_auto');

      // 3. Проверяем префиксованный балансировщик `exit-<hash>-yt_auto`,
      // разрешение префиксного `fallbackTag: "zslow"` -> `exit-<hash>-zslow-1`
      // и отсутствие утечки не-YouTube доменов в `direct`.
      final ytExitTag = exitTagFor(ytAutoServer.key);
      final ytInboundTag = 'in-$ytExitTag';
      final ytBalancerTag = '$ytExitTag-yt_auto';

      final balancers = ((cfg['routing'] as Map)['balancers'] as List)
          .cast<Map<String, dynamic>>();
      final ytBal = balancers.singleWhere((b) => b['tag'] == ytBalancerTag);
      expect(ytBal['selector'], ['$ytExitTag-proxy']);
      expect(ytBal['fallbackTag'], '$ytExitTag-zslow-1');

      final rules = ((cfg['routing'] as Map)['rules'] as List)
          .cast<Map<String, dynamic>>();
      final ytRules = rules
          .where((r) =>
              r['inboundTag'] is List &&
              (r['inboundTag'] as List).contains(ytInboundTag))
          .toList();
      // Ровно 3 правила для моста yt_auto: LAN -> direct, UDP:443 -> block, tcp,udp -> exit-*-yt_auto.
      expect(ytRules.length, 3);
      expect(ytRules[0]['outboundTag'], 'direct');
      expect(ytRules[0]['ip'], isNotEmpty);
      expect(ytRules[1]['outboundTag'], 'block');
      expect(ytRules[1]['port'], '443');
      expect(ytRules[2]['network'], 'tcp,udp');
      expect(ytRules[2]['balancerTag'], ytBalancerTag);
      expect(ytRules[2].containsKey('domain'), isFalse,
          reason: 'любой домен (discord.com, 2ip.ru), отправленный правилом sing-box '
              'в этот выход, обязан идти через балансировщик профиля, а не утекать в direct');

      // 4. burstObservatory следит за префиксом моста.
      final burst = cfg['burstObservatory'] as Map<String, dynamic>;
      expect(burst['subjectSelector'], contains('$ytExitTag-proxy'));

      // 5. Домены внутри клонированных outbounds получили предрезолвленные IP и сохранили SNI.
      final outbounds = (cfg['outbounds'] as List).cast<Map<String, dynamic>>();
      final p1 = outbounds.singleWhere((o) => o['tag'] == '$ytExitTag-proxy-1');
      final vnext1 = ((p1['settings'] as Map)['vnext'] as List).first as Map;
      expect(vnext1['address'], '198.51.100.132');
      expect(((p1['streamSettings'] as Map)['tlsSettings'] as Map)['serverName'],
          'nl.yt.example');
    });

    test('если в профиле нет запасных нод zslow, висячий fallbackTag удаляется', () {
      final noZslowServer = VpnServer(
        protocol: 'vless',
        remark: '🎬 Авто (без zslow)',
        address: 'nl.yt.example',
        port: 443,
        id: '11111111-1111-1111-1111-111111111111',
        rawLink: 'panel://🎬 Авто (без zslow)?sub=main',
        rawPanelConfig: _buildExpandedYtAutoJson(includeZslow: false),
      );
      final exits = {noZslowServer.key: noZslowServer};
      final ports = assignXrayExitBridgePorts(exits);
      final auxJson = injectXrayExitBridges(
        null,
        exitServers: exits,
        bridgePorts: ports,
      );
      final cfg = jsonDecode(auxJson) as Map<String, dynamic>;
      final bal = (((cfg['routing'] as Map)['balancers'] as List).single)
          as Map<String, dynamic>;
      expect(bal.containsKey('fallbackTag'), isFalse);
    });
  });

  group('Проверка реальными ядрами xray.exe run -test и sing-box.exe check', () {
    File? findBinary(String name) {
      for (final rel in ['../engine/windows/bin/$name', 'engine/windows/bin/$name']) {
        final f = File(rel);
        if (f.existsSync()) return f.absolute;
      }
      return null;
    }

    test('объединённый и автономный конфиги Xray + sing-box TUN проходят валидацию ядер с кодом 0',
        () async {
      final xrayExe = findBinary('xray.exe');
      final singboxExe = findBinary('sing-box.exe');
      expect(xrayExe, isNotNull, reason: 'xray.exe должен лежать в engine/windows/bin');
      expect(singboxExe, isNotNull,
          reason: 'sing-box.exe должен лежать в engine/windows/bin');

      final tmp = await Directory.systemTemp.createTemp('sg_exit_bridge_check_');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });

      final exits = <String, VpnServer>{
        ytAutoServer.key: ytAutoServer,
        xhttpServer.key: xhttpServer,
        mainVlessServer.key: mainVlessServer,
      };
      final bridgePorts = assignXrayExitBridgePorts(exits);

      // A) Основной Xray (панельный Авто YouTube) + мосты выходов.
      final mainAutoBase = ensureXrayStats(
        normalizeOverridePorts(
          _buildExpandedYtAutoJson(),
          socksPort: 10808,
          httpPort: 10809,
        ).json,
        apiPort: 10085,
      );
      final mergedXrayJson = injectXrayExitBridges(
        mainAutoBase,
        exitServers: exits,
        bridgePorts: bridgePorts,
        socksUser: 'u1',
        socksPassword: 'p1',
      );
      final mergedXrayFile = File('${tmp.path}/merged_xray.json')
        ..writeAsStringSync(mergedXrayJson);
      final xrRes1 = await Process.run(
        xrayExe!.path,
        ['run', '-test', '-c', mergedXrayFile.path],
        workingDirectory: xrayExe.parent.path,
      );
      expect(xrRes1.exitCode, 0,
          reason: 'xray -test упал на merged_xray.json:\n'
              '${xrRes1.stdout}\n${xrRes1.stderr}');

      // B) Автономный вспомогательный Xray (`baseXrayJson: null`, когда основной = Hysteria2)
      //    плюс прогон через `stripXrayApi` (путь Android).
      final auxXrayJson = stripXrayApi(injectXrayExitBridges(
        null,
        exitServers: exits,
        bridgePorts: bridgePorts,
        socksUser: 'u1',
        socksPassword: 'p1',
      ));
      final auxXrayFile = File('${tmp.path}/aux_xray.json')
        ..writeAsStringSync(auxXrayJson);
      final xrRes2 = await Process.run(
        xrayExe.path,
        ['run', '-test', '-c', auxXrayFile.path],
        workingDirectory: xrayExe.parent.path,
      );
      expect(xrRes2.exitCode, 0,
          reason: 'xray -test упал на aux_xray.json:\n'
              '${xrRes2.stdout}\n${xrRes2.stderr}');

      // C) Настоящий sing-box TUN конфиг с мостовыми SOCKS5-выходами и автопереключением (`selector`).
      final builtExits = ExitOutbounds.build(
        servers: exits,
        resolvedIps: const {
          'fi.main.example': '198.51.100.10',
        },
        fallbackTag: 'proxy',
        xrayBridgePorts: bridgePorts,
        xrayBridgeUser: 'u1',
        xrayBridgePassword: 'p1',
      );
      expect(builtExits.skipped, isEmpty);
      expect(builtExits.outbounds.length, 6,
          reason: '3 целевых выхода + 3 selector-обёртки с fallbackTag');

      final sbJson = SingboxConfigBuilder(
        options: const TunOptions(clashApiPort: 10811, clashApiSecret: 'sec'),
        exitOutbounds: builtExits.outbounds,
      ).buildJson(
        SplitTunnelConfig(
          mode: SplitMode.all,
          sites: [
            SiteRule('youtube.com',
                action: AppAction.tunnel, serverKey: ytAutoServer.key),
            SiteRule('discord.com',
                action: AppAction.tunnel, serverKey: xhttpServer.key),
            SiteRule('2ip.io',
                action: AppAction.tunnel, serverKey: mainVlessServer.key),
          ],
        ),
      );
      final sbFile = File('${tmp.path}/singbox_tun.json')
        ..writeAsStringSync(sbJson);
      final sbRes = await Process.run(
        singboxExe!.path,
        ['check', '-c', sbFile.path],
        workingDirectory: singboxExe.parent.path,
      );
      expect(sbRes.exitCode, 0,
          reason: 'sing-box check упал на singbox_tun.json:\n'
              '${sbRes.stdout}\n${sbRes.stderr}');
    });
  });
}
