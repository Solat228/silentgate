import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../platform/app_log.dart';
import 'dpi_strategy.dart';

/// Информация о физическом IPv4-шлюзе по умолчанию (в обход `silentgate-tun`).
class PhysicalGatewayInfo {
  final int ifIndex;
  final String nextHopIp;
  final int metric;
  final String alias;
  final int ifType;

  const PhysicalGatewayInfo({
    required this.ifIndex,
    required this.nextHopIp,
    required this.metric,
    required this.alias,
    required this.ifType,
  });

  String get displayLabel => alias.isNotEmpty
      ? '$alias (ifIndex=$ifIndex, шлюз $nextHopIp)'
      : 'ifIndex=$ifIndex (шлюз $nextHopIp)';
}

/// Единый интерфейс исходящего TCP-сокета для `LocalDpiBypassProxy`.
abstract class DpiUpstreamSocket {
  /// Поддерживает ли сокет отправку срочного TCP-байта (`MSG_OOB`).
  bool get supportsOob;

  /// Поток входящих байт от удалённого сервера.
  Stream<Uint8List> get stream;

  /// Отправить десинхронизированные сегменты первого пакета (`ClientHello` / HTTP).
  Future<void> sendSegments(List<DpiDesyncSegment> segments);

  /// Поставить обычные данные в очередь отправки.
  void write(Uint8List data);

  /// Дождаться выталкивания буфера (для `dart:io` `Socket`).
  Future<void> flush();

  /// Немедленно закрыть соединение.
  void destroy();
}

/// Обёртка над стандартным `dart:io` `Socket` (используется на Android и в unit-тестах).
class DartDpiUpstreamSocket implements DpiUpstreamSocket {
  final Socket _socket;

  DartDpiUpstreamSocket(this._socket) {
    try {
      _socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
  }

  @override
  bool get supportsOob => false;

  @override
  Stream<Uint8List> get stream => _socket;

  @override
  Future<void> sendSegments(List<DpiDesyncSegment> segments) async {
    for (var i = 0; i < segments.length; i++) {
      final bytes = segments[i].bytesWithoutOob();
      if (bytes.isEmpty) continue;
      _socket.add(bytes);
      await _socket.flush();
      if (i + 1 < segments.length) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }
  }

  @override
  void write(Uint8List data) {
    if (data.isEmpty) return;
    _socket.add(data);
  }

  @override
  Future<void> flush() async {
    try {
      await _socket.flush();
    } catch (_) {}
  }

  @override
  void destroy() {
    try {
      _socket.destroy();
    } catch (_) {}
  }
}

// ── FFI структуры и константы WinSock2 / IP Helper API ──────────────────────

final class _WsaPollFd extends Struct {
  @IntPtr()
  external int fd;

  @Int16()
  external int events;

