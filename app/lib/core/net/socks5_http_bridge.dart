import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models/vpn_server.dart';
import '../whitelist_bypass/whitelist_bypass_helper.dart';
import 'ip_info.dart';

/// Выделяет свободный локальный TCP-порт на `127.0.0.1`.
Future<int> allocateLoopbackPort() async {
  final srv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = srv.port;
  await srv.close();
  return port;
}

/// Кэш реальных выходных IP-адресов серверов обхода белых списков (`whitelist://` и `/sgbs`).
///
/// Сигнальные домены (`vk.ru`, `telemost.yandex.ru` и т.д.) принадлежат площадке
/// звонков, а не выходной ноде, поэтому реальный IP определяется запросом ВНУТРИ
/// звонка и кэшируется на время сессии приложения.
abstract final class WhitelistExitIpCache {
  static final Map<String, IpInfo> _byRoomKey = <String, IpInfo>{};

  static String keyFor(VpnServer s) {
    if (s.usesWhitelistRelay) {
      final platform = (s.whitelistPlatform ?? '').trim().toLowerCase();
      final room = WhitelistBypassSpec.normalizeRoom(
        platform,
        s.whitelistRoom ?? '',
      );
      if (platform.isNotEmpty && room.isNotEmpty) {
        return 'bs|$platform|$room';
      }
    }
    return s.key;
  }

  static IpInfo? get(VpnServer s) => _byRoomKey[keyFor(s)];

  static void put(VpnServer s, IpInfo info) {
    if (info.ip.trim().isEmpty) return;
    _byRoomKey[keyFor(s)] = info;
  }

  static void clear() => _byRoomKey.clear();
}

/// Лёгкий локальный мост `HTTP Proxy (Basic Auth) -> SOCKS5 (127.0.0.1:socksPort)`.
///
/// Зачем он нужен:
/// - `whitelist-bypass` (`whitelist-bypass.exe` на Windows и `librelay.so` на Android)
///   поднимает локальный SOCKS5-порт внутри активного WebRTC-звонка;
/// - все штатные потребители проб в приложении (`ProxyProbe`, `SpeedTest`,
///   `IpInfoService`) ходят через локальный HTTP-прокси с Basic-аутентификацией;
/// - мост закрывает свой порт на `127.0.0.1` случайным паролем и переводит как
///   `CONNECT host:port` (HTTPS), так и обычные `GET/HEAD http://...` запросы
///   в SOCKS5-соединения с полноценным backpressure (для замеров 5–20 МБ).
class LocalHttpToSocksBridge {
  final ServerSocket _server;
  final int socksPort;
  final String user;
  final String password;
  final bool preferIpv4;
  final String _expectedBasicToken;
  final Set<Socket> _activeSockets = <Socket>{};
  bool _stopped = false;

  LocalHttpToSocksBridge._({
    required ServerSocket server,
    required this.socksPort,
    required this.user,
    required this.password,
    this.preferIpv4 = false,
  })  : _server = server,
        _expectedBasicToken = base64Encode(utf8.encode('$user:$password')) {
    _server.listen(
      _handleClient,
      onError: (_) {},
      cancelOnError: false,
    );
  }

  int get port => _server.port;

