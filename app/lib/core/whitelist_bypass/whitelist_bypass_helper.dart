import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../models/vpn_server.dart';
import '../platform/app_launcher.dart';
import '../platform/app_log.dart';
import '../platform/app_paths.dart';
import '../platform/core_cleanup.dart';
import '../../engine/windows/xray_paths.dart';

/// Метаданные транспорта обхода белых списков, извлечённые из WS/HTTP `path`
/// ноды Remnawave (формат `/sgbs?p=<platform>&r=<room>&m=<video|dc>&...`).
class WhitelistTransportMeta {
  final String cleanWsPath;
  final String platform;
  final String room;
  final String mode;
  final bool reliable;
  final bool dualTrack;
  final int? vp8Fps;
  final int? vp8Batch;
  final String? blinkToken;

  const WhitelistTransportMeta({
    required this.cleanWsPath,
    required this.platform,
    required this.room,
    required this.mode,
    this.reliable = false,
    this.dualTrack = false,
    this.vp8Fps,
    this.vp8Batch,
    this.blinkToken,
  });
}

/// Единая спецификация и нормализатор всех 6 способов обхода белых списков:
/// `wbstream`, `telemost`, `dion`, `bitrix`, `vk`, `blink`.
///
/// Гарантирует совпадение формата комнаты/ссылки между клиентом и creator-нодой
/// (от этого зависит как HTTP/WS-сигнализация платформы, так и ключ обфускации ChaCha20).
abstract final class WhitelistBypassSpec {
  static const Set<String> supportedPlatforms = {
    'wbstream',
    'telemost',
    'dion',
    'bitrix',
    'vk',
    'blink',
  };

  /// Поддерживает ли платформа второй видеопоток (демонстрацию экрана).
  static bool supportsDualTrack(String platform) {
    final p = platform.trim().toLowerCase();
    return p != 'vk' && p != 'dion';
  }

  /// Нормализация режима туннеля с учётом ограничений платформы
  /// (`telemost` и `dion` работают исключительно поверх видеопотока).
  static String normalizeMode(String platform, String? mode) {
    final p = platform.trim().toLowerCase();
    if (p == 'telemost' || p == 'dion') return 'video';
    return (mode ?? '').trim().toLowerCase() == 'dc' ? 'dc' : 'video';
  }

  /// Приводит идентификатор комнаты или ссылку звонка к формату, который ждёт
  /// соответствующий headless-joiner в `whitelist-bypass`.
  static String normalizeRoom(String platform, String raw) {
    final p = platform.trim().toLowerCase();
    var val = raw.trim();
    if (val.isEmpty) return '';

    switch (p) {
      case 'wbstream':
        val = val
            .replaceFirst(RegExp(r'^wbstream://', caseSensitive: false), '')
            .replaceFirst(
                RegExp(r'^https?://stream\.wb\.ru/room/', caseSensitive: false),
                '')
            .replaceFirst(RegExp(r'^room/', caseSensitive: false), '');
        final qIdx = val.indexOf(RegExp(r'[?#]'));
        if (qIdx >= 0) val = val.substring(0, qIdx);
        return val.replaceAll(RegExp(r'^/+|/+$'), '');

      case 'dion':
        val = val
            .replaceFirst(RegExp(r'^dion://', caseSensitive: false), '')
            .replaceFirst(
                RegExp(r'^https?://dion\.vc/event/', caseSensitive: false), '')
            .replaceFirst(
                RegExp(r'^https?://dion\.vc/', caseSensitive: false), '');
        final qIdx = val.indexOf(RegExp(r'[?#/]'));
        if (qIdx >= 0) val = val.substring(0, qIdx);
        return val;

      case 'telemost':
        val = val.replaceFirst(RegExp(r'^telemost://', caseSensitive: false), '');
        if (val.startsWith('http://') || val.startsWith('https://')) {
          final qIdx = val.indexOf(RegExp(r'[?#]'));
          if (qIdx >= 0) val = val.substring(0, qIdx);
          return val.replaceAll(RegExp(r'/+$'), '');
        }
        val = val
            .replaceFirst(RegExp(r'^j/', caseSensitive: false), '')
            .replaceAll(RegExp(r'^/+|/+$'), '');
        return 'https://telemost.yandex.ru/j/$val';

      case 'vk':
        val = val.replaceFirst(RegExp(r'^vkcall://', caseSensitive: false), '');
        if (val.toLowerCase().startsWith('https://vk.com/call/join/')) {
          val = 'https://vk.ru/call/join/${val.substring('https://vk.com/call/join/'.length)}';
        } else if (val.toLowerCase().startsWith('http://vk.com/call/join/')) {
          val = 'https://vk.ru/call/join/${val.substring('http://vk.com/call/join/'.length)}';
        }
        if (val.startsWith('http://') || val.startsWith('https://')) {
          final qIdx = val.indexOf(RegExp(r'[?#]'));
          if (qIdx >= 0) val = val.substring(0, qIdx);
          return val.replaceAll(RegExp(r'/+$'), '');
        }
        val = val
            .replaceFirst(RegExp(r'^call/join/', caseSensitive: false), '')
            .replaceAll(RegExp(r'^/+|/+$'), '');
        return 'https://vk.ru/call/join/$val';

      case 'bitrix':
        if (val.toLowerCase().startsWith('bitrix://')) {
          val = 'https://${val.substring('bitrix://'.length)}';
        }
        final uri = Uri.tryParse(val);
        if (uri != null && uri.host.isNotEmpty) {
          var path = uri.path;
          if (path.startsWith('/call/')) {
            path = '/video/${path.substring('/call/'.length)}';
          }
          final portPart = uri.hasPort ? ':${uri.port}' : '';
          return '${uri.scheme}://${uri.host}$portPart$path';
        }
        return val;

      case 'blink':
        final hashIdx = val.indexOf('#');
        if (hashIdx >= 0) val = val.substring(0, hashIdx);
        if (val.startsWith('blink://') ||
            val.startsWith('https://') ||
            val.startsWith('http://')) {
          return val;
        }
        return 'blink://${val.replaceAll(RegExp(r'^/+|/+$'), '')}';

      default:
        return val;
    }
  }

