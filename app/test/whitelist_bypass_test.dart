import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/singbox/singbox_outbound_factory.dart';
import 'package:silentgate/core/singbox/singbox_proxy_config_builder.dart';
import 'package:silentgate/core/whitelist_bypass/whitelist_bypass_helper.dart';

void main() {
  group('Whitelist Bypass - ShareLinkParser & VpnServer', () {
    test('Разбор whitelist:// ссылки', () {
      const link = 'whitelist://wbstream?room=testroom123&mode=video#WB%20Server';
      final s = ShareLinkParser.tryParse(link);
      expect(s, isNotNull);
      expect(s!.protocol, 'whitelist_bypass');
      expect(s.isWhitelistBypass, isTrue);
      expect(s.whitelistPlatform, 'wbstream');
      expect(s.whitelistRoom, 'testroom123');
      expect(s.whitelistMode, 'video');
      expect(s.remark, 'WB Server');
      expect(s.address, '127.0.0.1');
      expect(s.port, 10855);
      expect(s.core, ProxyCore.singbox);
      expect(s.protocolLabel, contains('Обход БС'));
      expect(s.configTags, contains('БЕЛЫЙ СПИСОК'));
      expect(s.configTags, contains('WBSTREAM'));
    });

    test('Разбор wbstream:// ссылки', () {
      const link = 'wbstream://room-abc-42#WB%20Node';
      final s = ShareLinkParser.tryParse(link);
      expect(s, isNotNull);
      expect(s!.protocol, 'whitelist_bypass');
      expect(s.whitelistPlatform, 'wbstream');
      expect(s.whitelistRoom, 'room-abc-42');
      expect(s.remark, 'WB Node');
      expect(s.core, ProxyCore.singbox);
      expect(s.key, startsWith('whitelist://wbstream'));
    });

    test('Разбор прямых ссылок WB Stream', () {
      const url = 'https://stream.wb.ru/room/my-cool-room';
      final s = ShareLinkParser.tryParse(url);
      expect(s, isNotNull);
      expect(s!.whitelistPlatform, 'wbstream');
      expect(s.whitelistRoom, 'my-cool-room');
      expect(s.core, ProxyCore.singbox);
    });

    test('Разбор прямых ссылок Яндекс Телемост', () {
      const url = 'https://telemost.yandex.ru/j/1234567890';
      final s = ShareLinkParser.tryParse(url);
      expect(s, isNotNull);
      expect(s!.whitelistPlatform, 'telemost');
      expect(s.whitelistRoom, '1234567890');
      expect(s.remark, contains('Телемост'));
      expect(s.core, ProxyCore.singbox);
    });

    test('Разбор прямых ссылок VK Звонки (vk.ru и vk.com)', () {
      const url1 = 'https://vk.ru/call/join/call-token-123';
      final s1 = ShareLinkParser.tryParse(url1);
      expect(s1, isNotNull);
      expect(s1!.whitelistPlatform, 'vk');
      expect(s1.whitelistRoom, 'call-token-123');
      expect(s1.remark, contains('VK'));
      expect(s1.core, ProxyCore.singbox);

      const url2 = 'https://vk.com/call/join/call-token-456#VK2';
      final s2 = ShareLinkParser.tryParse(url2);
      expect(s2, isNotNull);
      expect(s2!.whitelistPlatform, 'vk');
      expect(s2.whitelistRoom, 'call-token-456');
      expect(s2.remark, 'VK2');
    });

    test('Канонизация и идемпотентность ключа whitelist://', () {
      const link = 'whitelist://vk?room=https%3A%2F%2Fvk.ru%2Fcall%2Fjoin%2Fxyz&mode=video#VK%20Call';
      final s1 = ShareLinkParser.tryParse(link);
      expect(s1, isNotNull);
      final key1 = s1!.key;
      final s2 = ShareLinkParser.tryParse(key1);
      expect(s2, isNotNull);
      expect(s2!.key, key1);
      expect(s2.identityKey, s1.identityKey);
    });
  });

  group('Whitelist Bypass - Singbox Outbound Factory', () {
    test('supports() возвращает true для whitelist_bypass', () {
      const s = VpnServer(
        protocol: 'whitelist_bypass',
        remark: 'Test',
        address: '127.0.0.1',
        port: 10855,
        id: '',
        rawLink: 'whitelist://wbstream?room=123',
      );
      expect(SingboxOutboundFactory.supports(s), isTrue);
    });

    test('build() генерирует корректный socks outbound', () {
      const s = VpnServer(
        protocol: 'whitelist_bypass',
        remark: 'Test',
        address: '127.0.0.1',
        port: 10855,
        id: '',
        whitelistPlatform: 'wbstream',
        whitelistRoom: '123',
        rawLink: 'whitelist://wbstream?room=123',
      );

      final outbound = SingboxOutboundFactory.build(s, tag: 'proxy');
      expect(outbound['type'], 'socks');
      expect(outbound['tag'], 'proxy');
      expect(outbound['server'], '127.0.0.1');
      expect(outbound['server_port'], 10855);
      expect(outbound['version'], '5');
    });

    test('конфиг SingboxProxyConfigBuilder проходит проверку sing-box check', () {
      final exe = File('../engine/windows/bin/sing-box.exe');
      if (!exe.existsSync()) return;

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

      final json = SingboxProxyConfigBuilder(
        ports: const SingboxProxyPorts(socks: 10808, http: 10809, api: 10810),
      ).buildJson([server]);

      final tmp = File('${Directory.systemTemp.path}/wb_proxy_check.json');
      tmp.writeAsStringSync(json);
      try {
        final res = Process.runSync(exe.path, ['check', '-c', tmp.path]);
        final combined = '${res.stdout}\n${res.stderr}'.trim();
        expect(res.exitCode, 0, reason: combined);
        expect(combined.toLowerCase(), isNot(contains('deprecated')),
            reason: 'Конфиг содержит deprecated-поля');
      } finally {
        if (tmp.existsSync()) tmp.deleteSync();
      }
    });
  });

  group('Whitelist Bypass - Endpoints & Routing', () {
    test('Домены и CIDR для прямого выхода', () {
      final vkDomains = WhitelistBypassEndpoint.domainsFor('vk');
      expect(vkDomains, contains('vk.com'));
      expect(vkDomains, contains('vk.ru'));

      final vkCidrs = WhitelistBypassEndpoint.cidrsFor('vk');
      expect(vkCidrs, contains('155.212.192.0/20'));

      final tmDomains = WhitelistBypassEndpoint.domainsFor('telemost');
      expect(tmDomains, contains('telemost.yandex.ru'));

      final tmCidrs = WhitelistBypassEndpoint.cidrsFor('telemost');
      expect(tmCidrs, contains('5.255.211.0/24'));

      final wbDomains = WhitelistBypassEndpoint.domainsFor('wbstream');
      expect(wbDomains, contains('stream.wb.ru'));
    });
  });
}