  @Int16()
  external int revents;
}

const int _afInet = 2;
const int _sockStream = 1;
const int _sockDgram = 2;
const int _ipprotoIp = 0;
const int _ipprotoTcp = 6;
const int _ipprotoUdp = 17;
const int _ipUnicastIf = 31;
const int _tcpNoDelay = 1;
const int _soError = 0x1007;
const int _solSocket = 0xFFFF;
const int _fionbio = -2147195266; // 0x8004667E (signed int32)
const int _msgOob = 0x1;
const int _wsaEwouldblock = 10035;
const int _wsaEinprogress = 10036;

// Битовые маски WSAPoll в Windows (`winsock2.h` — отличаются от POSIX!)
const int _pollRdNorm = 0x0100;
const int _pollWrNorm = 0x0010;
const int _pollErr = 0x0001;
const int _pollHup = 0x0002;
const int _pollNval = 0x0004;

typedef _GetIpForwardTableNative = Uint32 Function(
  Pointer<Uint8> pIpForwardTable,
  Pointer<Uint32> pdwSize,
  Int32 bOrder,
);
typedef _GetIpForwardTableDart = int Function(
  Pointer<Uint8> pIpForwardTable,
  Pointer<Uint32> pdwSize,
  int bOrder,
);

typedef _ConvertIndexToLuidNative = Uint32 Function(
  Uint32 interfaceIndex,
  Pointer<Uint64> interfaceLuid,
);
typedef _ConvertIndexToLuidDart = int Function(
  int interfaceIndex,
  Pointer<Uint64> interfaceLuid,
);

typedef _ConvertLuidToAliasNative = Uint32 Function(
  Pointer<Uint64> interfaceLuid,
  Pointer<Uint16> interfaceAlias,
  IntPtr length,
);
typedef _ConvertLuidToAliasDart = int Function(
  Pointer<Uint64> interfaceLuid,
  Pointer<Uint16> interfaceAlias,
  int length,
);

/// Определить физический сетевой адаптер Windows с маршрутом `0.0.0.0/0`
/// наименьшей метрики (исключая `silentgate-tun`, `Wintun` и виртуальные VPN).
PhysicalGatewayInfo? detectPhysicalIpv4Gateway() {
  if (!Platform.isWindows) return null;
  try {
    final iphlpapi = DynamicLibrary.open('iphlpapi.dll');
    final getForwardTable = iphlpapi
        .lookupFunction<_GetIpForwardTableNative, _GetIpForwardTableDart>(
      'GetIpForwardTable',
    );
    final indexToLuid = iphlpapi
        .lookupFunction<_ConvertIndexToLuidNative, _ConvertIndexToLuidDart>(
      'ConvertInterfaceIndexToLuid',
    );
    final luidToAlias = iphlpapi
        .lookupFunction<_ConvertLuidToAliasNative, _ConvertLuidToAliasDart>(
      'ConvertInterfaceLuidToAlias',
    );

    final sizePtr = calloc<Uint32>();
    Pointer<Uint8> tableBuf = nullptr;
    final luidPtr = calloc<Uint64>();
    final aliasBuf = calloc<Uint16>(258);
    try {
      sizePtr.value = 0;
      final firstRc = getForwardTable(nullptr, sizePtr, 0);
      if (firstRc != 122 && firstRc != 0) return null; // 122 = ERROR_INSUFFICIENT_BUFFER
      final allocBytes = sizePtr.value + 512;
      sizePtr.value = allocBytes;
      tableBuf = calloc<Uint8>(allocBytes);
      final rc = getForwardTable(tableBuf, sizePtr, 0);
      if (rc != 0) return null;

      final words = tableBuf.cast<Uint32>();
      final count = words[0];
      PhysicalGatewayInfo? bestPhysical;
      PhysicalGatewayInfo? bestFallback;

      for (var i = 0; i < count; i++) {
        final base = 1 + i * 14;
        final dest = words[base + 0];
        final mask = words[base + 1];
        final nextHop = words[base + 3];
        final ifIndex = words[base + 4];
        final metric1 = words[base + 9];

        // Ищем только полноценный маршрут 0.0.0.0/0 с реальным шлюзом
        // (туннель silentgate-tun использует /1 маршруты 0.0.0.0/1 и 128.0.0.0/1).
        if (dest != 0 || mask != 0 || nextHop == 0 || ifIndex <= 0) continue;

        final hopIp = _ipv4FromNetworkDword(nextHop);
        var alias = '';
        var ifType = 0;
        luidPtr.value = 0;
        if (indexToLuid(ifIndex, luidPtr) == 0) {
          final luid = luidPtr.value;
          ifType = (luid >> 48) & 0xFFFF;
          if (luidToAlias(luidPtr, aliasBuf, 257) == 0) {
            final units = <int>[];
            for (var c = 0; c < 257; c++) {
              final ch = aliasBuf[c];
              if (ch == 0) break;
              units.add(ch);
            }
            alias = String.fromCharCodes(units).trim();
          }
        }

        // Пропускаем loopback и собственный туннель
        if (ifType == 24) continue; // IF_TYPE_SOFTWARE_LOOPBACK
        final lowAlias = alias.toLowerCase();
        if (lowAlias.contains('silentgate') || lowAlias.contains('wintun')) {
          continue;
        }

        final candidate = PhysicalGatewayInfo(
          ifIndex: ifIndex,
          nextHopIp: hopIp,
          metric: metric1,
          alias: alias,
          ifType: ifType,
        );

        final isVirtualOverlay = ifType == 53 ||
            ifType == 131 ||
            lowAlias.contains('radmin') ||
            lowAlias.contains('tailscale') ||
            lowAlias.contains('zerotier') ||
            lowAlias.contains('hamachi') ||
            lowAlias.contains('wireguard') ||
            lowAlias.contains('vethernet') ||
            lowAlias.contains('wsl') ||
            lowAlias.contains('hyper-v');

        if (!isVirtualOverlay) {
          if (bestPhysical == null || candidate.metric < bestPhysical.metric) {
            bestPhysical = candidate;
          }
        } else {
          if (bestFallback == null || candidate.metric < bestFallback.metric) {
            bestFallback = candidate;
          }
        }
      }

      return bestPhysical ?? bestFallback;
    } finally {
      if (tableBuf != nullptr) calloc.free(tableBuf);
      calloc.free(sizePtr);
      calloc.free(luidPtr);
      calloc.free(aliasBuf);
    }
  } catch (e) {
    AppLog.w('DPI: ошибка поиска физического адаптера: $e');
    return null;
  }
}

String _ipv4FromNetworkDword(int val) {
  final b0 = val & 0xFF;
  final b1 = (val >> 8) & 0xFF;
  final b2 = (val >> 16) & 0xFF;
  final b3 = (val >> 24) & 0xFF;
  return '$b0.$b1.$b2.$b3';
}

/// Менеджер фонового изолята WinSock2 для сокетов с привязкой к физическому
/// сетевому адаптеру (`IP_UNICAST_IF`) и нативной поддержкой `MSG_OOB`.
class PhysicalNicSocketManager {
  PhysicalNicSocketManager._();