  /// Разбирает путь транспорта Remnawave (`/sgbs?p=wbstream&r=...`).
  /// Возвращает `null`, если путь не относится к транспорту БС.
  static WhitelistTransportMeta? tryParseTransportPath(String? rawPath) {
    if (rawPath == null || rawPath.isEmpty || !rawPath.contains('?')) {
      return null;
    }
    final uri = Uri.tryParse(rawPath);
    if (uri == null) return null;
    final basePath = uri.path.isEmpty ? '/' : uri.path;
    final q = uri.queryParameters;

    final isSgbsPath = basePath == '/sgbs' ||
        basePath.endsWith('/sgbs') ||
        q['sgbs'] == '1';
    if (!isSgbsPath) return null;

    final platform = (q['p'] ?? q['platform'] ?? '').trim().toLowerCase();
    final rawRoom = (q['r'] ?? q['room'] ?? '').trim();
    if (!supportedPlatforms.contains(platform) || rawRoom.isEmpty) {
      return null;
    }

    final room = normalizeRoom(platform, rawRoom);
    if (room.isEmpty) return null;

    final mode = normalizeMode(platform, q['m'] ?? q['mode']);
    final reliable = _parseBool(q['rel'] ?? q['reliable']);
    final dualTrack =
        supportsDualTrack(platform) && _parseBool(q['dt'] ?? q['dual']);
    final fps = _parsePosInt(q['fps']);
    final batch = _parsePosInt(q['batch']);
    final bt = (q['bt'] ?? '').trim();

    return WhitelistTransportMeta(
      cleanWsPath: basePath,
      platform: platform,
      room: room,
      mode: mode,
      reliable: reliable,
      dualTrack: dualTrack,
      vp8Fps: fps,
      vp8Batch: batch,
      blinkToken: bt.isEmpty || platform != 'blink' ? null : bt,
    );
  }

  /// Снимает служебные query-параметры БС с пути WebSocket перед передачей в Xray.
  static String cleanTransportPath(String? rawPath) {
    final meta = tryParseTransportPath(rawPath);
    if (meta != null) return meta.cleanWsPath;
    if (rawPath == null || rawPath.isEmpty) return '/';
    final qIdx = rawPath.indexOf('?');
    return qIdx >= 0 ? (rawPath.substring(0, qIdx).isEmpty ? '/' : rawPath.substring(0, qIdx)) : rawPath;
  }

  static bool _parseBool(String? v) {
    final s = (v ?? '').trim().toLowerCase();
    return s == '1' || s == 'true';
  }

  static int? _parsePosInt(String? v) {
    if (v == null || v.isEmpty) return null;
    final parsed = int.tryParse(v.trim());
    return (parsed != null && parsed > 0) ? parsed : null;
  }
}

