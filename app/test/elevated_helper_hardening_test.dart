import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/exit_tags.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/singbox/singbox_outbound_factory.dart';
import 'package:silentgate/engine/windows/tun/tun_helper.dart';
import 'package:silentgate/engine/windows/xray_paths.dart';

/// Помощник TUN работает с правами администратора, а всё, что он читает из
/// окружения пользователя и `%APPDATA%`, может подсунуть процесс без прав
/// (аудит 25.10.2026, D2).
void main() {
  test('поиск для помощника не смотрит ни в переменную, ни в текущий каталог',
      () {
    final trusted = XrayPaths.candidates(trusted: true);
    final exeDir = File(Platform.resolvedExecutable).parent.path.toLowerCase();
    const devTail = r'\engine\windows\bin\xray.exe';
    for (final c in trusted) {
      final low = c.toLowerCase();
      // Либо рядом с exe, либо dev-раскладка в одном из ПРЕДКОВ каталога exe.
      final root = low.endsWith(devTail)
          ? low.substring(0, low.length - devTail.length)
          : low.endsWith(r'\xray\xray.exe')
              ? File(low).parent.parent.path
              : File(low).parent.path;
      expect(exeDir.startsWith(root), isTrue, reason: c);
    }
    final env = Platform.environment['SILENTGATE_XRAY'];
    if (env != null && env.isNotEmpty) {
      expect(trusted, isNot(contains(env)));
    }
  });

  test('конфиг для ядра помощника теряет поля, пишущие файлы', () {
    final raw = jsonEncode({
      'log': {'level': 'info', 'output': r'C:\Windows\System32\x.dll'},
      'experimental': {
        'cache_file': {'enabled': true, 'path': r'C:\Windows\x'},
        'clash_api': {
          'external_controller': '127.0.0.1:10813',
          'secret': 's',
          'external_ui': r'C:\Windows',
          'external_ui_download_url': 'https://example.com/ui.zip',
          'external_ui_download_detour': 'direct',
        },
      },
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'}
      ],
    });
    final out =
        jsonDecode(TunHelper.sanitizeElevatedConfig(raw)) as Map<String, dynamic>;
    expect(out['log'], {'level': 'info'});
    final exp = out['experimental'] as Map;
    expect(exp.containsKey('cache_file'), isFalse);
    expect(exp['clash_api'],
        {'external_controller': '127.0.0.1:10813', 'secret': 's'});
    expect(out['outbounds'], isNotEmpty);
  });

  test('конфиг без этих разделов проходит как есть', () {
    final raw = jsonEncode({
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'}
      ]
    });
    expect(jsonDecode(TunHelper.sanitizeElevatedConfig(raw)), jsonDecode(raw));
  });

  group('белый список (ревью 29.10.2026, H1/H2)', () {
    String cfg(Map<String, dynamic> m) => jsonEncode(m);
    void rejects(Map<String, dynamic> m) => expect(
        () => TunHelper.sanitizeElevatedConfig(cfg(m)),
        throwsFormatException,
        reason: jsonEncode(m));

    test('ключ в другом регистре — отказ, а не пропуск', () {
      rejects({
        'Log': {'output': r'C:\Windows\System32\x.dll'},
      });
      rejects({
        'log': {'Output': r'C:\Windows\System32\x.dll'},
      });
      rejects({
        'experimental': {
          'Cache_File': {'enabled': true, 'path': r'C:\Windows\x'},
        },
      });
    });

    test('outbound tor (запуск exe) — отказ', () {
      rejects({
        'outbounds': [
          {'type': 'tor', 'tag': 't', 'executable_path': r'C:\x.exe'},
        ],
      });
    });

    test('чужие разделы и inbound с tls — отказ', () {
      rejects({
        'services': [
          {'type': 'ssm-api', 'cache_path': r'C:\Windows\x'},
        ],
      });
      rejects({'endpoints': []});
      rejects({
        'inbounds': [
          {
            'type': 'mixed',
            'tls': {
              'acme': {'data_directory': r'C:\Windows'},
            },
          },
        ],
      });
      rejects({
        'inbounds': [
          {'type': 'shadowsocks'},
        ],
      });
    });

    test('заголовки HTTP с заглавными буквами проходят', () {
      final raw = cfg({
        'outbounds': [
          {
            'type': 'vless',
            'tag': 'x',
            'transport': {
              'type': 'ws',
              'headers': {'Host': 'example.com'},
            },
          },
        ],
      });
      expect(jsonDecode(TunHelper.sanitizeElevatedConfig(raw)), jsonDecode(raw));
    });

    test('каждый TUN-конфиг нашего построителя проходит', () {
      final exits = [
        'vless://11111111-2222-3333-4444-555555555555@exit.example.com:443'
            '?security=reality&sni=www.example.com'
            '&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=ab&fp=chrome'
            '&type=tcp#Exit',
        'vless://11111111-2222-3333-4444-555555555555@ws.example.com:443'
            '?security=tls&sni=ws.example.com&type=ws&host=ws.example.com'
            '&path=%2Fws#Ws',
        'trojan://pwd@tr.example.com:443?sni=tr.example.com#Tr',
        'hysteria2://pwd@hy.example.com:8443?sni=hy.example.com'
            '&obfs=salamander&obfs-password=x#Hy2',
      ].map((l) => ShareLinkParser.tryParse(l)!).toList();
      final exitOuts = [
        for (final s in exits)
          {...SingboxOutboundFactory.build(s), 'tag': exitTagFor(s.rawLink)},
      ];
      final split = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [
          for (final s in exits)
            SiteRule('${s.remark}.example',
                action: AppAction.tunnel, serverKey: s.rawLink),
          const SiteRule('ads.example', action: AppAction.block),
          const SiteRule('direct.example'),
        ],
        apps: const [AppRule('chrome.exe', action: AppAction.tunnel)],
      );
      final configs = [
        SingboxConfigBuilder(
          exitOutbounds: exitOuts,
          options: const TunOptions(
            serverIps: ['203.0.113.10'],
            serverDomains: ['panel.example.com'],
            dnsMode: DnsMode.custom,
            dnsServer: 'dns.google',
            tunnelDnsForAll: true,
            fallbackDnsPort: 10814,
            directFallbackDnsPort: 10815,
            blockQuic: true,
            blockEncryptedDns: true,
            noRealIp: true,
            clashApiPort: 10813,
            clashApiSecret: 'test',
          ),
        ).buildJson(split),
        const SingboxConfigBuilder(options: TunOptions(dnsMode: DnsMode.system))
            .buildJson(split),
        SingboxConfigBuilder(options: const TunOptions().asBlackhole())
            .buildJson(split),
        const SingboxConfigBuilder(options: TunOptions())
            .buildJson(const SplitTunnelConfig()),
      ];
      for (final c in configs) {
        expect(() => TunHelper.sanitizeElevatedConfig(c), returnsNormally,
            reason: c);
      }
    });
  });

  test('помощник запускает ядро с конфигом из stdin и доверенным путём', () {
    final src =
        File('lib/engine/windows/tun/tun_helper.dart').readAsStringSync();
    expect(src, contains("['run', '-c', 'stdin']"));
    expect(src, isNot(contains("['run', '-c', configPath]")));
    expect(src, isNot(contains('XrayPaths.locate()')));
    expect(src, contains('sanitizeElevatedConfig('));
  });
}
