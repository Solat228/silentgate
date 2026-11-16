import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../platform/app_log.dart';
import '../singbox/exit_tags.dart';
import 'dpi_bypass_lists.dart';
import 'dpi_strategy.dart';
import 'physical_nic_socket_windows.dart';

/// Порог байт, при обрыве до которого ТСПУ считается заблокировавшим поток
/// по счётчику пакета (типичная блокировка Cloudflare / CDN на 16–20 КБ).
const int kTspuFreezeThresholdBytes = 24 * 1024;

/// Сводная статистика живого рантайма обхода DPI для отображения на экране настроек Zapret.
class DpiRuntimeRegistry {
  DpiRuntimeRegistry._();

  static final Set<LocalDpiBypassProxy> _liveProxies = <LocalDpiBypassProxy>{};
  static bool winwsRunning = false;
  static String? winwsBinaryPath;

  static void register(LocalDpiBypassProxy proxy) {
    _liveProxies.add(proxy);
  }

  static void unregister(LocalDpiBypassProxy proxy) {
    _liveProxies.remove(proxy);
  }

  static bool get isProxyRunning => _liveProxies.any((p) => p.isRunning);

  static int get directSuccessCount =>
      _liveProxies.fold(0, (sum, p) => sum + p.directSuccessCount);

  static int get fallbackCount =>
      _liveProxies.fold(0, (sum, p) => sum + p.fallbackCount);

  static Set<String> get learnedFallbackHosts => {
        for (final p in _liveProxies) ...p.learnedFallbackHosts,
      };

  static void clearLearnedFallbacks() {
    for (final p in _liveProxies) {
      p.clearLearnedFallbacks();
    }
  }
}

/// Фрагментатор TLS `ClientHello` и HTTP `Host:` в стиле `GoodByeDPI` / `Zapret` (`multisplit`).
///
/// Разбивает одну запись TLS Handshake (`0x16`) на 2–3 легитимных TLS-рекорда
/// (первый разрез на 2-м байте полезной нагрузки, второй — ровно внутри имени
/// хоста в расширении SNI `0x0000`). Для всех стандартных TLS-серверов это
/// полностью валидный RFC 5246/8446 поток, но сигнатурные анализаторы DPI/ТСПУ,
/// ожидающие полный `ClientHello` в одном рекорде, не видят SNI.
class TlsClientHelloFragmenter {
  TlsClientHelloFragmenter._();

  /// Является ли пакет началом TLS `ClientHello` (`ContentType == 0x16`, `HandshakeType == 0x01`).
  static bool isTlsClientHello(Uint8List data) {
    if (data.length < 44) return false;
    // ContentType: Handshake (0x16), Legacy Version: 0x0301..0x0304
    if (data[0] != 0x16 || data[1] != 0x03) return false;
    // HandshakeType: ClientHello (0x01)
    if (data[5] != 0x01) return false;
    return true;
  }

  /// Найти смещение (относительно начала payload первой TLS-записи, т.е. `data[5..]`)
  /// середины SNI-домена внутри расширения `server_name` (`0x0000`).
  static int? findSniPayloadOffset(Uint8List payload) {
    final info = DpiDesyncConfig.inspectSniOffsets(payload);
    return info?.splitOffset;
  }

