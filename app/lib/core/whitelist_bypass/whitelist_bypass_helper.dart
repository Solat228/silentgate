import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/vpn_server.dart';
import '../platform/app_log.dart';
import '../../engine/windows/xray_paths.dart';

/// Эндпоинты медиа-серверов белых списков для прямого роутинга (direct).
///
/// Трафик к этим доменам и IP-подсетям ОБЯЗАН идти напрямую (через сотового оператора),
/// а не заворачиваться в туннель, иначе возникнет петля маршрутизации (routing loop).
abstract final class WhitelistBypassEndpoint {
  /// Домены для прямого доступа.
  static List<String> domainsFor(String platform) {
    switch (platform.toLowerCase()) {
      case 'wbstream':
        return const ['stream.wb.ru', 'wb.ru'];
      case 'telemost':
        return const [
          'telemost.yandex.ru',
          'yandex.ru',
          'yandex.net',
        ];
      case 'vk':
        return const [
          'vk.ru',
          'vk.com',
          'vk.me',
          'vk-portal.net',
          'userapi.com',
        ];
      case 'dion':
        return const ['dion.vc'];
      case 'bitrix':
        return const ['bitrix24.ru', 'bitrix.info'];
      case 'blink':
        return const ['blink.im'];
      default:
        return const [];
    }
  }

  /// Диапазоны IP-адресов медиа-серверов/TURN для прямого доступа.
  static List<String> cidrsFor(String platform) {
    switch (platform.toLowerCase()) {
      case 'vk':
        return const [
          '155.212.192.0/20',
          '95.142.192.0/20',
          '95.213.192.0/19',
          '87.240.128.0/18',
          '93.186.224.0/20',
        ];
      case 'telemost':
        return const [
          '5.255.211.0/24',
          '77.88.0.0/18',
          '87.250.250.0/24',
          '213.180.193.0/24',
        ];
      default:
        return const [];
    }
  }

  /// Все домены прямого доступа для переданного сервера.
  static List<String> domainsForServer(VpnServer server) {
    if (!server.isWhitelistBypass) return const [];
    return domainsFor(server.whitelistPlatform ?? 'wbstream');
  }

  /// Все CIDR прямого доступа для переданного сервера.
  static List<String> cidrsForServer(VpnServer server) {
    if (!server.isWhitelistBypass) return const [];
    return cidrsFor(server.whitelistPlatform ?? 'wbstream');
  }
}

/// Управление дочерним процессом WebRTC-релея (`whitelist-bypass.exe` / `librelay.so`).
///
/// Релей подключается к комнате видеозвонка (WB Stream / VK Calls / Telemost и др.)
/// и поднимает локальный SOCKS5-прокси (по умолчанию `127.0.0.1:10855`).
class WhitelistBypassProcess {
  Process? _process;
  final List<String> _tail = [];
  static const _tailMax = 100;

  Completer<void>? _connectCompleter;
  bool _exited = false;
  String? _lastError;

  bool get isRunning => _process != null && !_exited;
  String get tail => _tail.join('\n');
  String? get lastError => _lastError;

  /// Поиск бинарника релея на хосте.
  static String? locateExecutable() {
    final env = Platform.environment['SILENTGATE_WHITELIST_BYPASS'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) {
      return env;
    }

    if (Platform.isWindows) {
      final loc = XrayPaths.locate();
      if (loc != null) {
        final path = '${loc.assetDir}${Platform.pathSeparator}whitelist-bypass.exe';
        if (File(path).existsSync()) return path;
      }
      final devPath = 'engine${Platform.pathSeparator}windows${Platform.pathSeparator}bin${Platform.pathSeparator}whitelist-bypass.exe';
      if (File(devPath).existsSync()) return devPath;
    }

    return null;
  }