  static final PhysicalNicSocketManager instance = PhysicalNicSocketManager._();

  Isolate? _isolate;
  SendPort? _workerPort;
  ReceivePort? _receivePort;
  Completer<SendPort>? _starting;
  int _nextId = 1;

  PhysicalGatewayInfo? _cachedGateway;
  DateTime? _gatewayCheckedAt;

  final Map<int, _PendingConnect> _pendingConnects = <int, _PendingConnect>{};
  final Map<int, WinSockPhysicalUpstreamSocket> _sockets =
      <int, WinSockPhysicalUpstreamSocket>{};
  final Map<int, Completer<String?>> _pendingDns = <int, Completer<String?>>{};

  /// Текущий активный физический шлюз (с коротким кэшем 5 секунд).
  PhysicalGatewayInfo? currentGateway({bool forceRefresh = false}) {
    if (!Platform.isWindows) return null;
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedGateway != null &&
        _gatewayCheckedAt != null &&
        now.difference(_gatewayCheckedAt!) < const Duration(seconds: 5)) {
      return _cachedGateway;
    }
    _cachedGateway = detectPhysicalIpv4Gateway();
    _gatewayCheckedAt = now;
    return _cachedGateway;
  }

  /// Открыть прямое TCP-соединение поверх физического адаптера (мимо Wintun).
  Future<DpiUpstreamSocket> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!Platform.isWindows) {
      final sock = await Socket.connect(host, port, timeout: timeout);
      return DartDpiUpstreamSocket(sock);
    }

    final gw = currentGateway();
    if (gw == null) {
      final sock = await Socket.connect(host, port, timeout: timeout);
      return DartDpiUpstreamSocket(sock);
    }

    final targetIp = await resolveIpv4(host, gateway: gw, timeout: timeout);
    if (targetIp == null) {
      throw SocketException('Не удалось разрешить IPv4-адрес для $host');
    }

    final worker = await _ensureWorker();
    final connId = _nextId++;
    final socketWrapper = WinSockPhysicalUpstreamSocket._(connId, worker, () {
      _sockets.remove(connId);
    });
    _sockets[connId] = socketWrapper;

    final c = Completer<void>();
    _pendingConnects[connId] = _PendingConnect(c);
    worker.send([
      'connect',
      connId,
      targetIp,
      port,
      gw.ifIndex,
      timeout.inMilliseconds.clamp(300, 15000),
    ]);

    try {
      await c.future.timeout(timeout + const Duration(milliseconds: 300));
      return socketWrapper;
    } catch (e) {
      _pendingConnects.remove(connId);
      _sockets.remove(connId);
      worker.send(['close', connId]);
      rethrow;
    }
  }

  /// Разрешить доменное имя в IPv4 напрямую через физический адаптер
  /// (`IP_UNICAST_IF`), не попадая в `silentgate-tun` или блокировку `1.1.1.1`.
  Future<String?> resolveIpv4(
    String host, {
    PhysicalGatewayInfo? gateway,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return null;
    final parsed = InternetAddress.tryParse(trimmed);
    if (parsed != null) {
      return parsed.type == InternetAddressType.IPv4 ? parsed.address : null;
    }

    final gw = gateway ?? currentGateway();
    if (Platform.isWindows && gw != null) {
      try {
        final worker = await _ensureWorker();
        final reqId = _nextId++;
        final c = Completer<String?>();
        _pendingDns[reqId] = c;
        final dnsTimeoutMs = min(timeout.inMilliseconds, 1800).clamp(400, 3000);
        worker.send([
          'dns',
          reqId,
          trimmed,
          gw.ifIndex,
          gw.nextHopIp,
          dnsTimeoutMs,
        ]);
        final ip = await c.future.timeout(
          Duration(milliseconds: dnsTimeoutMs + 250),
          onTimeout: () => null,
        );
        _pendingDns.remove(reqId);
        if (ip != null && ip.isNotEmpty) return ip;
      } catch (_) {}
    }

    // Запасной системный lookup (например, hosts-файл или корпоративный DNS)
    try {
      final addrs = await InternetAddress.lookup(
        trimmed,
        type: InternetAddressType.IPv4,
      ).timeout(timeout);
      if (addrs.isNotEmpty) return addrs.first.address;
    } catch (_) {}
    return null;
  }

  Future<SendPort> _ensureWorker() async {
    if (_workerPort != null) return _workerPort!;
    if (_starting != null) return _starting!.future;
    final comp = Completer<SendPort>();
    _starting = comp;

    final rp = ReceivePort();
    _receivePort = rp;
    rp.listen(_onWorkerMessage);

    try {
      _isolate = await Isolate.spawn(_winSockIsolateEntry, rp.sendPort);
      final sp = await comp.future.timeout(const Duration(seconds: 5));
      _workerPort = sp;
      _starting = null;
      return sp;
    } catch (e) {
      _starting = null;
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _receivePort?.close();
      _receivePort = null;
      rethrow;
    }
  }

  void _onWorkerMessage(dynamic msg) {
    if (msg is SendPort) {
      _starting?.complete(msg);
      return;
    }
    if (msg is! List || msg.isEmpty) return;
    final kind = msg[0] as String;
    switch (kind) {
      case 'connected':
        final id = msg[1] as int;
        final p = _pendingConnects.remove(id);
        if (p != null && !p.completer.isCompleted) {
          p.completer.complete();
        }
        break;
      case 'connect_err':
        final id = msg[1] as int;
        final err = msg[2] as String;
        final p = _pendingConnects.remove(id);
        _sockets.remove(id)?._markClosed();
        if (p != null && !p.completer.isCompleted) {
          p.completer.completeError(SocketException(err));
        }
        break;
      case 'data':
        final id = msg[1] as int;
        final ttd = msg[2] as TransferableTypedData;
        final sock = _sockets[id];
        sock?._onData(ttd.materialize().asUint8List());
        break;
      case 'closed':
        final id = msg[1] as int;
        final errMsg = msg.length > 2 ? msg[2] as String? : null;
        final sock = _sockets.remove(id);
        sock?._onRemoteClose(errMsg);
        break;
      case 'dns_res':
        final id = msg[1] as int;
        final ip = msg[2] as String?;
        final c = _pendingDns.remove(id);
        if (c != null && !c.isCompleted) {
          c.complete(ip);
        }
        break;
    }
  }
}