  /// Разбить первый пакет соединения (`ClientHello` или HTTP-запрос) на
  /// фрагменты для отправки отдельными TCP-сегментами.
  static List<Uint8List> fragmentFirstPacket(Uint8List data) {
    if (isTlsClientHello(data)) {
      final recordLen = (data[3] << 8) | data[4];
      if (recordLen > 6 && 5 + recordLen <= data.length) {
        final major = data[1];
        final minor = data[2];
        final payload = Uint8List.sublistView(data, 5, 5 + recordLen);

        final sniSplit = findSniPayloadOffset(payload);
        final split1 = 2; // аналог --dpi-desync-split-pos=2
        final split2 = (sniSplit != null && sniSplit > split1 + 1 && sniSplit < recordLen)
            ? sniSplit
            : (recordLen ~/ 2 > split1 + 1 ? recordLen ~/ 2 : null);

        final out = <Uint8List>[];
        if (split2 != null) {
          out.add(_wrapTlsRecord(major, minor, Uint8List.sublistView(payload, 0, split1)));
          out.add(_wrapTlsRecord(major, minor, Uint8List.sublistView(payload, split1, split2)));
          out.add(_wrapTlsRecord(major, minor, Uint8List.sublistView(payload, split2)));
        } else {
          out.add(_wrapTlsRecord(major, minor, Uint8List.sublistView(payload, 0, split1)));
          out.add(_wrapTlsRecord(major, minor, Uint8List.sublistView(payload, split1)));
        }
        if (data.length > 5 + recordLen) {
          out.add(Uint8List.fromList(Uint8List.sublistView(data, 5 + recordLen)));
        }
        return out;
      }
    }

    // Plain HTTP: разбиваем заголовок `Host: ` пополам (`Ho` + `st: ...`)
    final httpSplit = _findHttpHostSplit(data);
    if (httpSplit != null && httpSplit > 0 && httpSplit < data.length) {
      return [
        Uint8List.fromList(Uint8List.sublistView(data, 0, httpSplit)),
        Uint8List.fromList(Uint8List.sublistView(data, httpSplit)),
      ];
    }

    return [data];
  }

  static Uint8List _wrapTlsRecord(int major, int minor, Uint8List slice) {
    final len = slice.length;
    final out = Uint8List(5 + len);
    out[0] = 0x16;
    out[1] = major;
    out[2] = minor;
    out[3] = (len >> 8) & 0xFF;
    out[4] = len & 0xFF;
    out.setRange(5, 5 + len, slice);
    return out;
  }

  static int? _findHttpHostSplit(Uint8List data) {
    if (data.length < 16) return null;
    final b0 = data[0];
    if (b0 != 0x47 && b0 != 0x50 && b0 != 0x48 && b0 != 0x4F) return null;
    final limit = data.length < 1024 ? data.length - 7 : 1024 - 7;
    for (var i = 0; i < limit; i++) {
      if (data[i] == 0x0D &&
          data[i + 1] == 0x0A &&
          (data[i + 2] | 0x20) == 0x68 &&
          (data[i + 3] | 0x20) == 0x6F &&
          (data[i + 4] | 0x20) == 0x73 &&
          (data[i + 5] | 0x20) == 0x74 &&
          data[i + 6] == 0x3A) {
        return i + 4;
      }
    }
    return null;
  }
}

/// Локальный SOCKS5 + HTTP-CONNECT прокси обхода DPI (встроенная в `SilentGate`
/// технология `Zapret` / `ByeDPI` / `GoodByeDPI`).
///
/// Ключевые отличия:
/// * На Windows при `bindToPhysicalNic == true` открывает сокеты напрямую через
///   физический адаптер по умолчанию (`IP_UNICAST_IF`), гарантированно обходя
///   пересборку сегментов в драйвере `Wintun` (`silentgate-tun`) и отправляя
///   настоящий TCP `MSG_OOB` байт прямо в середину SNI.
/// * В совместном режиме «Zapret → VPN» (`allowVpnFallback == true`) при RST,
///   таймауте или заморозке потока на 16–24 КБ ТСПУ прозрачно переигрывает
///   соединение через активный VPN-туннель (`127.0.0.1:vpnSocksPort`).
class LocalDpiBypassProxy {
  final bool allowVpnFallback;
  int? vpnSocksPort;
  String? vpnSocksUsername;
  String? vpnSocksPassword;
  Duration fallbackTimeout;
  int tspuThresholdBytes;
  DpiDesyncConfig strategy;
  final bool bindToPhysicalNic;
  final bool registerInRuntime;
  final Future<Socket> Function(String host, int port, {Duration? timeout})?
      _customDirectConnector;

  ServerSocket? _server;
  final Set<Socket> _activeClientSockets = <Socket>{};
  final Set<DpiUpstreamSocket> _activeUpstreams = <DpiUpstreamSocket>{};
  final Set<String> _vpnFallbackHosts = <String>{};

  int _directSuccessCount = 0;
  int _fallbackCount = 0;