  /// Запуск релея для подключения к серверу.
  Future<void> start({
    required VpnServer server,
    int socksPort = 10855,
    String? executablePath,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    if (_process != null) {
      await stop();
    }

    final exe = executablePath ?? locateExecutable();
    if (exe == null || !File(exe).existsSync()) {
      if (Platform.isAndroid) {
        throw StateError(
          'Модуль обхода белых списков (librelay.so) не найден по пути: $exe. '
          'Убедитесь, что APK собран с нативным модулем и extractNativeLibs=true.',
        );
      }
      throw StateError(
        'Исполняемый файл whitelist-bypass не найден: $exe. '
        'Убедитесь, что whitelist-bypass.exe находится в папке ядра.',
      );
    }

    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['755', exe]);
      } catch (_) {}
    }

    final platform = (server.whitelistPlatform ?? 'wbstream').toLowerCase();
    final mode = '$platform-headless-joiner';

    _exited = false;
    _lastError = null;
    _connectCompleter = Completer<void>();

    final args = [
      '--mode', mode,
      '--socks-host', '127.0.0.1',
      '--socks-port', '$socksPort',
    ];

    AppLog.i('Запуск релея обхода БС: $exe ${args.join(" ")}');

    final proc = await Process.start(exe, args, mode: ProcessStartMode.normal);
    _process = proc;

    // Чтение stdout построчно для протокола handshake и DNS-резолвинга
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => _handleOutputLine(line, proc, server),
          onError: (e) {
            AppLog.w('Ошибка stdout релея: $e');
          },
          onDone: () {
            _exited = true;
          },
        );

    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _recordTail('[ERR] $line');
          AppLog.d('[whitelist-bypass stderr] $line');
        });

    proc.exitCode.then((code) {
      _exited = true;
      AppLog.i('Процесс релея завершился с кодом $code');
      if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
        _connectCompleter!.completeError(
          StateError('Релей завершился до установки туннеля (код $code): $_lastError\n$tail'),
        );
      }
    });

    try {
      await _connectCompleter!.future.timeout(timeout);
    } on TimeoutException {
      await stop();
      throw TimeoutException('Превышено время ожидания подключения к комнате видеозвонка ($timeout)');
    }
  }

  void _handleOutputLine(String line, Process proc, VpnServer server) {
    _recordTail(line);
    AppLog.d('[whitelist-bypass stdout] $line');

    if (line == 'STATUS:READY') {
      _sendJoinCommand(proc, server);
    } else if (line.startsWith('RESOLVE:')) {
      final host = line.substring('RESOLVE:'.length).trim();
      _resolveAndReply(proc, host);
    } else if (line == 'STATUS:TUNNEL_CONNECTED') {
      AppLog.i('Туннель обхода белых списков успешно установлен!');
      if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
        _connectCompleter!.complete();
      }
    } else if (line.startsWith('STATUS:ERROR:')) {
      final err = line.substring('STATUS:ERROR:'.length).trim();
      _lastError = err;
      AppLog.w('Ошибка релея белых списков: $err');
      if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
        _connectCompleter!.completeError(StateError(err));
      }
    }
  }

  void _sendJoinCommand(Process proc, VpnServer server) {
    final platform = (server.whitelistPlatform ?? 'wbstream').toLowerCase();
    final mode = server.whitelistMode ?? 'video';
    final room = server.whitelistRoom ?? '';

    final payload = <String, dynamic>{
      'displayName': 'SilentGate',
      'tunnelMode': mode,
    };

    if (platform == 'vk') {
      payload['joinLink'] = room;
      payload['reliable'] = true;
      final cmd = 'AUTH:${jsonEncode(payload)}\n';
      AppLog.i('Отправка команды авторизации VK в релей');
      proc.stdin.write(cmd);
    } else if (platform == 'wbstream') {
      payload['roomId'] = room;
      final cmd = 'JOIN:${jsonEncode(payload)}\n';
      AppLog.i('Отправка команды подключения WBStream в релей');
      proc.stdin.write(cmd);
    } else {
      payload['joinLink'] = room;
      final cmd = 'JOIN:${jsonEncode(payload)}\n';
      AppLog.i('Отправка команды подключения $platform в релей');
      proc.stdin.write(cmd);
    }
  }

  void _resolveAndReply(Process proc, String hostname) {
    AppLog.d('Релей запросил резолв: $hostname');
    InternetAddress.lookup(hostname).then((addrs) {
      if (addrs.isEmpty) {
        proc.stdin.writeln('');
        return;
      }
      final target = addrs.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => addrs.first,
      );
      AppLog.d('Резолв $hostname -> ${target.address}');
      proc.stdin.writeln(target.address);
    }).catchError((err) {
      AppLog.w('Ошибка резолва для $hostname: $err');
      proc.stdin.writeln('');
    });
  }

  void _recordTail(String line) {
    if (_tail.length >= _tailMax) {
      _tail.removeAt(0);
    }
    _tail.add(line);
  }

  /// Остановка релея.
  Future<void> stop() async {
    final p = _process;
    _process = null;
    if (p != null && !_exited) {
      try {
        p.kill(ProcessSignal.sigterm);
        await p.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            p.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } catch (_) {
        // Игнорируем ошибки при завершении процесса
      }
    }
    _exited = true;
  }
}