class _PendingConnect {
  final Completer<void> completer;
  _PendingConnect(this.completer);
}

/// TCP-сокет поверх WinSock2, жёстко привязанный к физическому адаптеру (`IP_UNICAST_IF`)
/// и отправляющий срочные байты через `send(..., MSG_OOB)`.
class WinSockPhysicalUpstreamSocket implements DpiUpstreamSocket {
  final int _id;
  final SendPort _worker;
  final void Function() _onDispose;
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();
  bool _closed = false;

  WinSockPhysicalUpstreamSocket._(this._id, this._worker, this._onDispose);

  @override
  bool get supportsOob => true;

  @override
  Stream<Uint8List> get stream => _controller.stream;

  @override
  Future<void> sendSegments(List<DpiDesyncSegment> segments) async {
    if (_closed || segments.isEmpty) return;
    final serialized = <List<dynamic>>[
      for (final s in segments)
        if (s.bytes.isNotEmpty)
          [TransferableTypedData.fromList([s.bytes]), s.isOob],
    ];
    if (serialized.isEmpty) return;
    _worker.send(['segments', _id, serialized]);
  }

  @override
  void write(Uint8List data) {
    if (_closed || data.isEmpty) return;
    _worker.send([
      'write',
      _id,
      TransferableTypedData.fromList([data]),
    ]);
  }

  @override
  Future<void> flush() async {}