  LocalDpiBypassProxy({
    required this.allowVpnFallback,
    this.vpnSocksPort,
    this.vpnSocksUsername,
    this.vpnSocksPassword,
    this.fallbackTimeout = const Duration(milliseconds: 1800),
    this.tspuThresholdBytes = kTspuFreezeThresholdBytes,
    this.strategy = DpiDesyncConfig.legacyDefault,
    this.bindToPhysicalNic = false,
    this.registerInRuntime = false,
    Future<Socket> Function(String host, int port, {Duration? timeout})?
        directConnector,
  }) : _customDirectConnector = directConnector;

  /// Порт, на котором слушает локальный прокси-сервер (0 — если не запущен).
  int get port => _server?.port ?? 0;

  /// Запущен ли прокси.
  bool get isRunning => _server != null;

  /// Количество успешных прямых соединений через Zapret.
  int get directSuccessCount => _directSuccessCount;

  /// Количество соединений, автоматически переведённых в VPN.
  int get fallbackCount => _fallbackCount;

  /// Домены, автоматически переведённые на VPN-фоллбэк в текущей сессии.
  Set<String> get learnedFallbackHosts => Set.unmodifiable(_vpnFallbackHosts);

  /// Принудительно пометить хост как требующий VPN-фоллбэка.
  void markHostForVpnFallback(String host) {
    final norm = host.trim().toLowerCase();
    if (norm.isNotEmpty) {
      _vpnFallbackHosts.add(norm);
    }
  }

  /// Очистить кэш доменов, переведённых на VPN-фоллбэк (например, после смены стратегии).
  void clearLearnedFallbacks() {
    _vpnFallbackHosts.clear();
  }

  /// Обновить стратегию и пороги на лету без смены порта прокси.
  void updateConfig({
    DpiDesyncConfig? strategy,
    Duration? fallbackTimeout,
    int? tspuThresholdBytes,
  }) {
    if (strategy != null && strategy.preset != this.strategy.preset) {
      _vpnFallbackHosts.clear();
    }
    if (strategy != null) this.strategy = strategy;
    if (fallbackTimeout != null) this.fallbackTimeout = fallbackTimeout;
    if (tspuThresholdBytes != null) {
      this.tspuThresholdBytes = tspuThresholdBytes;
    }
  }

  /// Обновить реквизиты локального SOCKS5 активного VPN-ядра без перезапуска прокси.
  void updateVpnSocks({
    required int? port,
    String? username,
    String? password,
  }) {
    vpnSocksPort = port;
    vpnSocksUsername = username;
    vpnSocksPassword = password;
  }