/// Эндпоинты медиа-серверов белых списков для прямого роутинга (direct).
///
/// Трафик к этим доменам и IP-подсетям ОБЯЗАН идти напрямую (через сотового оператора),
/// а не заворачиваться в туннель, иначе возникнет петля маршрутизации (routing loop).
abstract final class WhitelistBypassEndpoint {
  /// Домены для прямого доступа.
  static List<String> domainsFor(String platform) {
    switch (platform.toLowerCase()) {
      case 'wbstream':
        return const ['stream.wb.ru', 'wb.ru', 'wildberries.ru'];
      case 'telemost':
        return const [
          'telemost.yandex.ru',
          'yandex.ru',
          'yandex.net',
        ];
      case 'vk':
        return const [
          'vk.ru',
          'id.vk.ru',
          'login.vk.ru',
          'vk.com',
          'vk.me',
          'vk-portal.net',
          'userapi.com',
          'ok.ru',
          'mycdn.me',
          'calls.okcdn.ru',
        ];
      case 'dion':
        return const ['dion.vc'];
      case 'bitrix':
        return const [
          'bitrix24.ru',
          'bitrix.info',
          'bitrix24.com',
          'bitrix24.net',
        ];
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
          '90.156.0.0/16',
          '155.212.192.0/20',
          '95.142.192.0/20',
          '95.213.192.0/19',
          '87.240.128.0/18',
          '93.186.224.0/20',
          '79.137.192.0/18',
          '5.61.16.0/21',
          '5.61.232.0/21',
          '217.20.144.0/20',
          '185.32.248.0/22',
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

  /// Все домены прямого доступа для переданного сервера (включая кастомный портал Bitrix).
  static List<String> domainsForServer(VpnServer server) {
    if (!server.usesWhitelistRelay) return const [];
    final platform = (server.whitelistPlatform ?? 'wbstream').toLowerCase();
    final base = domainsFor(platform);
    if (platform == 'bitrix') {
      final roomHost = Uri.tryParse(server.whitelistRoom ?? '')?.host.trim() ?? '';
      if (roomHost.isNotEmpty && !base.contains(roomHost)) {
        return [...base, roomHost];
      }
    }
    return base;
  }

  /// Все CIDR прямого доступа для переданного сервера.
  static List<String> cidrsForServer(VpnServer server) {
    if (!server.usesWhitelistRelay) return const [];
    return cidrsFor(server.whitelistPlatform ?? 'wbstream');
  }
}

/// Управление дочерним процессом WebRTC-релея (`whitelist-bypass.exe` / `librelay.so`).
///
/// Релей подключается к комнате видеозвонка (WB Stream / Telemost / Dion / Bitrix / VK / Blink)
/// и поднимает локальный SOCKS5-прокси (по умолчанию `127.0.0.1:10855`).
class WhitelistBypassProcess {
  Process? _process;
  final List<String> _tail = [];
  static const _tailMax = 100;

  Completer<void>? _connectCompleter;
  DateTime? _deadline;
  bool _exited = false;
  String? _lastError;
  String? _blinkCookiesPath;

  bool get isRunning => _process != null && !_exited;
  String get tail => _tail.join('\n');
  String? get lastError => _lastError;

  /// Формирует точную stdin-команду (`JOIN:{...}\n` или `AUTH:{...}\n`) для релея
  /// под любую из 6 поддерживаемых платформ. Вынесено для детерминированных тестов.
  static String buildStdinCommand(
    VpnServer server, {
    String? blinkCookiesPath,
  }) {
    final platform = (server.whitelistPlatform ?? 'wbstream').toLowerCase();
    final room =
        WhitelistBypassSpec.normalizeRoom(platform, server.whitelistRoom ?? '');
    final mode = WhitelistBypassSpec.normalizeMode(platform, server.whitelistMode);

    void addTuning(Map<String, dynamic> m, {required bool allowDualTrack}) {
      if ((server.whitelistVp8Fps ?? 0) > 0) {
        m['vp8Fps'] = server.whitelistVp8Fps;
      }
      if ((server.whitelistVp8Batch ?? 0) > 0) {
        m['vp8Batch'] = server.whitelistVp8Batch;
      }
      if (allowDualTrack &&
          WhitelistBypassSpec.supportsDualTrack(platform) &&
          server.whitelistDualTrack) {
        m['dualTrack'] = true;
      }
    }

    switch (platform) {
      case 'wbstream':
        final payload = <String, dynamic>{
          'roomId': room,
          'displayName': 'SilentGate',
          'tunnelMode': mode,
          if (server.whitelistReliable) 'reliable': true,
        };
        addTuning(payload, allowDualTrack: true);
        return 'JOIN:${jsonEncode(payload)}\n';

      case 'dion':
        final payload = <String, dynamic>{
          'roomId': room,
          'displayName': 'SilentGate',
        };
        return 'JOIN:${jsonEncode(payload)}\n';

      case 'telemost':
        final payload = <String, dynamic>{
          'joinLink': room,
          'displayName': 'SilentGate',
          if (server.whitelistReliable) 'reliable': true,
        };
        addTuning(payload, allowDualTrack: true);
        return 'JOIN:${jsonEncode(payload)}\n';

      case 'bitrix':
        final payload = <String, dynamic>{
          'joinLink': room,
          'displayName': 'SilentGate',
          'tunnelMode': mode,
          if (server.whitelistReliable) 'reliable': true,
        };
        addTuning(payload, allowDualTrack: true);
        return 'JOIN:${jsonEncode(payload)}\n';

      case 'vk':
        final payload = <String, dynamic>{
          'joinLink': room,
          'displayName': 'SilentGate',
          'tunnelMode': mode,
          // В видеорежиме VK без KCP теряет пакеты на SFU/TURN, поэтому включён по умолчанию.
          'reliable': server.whitelistReliable || mode == 'video',
        };
        addTuning(payload, allowDualTrack: false);
        return 'AUTH:${jsonEncode(payload)}\n';

      case 'blink':
        final payload = <String, dynamic>{
          'joinLink': room,
          'cookiesPath': blinkCookiesPath ?? '',
          'tunnelMode': mode,
          if (server.whitelistReliable) 'reliable': true,
        };
        addTuning(payload, allowDualTrack: true);
        return 'JOIN:${jsonEncode(payload)}\n';

      default:
        final payload = <String, dynamic>{
          'joinLink': room,
          'displayName': 'SilentGate',
          'tunnelMode': mode,
        };
        return 'JOIN:${jsonEncode(payload)}\n';
    }
  }

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

  /// Подготавливает файл сессии Blink (`blink-cookies.json`) в каталоге приложения.
  /// Если нода передала гостевой `whitelistBlinkToken`, записывает его в файл,
  /// чтобы подключение прошло без интерактивного входа пользователя.
  static Future<String> prepareBlinkCookiesFile(VpnServer server) async {
    final dir = await AppPaths.supportDir();
    final file = File('${dir.path}${Platform.pathSeparator}blink-cookies.json');
    final guestToken = (server.whitelistBlinkToken ?? '').trim();
    if (guestToken.isNotEmpty) {
      var alreadyHasToken = false;
      if (file.existsSync()) {
        try {
          final raw = file.readAsStringSync();
          alreadyHasToken = raw.contains(guestToken);
        } catch (_) {}
      }
      if (!alreadyHasToken) {
        final payload = jsonEncode([
          {'name': 'blink_refresh_token', 'value': guestToken},
        ]);
        await file.writeAsString(payload, flush: true);
      }
    }
    return file.path;
  }

  /// Запуск релея для подключения к серверу.
  Future<void> start({
    required VpnServer server,
    int socksPort = 10855,
    String? executablePath,
    Duration timeout = const Duration(seconds: 45),
    bool Function()? abort,
    void Function(String kind, String url)? onInteractiveUrl,
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
    if (platform == 'blink') {
      _blinkCookiesPath = await prepareBlinkCookiesFile(server);
    } else {
      _blinkCookiesPath = null;
    }

    final mode = '$platform-headless-joiner';

    _exited = false;
    _lastError = null;
    _connectCompleter = Completer<void>();
    _deadline = DateTime.now().add(timeout);

    final args = [
      '--mode', mode,
      '--socks-host', '127.0.0.1',
      '--socks-port', '$socksPort',
    ];

    AppLog.i('Запуск релея обхода БС: $exe ${args.join(" ")}');

    final proc = await Process.start(exe, args, mode: ProcessStartMode.normal);
    CoreCleanup.register(proc);
    _process = proc;

    // Чтение stdout построчно для протокола handshake и DNS-резолвинга
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => _handleOutputLine(line, proc, server, onInteractiveUrl),
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
      CoreCleanup.unregister(proc);
      AppLog.i('Процесс релея завершился с кодом $code');
      if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
        _connectCompleter!.completeError(
          StateError('Релей завершился до установки туннеля (код $code): $_lastError\n$tail'),
        );
      }
    });

    try {
      await _waitConnectedOrAborted(timeout, abort);
    } on TimeoutException {
      await stop();
      throw TimeoutException('Превышено время ожидания подключения к комнате видеозвонка ($timeout)');
    }
  }