  static String _randomHex(int length) {
    final rnd = Random.secure();
    return List.generate(length, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  static Future<LocalHttpToSocksBridge> start({
    required int socksPort,
    String user = 'sgprobe',
    String? password,
    bool preferIpv4 = false,
  }) async {
    final srv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return LocalHttpToSocksBridge._(
      server: srv,
      socksPort: socksPort,
      user: user,
      password: password ?? _randomHex(32),
      preferIpv4: preferIpv4,
    );
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    try {
      await _server.close();
    } catch (_) {}
    final sockets = List<Socket>.from(_activeSockets);
    _activeSockets.clear();
    for (final s in sockets) {
      try {
        s.destroy();
      } catch (_) {}
    }
  }

  void _trackSocket(Socket s) {
    if (_stopped) {
      s.destroy();
      return;
    }
    _activeSockets.add(s);
    s.done.whenComplete(() => _activeSockets.remove(s)).ignore();
  }

  Future<void> _handleClient(Socket client) async {
    _trackSocket(client);
    client.setOption(SocketOption.tcpNoDelay, true);
    final clientChan = _SocketChannel(client);
    Socket? socks;
    _SocketChannel? socksChan;

    try {
      final headerRes = await clientChan
          .readHttpHeader(maxBytes: 16384)
          .timeout(const Duration(seconds: 15));
      if (headerRes == null) {
        await clientChan.dispose();
        return;
      }

      final lines = headerRes.headerText.split('\r\n');
      if (lines.isEmpty || lines.first.trim().isEmpty) {
        await clientChan.dispose();
        return;
      }

      if (!_checkProxyAuth(lines)) {
        client.add(ascii.encode(
          'HTTP/1.1 407 Proxy Authentication Required\r\n'
          'Proxy-Authenticate: Basic realm="SilentGate"\r\n'
          'Connection: close\r\n'
          'Content-Length: 0\r\n\r\n',
        ));
        await client.flush().catchError((_) {});
        await clientChan.dispose();
        return;
      }

      final reqParts = lines.first.split(' ');
      if (reqParts.length < 2) {
        await clientChan.dispose();
        return;
      }
      final method = reqParts[0].toUpperCase();
      final rawTarget = reqParts[1];
      final httpVersion = reqParts.length >= 3 ? reqParts[2] : 'HTTP/1.1';

      String targetHost;
      int targetPort;
      Uint8List? initialUpstreamPayload;

      if (method == 'CONNECT') {
        final parsed = _parseConnectAuthority(rawTarget);
        if (parsed == null) {
          await _replyError(client, clientChan, '400 Bad Request');
          return;
        }
        targetHost = parsed.host;
        targetPort = parsed.port;
      } else {
        final uri = Uri.tryParse(rawTarget);
        if (uri == null || uri.host.isEmpty) {
          await _replyError(client, clientChan, '400 Bad Request');
          return;
        }
        targetHost = uri.host;
        targetPort = uri.hasPort
            ? uri.port
            : (uri.scheme.toLowerCase() == 'https' ? 443 : 80);
        final path = uri.path.isEmpty ? '/' : uri.path;
        final originTarget = uri.hasQuery ? '$path?${uri.query}' : path;

        final rebuilt = StringBuffer()
          ..write('$method $originTarget $httpVersion\r\n');
        var sawConnection = false;
        for (var i = 1; i < lines.length; i++) {
          final line = lines[i];
          if (line.isEmpty) continue;
          final lower = line.toLowerCase();
          if (lower.startsWith('proxy-authorization:') ||
              lower.startsWith('proxy-connection:')) {
            continue;
          }
          if (lower.startsWith('connection:')) {
            rebuilt.write('Connection: close\r\n');
            sawConnection = true;
            continue;
          }
          rebuilt.write('$line\r\n');
        }
        if (!sawConnection) {
          rebuilt.write('Connection: close\r\n');
        }
        rebuilt.write('\r\n');
        initialUpstreamPayload = Uint8List.fromList(utf8.encode(rebuilt.toString()));
      }

      socks = await Socket.connect(
        InternetAddress.loopbackIPv4,
        socksPort,
        timeout: const Duration(seconds: 10),
      );
      _trackSocket(socks);
      socks.setOption(SocketOption.tcpNoDelay, true);
      socksChan = _SocketChannel(socks);

      var dialHost = targetHost;
      if (preferIpv4 && InternetAddress.tryParse(targetHost) == null) {
        try {
          final addrs = await InternetAddress.lookup(
            targetHost,
            type: InternetAddressType.IPv4,
          ).timeout(const Duration(milliseconds: 1800));
          for (final a in addrs) {
            if (a.type == InternetAddressType.IPv4 && !a.isLoopback) {
              dialHost = a.address;
              break;
            }
          }
        } catch (_) {}
      }

      final connected = await _performSocks5Connect(
        socks,
        socksChan,
        dialHost,
        targetPort,
      ).timeout(const Duration(seconds: 20));

      if (!connected) {
        await _replyError(client, clientChan, '502 Bad Gateway');
        await socksChan.dispose();
        return;
      }

      if (method == 'CONNECT') {
        client.add(ascii.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
        await client.flush().catchError((_) {});
      } else if (initialUpstreamPayload != null) {
        socks.add(initialUpstreamPayload);
      }

      final f1 = clientChan.pipeRemainingTo(socks);
      final f2 = socksChan.pipeRemainingTo(client);
      await Future.wait([f1, f2]);
    } catch (_) {
      try {
        await clientChan.dispose();
      } catch (_) {}
      try {
        await socksChan?.dispose();
      } catch (_) {}
    }
  }

  bool _checkProxyAuth(List<String> lines) {
    if (user.isEmpty && password.isEmpty) return true;
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.toLowerCase().startsWith('proxy-authorization:')) {
        final val = line.substring('proxy-authorization:'.length).trim();
        if (val.length > 6 && val.substring(0, 6).toLowerCase() == 'basic ') {
          final token = val.substring(6).trim();
          if (token == _expectedBasicToken) return true;
        }
      }
    }
    return false;
  }

  static ({String host, int port})? _parseConnectAuthority(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('[')) {
      final closeIdx = trimmed.indexOf(']');
      if (closeIdx <= 1) return null;
      final host = trimmed.substring(1, closeIdx);
      var port = 443;
      if (closeIdx + 1 < trimmed.length && trimmed[closeIdx + 1] == ':') {
        final p = int.tryParse(trimmed.substring(closeIdx + 2));
        if (p == null || p <= 0 || p > 65535) return null;
        port = p;
      }
      return (host: host, port: port);
    }
    final colonIdx = trimmed.lastIndexOf(':');
    if (colonIdx <= 0) {
      return (host: trimmed, port: 443);
    }
    final host = trimmed.substring(0, colonIdx);
    final port = int.tryParse(trimmed.substring(colonIdx + 1));
    if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
    return (host: host, port: port);
  }