  /// Запустить локальный SOCKS5 / HTTP-CONNECT сервер на `127.0.0.1`.
  Future<int> start({int bindPort = 0}) async {
    if (_server != null) return _server!.port;
    final srv = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      bindPort,
      shared: false,
    );
    _server = srv;
    if (registerInRuntime) {
      DpiRuntimeRegistry.register(this);
    }
    srv.listen(
      _handleClient,
      onError: (Object e) => AppLog.w('DPI-прокси ошибка сокета: $e'),
      cancelOnError: false,
    );
    final gw = (bindToPhysicalNic && Platform.isWindows)
        ? PhysicalNicSocketManager.instance.currentGateway()
        : null;
    AppLog.i(
      'DPI-прокси запущен на 127.0.0.1:${srv.port} '
      '(режим: ${allowVpnFallback ? "Zapret → VPN" : "только Zapret"}, '
      'стратегия: ${strategy.preset.name}'
      '${gw != null ? ", адаптер: ${gw.displayLabel}" : ""})',
    );
    return srv.port;
  }

  /// Остановить прокси и закрыть активные соединения.
  Future<void> stop() async {
    if (registerInRuntime) {
      DpiRuntimeRegistry.unregister(this);
    }
    final srv = _server;
    _server = null;
    if (srv != null) {
      try {
        await srv.close();
      } catch (_) {}
    }
    for (final s in _activeClientSockets.toList()) {
      try {
        s.destroy();
      } catch (_) {}
    }
    _activeClientSockets.clear();
    for (final u in _activeUpstreams.toList()) {
      u.destroy();
    }
    _activeUpstreams.clear();
  }

  /// Сформировать список дополнительных `exitOutbounds` для `SingboxConfigBuilder`.
  static List<Map<String, dynamic>> buildExitOutbounds({
    int? directPort,
    int? fallbackPort,
  }) {
    final out = <Map<String, dynamic>>[];
    if (directPort != null && directPort > 0) {
      out.add({
        'type': 'socks',
        'tag': exitTagFor(kDpiBypassDirectKey),
        'server': '127.0.0.1',
        'server_port': directPort,
        'version': '5',
      });
    }
    if (fallbackPort != null && fallbackPort > 0) {
      out.add({
        'type': 'socks',
        'tag': exitTagFor(kDpiBypassFallbackKey),
        'server': '127.0.0.1',
        'server_port': fallbackPort,
        'version': '5',
      });
    }
    return out;
  }

  Future<DpiUpstreamSocket> _openDirectUpstream(
    String host,
    int port, {
    required Duration timeout,
  }) async {
    if (_customDirectConnector != null) {
      final sock = await _customDirectConnector(host, port, timeout: timeout);
      return DartDpiUpstreamSocket(sock);
    }
    if (bindToPhysicalNic && Platform.isWindows) {
      return PhysicalNicSocketManager.instance.connect(
        host,
        port,
        timeout: timeout,
      );
    }
    final sock = await Socket.connect(host, port, timeout: timeout);
    return DartDpiUpstreamSocket(sock);
  }

  Future<void> _handleClient(Socket client) async {
    _activeClientSockets.add(client);
    try {
      client.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}

    final reader = _BufferedStreamReader.fromSocket(client);
    try {
      final peek = await reader.readExact(1, timeout: const Duration(seconds: 5));
      if (peek == null) {
        client.destroy();
        return;
      }

      String targetHost;
      int targetPort;

      if (peek[0] == 0x05) {
        // ── SOCKS5 рукопожатие ──────────────────────────────────────────────
        final nMethBytes =
            await reader.readExact(1, timeout: const Duration(seconds: 5));
        if (nMethBytes == null) {
          client.destroy();
          return;
        }
        final methods = await reader.readExact(
          nMethBytes[0],
          timeout: const Duration(seconds: 5),
        );
        if (methods == null) {
          client.destroy();
          return;
        }
        client.add(const [0x05, 0x00]);
        await client.flush();

        final reqHdr =
            await reader.readExact(4, timeout: const Duration(seconds: 5));
        if (reqHdr == null || reqHdr[0] != 0x05 || reqHdr[1] != 0x01) {
          client.add(const [0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
          await client.flush();
          client.destroy();
          return;
        }

        final atyp = reqHdr[3];
        if (atyp == 0x01) {
          final ipBytes =
              await reader.readExact(4, timeout: const Duration(seconds: 5));
          if (ipBytes == null) {
            client.destroy();
            return;
          }
          targetHost = ipBytes.join('.');
        } else if (atyp == 0x03) {
          final lenByte =
              await reader.readExact(1, timeout: const Duration(seconds: 5));
          if (lenByte == null) {
            client.destroy();
            return;
          }
          final domainBytes = await reader.readExact(
            lenByte[0],
            timeout: const Duration(seconds: 5),
          );
          if (domainBytes == null) {
            client.destroy();
            return;
          }
          targetHost = utf8.decode(domainBytes, allowMalformed: true);
        } else if (atyp == 0x04) {
          final ip6Bytes =
              await reader.readExact(16, timeout: const Duration(seconds: 5));
          if (ip6Bytes == null) {
            client.destroy();
            return;
          }
          final parts = <String>[];
          for (var i = 0; i < 16; i += 2) {
            parts.add(((ip6Bytes[i] << 8) | ip6Bytes[i + 1]).toRadixString(16));
          }
          targetHost = parts.join(':');
        } else {
          client.add(const [0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
          await client.flush();
          client.destroy();
          return;
        }

        final portBytes =
            await reader.readExact(2, timeout: const Duration(seconds: 5));
        if (portBytes == null) {
          client.destroy();
          return;
        }
        targetPort = (portBytes[0] << 8) | portBytes[1];

        client.add(const [0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await client.flush();
      } else if (peek[0] == 0x43 || peek[0] == 0x63) {
        // ── HTTP CONNECT (удобно для HttpClient в живой проверке и автоподборе) ──
        final rest = await reader.readUntilCrLfCrLf(
          initial: peek,
          timeout: const Duration(seconds: 5),
        );
        if (rest == null) {
          client.destroy();
          return;
        }
        final headerText = ascii.decode(rest, allowInvalid: true);
        final firstLine = headerText.split('\r\n').first;
        final match =
            RegExp(r'^CONNECT\s+([^\s:]+):(\d+)\s+HTTP/', caseSensitive: false)
                .firstMatch(firstLine);
        if (match == null) {
          client.destroy();
          return;
        }
        targetHost = match.group(1)!;
        targetPort = int.tryParse(match.group(2)!) ?? 443;
        client.add(ascii.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
        await client.flush();
      } else {
        client.destroy();
        return;
      }

      // Ждём первый пакет от клиента (TLS ClientHello или HTTP-запрос)
      final firstPacket =
          await reader.readAvailable(timeout: const Duration(seconds: 3));

      // Если целью пришёл голый IP, пробуем извлечь реальное имя домена из SNI
      // для точного кэширования `_vpnFallbackHosts` и логов!
      final sniHost = firstPacket != null ? _extractSniDomain(firstPacket) : null;
      final normHost = (sniHost ?? targetHost).trim().toLowerCase();
      final canFallback = allowVpnFallback && (vpnSocksPort ?? 0) > 0;

      if (canFallback && _vpnFallbackHosts.contains(normHost)) {
        _fallbackCount++;
        final vpn = await _connectViaVpnSocks(
          sniHost ?? targetHost,
          targetPort,
        );
        if (vpn != null) {
          _activeUpstreams.add(vpn.upstream);
          if (firstPacket != null && firstPacket.isNotEmpty) {
            vpn.upstream.write(firstPacket);
            await vpn.upstream.flush();
          }
          await _pipeRest(
            reader,
            client,
            vpn.upstream,
            remoteReader: vpn.reader,
          );
          return;
        }
      }

      await _tryDirectWithOptionalFallback(
        reader: reader,
        client: client,
        targetHost: targetHost,
        vpnHost: sniHost ?? targetHost,
        normHost: normHost,
        targetPort: targetPort,
        firstPacket: firstPacket,
        canFallback: canFallback,
      );
    } catch (_) {
      try {
        client.destroy();
      } catch (_) {}
    } finally {
      _activeClientSockets.remove(client);
    }
  }

  static String? _extractSniDomain(Uint8List data) {
    if (!TlsClientHelloFragmenter.isTlsClientHello(data)) return null;
    final recordLen = (data[3] << 8) | data[4];
    if (recordLen <= 6 || 5 + recordLen > data.length) return null;
    final payload = Uint8List.sublistView(data, 5, 5 + recordLen);
    final info = DpiDesyncConfig.inspectSniOffsets(payload);
    if (info == null) return null;
    final end = info.hostStart + info.hostLength;
    if (end > payload.length) return null;
    return utf8.decode(
      Uint8List.sublistView(payload, info.hostStart, end),
      allowMalformed: true,
    );
  }

  Future<void> _tryDirectWithOptionalFallback({
    required _BufferedStreamReader reader,
    required Socket client,
    required String targetHost,
    required String vpnHost,
    required String normHost,
    required int targetPort,
    required Uint8List? firstPacket,
    required bool canFallback,
  }) async {
    DpiUpstreamSocket? direct;
    try {
      direct = await _openDirectUpstream(
        targetHost,
        targetPort,
        timeout: canFallback ? fallbackTimeout : const Duration(seconds: 6),
      );
      _activeUpstreams.add(direct);
    } catch (_) {
      if (canFallback) {
        _vpnFallbackHosts.add(normHost);
        _fallbackCount++;
        final vpn = await _connectViaVpnSocks(vpnHost, targetPort);
        if (vpn != null) {
          _activeUpstreams.add(vpn.upstream);
          if (firstPacket != null && firstPacket.isNotEmpty) {
            vpn.upstream.write(firstPacket);
            await vpn.upstream.flush();
          }
          await _pipeRest(
            reader,
            client,
            vpn.upstream,
            remoteReader: vpn.reader,
          );
          return;
        }
      }
      client.destroy();
      return;
    }

    final remoteReader = _BufferedStreamReader(direct.stream);

    if (!canFallback || firstPacket == null || firstPacket.isEmpty) {
      if (firstPacket != null && firstPacket.isNotEmpty) {
        await _sendDesynced(direct, firstPacket);
      }
      final firstReply =
          await remoteReader.readAvailable(timeout: const Duration(seconds: 5));
      if (firstReply != null && firstReply.isNotEmpty) {
        _directSuccessCount++;
        client.add(firstReply);
        await client.flush();
      }
      await _pipeRest(reader, client, direct, remoteReader: remoteReader);
      return;
    }

    try {
      await _sendDesynced(direct, firstPacket);
      final firstReply = await remoteReader.readAvailable(timeout: fallbackTimeout);
      if (firstReply == null || firstReply.isEmpty) {
        throw const SocketException(
          'Empty or timed out ServerHello after DPI desync',
        );
      }

      _directSuccessCount++;
      client.add(firstReply);
      await client.flush();

      await _pipeWithTspuMonitor(
        clientReader: reader,
        client: client,
        remoteReader: remoteReader,
        remote: direct,
        normHost: normHost,
        initialRemoteBytes: firstReply.length,
      );
    } catch (_) {
      _activeUpstreams.remove(direct);
      remoteReader.dispose();
      direct.destroy();
      _vpnFallbackHosts.add(normHost);
      _fallbackCount++;
      AppLog.i(
        'DPI → VPN фоллбэк для $normHost:$targetPort (прямой обход не ответил)',
      );

      final vpn = await _connectViaVpnSocks(vpnHost, targetPort);
      if (vpn != null) {
        _activeUpstreams.add(vpn.upstream);
        vpn.upstream.write(firstPacket);
        await vpn.upstream.flush();
        await _pipeRest(
          reader,
          client,
          vpn.upstream,
          remoteReader: vpn.reader,
        );
      } else {
        client.destroy();
      }
    }
  }

  Future<void> _sendDesynced(DpiUpstreamSocket remote, Uint8List packet) async {
    final segments = strategy.buildSegments(
      packet,
      socketSupportsOob: remote.supportsOob,
    );
    await remote.sendSegments(segments);
  }

  Future<({DpiUpstreamSocket upstream, _BufferedStreamReader reader})?>
      _connectViaVpnSocks(
    String targetHost,
    int targetPort,
  ) async {
    final socksPort = vpnSocksPort;
    if (socksPort == null || socksPort <= 0) return null;
    Socket? s;
    try {
      s = await Socket.connect(
        InternetAddress.loopbackIPv4,
        socksPort,
        timeout: const Duration(seconds: 5),
      );
      final upstream = DartDpiUpstreamSocket(s);
      final r = _BufferedStreamReader(upstream.stream);
      final user = vpnSocksUsername;
      final pass = vpnSocksPassword;
      final hasAuth =
          user != null && user.isNotEmpty && pass != null && pass.isNotEmpty;

      if (hasAuth) {
        s.add(const [0x05, 0x02, 0x00, 0x02]);
      } else {
        s.add(const [0x05, 0x01, 0x00]);
      }
      await s.flush();

      final greet = await r.readExact(2, timeout: const Duration(seconds: 4));
      if (greet == null || greet[0] != 0x05) {
        r.dispose();
        upstream.destroy();
        return null;
      }
      if (greet[1] == 0x02 && hasAuth) {
        final uBytes = utf8.encode(user);
        final pBytes = utf8.encode(pass);
        s.add([0x01, uBytes.length, ...uBytes, pBytes.length, ...pBytes]);
        await s.flush();
        final authResp =
            await r.readExact(2, timeout: const Duration(seconds: 4));
        if (authResp == null || authResp[1] != 0x00) {
          r.dispose();
          upstream.destroy();
          return null;
        }
      } else if (greet[1] != 0x00) {
        r.dispose();
        upstream.destroy();
        return null;
      }

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

      final connHdr = await r.readExact(4, timeout: const Duration(seconds: 5));
      if (connHdr == null || connHdr[1] != 0x00) {
        r.dispose();
        upstream.destroy();
        return null;
      }
      final atyp = connHdr[3];
      final skipLen = atyp == 0x01
          ? 6
          : atyp == 0x04
              ? 18
              : 0;
      if (skipLen > 0) {
        await r.readExact(skipLen, timeout: const Duration(seconds: 4));
      } else if (atyp == 0x03) {
        final l = await r.readExact(1, timeout: const Duration(seconds: 4));
        if (l != null) {
          await r.readExact(l[0] + 2, timeout: const Duration(seconds: 4));
        }
      }

      return (upstream: upstream, reader: r);
    } catch (_) {
      try {
        s?.destroy();
      } catch (_) {}
      return null;
    }
  }

  Future<void> _pipeRest(
    _BufferedStreamReader clientReader,
    Socket client,
    DpiUpstreamSocket remote, {
    required _BufferedStreamReader remoteReader,
  }) async {
    final leftover = clientReader.takeRemaining();
    if (leftover.isNotEmpty) {
      remote.write(leftover);
      await remote.flush();
    }
    final remLeftover = remoteReader.takeRemaining();
    if (remLeftover.isNotEmpty) {
      client.add(remLeftover);
      await client.flush();
    }
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    final sub1 = clientReader.stream.listen(
      (chunk) => remote.write(chunk),
      onError: (_) => finish(),
      onDone: finish,
      cancelOnError: true,
    );
    final sub2 = remoteReader.stream.listen(
      (chunk) => client.add(chunk),
      onError: (_) => finish(),
      onDone: finish,
      cancelOnError: true,
    );
    await done.future;
    await sub1.cancel();
    await sub2.cancel();
    clientReader.dispose();
    remoteReader.dispose();
    _activeUpstreams.remove(remote);
    remote.destroy();
    try {
      client.destroy();
    } catch (_) {}
  }

  Future<void> _pipeWithTspuMonitor({
    required _BufferedStreamReader clientReader,
    required Socket client,
    required _BufferedStreamReader remoteReader,
    required DpiUpstreamSocket remote,
    required String normHost,
    required int initialRemoteBytes,
  }) async {
    var remoteBytes = initialRemoteBytes;
    var remoteErrored = false;
    var frozenInTspuWindow = false;
    Timer? freezeWatchdog;

    final clientLeftover = clientReader.takeRemaining();
    if (clientLeftover.isNotEmpty) {
      remote.write(clientLeftover);
    }
    final remoteLeftover = remoteReader.takeRemaining();
    if (remoteLeftover.isNotEmpty) {
      remoteBytes += remoteLeftover.length;
      client.add(remoteLeftover);
    }

    final done = Completer<void>();
    void finish() {
      freezeWatchdog?.cancel();
      if (!done.isCompleted) done.complete();
    }

    void armFreezeWatchdog() {
      freezeWatchdog?.cancel();
      // Типичный silent-drop ТСПУ замораживает поток ровно на 14–22 КБ без RST:
      // если объём вошёл в окно 10 КБ .. tspuThresholdBytes и замер на 4.5 с,
      // помечаем хост для VPN-фоллбэка и разрываем повисший сокет, чтобы браузер
      // сразу переподключился через VPN!
      if (remoteBytes >= 10 * 1024 && remoteBytes < tspuThresholdBytes) {
        freezeWatchdog = Timer(const Duration(milliseconds: 4500), () {
          if (remoteBytes >= 10 * 1024 && remoteBytes < tspuThresholdBytes) {
            frozenInTspuWindow = true;
            finish();
          }
        });
      }
    }

    armFreezeWatchdog();

    final sub1 = clientReader.stream.listen(
      (chunk) => remote.write(chunk),
      onError: (_) => finish(),
      onDone: finish,
      cancelOnError: true,
    );
    final sub2 = remoteReader.stream.listen(
      (chunk) {
        remoteBytes += chunk.length;
        armFreezeWatchdog();
        client.add(chunk);
      },
      onError: (_) {
        remoteErrored = true;
        finish();
      },
      onDone: finish,
      cancelOnError: true,
    );

    await done.future;
    await sub1.cancel();
    await sub2.cancel();
    clientReader.dispose();
    remoteReader.dispose();

    if ((remoteErrored || frozenInTspuWindow) &&
        remoteBytes > 0 &&
        remoteBytes < tspuThresholdBytes) {
      _vpnFallbackHosts.add(normHost);
      _fallbackCount++;
      AppLog.i(
        'DPI: обнаружена блокировка ТСПУ на $remoteBytes байтах для $normHost — '
        'следующие соединения пойдут через VPN',
      );
    }

    _activeUpstreams.remove(remote);
    remote.destroy();
    try {
      client.destroy();
    } catch (_) {}
  }
}

/// Буферизующий читатель поверх `Stream<Uint8List>`, позволяющий сначала
/// прочитать заголовки SOCKS5/CONNECT и первый пакет `ClientHello`, а затем
/// переключить поток в режим потоковой пересылки без повторного `listen()`.
class _BufferedStreamReader {
  final List<int> _buffer = <int>[];
  final StreamController<Uint8List> _passthrough =
      StreamController<Uint8List>();
  late final StreamSubscription<Uint8List> _sub;
  Completer<void>? _waiter;
  bool _closed = false;
  bool _streaming = false;

  _BufferedStreamReader(Stream<Uint8List> source) {
    _sub = source.listen(
      (chunk) {
        if (_streaming) {
          if (!_passthrough.isClosed) _passthrough.add(chunk);
          return;
        }
        _buffer.addAll(chunk);
        final w = _waiter;
        _waiter = null;
        if (w != null && !w.isCompleted) w.complete();
      },
      onError: (Object e, StackTrace st) {
        _closed = true;
        final w = _waiter;
        _waiter = null;
        if (w != null && !w.isCompleted) w.complete();
        if (_streaming && !_passthrough.isClosed) {
          _passthrough.addError(e, st);
        }
      },
      onDone: () {
        _closed = true;
        final w = _waiter;
        _waiter = null;
        if (w != null && !w.isCompleted) w.complete();
        if (!_passthrough.isClosed) _passthrough.close();
      },
      cancelOnError: false,
    );
  }

  factory _BufferedStreamReader.fromSocket(Socket socket) =>
      _BufferedStreamReader(socket);

  Future<Uint8List?> readExact(int count, {required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (_buffer.length < count) {
      if (_closed) return null;
      final rem = deadline.difference(DateTime.now());
      if (rem <= Duration.zero) return null;
      final w = Completer<void>();
      _waiter = w;
      try {
        await w.future.timeout(rem);
      } on TimeoutException {
        _waiter = null;
        return null;
      }
    }
    final out = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return out;
  }

  Future<Uint8List?> readUntilCrLfCrLf({
    required Uint8List initial,
    required Duration timeout,
  }) async {
    final acc = <int>[...initial];
    final deadline = DateTime.now().add(timeout);
    while (acc.length < 8192) {
      while (_buffer.isNotEmpty) {
        acc.add(_buffer.removeAt(0));
        final n = acc.length;
        if (n >= 4 &&
            acc[n - 4] == 0x0D &&
            acc[n - 3] == 0x0A &&
            acc[n - 2] == 0x0D &&
            acc[n - 1] == 0x0A) {
          return Uint8List.fromList(acc);
        }
      }
      if (_closed) return null;
      final rem = deadline.difference(DateTime.now());
      if (rem <= Duration.zero) return null;
      final w = Completer<void>();
      _waiter = w;
      try {
        await w.future.timeout(rem);
      } on TimeoutException {
        _waiter = null;
        return null;
      }
    }
    return null;
  }

  Future<Uint8List?> readAvailable({required Duration timeout}) async {
    if (_buffer.isEmpty && !_closed) {
      final w = Completer<void>();
      _waiter = w;
      try {
        await w.future.timeout(timeout);
      } on TimeoutException {
        _waiter = null;
        return null;
      }
    }
    if (_buffer.isEmpty) return null;
    final out = Uint8List.fromList(_buffer);
    _buffer.clear();
    return out;
  }

  Uint8List takeRemaining() {
    _streaming = true;
    if (_buffer.isEmpty) return Uint8List(0);
    final out = Uint8List.fromList(_buffer);
    _buffer.clear();
    return out;
  }

  Stream<Uint8List> get stream {
    _streaming = true;
    return _passthrough.stream;
  }

  void dispose() {
    _sub.cancel();
    if (!_passthrough.isClosed) {
      _passthrough.close();
    }
  }
}