  Future<void> _waitConnectedOrAborted(
      Duration initialTimeout, bool Function()? abort) async {
    final completer = _connectCompleter!;
    _deadline ??= DateTime.now().add(initialTimeout);
    final poll = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (completer.isCompleted) {
        t.cancel();
        return;
      }
      if (abort != null && abort()) {
        t.cancel();
        completer.completeError(
            const SocketException('Подключение отменено пользователем'));
        return;
      }
      final dl = _deadline;
      if (dl != null && DateTime.now().isAfter(dl)) {
        t.cancel();
        completer.completeError(TimeoutException(
            'Превышено время ожидания подключения к комнате видеозвонка'));
      }
    });
    try {
      await completer.future;
    } catch (e) {
      if (abort?.call() ?? false) {
        await stop();
      }
      rethrow;
    } finally {
      poll.cancel();
    }
  }

  void _handleOutputLine(
    String line,
    Process proc,
    VpnServer server,
    void Function(String kind, String url)? onInteractiveUrl,
  ) {
    _recordTail(line);
    AppLog.d('[whitelist-bypass stdout] $line');

    if (line == 'STATUS:READY') {
      _sendJoinCommand(proc, server);
    } else if (line.startsWith('RESOLVE:')) {
      final host = line.substring('RESOLVE:'.length).trim();
      _resolveAndReply(proc, host);
    } else if (line.startsWith('STATUS:CAPTCHA:')) {
      final url = line.substring('STATUS:CAPTCHA:'.length).trim();
      AppLog.i('VK запросил прохождение капчи, открываю браузер: $url');
      // Продлеваем ожидание до 5 минут, пока пользователь проходит капчу.
      _deadline = DateTime.now().add(const Duration(minutes: 5));
      onInteractiveUrl?.call('captcha', url);
      unawaited(openInteractiveUrl(url));
    } else if (line.startsWith('STATUS:LOGIN_LINK:')) {
      final url = line.substring('STATUS:LOGIN_LINK:'.length).trim();
      AppLog.i('Blink запросил подтверждение входа, открываю ссылку: $url');
      _deadline = DateTime.now().add(const Duration(minutes: 5));
      onInteractiveUrl?.call('login', url);
      unawaited(openInteractiveUrl(url));
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
    final cmd = buildStdinCommand(server, blinkCookiesPath: _blinkCookiesPath);
    AppLog.i('Отправка команды подключения $platform в релей');
    proc.stdin.write(cmd);
  }

  /// Открывает интерактивную ссылку подтверждения (капча VK / вход Blink)
  /// через штатный платформенный [UrlOpener] (`ACTION_VIEW` на Android,
  /// `rundll32 url.dll,FileProtocolHandler` на Windows с валидацией URI).
  @visibleForTesting
  static Future<void> openInteractiveUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty ||
        (!trimmed.startsWith('http://') && !trimmed.startsWith('https://'))) {
      return;
    }
    try {
      await UrlOpener.open(trimmed);
    } catch (e) {
      AppLog.w('Не удалось автоматически открыть браузер для БС: $e');
    }
  }

  void _resolveAndReply(Process proc, String hostname) {
    AppLog.d('Релей запросил резолв: $hostname');
    InternetAddress.lookup(hostname)
        .timeout(const Duration(seconds: 3))
        .then((addrs) {
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
  void forceKill() {
    final p = _process;
    _process = null;
    if (p != null) {
      CoreCleanup.unregister(p);
      if (Platform.isWindows) {
        try {
          Process.start('taskkill', ['/F', '/T', '/PID', '${p.pid}'],
              mode: ProcessStartMode.detached);
        } catch (_) {}
      }
      try {
        p.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    _exited = true;
  }

  Future<void> stop() async {
    final p = _process;
    _process = null;
    if (p != null && !_exited) {
      try {
        CoreCleanup.unregister(p);
        p.kill(ProcessSignal.sigterm);
        await p.exitCode.timeout(
          const Duration(milliseconds: 800),
          onTimeout: () {
            if (Platform.isWindows) {
              Process.start('taskkill', ['/F', '/T', '/PID', '${p.pid}'],
                  mode: ProcessStartMode.detached);
            }
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
