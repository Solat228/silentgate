import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import '../models/vpn_server.dart';
import '../platform/app_launcher.dart';
import '../platform/app_log.dart';
import '../platform/app_paths.dart';
import '../platform/captcha_webview.dart';
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
  /// (`telemost` и `dion` работают исключительно поверх видеопотока;
  /// `vk` без явного `mode` работает в режиме `auto`: DataChannel -> авто-откат на Video + KCP).
  static String normalizeMode(String platform, String? mode) {
    final p = platform.trim().toLowerCase();
    if (p == 'telemost' || p == 'dion') return 'video';
    final m = (mode ?? '').trim().toLowerCase();
    if (m == 'dc') return 'dc';
    if (m == 'video') return 'video';
    if (m == 'auto') return 'auto';
    if (p == 'vk') return 'auto';
    return 'video';
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
    final rawRel = q['rel'] ?? q['reliable'];
    final reliable = (rawRel != null && rawRel.trim().isNotEmpty)
        ? _parseBool(rawRel)
        : platform == 'telemost';
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
          '37.9.64.0/18',
          '77.88.0.0/18',
          '87.250.224.0/19',
          '87.250.250.0/24',
          '93.158.128.0/18',
          '213.180.192.0/19',
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
  /// Кэш выбранного в режиме `auto` транспорта на 30 минут по ключу `platform|room`,
  /// чтобы повторные переподключения на сетях, где оператор режет SCTP DataChannel
  /// (или нода ещё не обновлена), сразу поднимали `video` без повторной пробы.
  static final Map<String, ({String mode, DateTime expiresAt})> _autoModeCache =
      {};
  static const Duration _autoModeCacheTtl = Duration(minutes: 30);

  @visibleForTesting
  static void clearAutoModeCacheForTests() => _autoModeCache.clear();

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
    String? modeOverride,
  }) {
    final platform = (server.whitelistPlatform ?? 'wbstream').toLowerCase();
    final room =
        WhitelistBypassSpec.normalizeRoom(platform, server.whitelistRoom ?? '');
    final requestedMode = modeOverride ??
        WhitelistBypassSpec.normalizeMode(platform, server.whitelistMode);
    final mode = requestedMode == 'auto' ? 'dc' : requestedMode;

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

  static String? _cachedAndroidExecutable;

  /// Доступен ли релей обхода БС на текущей платформе (синхронная проверка для гейтов UI).
  static bool get canLocateOrAndroid =>
      Platform.isAndroid || locateExecutable() != null;

  /// Асинхронный поиск бинарника релея на Windows (`whitelist-bypass.exe`)
  /// и Android (`librelay.so` в `nativeLibraryDir`).
  static Future<String?> resolveExecutablePath() async {
    final syncPath = locateExecutable();
    if (syncPath != null) return syncPath;
    if (Platform.isAndroid) {
      if (_cachedAndroidExecutable != null &&
          File(_cachedAndroidExecutable!).existsSync()) {
        return _cachedAndroidExecutable;
      }
      try {
        final nativeDir = await const MethodChannel('lol.silentgate/device')
            .invokeMethod<String>('nativeLibraryDir');
        if (nativeDir != null && nativeDir.isNotEmpty) {
          final candidate = '$nativeDir/librelay.so';
          if (File(candidate).existsSync()) {
            _cachedAndroidExecutable = candidate;
            return candidate;
          }
        }
      } catch (_) {}
    }
    return null;
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
  ///
  /// Если у сервера режим `auto` (по умолчанию для ссылок ВК), сначала поднимается
  /// скоростной `DataChannel` (`dc`) с проверкой прокачки потока `> 70 КБ` через
  /// локальный SOCKS5. Если оператор связи блокирует SCTP DataChannel или на сервере
  /// урезан буфер чтения, релей прозрачно переключается на `Video + KCP` (`video`),
  /// переиспользуя уже сохранённый токен авторизации ВК без повторной капчи.
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

    final supportDir = await AppPaths.supportDir();
    final platform = (server.whitelistPlatform ?? 'wbstream').toLowerCase();
    if (platform == 'blink') {
      _blinkCookiesPath = await prepareBlinkCookiesFile(server);
    } else {
      _blinkCookiesPath = null;
    }

    final requestedMode =
        WhitelistBypassSpec.normalizeMode(platform, server.whitelistMode);
    if (requestedMode != 'auto') {
      await _startSingleMode(
        exe: exe,
        supportDirPath: supportDir.path,
        server: server,
        concreteMode: requestedMode,
        socksPort: socksPort,
        timeout: timeout,
        abort: abort,
        onInteractiveUrl: onInteractiveUrl,
      );
      return;
    }

    final normRoom =
        WhitelistBypassSpec.normalizeRoom(platform, server.whitelistRoom ?? '');
    final cacheKey = '$platform|$normRoom';
    final cached = _autoModeCache[cacheKey];
    if (cached != null &&
        cached.mode == 'video' &&
        DateTime.now().isBefore(cached.expiresAt)) {
      AppLog.i(
        'Автовыбор БС ($platform): используем закэшированный режим Video + KCP',
      );
      await _startSingleMode(
        exe: exe,
        supportDirPath: supportDir.path,
        server: server,
        concreteMode: 'video',
        socksPort: socksPort,
        timeout: timeout,
        abort: abort,
        onInteractiveUrl: onInteractiveUrl,
      );
      return;
    }

    // 1. Сначала пробуем скоростной WebRTC DataChannel (SCTP) и проверяем поток > 70 КБ.
    final dcInitialTimeout =
        timeout < const Duration(seconds: 18) ? timeout : const Duration(seconds: 18);
    try {
      await _startSingleMode(
        exe: exe,
        supportDirPath: supportDir.path,
        server: server,
        concreteMode: 'dc',
        socksPort: socksPort,
        timeout: dcInitialTimeout,
        abort: abort,
        onInteractiveUrl: onInteractiveUrl,
      );
      if (abort?.call() ?? false) {
        await stop();
        return;
      }

      final bulkOk = await _probeDcBulkTransfer(socksPort, abort);
      if (abort?.call() ?? false) {
        await stop();
        return;
      }
      if (bulkOk) {
        _autoModeCache[cacheKey] = (
          mode: 'dc',
          expiresAt: DateTime.now().add(_autoModeCacheTtl),
        );
        AppLog.i('Автовыбор БС ($platform): DataChannel прошёл проверку крупным потоком');
        return;
      }
      AppLog.w(
        'Автовыбор БС ($platform): DataChannel пропускает рукопожатие, но режет поток > 64 КБ — переключаюсь на Video + KCP',
      );
    } catch (e) {
      if (abort?.call() ?? false) {
        await stop();
        rethrow;
      }
      AppLog.w(
        'Автовыбор БС ($platform): DataChannel недоступен ($e) — автоматический откат на Video + KCP',
      );
    }

    // 2. Бесшовный откат на Video + KCP (токен ВК уже лежит в SILENTGATE_CACHE_DIR — второй капчи нет).
    await stop();
    _autoModeCache[cacheKey] = (
      mode: 'video',
      expiresAt: DateTime.now().add(_autoModeCacheTtl),
    );
    await _startSingleMode(
      exe: exe,
      supportDirPath: supportDir.path,
      server: server,
      concreteMode: 'video',
      socksPort: socksPort,
      timeout: timeout,
      abort: abort,
      onInteractiveUrl: onInteractiveUrl,
    );
  }

  Future<void> _startSingleMode({
    required String exe,
    required String supportDirPath,
    required VpnServer server,
    required String concreteMode,
    required int socksPort,
    required Duration timeout,
    bool Function()? abort,
    void Function(String kind, String url)? onInteractiveUrl,
  }) async {
    final platform = (server.whitelistPlatform ?? 'wbstream').toLowerCase();
    final cliMode = '$platform-headless-joiner';

    _exited = false;
    _lastError = null;
    _connectCompleter = Completer<void>();
    _deadline = DateTime.now().add(timeout);

    final args = [
      '--mode',
      cliMode,
      '--socks-host',
      '127.0.0.1',
      '--socks-port',
      '$socksPort',
    ];

    AppLog.i(
      'Запуск релея обхода БС ($concreteMode): $exe ${args.join(" ")}',
    );

    final proc = await Process.start(
      exe,
      args,
      environment: <String, String>{
        'SILENTGATE_CACHE_DIR': supportDirPath,
      },
      mode: ProcessStartMode.normal,
    );
    CoreCleanup.register(proc);
    _process = proc;

    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => _handleOutputLine(
            line,
            proc,
            server,
            concreteMode,
            onInteractiveUrl,
          ),
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
      if (_process == proc) {
        _exited = true;
      }
      CoreCleanup.unregister(proc);
      AppLog.i('Процесс релея ($concreteMode) завершился с кодом $code');
      if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
        _connectCompleter!.completeError(
          StateError(
            'Релей завершился до установки туннеля (код $code): $_lastError\n$tail',
          ),
        );
      }
    });

    try {
      await _waitConnectedOrAborted(timeout, abort);
    } on TimeoutException {
      await stop();
      throw TimeoutException(
        'Превышено время ожидания подключения к комнате видеозвонка ($timeout)',
      );
    }
  }

  /// Проверяет, что поднятый `DataChannel` реально пропускает непрерывный HTTPS-поток
  /// свыше 64 КБ (отсекает как блокировку SCTP оператором, так и переполнение 64 КБ
  /// буфера на старых бинарниках ноды, где мелкие запросы `2ip.ru` проходят, а YouTube рвётся).
  static Future<bool> _probeDcBulkTransfer(
    int socksPort,
    bool Function()? abort,
  ) async {
    const targets = <({String host, String path})>[
      (
        host: 'ajax.googleapis.com',
        path: '/ajax/libs/jquery/3.7.1/jquery.min.js',
      ),
      (
        host: 'speed.cloudflare.com',
        path: '/__down?bytes=98304',
      ),
    ];
    for (final t in targets) {
      if (abort?.call() ?? false) return false;
      final ok = await _probeSingleHttpsTargetOverSocks5(
        socksPort: socksPort,
        host: t.host,
        path: t.path,
      );
      if (ok) return true;
    }
    return false;
  }

  static Future<bool> _probeSingleHttpsTargetOverSocks5({
    required int socksPort,
    required String host,
    required String path,
  }) async {
    RawSocket? raw;
    RawSecureSocket? tls;
    StreamSubscription<RawSocketEvent>? sub;
    try {
      raw = await RawSocket.connect(
        '127.0.0.1',
        socksPort,
        timeout: const Duration(seconds: 2),
      );
      final rx = <int>[];
      var waiters = <void Function()>[];
      var closed = false;

      void notify() {
        final copy = List<void Function()>.from(waiters);
        waiters.clear();
        for (final w in copy) {
          w();
        }
      }

      sub = raw.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final chunk = raw?.read();
            if (chunk != null && chunk.isNotEmpty) {
              rx.addAll(chunk);
              notify();
            }
          } else if (event == RawSocketEvent.readClosed ||
              event == RawSocketEvent.closed) {
            closed = true;
            notify();
          }
        },
        onError: (_) {
          closed = true;
          notify();
        },
        onDone: () {
          closed = true;
          notify();
        },
      );

      Future<Uint8List> readExact(int count) async {
        while (rx.length < count && !closed) {
          final c = Completer<void>();
          waiters.add(() {
            if (!c.isCompleted) c.complete();
          });
          await c.future;
        }
        if (rx.length < count) {
          throw const SocketException('Преждевременное закрытие SOCKS5-рукопожатия');
        }
        final out = Uint8List.fromList(rx.sublist(0, count));
        rx.removeRange(0, count);
        return out;
      }

      // 1. SOCKS5 приветствие без авторизации
      raw.write(const <int>[0x05, 0x01, 0x00]);
      final greet = await readExact(2).timeout(const Duration(seconds: 2));
      if (greet[0] != 0x05 || greet[1] != 0x00) return false;

      // 2. SOCKS5 CONNECT по доменному имени на порт 443
      final hostBytes = ascii.encode(host);
      final req = <int>[
        0x05,
        0x01,
        0x00,
        0x03,
        hostBytes.length,
        ...hostBytes,
        0x01,
        0xBB,
      ];
      raw.write(req);

      final head = await readExact(4).timeout(const Duration(seconds: 3));
      if (head[0] != 0x05 || head[1] != 0x00) return false;
      final atyp = head[3];
      if (atyp == 0x01) {
        await readExact(6).timeout(const Duration(seconds: 2));
      } else if (atyp == 0x04) {
        await readExact(18).timeout(const Duration(seconds: 2));
      } else if (atyp == 0x03) {
        final lenByte = await readExact(1).timeout(const Duration(seconds: 2));
        await readExact(lenByte[0] + 2).timeout(const Duration(seconds: 2));
      } else {
        return false;
      }

      // 3. Обновляем RawSocket до TLS и скачиваем >= 70 КБ полезной нагрузки
      tls = await RawSecureSocket.secure(
        raw,
        subscription: sub,
        host: host,
      ).timeout(const Duration(seconds: 3));
      sub = null; // Владение подпиской передано в RawSecureSocket

      final httpReq = ascii.encode(
        'GET $path HTTP/1.1\r\n'
        'Host: $host\r\n'
        'User-Agent: curl/8.7.1\r\n'
        'Accept-Encoding: identity\r\n'
        'Connection: close\r\n\r\n',
      );

      final done = Completer<bool>();
      var totalBytes = 0;
      var headerChecked = false;
      final headBuf = <int>[];

      tls.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final chunk = tls?.read();
            if (chunk != null && chunk.isNotEmpty) {
              totalBytes += chunk.length;
              if (!headerChecked && headBuf.length < 32) {
                headBuf.addAll(chunk.take(32 - headBuf.length));
                if (headBuf.length >= 12) {
                  headerChecked = true;
                  final statusLine = ascii.decode(headBuf, allowInvalid: true);
                  if (!statusLine.startsWith('HTTP/1.1 200') &&
                      !statusLine.startsWith('HTTP/1.0 200')) {
                    if (!done.isCompleted) done.complete(false);
                    return;
                  }
                }
              }
              if (totalBytes >= 70000 && !done.isCompleted) {
                done.complete(true);
              }
            }
          } else if (event == RawSocketEvent.readClosed ||
              event == RawSocketEvent.closed) {
            if (!done.isCompleted) done.complete(totalBytes >= 70000);
          }
        },
        onError: (_) {
          if (!done.isCompleted) done.complete(false);
        },
        onDone: () {
          if (!done.isCompleted) done.complete(totalBytes >= 70000);
        },
      );

      tls.write(httpReq);
      return await done.future.timeout(
        const Duration(milliseconds: 4500),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    } finally {
      try {
        await sub?.cancel();
      } catch (_) {}
      try {
        await tls?.close();
      } catch (_) {}
      try {
        await raw?.close();
      } catch (_) {}
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
    String concreteMode,
    void Function(String kind, String url)? onInteractiveUrl,
  ) {
    _recordTail(line);
    AppLog.d('[whitelist-bypass stdout] $line');

    if (line == 'STATUS:READY') {
      _sendJoinCommand(proc, server, concreteMode);
    } else if (line.startsWith('RESOLVE:')) {
      final host = line.substring('RESOLVE:'.length).trim();
      _resolveAndReply(proc, host);
    } else if (line.startsWith('STATUS:CAPTCHA:')) {
      final url = line.substring('STATUS:CAPTCHA:'.length).trim();
      AppLog.i('VK запросил прохождение капчи, открываю встроенное окно: $url');
      // Продлеваем ожидание до 5 минут, пока проходит автоклик или ручной ввод капчи.
      _deadline = DateTime.now().add(const Duration(minutes: 5));
      onInteractiveUrl?.call('captcha', url);
      unawaited(openCaptchaUrl(url));
    } else if (line == 'STATUS:CAPTCHA_SOLVED') {
      AppLog.i('Капча ВК успешно пройдена, закрываю встроенное окно');
      unawaited(CaptchaWebViewBridge.close());
    } else if (line.startsWith('STATUS:LOGIN_LINK:')) {
      final url = line.substring('STATUS:LOGIN_LINK:'.length).trim();
      AppLog.i('Blink запросил подтверждение входа, открываю ссылку: $url');
      _deadline = DateTime.now().add(const Duration(minutes: 5));
      onInteractiveUrl?.call('login', url);
      unawaited(openInteractiveUrl(url));
    } else if (line == 'STATUS:TUNNEL_CONNECTED') {
      AppLog.i('Туннель обхода белых списков ($concreteMode) успешно установлен!');
      unawaited(CaptchaWebViewBridge.close());
      if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
        _connectCompleter!.complete();
      }
    } else if (line.startsWith('STATUS:ERROR:')) {
      final err = line.substring('STATUS:ERROR:'.length).trim();
      _lastError = err;
      AppLog.w('Ошибка релея белых списков ($concreteMode): $err');
      unawaited(CaptchaWebViewBridge.close());
      if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
        _connectCompleter!.completeError(StateError(err));
      }
    }
  }

  void _sendJoinCommand(Process proc, VpnServer server, String concreteMode) {
    final platform = (server.whitelistPlatform ?? 'wbstream').toLowerCase();
    final cmd = buildStdinCommand(
      server,
      blinkCookiesPath: _blinkCookiesPath,
      modeOverride: concreteMode,
    );
    AppLog.i('Отправка команды подключения $platform ($concreteMode) в релей');
    try {
      proc.stdin.write(cmd);
    } catch (_) {}
  }

  /// Открывает капчу ВК сначала во встроенном нативном WebView с фоновым автокликом
  /// чекбокса (`WebView2` на Windows / `android.webkit.WebView` на Android),
  /// а при отсутствии системного WebView откатывается на внешний браузер.
  @visibleForTesting
  static Future<void> openCaptchaUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty ||
        (!trimmed.startsWith('http://') && !trimmed.startsWith('https://'))) {
      return;
    }
    final openedInApp = await CaptchaWebViewBridge.open(trimmed);
    if (!openedInApp) {
      await openInteractiveUrl(trimmed);
    }
  }

  /// Открывает интерактивную ссылку подтверждения (вход Blink или запасной откат капчи)
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
    void safeWriteLn(String v) {
      if (_process != proc || _exited) return;
      try {
        proc.stdin.writeln(v);
      } catch (_) {}
    }

    InternetAddress.lookup(hostname)
        .timeout(const Duration(seconds: 3))
        .then((addrs) {
      if (addrs.isEmpty) {
        safeWriteLn('');
        return;
      }
      final target = addrs.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => addrs.first,
      );
      AppLog.d('Резолв $hostname -> ${target.address}');
      safeWriteLn(target.address);
    }).catchError((err) {
      AppLog.w('Ошибка резолва для $hostname: $err');
      safeWriteLn('');
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
    unawaited(CaptchaWebViewBridge.close());
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
    unawaited(CaptchaWebViewBridge.close());
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