  static Future<void> _replyError(
    Socket client,
    _SocketChannel chan,
    String status,
  ) async {
    try {
      client.add(ascii.encode(
        'HTTP/1.1 $status\r\n'
        'Connection: close\r\n'
        'Content-Length: 0\r\n\r\n',
      ));
      await client.flush();
    } catch (_) {}
    await chan.dispose();
  }

  static Future<bool> _performSocks5Connect(
    Socket socks,
    _SocketChannel chan,
    String host,
    int port,
  ) async {
    // 1. Greeting: VER=5, NMETHODS=1, METHOD=0 (No Auth)
    socks.add(const [0x05, 0x01, 0x00]);
    await socks.flush();
    final greet = await chan.readExact(2);
    if (greet == null || greet[0] != 0x05 || greet[1] != 0x00) {
      return false;
    }

    // 2. CONNECT request: VER=5, CMD=1, RSV=0, ATYP=...
    final req = BytesBuilder(copy: false)..add(const [0x05, 0x01, 0x00]);
    final ip = InternetAddress.tryParse(host);
    if (ip != null && ip.type == InternetAddressType.IPv4) {
      req
        ..addByte(0x01)
        ..add(ip.rawAddress);
    } else if (ip != null && ip.type == InternetAddressType.IPv6) {
      req
        ..addByte(0x04)
        ..add(ip.rawAddress);
    } else {
      final hostBytes = utf8.encode(host);
      if (hostBytes.isEmpty || hostBytes.length > 255) return false;
      req
        ..addByte(0x03)
        ..addByte(hostBytes.length)
        ..add(hostBytes);
    }
    req
      ..addByte((port >> 8) & 0xFF)
      ..addByte(port & 0xFF);
    socks.add(req.takeBytes());
    await socks.flush();

    // 3. Reply: VER=5, REP=0, RSV=0, ATYP=...
    final head = await chan.readExact(4);
    if (head == null || head[0] != 0x05 || head[1] != 0x00) {
      return false;
    }
    switch (head[3]) {
      case 0x01: // IPv4 (4) + Port (2)
        if (await chan.readExact(6) == null) return false;
      case 0x04: // IPv6 (16) + Port (2)
        if (await chan.readExact(18) == null) return false;
      case 0x03: // Domain (1 len + N + 2 port)
        final lenBuf = await chan.readExact(1);
        if (lenBuf == null) return false;
        if (await chan.readExact(lenBuf[0] + 2) == null) return false;
      default:
        return false;
    }
    return true;
  }
}

