import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/dpi/dpi_bypass_lists.dart';
import 'package:silentgate/core/dpi/dpi_bypass_proxy.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_service_presets.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/exit_tags.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/engine/windows/zapret_winws_runner.dart';

/// Собрать синтетический, но структурно валидный TLS 1.2 ClientHello с SNI [host].
Uint8List _buildSampleClientHello(String host) {
  final hostBytes = ascii.encode(host);
  // SNI extension (0x0000)
  // ServerNameListLen (2) = hostBytes.length + 3
  // NameType (1) = 0x00
  // HostNameLen (2) = hostBytes.length
  final sniExtPayload = <int>[
    ((hostBytes.length + 3) >> 8) & 0xFF,
    (hostBytes.length + 3) & 0xFF,
    0x00,
    (hostBytes.length >> 8) & 0xFF,
    hostBytes.length & 0xFF,
    ...hostBytes,
  ];
  final extBlock = <int>[
    0x00, 0x00, // ExtensionType = server_name (0)
    (sniExtPayload.length >> 8) & 0xFF,
    sniExtPayload.length & 0xFF,
    ...sniExtPayload,
  ];

  final body = <int>[
    0x03, 0x03, // ClientVersion TLS 1.2
    ...List<int>.filled(32, 0xAB), // Random (32 bytes)
    0x00, // SessionID len = 0
    0x00, 0x02, 0x13, 0x01, // CipherSuites (1 suite)
    0x01, 0x00, // CompressionMethods (null)
    (extBlock.length >> 8) & 0xFF,
    extBlock.length & 0xFF,
    ...extBlock,
  ];

  final handshake = <int>[
    0x01, // HandshakeType = ClientHello
    (body.length >> 16) & 0xFF,
    (body.length >> 8) & 0xFF,
    body.length & 0xFF,
    ...body,
  ];

  return Uint8List.fromList([
    0x16, 0x03, 0x01, // TLS Handshake record header
    (handshake.length >> 8) & 0xFF,
    handshake.length & 0xFF,
    ...handshake,
  ]);
}

/// Выполнить подключение клиента к SOCKS5-прокси на [proxyPort] к целевому
/// [targetHost]:[targetPort], отправить [payload] и прочитать первый ответ.
Future<Uint8List> _socks5Request({
  required int proxyPort,
  required String targetHost,
  required int targetPort,
  required Uint8List payload,
}) async {
  final s = await Socket.connect(InternetAddress.loopbackIPv4, proxyPort);
  final chunks = <int>[];
  final completer = Completer<void>();
  Waiter? currentWaiter;

  s.listen(
    (data) {
      chunks.addAll(data);
      currentWaiter?.notify();
    },
    onDone: () {
      if (!completer.isCompleted) completer.complete();
      currentWaiter?.notify();
    },
    onError: (_) {
      if (!completer.isCompleted) completer.complete();
      currentWaiter?.notify();
    },
  );

  Future<void> waitBytes(int n) async {
    while (chunks.length < n && !completer.isCompleted) {
      final w = Waiter();
      currentWaiter = w;
      await w.future.timeout(const Duration(seconds: 4));
    }
  }

  // 1. Greeting
  s.add(const [0x05, 0x01, 0x00]);
  await s.flush();
  await waitBytes(2);
  chunks.removeRange(0, 2);

  // 2. CONNECT
  final hostBytes = utf8.encode(targetHost);
  s.add([
    0x05,
    0x01,
    0x00,
    0x03,
    hostBytes.length,
    ...hostBytes,
    (targetPort >> 8) & 0xFF,
    targetPort & 0xFF,
  ]);
  await s.flush();
  await waitBytes(10);
  chunks.removeRange(0, 10);

  // 3. Payload
  s.add(payload);
  await s.flush();
  await waitBytes(1);
  await Future<void>.delayed(const Duration(milliseconds: 40));
  final out = Uint8List.fromList(chunks);
  s.destroy();
  return out;
}

class Waiter {
  final Completer<void> _c = Completer<void>();
  Future<void> get future => _c.future;
  void notify() {
    if (!_c.isCompleted) _c.complete();
  }
}

