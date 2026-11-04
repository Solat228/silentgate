import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/app_launcher.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/exit_outbounds.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/singbox/singbox_outbound_factory.dart';
import 'package:silentgate/core/singbox/singbox_proxy_config_builder.dart';
import 'package:silentgate/core/subscription/xray_json_subscription.dart';
import 'package:silentgate/core/whitelist_bypass/whitelist_bypass_helper.dart';
import 'package:silentgate/core/xray/xray_outbound_factory.dart';

void main() {
  group('Whitelist Bypass - Все 6 платформ (разбор и канонизация)', () {
    test('1. WB Stream: whitelist://, wbstream:// и https://stream.wb.ru/room/...', () {
      const link =
          'whitelist://wbstream?room=testroom123&mode=dc&reliable=1&dual=1&fps=30&batch=4#WB%20Server';
      final s = ShareLinkParser.tryParse(link)!;
      expect(s.protocol, 'whitelist_bypass');
      expect(s.isWhitelistBypass, isTrue);
      expect(s.usesWhitelistRelay, isTrue);
      expect(s.whitelistPlatform, 'wbstream');
      expect(s.whitelistRoom, 'testroom123');
      expect(s.whitelistMode, 'dc');
      expect(s.whitelistReliable, isTrue);
      expect(s.whitelistDualTrack, isTrue);
      expect(s.whitelistVp8Fps, 30);
      expect(s.whitelistVp8Batch, 4);
      expect(s.remark, 'WB Server');
      expect(ShareLinkParser.tryParse(s.key)!.key, s.key);

      final sShort = ShareLinkParser.tryParse('wbstream://room-abc-42#WB%20Node')!;
      expect(sShort.whitelistRoom, 'room-abc-42');

      final sUrl =
          ShareLinkParser.tryParse('https://stream.wb.ru/room/my-cool-room')!;
      expect(sUrl.whitelistPlatform, 'wbstream');
      expect(sUrl.whitelistRoom, 'my-cool-room');
    });

    test('2. Яндекс Телемост: сохраняет полный URL звонка и принудительный video-режим', () {
      const url = 'https://telemost.yandex.ru/j/1234567890';
      final s = ShareLinkParser.tryParse(url)!;
      expect(s.whitelistPlatform, 'telemost');
      expect(s.whitelistRoom, 'https://telemost.yandex.ru/j/1234567890');
      expect(s.whitelistMode, 'video');
      expect(s.remark, contains('Телемост'));
      expect(ShareLinkParser.tryParse(s.key)!.key, s.key);

      final sShort = ShareLinkParser.tryParse(
          'whitelist://telemost?room=1234567890&mode=dc&dual=1#TM')!;
      expect(sShort.whitelistRoom, 'https://telemost.yandex.ru/j/1234567890');
      // Телемост не поддерживает DataChannel -> нормализуется в video
      expect(sShort.whitelistMode, 'video');
      expect(sShort.whitelistDualTrack, isTrue);
      expect(ShareLinkParser.tryParse(sShort.key)!.key, sShort.key);
    });

    test('3. Dion: извлекает чистый slug события и отключает dualTrack/dc', () {
      final s1 = ShareLinkParser.tryParse('https://dion.vc/event/room-dion-123')!;
      expect(s1.whitelistPlatform, 'dion');
      expect(s1.whitelistRoom, 'room-dion-123');
      expect(s1.whitelistMode, 'video');

      final s2 = ShareLinkParser.tryParse('dion://slug-777#Dion%20Room')!;
      expect(s2.whitelistPlatform, 'dion');
      expect(s2.whitelistRoom, 'slug-777');
      expect(ShareLinkParser.tryParse(s2.key)!.key, s2.key);
    });

    test('4. Битрикс24: нормализует /call/ -> /video/ и сохраняет портал', () {
      const bitrixUrl =
          'https://portal.bitrix24.ru/call/abc?host=203.0.113.10#B24';
      final s = ShareLinkParser.tryParse(bitrixUrl)!;
      expect(s.whitelistPlatform, 'bitrix');
      expect(s.whitelistRoom, 'https://portal.bitrix24.ru/video/abc');
      expect(s.whitelistCreatorHost, '203.0.113.10');
      expect(
        WhitelistBypassEndpoint.domainsForServer(s),
        contains('portal.bitrix24.ru'),
      );
      expect(ShareLinkParser.tryParse(s.key)!.key, s.key);

      final sScheme =
          ShareLinkParser.tryParse('bitrix://corp.bitrix24.ru/video/conf9')!;
      expect(sScheme.whitelistRoom, 'https://corp.bitrix24.ru/video/conf9');
    });

    test('5. VK Звонки: приводит vk.com и короткие токены к https://vk.ru/call/join/...', () {
      final s1 = ShareLinkParser.tryParse('https://vk.ru/call/join/call-token-123')!;
      expect(s1.whitelistPlatform, 'vk');
      expect(s1.whitelistRoom, 'https://vk.ru/call/join/call-token-123');

      final s2 =
          ShareLinkParser.tryParse('https://vk.com/call/join/call-token-456#VK2')!;
      expect(s2.whitelistPlatform, 'vk');
      expect(s2.whitelistRoom, 'https://vk.ru/call/join/call-token-456');
      expect(s2.remark, 'VK2');

      final s3 = ShareLinkParser.tryParse('vkcall://tok-789')!;
      expect(s3.whitelistRoom, 'https://vk.ru/call/join/tok-789');
      expect(ShareLinkParser.tryParse(s3.key)!.key, s3.key);
    });

    test('6. Blink: сохраняет blink://<chatId>, invite URL и гостевой токен bt', () {
      final s1 = ShareLinkParser.tryParse('blink://987654321#BlinkChat')!;
      expect(s1.whitelistPlatform, 'blink');
      expect(s1.whitelistRoom, 'blink://987654321');
      expect(ShareLinkParser.tryParse(s1.key)!.key, s1.key);

      final s2 = ShareLinkParser.tryParse(
          'whitelist://blink?room=987654321&mode=dc&bt=guest-refresh-tok#BlinkDC')!;
      expect(s2.whitelistRoom, 'blink://987654321');
      expect(s2.whitelistMode, 'dc');
      expect(s2.whitelistBlinkToken, 'guest-refresh-tok');
      expect(ShareLinkParser.tryParse(s2.key)!.key, s2.key);

      final s3 = ShareLinkParser.tryParse('https://blink.im/room/blink-456')!;
      expect(s3.whitelistPlatform, 'blink');
      expect(s3.whitelistRoom, 'https://blink.im/room/blink-456');
    });
  });

  group('Whitelist Bypass - Протокол stdin команд для librelay / whitelist-bypass.exe', () {
    test('Генерация точных JOIN:/AUTH: команд для всех 6 платформ', () {
      // 1. WB Stream -> JOIN + roomId
      final wb = ShareLinkParser.tryParse(
          'whitelist://wbstream?room=wb-42&mode=dc&reliable=1&dual=1')!;
      final wbCmd = WhitelistBypassProcess.buildStdinCommand(wb);
      expect(wbCmd, startsWith('JOIN:'));
      final wbJson = jsonDecode(wbCmd.substring(5).trim()) as Map<String, dynamic>;
      expect(wbJson['roomId'], 'wb-42');
      expect(wbJson['tunnelMode'], 'dc');
      expect(wbJson['reliable'], isTrue);
      expect(wbJson['dualTrack'], isTrue);

      // 2. Dion -> JOIN + roomId (без лишних полей)
      final dion = ShareLinkParser.tryParse('dion://dion-slug')!;
      final dionCmd = WhitelistBypassProcess.buildStdinCommand(dion);
      expect(dionCmd, startsWith('JOIN:'));
      final dionJson =
          jsonDecode(dionCmd.substring(5).trim()) as Map<String, dynamic>;
      expect(dionJson['roomId'], 'dion-slug');
      expect(dionJson.containsKey('joinLink'), isFalse);

      // 3. Telemost -> JOIN + полный joinLink
      final tm = ShareLinkParser.tryParse(
          'whitelist://telemost?room=555666&reliable=1&fps=25&batch=3')!;
      final tmCmd = WhitelistBypassProcess.buildStdinCommand(tm);
      final tmJson = jsonDecode(tmCmd.substring(5).trim()) as Map<String, dynamic>;
      expect(tmJson['joinLink'], 'https://telemost.yandex.ru/j/555666');
      expect(tmJson['vp8Fps'], 25);
      expect(tmJson['vp8Batch'], 3);

      // 4. Bitrix -> JOIN + полный joinLink (/video/)
      final bx = ShareLinkParser.tryParse(
          'https://team.bitrix24.ru/call/standup')!;
      final bxCmd = WhitelistBypassProcess.buildStdinCommand(bx);
      final bxJson = jsonDecode(bxCmd.substring(5).trim()) as Map<String, dynamic>;
      expect(bxJson['joinLink'], 'https://team.bitrix24.ru/video/standup');
      expect(bxJson['tunnelMode'], 'video');

      // 5. VK -> AUTH + полный joinLink + reliable=true в video режиме
      final vk = ShareLinkParser.tryParse('vkcall://vk-tok-1')!;
      final vkCmd = WhitelistBypassProcess.buildStdinCommand(vk);
      expect(vkCmd, startsWith('AUTH:'));
      final vkJson = jsonDecode(vkCmd.substring(5).trim()) as Map<String, dynamic>;
      expect(vkJson['joinLink'], 'https://vk.ru/call/join/vk-tok-1');
      expect(vkJson['reliable'], isTrue);

      // 6. Blink -> JOIN + joinLink + cookiesPath
      final blink = ShareLinkParser.tryParse('blink://112233')!;
      final blinkCmd = WhitelistBypassProcess.buildStdinCommand(
        blink,
        blinkCookiesPath: '/tmp/blink-cookies.json',
      );
      expect(blinkCmd, startsWith('JOIN:'));
      final blinkJson =
          jsonDecode(blinkCmd.substring(5).trim()) as Map<String, dynamic>;
      expect(blinkJson['joinLink'], 'blink://112233');
      expect(blinkJson['cookiesPath'], '/tmp/blink-cookies.json');
    });

    test('prepareBlinkCookiesFile материализует гостевой refresh-токен Blink', () async {
      final tmp = Directory.systemTemp.createTempSync('sg_blink_test_');
      AppPaths.overrideRoot(tmp);
      addTearDown(() {
        AppPaths.resetForTests();
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      final srv = ShareLinkParser.tryParse(
          'whitelist://blink?room=777&bt=test-blink-refresh-token')!;
      final path = await WhitelistBypassProcess.prepareBlinkCookiesFile(srv);
      final content = File(path).readAsStringSync();
      expect(content, contains('blink_refresh_token'));
      expect(content, contains('test-blink-refresh-token'));
    });
  });

  group('Whitelist Bypass - Интеграция с Remnawave (VLESS поверх WebRTC /sgbs)', () {
    test('XRAY_JSON и vless:// с /sgbs?... собирают цепочку dialerProxy -> wb-relay', () {
      final panelJson = jsonEncode([
        {
          'remarks': '🇳🇱 Нидерланды БС (Телемост)',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': '198.51.100.42',
                    'port': 14443,
                    'users': [
                      {
                        'id': '11111111-2222-3333-4444-555555555555',
                        'encryption': 'none',
                      },
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': 'ws',
                'security': 'none',
                'wsSettings': {
                  'path':
                      '/sgbs?p=telemost&r=https%3A%2F%2Ftelemost.yandex.ru%2Fj%2F998877&m=video&rel=1&dt=1',
                },
              },
            },
            {'tag': 'direct', 'protocol': 'freedom'},
          ],
        },
      ]);

      final servers = XrayJsonSubscription.parse(panelJson);
      expect(servers, hasLength(1));
      final s = servers.first;
      expect(s.protocol, 'vless');
      expect(s.isWhitelistBypass, isFalse);
      expect(s.usesWhitelistRelay, isTrue);
      expect(s.whitelistPlatform, 'telemost');
      expect(s.whitelistRoom, 'https://telemost.yandex.ru/j/998877');
      expect(s.whitelistReliable, isTrue);
      expect(s.whitelistDualTrack, isTrue);
      expect(s.core, ProxyCore.xray);
      expect(s.configTags, contains('БС · TELEMOST'));
      // Нельзя поднимать вторым туннелем (требует собственного WebRTC-процесса)
      expect(exitServerRejection(s), isNotNull);

      // 1) Сборка из панельного rawOutboundJson
      final panelOutbounds = XrayOutboundFactory.build(s, tag: 'proxy');
      expect(panelOutbounds, hasLength(2));
      expect(panelOutbounds[0]['tag'], 'proxy');
      expect(
        ((panelOutbounds[0]['streamSettings'] as Map)['wsSettings'] as Map)['path'],
        '/sgbs',
      );
      expect(
        ((panelOutbounds[0]['streamSettings'] as Map)['sockopt'] as Map)['dialerProxy'],
        'wb-relay-proxy',
      );
      expect(panelOutbounds[1]['tag'], 'wb-relay-proxy');
      expect(panelOutbounds[1]['protocol'], 'socks');

      // 2) Перезапуск приложения: восстановление из сохранённой vless:// ссылки
      final restored = ShareLinkParser.tryParse(s.key)!;
      expect(restored.key, s.key);
      expect(restored.usesWhitelistRelay, isTrue);
      expect(restored.whitelistPlatform, 'telemost');
      expect(restored.whitelistRoom, 'https://telemost.yandex.ru/j/998877');

      final rebuiltOutbounds = XrayOutboundFactory.build(restored, tag: 'proxy');
      expect(rebuiltOutbounds, hasLength(2));
      expect(
        ((rebuiltOutbounds[0]['streamSettings'] as Map)['wsSettings'] as Map)['path'],
        '/sgbs',
      );
      expect(
        ((rebuiltOutbounds[0]['streamSettings'] as Map)['sockopt'] as Map)['dialerProxy'],
        'wb-relay-proxy',
      );
    });
  });

  group('Whitelist Bypass - Singbox TUN loop-protection & Outbound Factory', () {
    test('SingboxConfigBuilder исключает whitelist-bypass.exe из TUN на Windows', () {
      final cfg = const SingboxConfigBuilder(
        options: TunOptions(serverIps: ['203.0.113.10']),
      ).buildMap(const SplitTunnelConfig());
      final rules = ((cfg['route'] as Map)['rules'] as List).cast<Map>();
      final procRule = rules.firstWhere((r) => r.containsKey('process_name'));
      expect(
        procRule['process_name'],
        containsAll(<String>[
          'xray.exe',
          'sing-box.exe',
          'silentgate.exe',
          'whitelist-bypass.exe',
        ]),
      );
      expect(procRule['outbound'], 'direct');
    });

    test('SingboxOutboundFactory и sing-box check для автономного whitelist_bypass', () {
      const server = VpnServer(
        protocol: 'whitelist_bypass',
        remark: 'WB Bypass',
        address: '127.0.0.1',
        port: 10855,
        id: '',
        whitelistPlatform: 'wbstream',
        whitelistRoom: 'room-1',
        rawLink: 'whitelist://wbstream?room=room-1',
      );
      expect(SingboxOutboundFactory.supports(server), isTrue);
      final outbound = SingboxOutboundFactory.build(server, tag: 'proxy');
      expect(outbound['type'], 'socks');
      expect(outbound['server'], '127.0.0.1');
      expect(outbound['server_port'], 10855);

      final exe = File('../engine/windows/bin/sing-box.exe');
      if (!exe.existsSync()) return;
      final json = const SingboxProxyConfigBuilder(
        ports: SingboxProxyPorts(socks: 10808, http: 10809, api: 10810),
      ).buildJson([server]);
      final tmp = File('${Directory.systemTemp.path}/wb_proxy_check.json');
      tmp.writeAsStringSync(json);
      try {
        final res = Process.runSync(exe.path, ['check', '-c', tmp.path]);
        expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      } finally {
        if (tmp.existsSync()) tmp.deleteSync();
      }
    });

    test('Домены и подсети прямого доступа включают ok.ru, id.vk.ru и VK Cloud TURN', () {
      expect(
        WhitelistBypassEndpoint.domainsFor('vk'),
        containsAll(<String>['ok.ru', 'id.vk.ru', 'login.vk.ru', 'calls.okcdn.ru']),
      );
      expect(
        WhitelistBypassEndpoint.cidrsFor('vk'),
        containsAll(<String>['90.156.0.0/16', '155.212.192.0/20']),
      );
      expect(WhitelistBypassEndpoint.cidrsFor('telemost'), contains('5.255.211.0/24'));
    });

    test('openInteractiveUrl делегирует открытие капчи VK / входа Blink в штатный AppLauncher', () async {
      final opened = <String>[];
      setAppLauncherForTests(_FakeAppLauncher(opened));
      addTearDown(() => setAppLauncherForTests(null));

      await WhitelistBypassProcess.openInteractiveUrl('http://127.0.0.1:41234/');
      await WhitelistBypassProcess.openInteractiveUrl('https://blink.im/auth?code=123&state=abc');
      await WhitelistBypassProcess.openInteractiveUrl('file:///etc/passwd');
      await WhitelistBypassProcess.openInteractiveUrl('');

      expect(
        opened,
        equals(<String>[
          'http://127.0.0.1:41234/',
          'https://blink.im/auth?code=123&state=abc',
        ]),
      );
    });
  });
}

class _FakeAppLauncher implements AppLauncher {
  _FakeAppLauncher(this.opened);
  final List<String> opened;

  @override
  Future<void> open(String url) async {
    opened.add(url);
  }

  @override
  Future<void> openTelegram(String url) async {
    opened.add('tg:$url');
  }
}