/// Обёртка над `Socket` с единственной подпиской `listen()`, позволяющая
/// сначала прочитать заголовки/рукопожатие побайтово, а затем переключиться
/// в потоковую прокачку с TCP-backpressure без повторного `listen()`.
class _SocketChannel {
  final Socket _socket;
  final List<int> _buffer = <int>[];
  late final StreamSubscription<Uint8List> _sub;
  StreamController<Uint8List>? _pipeCtrl;
  Completer<void>? _waiter;
  bool _eof = false;
  bool _piping = false;

  _SocketChannel(this._socket) {
    _sub = _socket.listen(
      _onData,
      onError: (_) => _onClosed(),
      onDone: _onClosed,
      cancelOnError: true,
    );
  }

  void _onData(Uint8List data) {
    if (_piping) {
      final ctrl = _pipeCtrl;
      if (ctrl != null && !ctrl.isClosed) {
        ctrl.add(data);
      }
      return;
    }
    _buffer.addAll(data);
    final w = _waiter;
    if (w != null && !w.isCompleted) {
      _waiter = null;
      w.complete();
    }
  }

  void _onClosed() {
    _eof = true;
    final w = _waiter;
    if (w != null && !w.isCompleted) {
      _waiter = null;
      w.complete();
    }
    final ctrl = _pipeCtrl;
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.close();
    }
  }

  Future<Uint8List?> readExact(int count) async {
    while (_buffer.length < count) {
      if (_eof) return null;
      final w = Completer<void>();
      _waiter = w;
      await w.future;
    }
    final out = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return out;
  }

  Future<({String headerText})?> readHttpHeader({int maxBytes = 16384}) async {
    while (true) {
      final endIdx = _findDoubleCrlf(_buffer);
      if (endIdx >= 0) {
        final headerBytes = _buffer.sublist(0, endIdx);
        _buffer.removeRange(0, endIdx + 4);
        return (headerText: latin1.decode(headerBytes));
      }
      if (_buffer.length > maxBytes || _eof) return null;
      final w = Completer<void>();
      _waiter = w;
      await w.future;
    }
  }

  static int _findDoubleCrlf(List<int> b) {
    for (var i = 0; i <= b.length - 4; i++) {
      if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  Future<void> pipeRemainingTo(Socket peer) async {
    final ctrl = StreamController<Uint8List>(
      onPause: _sub.pause,
      onResume: _sub.resume,
      onCancel: () => _sub.cancel(),
    );
    _pipeCtrl = ctrl;
    _piping = true;
    if (_buffer.isNotEmpty) {
      ctrl.add(Uint8List.fromList(_buffer));
      _buffer.clear();
    }
    if (_eof && !ctrl.isClosed) {
      await ctrl.close();
    }
    try {
      await peer.addStream(ctrl.stream);
      await peer.flush();
    } catch (_) {
    } finally {
      try {
        peer.destroy();
      } catch (_) {}
      await dispose();
    }
  }

  Future<void> dispose() async {
    _eof = true;
    try {
      await _sub.cancel();
    } catch (_) {}
    final ctrl = _pipeCtrl;
    if (ctrl != null && !ctrl.isClosed) {
      try {
        await ctrl.close();
      } catch (_) {}
    }
    try {
      _socket.destroy();
    } catch (_) {}
  }
}