  @override
  void destroy() {
    if (_closed) return;
    _closed = true;
    _onDispose();
    _worker.send(['close', _id]);
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  void _markClosed() {
    _closed = true;
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  void _onData(Uint8List chunk) {
    if (!_closed && !_controller.isClosed) {
      _controller.add(chunk);
    }
  }

  void _onRemoteClose(String? errorMessage) {
    if (_closed) return;
    _closed = true;
    if (!_controller.isClosed) {
      if (errorMessage != null && errorMessage.isNotEmpty) {
        _controller.addError(SocketException(errorMessage));
      }
      _controller.close();
    }
  }
}

// ── Изолят-воркер WinSock2 ──────────────────────────────────────────────────

typedef _WsaStartupNative = Int32 Function(Uint16 version, Pointer<Uint8> data);
typedef _WsaStartupDart = int Function(int version, Pointer<Uint8> data);

typedef _SocketNative = IntPtr Function(Int32 af, Int32 type, Int32 protocol);
typedef _SocketDart = int Function(int af, int type, int protocol);

typedef _CloseSocketNative = Int32 Function(IntPtr s);
typedef _CloseSocketDart = int Function(int s);

typedef _IoctlSocketNative = Int32 Function(
  IntPtr s,
  Int32 cmd,
  Pointer<Uint32> argp,
);
typedef _IoctlSocketDart = int Function(int s, int cmd, Pointer<Uint32> argp);

typedef _SetSockOptNative = Int32 Function(
  IntPtr s,
  Int32 level,
  Int32 optname,
  Pointer<Uint8> optval,
  Int32 optlen,
);
typedef _SetSockOptDart = int Function(
  int s,
  int level,
  int optname,
  Pointer<Uint8> optval,
  int optlen,
);

typedef _GetSockOptNative = Int32 Function(
  IntPtr s,
  Int32 level,
  Int32 optname,
  Pointer<Int32> optval,
  Pointer<Int32> optlen,
);
typedef _GetSockOptDart = int Function(
  int s,
  int level,
  int optname,
  Pointer<Int32> optval,
  Pointer<Int32> optlen,
);

typedef _ConnectNative = Int32 Function(
  IntPtr s,
  Pointer<Uint8> name,
  Int32 namelen,
);
typedef _ConnectDart = int Function(int s, Pointer<Uint8> name, int namelen);

typedef _SendNative = Int32 Function(
  IntPtr s,
  Pointer<Uint8> buf,
  Int32 len,
  Int32 flags,
);
typedef _SendDart = int Function(int s, Pointer<Uint8> buf, int len, int flags);

typedef _SendToNative = Int32 Function(
  IntPtr s,
  Pointer<Uint8> buf,
  Int32 len,
  Int32 flags,
  Pointer<Uint8> to,
  Int32 tolen,
);
typedef _SendToDart = int Function(
  int s,
  Pointer<Uint8> buf,
  int len,
  int flags,
  Pointer<Uint8> to,
  int tolen,
);

typedef _RecvNative = Int32 Function(
  IntPtr s,
  Pointer<Uint8> buf,
  Int32 len,
  Int32 flags,
);
typedef _RecvDart = int Function(int s, Pointer<Uint8> buf, int len, int flags);

typedef _WsaGetLastErrorNative = Int32 Function();
typedef _WsaGetLastErrorDart = int Function();

typedef _WsaPollNative = Int32 Function(
  Pointer<_WsaPollFd> fdarray,
  Uint32 fds,
  Int32 timeout,
);
typedef _WsaPollDart = int Function(
  Pointer<_WsaPollFd> fdarray,
  int fds,
  int timeout,
);

class _PendingSegment {
  final Uint8List bytes;
  int offset = 0;
  final bool isOob;
  final DateTime? notBefore;

  _PendingSegment(this.bytes, {this.isOob = false, this.notBefore});
}

class _WorkerTcpConn {
  final int id;
  final int fd;
  final DateTime connectDeadline;
  bool connected = false;
  final Queue<_PendingSegment> outQueue = Queue<_PendingSegment>();

  _WorkerTcpConn({
    required this.id,
    required this.fd,
    required this.connectDeadline,
  });
}

class _WorkerDnsQuery {
  final int id;
  final int fd;
  final int txId;
  final DateTime deadline;

  _WorkerDnsQuery({
    required this.id,
    required this.fd,
    required this.txId,
    required this.deadline,
  });
}

void _winSockIsolateEntry(SendPort mainPort) {
  final ws2 = DynamicLibrary.open('ws2_32.dll');
  final wsaStartup =
      ws2.lookupFunction<_WsaStartupNative, _WsaStartupDart>('WSAStartup');
  final createSocket =
      ws2.lookupFunction<_SocketNative, _SocketDart>('socket');
  final closeSocket =
      ws2.lookupFunction<_CloseSocketNative, _CloseSocketDart>('closesocket');
  final ioctlSocket =
      ws2.lookupFunction<_IoctlSocketNative, _IoctlSocketDart>('ioctlsocket');
  final setSockOpt =
      ws2.lookupFunction<_SetSockOptNative, _SetSockOptDart>('setsockopt');
  final getSockOpt =
      ws2.lookupFunction<_GetSockOptNative, _GetSockOptDart>('getsockopt');
  final connectFn =
      ws2.lookupFunction<_ConnectNative, _ConnectDart>('connect');
  final sendFn = ws2.lookupFunction<_SendNative, _SendDart>('send');
  final sendToFn = ws2.lookupFunction<_SendToNative, _SendToDart>('sendto');
  final recvFn = ws2.lookupFunction<_RecvNative, _RecvDart>('recv');
  final lastErr = ws2.lookupFunction<_WsaGetLastErrorNative, _WsaGetLastErrorDart>(
      'WSAGetLastError');
  final wsaPoll =
      ws2.lookupFunction<_WsaPollNative, _WsaPollDart>('WSAPoll');

  final wsaData = calloc<Uint8>(512);
  wsaStartup(0x0202, wsaData);
  calloc.free(wsaData);

  final recvBuf = calloc<Uint8>(65536);
  final sendBuf = calloc<Uint8>(65536);
  final sockAddr = calloc<Uint8>(16);
  final optBuf = calloc<Uint8>(8);
  final errVal = calloc<Int32>();
  final errLen = calloc<Int32>();
  final nonBlockArg = calloc<Uint32>();
  var pollCap = 64;
  var pollArray = calloc<_WsaPollFd>(pollCap);

  final conns = <int, _WorkerTcpConn>{};
  final dnsQueries = <int, _WorkerDnsQuery>{};
  final rng = Random();
  Timer? loopTimer;

  void writeSockAddrIn(Pointer<Uint8> dst, String ip, int port) {
    for (var i = 0; i < 16; i++) {
      dst[i] = 0;
    }
    final parts = ip.split('.');
    dst[0] = _afInet;
    dst[1] = 0;
    dst[2] = (port >> 8) & 0xFF;
    dst[3] = port & 0xFF;
    if (parts.length == 4) {
      dst[4] = int.tryParse(parts[0]) ?? 0;
      dst[5] = int.tryParse(parts[1]) ?? 0;
      dst[6] = int.tryParse(parts[2]) ?? 0;
      dst[7] = int.tryParse(parts[3]) ?? 0;
    }
  }

  bool bindToIfIndex(int fd, int ifIndex) {
    // MSDN: IP_UNICAST_IF (optname=31) принимает 32-битный ifIndex в сетевом порядке (big-endian)!
    optBuf[0] = (ifIndex >> 24) & 0xFF;
    optBuf[1] = (ifIndex >> 16) & 0xFF;
    optBuf[2] = (ifIndex >> 8) & 0xFF;
    optBuf[3] = ifIndex & 0xFF;
    return setSockOpt(fd, _ipprotoIp, _ipUnicastIf, optBuf, 4) == 0;
  }

  void setNoDelayAndNonBlock(int fd) {
    optBuf[0] = 1;
    optBuf[1] = 0;
    optBuf[2] = 0;
    optBuf[3] = 0;
    setSockOpt(fd, _ipprotoTcp, _tcpNoDelay, optBuf, 4);
    nonBlockArg.value = 1;
    ioctlSocket(fd, _fionbio, nonBlockArg);
  }

  void destroyConn(int id, {String? error, bool notify = true}) {
    final c = conns.remove(id);
    if (c == null) return;
    closeSocket(c.fd);
    if (notify) {
      if (!c.connected) {
        mainPort.send(['connect_err', id, error ?? 'Connection failed']);
      } else {
        mainPort.send(['closed', id, error]);
      }
    }
  }

  void destroyDns(int id, String? ip) {
    final q = dnsQueries.remove(id);
    if (q == null) return;
    closeSocket(q.fd);
    mainPort.send(['dns_res', id, ip]);
  }

  void flushConnQueue(_WorkerTcpConn c, DateTime now) {
    if (!c.connected) return;
    while (c.outQueue.isNotEmpty) {
      final seg = c.outQueue.first;
      if (seg.notBefore != null && now.isBefore(seg.notBefore!)) {
        break;
      }
      final rem = seg.bytes.length - seg.offset;
      if (rem <= 0) {
        c.outQueue.removeFirst();
        continue;
      }
      final chunkLen = rem > 65536 ? 65536 : rem;
      final view = sendBuf.asTypedList(chunkLen);
      view.setRange(0, chunkLen, seg.bytes, seg.offset);
      // Флаг MSG_OOB ставим только на последний чанк сегмента, где лежит срочный байт!
      final isFinalChunk = (seg.offset + chunkLen) == seg.bytes.length;
      final flags = (seg.isOob && isFinalChunk) ? _msgOob : 0;
      final sent = sendFn(c.fd, sendBuf, chunkLen, flags);
      if (sent > 0) {
        seg.offset += sent;
        if (seg.offset >= seg.bytes.length) {
          c.outQueue.removeFirst();
        }
      } else {
        final err = lastErr();
        if (err == _wsaEwouldblock || err == _wsaEinprogress) {
          break;
        }
        destroyConn(c.id, error: 'WinSock send error $err');
        return;
      }
    }
  }

  late void Function() scheduleTick;

  void tick() {
    loopTimer = null;
    if (conns.isEmpty && dnsQueries.isEmpty) return;

    final now = DateTime.now();
    final total = conns.length + dnsQueries.length;
    if (total > pollCap) {
      calloc.free(pollArray);
      pollCap = total * 2;
      pollArray = calloc<_WsaPollFd>(pollCap);
    }

    final tcpList = conns.values.toList(growable: false);
    final dnsList = dnsQueries.values.toList(growable: false);

    var idx = 0;
    for (final c in tcpList) {
      final entry = (pollArray + idx).ref;
      entry.fd = c.fd;
      final wantsWrite = !c.connected ||
          (c.outQueue.isNotEmpty &&
              (c.outQueue.first.notBefore == null ||
                  !now.isBefore(c.outQueue.first.notBefore!)));
      entry.events = _pollRdNorm | (wantsWrite ? _pollWrNorm : 0);
      entry.revents = 0;
      idx++;
    }
    for (final q in dnsList) {
      final entry = (pollArray + idx).ref;
      entry.fd = q.fd;
      entry.events = _pollRdNorm;
      entry.revents = 0;
      idx++;
    }

    if (idx > 0) {
      wsaPoll(pollArray, idx, 3);
    }

    final afterPoll = DateTime.now();

    for (var i = 0; i < tcpList.length; i++) {
      final c = tcpList[i];
      if (!conns.containsKey(c.id)) continue;
      final rev = (pollArray + i).ref.revents;

      if (!c.connected) {
        if ((rev & (_pollErr | _pollHup | _pollNval)) != 0) {
          errLen.value = 4;
          errVal.value = 0;
          getSockOpt(c.fd, _solSocket, _soError, errVal, errLen);
          destroyConn(c.id, error: 'Connect failed (WSA ${errVal.value})');
          continue;
        }
        if ((rev & _pollWrNorm) != 0) {
          errLen.value = 4;
          errVal.value = 0;
          getSockOpt(c.fd, _solSocket, _soError, errVal, errLen);
          if (errVal.value != 0) {
            destroyConn(c.id, error: 'Connect error (WSA ${errVal.value})');
            continue;
          }
          c.connected = true;
          mainPort.send(['connected', c.id]);
          flushConnQueue(c, afterPoll);
        } else if (afterPoll.isAfter(c.connectDeadline)) {
          destroyConn(c.id, error: 'Connect timeout');
          continue;
        }
      } else {
        if ((rev & _pollRdNorm) != 0) {
          while (true) {
            final n = recvFn(c.fd, recvBuf, 65536, 0);
            if (n > 0) {
              final copy = Uint8List.fromList(recvBuf.asTypedList(n));
              mainPort.send([
                'data',
                c.id,
                TransferableTypedData.fromList([copy]),
              ]);
            } else if (n == 0) {
              destroyConn(c.id);
              break;
            } else {
              final err = lastErr();
              if (err == _wsaEwouldblock) break;
              destroyConn(c.id, error: 'TCP RST / recv error (WSA $err)');
              break;
            }
          }
        }
        if (conns.containsKey(c.id) &&
            (rev & (_pollErr | _pollHup | _pollNval)) != 0) {
          errLen.value = 4;
          errVal.value = 0;
          getSockOpt(c.fd, _solSocket, _soError, errVal, errLen);
          final code = errVal.value;
          destroyConn(
            c.id,
            error: code != 0 ? 'Socket error (WSA $code)' : null,
          );
          continue;
        }
        if (conns.containsKey(c.id) && c.outQueue.isNotEmpty) {
          flushConnQueue(c, afterPoll);
        }
      }
    }

    final dnsBase = tcpList.length;
    for (var j = 0; j < dnsList.length; j++) {
      final q = dnsList[j];
      if (!dnsQueries.containsKey(q.id)) continue;
      final rev = (pollArray + dnsBase + j).ref.revents;
      if ((rev & _pollRdNorm) != 0) {
        final n = recvFn(q.fd, recvBuf, 2048, 0);
        if (n >= 12) {
          final parsedIp = _parseDnsAReply(recvBuf.asTypedList(n), q.txId);
          if (parsedIp != null) {
            destroyDns(q.id, parsedIp);
            continue;
          }
        }
      }
      if (afterPoll.isAfter(q.deadline) ||
          (rev & (_pollErr | _pollNval)) != 0) {
        destroyDns(q.id, null);
      }
    }

    if (conns.isNotEmpty || dnsQueries.isNotEmpty) {
      loopTimer ??= Timer(const Duration(milliseconds: 2), tick);
    }
  }

  scheduleTick = () {
    if (loopTimer == null && (conns.isNotEmpty || dnsQueries.isNotEmpty)) {
      loopTimer = Timer(Duration.zero, tick);
    }
  };

  final cmdPort = ReceivePort();
  mainPort.send(cmdPort.sendPort);

  cmdPort.listen((dynamic raw) {
    if (raw is! List || raw.isEmpty) return;
    final op = raw[0] as String;
    switch (op) {
      case 'connect':
        final id = raw[1] as int;
        final ip = raw[2] as String;
        final port = raw[3] as int;
        final ifIndex = raw[4] as int;
        final timeoutMs = raw[5] as int;

        final fd = createSocket(_afInet, _sockStream, _ipprotoTcp);
        if (fd == -1 || fd == ~0) {
          mainPort.send(['connect_err', id, 'socket() failed (${lastErr()})']);
          return;
        }
        bindToIfIndex(fd, ifIndex);
        setNoDelayAndNonBlock(fd);
        writeSockAddrIn(sockAddr, ip, port);
        final rc = connectFn(fd, sockAddr, 16);
        if (rc != 0) {
          final err = lastErr();
          if (err != _wsaEwouldblock && err != _wsaEinprogress) {
            closeSocket(fd);
            mainPort.send(['connect_err', id, 'connect() failed (WSA $err)']);
            return;
          }
        }
        final conn = _WorkerTcpConn(
          id: id,
          fd: fd,
          connectDeadline: DateTime.now().add(Duration(milliseconds: timeoutMs)),
        );
        if (rc == 0) {
          conn.connected = true;
          conns[id] = conn;
          mainPort.send(['connected', id]);
        } else {
          conns[id] = conn;
        }
        scheduleTick();
        break;

      case 'segments':
        final id = raw[1] as int;
        final list = raw[2] as List;
        final conn = conns[id];
        if (conn == null) return;
        final baseTime = DateTime.now();
        for (var i = 0; i < list.length; i++) {
          final item = list[i] as List;
          final ttd = item[0] as TransferableTypedData;
          final isOob = item[1] as bool;
          final bytes = ttd.materialize().asUint8List();
          conn.outQueue.add(_PendingSegment(
            bytes,
            isOob: isOob,
            notBefore: i == 0 ? null : baseTime.add(Duration(milliseconds: i)),
          ));
        }
        flushConnQueue(conn, baseTime);
        scheduleTick();
        break;

      case 'write':
        final id = raw[1] as int;
        final ttd = raw[2] as TransferableTypedData;
        final conn = conns[id];
        if (conn == null) return;
        conn.outQueue.add(_PendingSegment(ttd.materialize().asUint8List()));
        flushConnQueue(conn, DateTime.now());
        scheduleTick();
        break;

      case 'close':
        final id = raw[1] as int;
        destroyConn(id, notify: false);
        break;

      case 'dns':
        final id = raw[1] as int;
        final host = raw[2] as String;
        final ifIndex = raw[3] as int;
        final gatewayIp = raw[4] as String;
        final timeoutMs = raw[5] as int;

        final txId = rng.nextInt(0xFFFF) + 1;
        final queryPkt = _buildDnsAQuery(host, txId);
        if (queryPkt == null) {
          mainPort.send(['dns_res', id, null]);
          return;
        }
        final fd = createSocket(_afInet, _sockDgram, _ipprotoUdp);
        if (fd == -1 || fd == ~0) {
          mainPort.send(['dns_res', id, null]);
          return;
        }
        bindToIfIndex(fd, ifIndex);
        nonBlockArg.value = 1;
        ioctlSocket(fd, _fionbio, nonBlockArg);

        sendBuf.asTypedList(queryPkt.length).setAll(0, queryPkt);
        // Отправляем запрос параллельно на роутер + 77.88.8.8 + 8.8.8.8 через физический NIC:
        // первый валидный ответ сразу побеждает, даже если 1.1.1.1 заблокирован ТСПУ.
        final resolvers = <String>{
          if (gatewayIp.isNotEmpty) gatewayIp,
          '77.88.8.8',
          '8.8.8.8',
        };
        for (final srv in resolvers) {
          writeSockAddrIn(sockAddr, srv, 53);
          sendToFn(fd, sendBuf, queryPkt.length, 0, sockAddr, 16);
        }
        dnsQueries[id] = _WorkerDnsQuery(
          id: id,
          fd: fd,
          txId: txId,
          deadline: DateTime.now().add(Duration(milliseconds: timeoutMs)),
        );
        scheduleTick();
        break;
    }
  });
}

Uint8List? _buildDnsAQuery(String host, int txId) {
  final labels = host.trim().replaceAll(RegExp(r'\.+$'), '').split('.');
  if (labels.isEmpty) return null;
  final bytes = <int>[
    (txId >> 8) & 0xFF,
    txId & 0xFF,
    0x01, 0x00, // RD = 1
    0x00, 0x01, // QDCOUNT = 1
    0x00, 0x00,
    0x00, 0x00,
    0x00, 0x00,
  ];
  for (final l in labels) {
    if (l.isEmpty || l.length > 63) return null;
    final units = l.codeUnits;
    bytes.add(units.length);
    bytes.addAll(units);
  }
  bytes.addAll(const [0x00, 0x00, 0x01, 0x00, 0x01]); // root, QTYPE=A, QCLASS=IN
  return Uint8List.fromList(bytes);
}

String? _parseDnsAReply(Uint8List pkt, int expectedTxId) {
  if (pkt.length < 12) return null;
  final txId = (pkt[0] << 8) | pkt[1];
  if (txId != expectedTxId) return null;
  if ((pkt[2] & 0x80) == 0) return null; // QR must be 1
  if ((pkt[3] & 0x0F) != 0) return null; // RCODE == 0
  final qdCount = (pkt[4] << 8) | pkt[5];
  final anCount = (pkt[6] << 8) | pkt[7];
  if (anCount <= 0) return null;

  var pos = 12;
  int? skipName(int p) {
    var safety = 0;
    while (p < pkt.length && safety++ < 128) {
      final b = pkt[p];
      if (b == 0) return p + 1;
      if ((b & 0xC0) == 0xC0) {
        return p + 2 <= pkt.length ? p + 2 : null;
      }
      p += 1 + b;
    }
    return null;
  }

  for (var q = 0; q < qdCount; q++) {
    final next = skipName(pos);
    if (next == null || next + 4 > pkt.length) return null;
    pos = next + 4;
  }

  for (var a = 0; a < anCount; a++) {
    final next = skipName(pos);
    if (next == null || next + 10 > pkt.length) return null;
    pos = next;
    final rtype = (pkt[pos] << 8) | pkt[pos + 1];
    final rclass = (pkt[pos + 2] << 8) | pkt[pos + 3];
    final rdlen = (pkt[pos + 8] << 8) | pkt[pos + 9];
    pos += 10;
    if (pos + rdlen > pkt.length) return null;
    if (rtype == 1 && rclass == 1 && rdlen == 4) {
      return '${pkt[pos]}.${pkt[pos + 1]}.${pkt[pos + 2]}.${pkt[pos + 3]}';
    }
    pos += rdlen;
  }
  return null;
}