void main() {
  group('TlsClientHelloFragmenter (GDPI / Zapret multisplit)', () {
    test('разбивает TLS ClientHello на 3 валидных TLS-рекорда по SNI без потери байт', () {
      final hello = _buildSampleClientHello('rr1---sn-googlevideo.com');
      expect(TlsClientHelloFragmenter.isTlsClientHello(hello), isTrue);

      final parts = TlsClientHelloFragmenter.fragmentFirstPacket(hello);
      expect(parts.length, 3);

      final reassembledPayload = <int>[];
      for (final rec in parts) {
        expect(rec[0], 0x16);
        expect(rec[1], 0x03);
        expect(rec[2], 0x01);
        final len = (rec[3] << 8) | rec[4];
        expect(rec.length, 5 + len);
        reassembledPayload.addAll(rec.sublist(5));
      }

      // Склеенная полезная нагрузка всех 3 TLS-рекордов побайтно равна исходной!
      expect(reassembledPayload, equals(hello.sublist(5)));
    });

    test('разбивает HTTP-запрос ровно внутри заголовка Host:', () {
      final req = Uint8List.fromList(
        ascii.encode('GET /watch?v=1 HTTP/1.1\r\nHost: www.youtube.com\r\n\r\n'),
      );
      final parts = TlsClientHelloFragmenter.fragmentFirstPacket(req);
      expect(parts.length, 2);
      expect(ascii.decode(parts[0]), endsWith('\r\nHo'));
      expect(ascii.decode(parts[1]), startsWith('st: www.youtube.com'));
    });
  });

  group('LocalDpiBypassProxy (прямой режим и совместный Zapret → VPN)', () {
    test('Режим 1: прямой обход доставляет фрагментированный ClientHello напрямую', () async {
      final receivedRecords = <Uint8List>[];
      final targetServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      targetServer.listen((sock) {
        var replied = false;
        sock.listen((data) {
          receivedRecords.add(Uint8List.fromList(data));
          if (!replied) {
            replied = true;
            sock.add(ascii.encode('SERVER_HELLO_DIRECT'));
            sock.flush();
          }
        });
      });

      final proxy = LocalDpiBypassProxy(
        allowVpnFallback: false,
        directConnector: (host, port, {timeout}) =>
            Socket.connect(InternetAddress.loopbackIPv4, targetServer.port, timeout: timeout),
      );
      final proxyPort = await proxy.start();

      try {
        final hello = _buildSampleClientHello('youtube.com');
        final reply = await _socks5Request(
          proxyPort: proxyPort,
          targetHost: 'youtube.com',
          targetPort: 443,
          payload: hello,
        );
        expect(ascii.decode(reply), 'SERVER_HELLO_DIRECT');
        final allSent = receivedRecords.expand((x) => x).toList();
        // В потоке должно быть 3 заголовка TLS-рекорда (5*3 = 15 байт заголовков вместо 5)
        expect(allSent.length, hello.length + 10);
      } finally {
        await proxy.stop();
        await targetServer.close();
      }
    });

    test('Режим 2 (Zapret → VPN): при сбросе прямого соединения автоматически уходит в VPN SOCKS5', () async {
      // Прямой сервер имитирует RST/блокировку ТСПУ (закрывает сокет без ответа)
      final blockedDirectServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      blockedDirectServer.listen((sock) {
        sock.destroy();
      });

      // Фейковый локальный SOCKS5-сервер активного VPN-ядра
      final fakeVpnSocks = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      fakeVpnSocks.listen((vpnClient) {
        var step = 0;
        vpnClient.listen((data) {
          if (step == 0) {
            step = 1;
            vpnClient.add(const [0x05, 0x00]);
          } else if (step == 1) {
            step = 2;
            vpnClient.add(const [0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
          } else {
            // Получили переигранный ClientHello через VPN!
            vpnClient.add(ascii.encode('SERVER_HELLO_VIA_VPN_FALLBACK'));
            vpnClient.flush();
          }
        });
      });

      final proxy = LocalDpiBypassProxy(
        allowVpnFallback: true,
        vpnSocksPort: fakeVpnSocks.port,
        fallbackTimeout: const Duration(milliseconds: 300),
        directConnector: (host, port, {timeout}) =>
            Socket.connect(InternetAddress.loopbackIPv4, blockedDirectServer.port, timeout: timeout),
      );
      final proxyPort = await proxy.start();

      try {
        final hello = _buildSampleClientHello('discord.com');
        final reply = await _socks5Request(
          proxyPort: proxyPort,
          targetHost: 'discord.com',
          targetPort: 443,
          payload: hello,
        );
        expect(ascii.decode(reply), 'SERVER_HELLO_VIA_VPN_FALLBACK');
        expect(proxy.learnedFallbackHosts, contains('discord.com'));
      } finally {
        await proxy.stop();
        await blockedDirectServer.close();
        await fakeVpnSocks.close();
      }
    });
  });

  group('DpiBypassLists, SplitServicePresets и SingboxConfigBuilder', () {
    test('пресет обхода DPI и маршрутизация через exitOutbounds в SingboxConfigBuilder', () {
      final toggled = SplitServicePresets.toggleDpiBypassPreset(
        const [],
        serverKey: kDpiBypassFallbackKey,
      );
      expect(toggled.added, isTrue);
      expect(
        SplitServicePresets.isDpiBypassPresetActive(
          toggled.sites,
          serverKey: kDpiBypassFallbackKey,
        ),
        isTrue,
      );

      final split = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: toggled.sites,
      );
      final dpiOutbounds = LocalDpiBypassProxy.buildExitOutbounds(
        directPort: 10891,
        fallbackPort: 10892,
      );
      final map = SingboxConfigBuilder(
        xraySocksPort: 10808,
        exitOutbounds: dpiOutbounds,
      ).buildMap(split);

      final outbounds = (map['outbounds'] as List).cast<Map<String, dynamic>>();
      final fallbackTag = exitTagFor(kDpiBypassFallbackKey);
      expect(
        outbounds.any((o) => o['tag'] == fallbackTag && o['server_port'] == 10892),
        isTrue,
      );

      final route = map['route'] as Map<String, dynamic>;
      final rules = (route['rules'] as List).cast<Map<String, dynamic>>();
      expect(
        rules.any((r) =>
            r['outbound'] == fallbackTag &&
            (r['domain_suffix'] as List?)?.contains('youtube.com') == true),
        isTrue,
      );
    });

    test('applyGlobalDpiRules добавляет домены без перезаписи пользовательских правил', () {
      const userRule = SiteRule('youtube.com', action: AppAction.direct);
      const split = SplitTunnelConfig(sites: [userRule]);
      const settings = AppSettings(
        dpiBypassEnabled: true,
        dpiBypassAutoFallbackToVpn: true,
      );

      final merged = DpiBypassLists.applyGlobalDpiRules(split, settings);
      final yt = merged.sites.firstWhere((s) => s.domain == 'youtube.com');
      expect(yt.action, AppAction.direct); // Пользовательское правило сохранено!

      final gv = merged.sites.firstWhere((s) => s.domain == 'googlevideo.com');
      expect(gv.action, AppAction.tunnel);
      expect(gv.serverKey, kDpiBypassFallbackKey);
    });
  });

  group('ZapretWinwsRunner (узкий режим Discord UDP + исключение VPN IP)', () {
    test('формирует ipset-vpn-exclude.txt и узкие аргументы --wf-udp с --ipset-exclude', () async {
      final tmp = await Directory.systemTemp.createTemp('sg_zapret_test_');
      try {
        final file = await ZapretWinwsRunner.writeVpnExcludeIpset(
          tmp,
          const ['203.0.113.230', '203.0.113.205', 'not-an-ip'],
        );
        final content = await file.readAsString();
        expect(content, contains('203.0.113.230'));
        expect(content, contains('203.0.113.205'));
        expect(content, isNot(contains('not-an-ip')));

        final args = ZapretWinwsRunner.buildArgs(
          excludeIpsetPath: file.path,
        );
        expect(args, contains('--wf-udp=443,19294-19344,50000-50100'));
        expect(args.where((a) => a == '--ipset-exclude=${file.path}').length, 2);
      } finally {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
    });
  });
}
