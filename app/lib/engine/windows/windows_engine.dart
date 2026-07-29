import 'dart:async';
import 'dart:io';

import '../../core/platform/app_log.dart';
import '../../core/platform/app_paths.dart';
import '../../core/platform/port_check.dart';
import '../../core/models/traffic_stats.dart';
import '../../core/models/vpn_server.dart';
import '../../core/models/vpn_status.dart';
import '../../core/settings/app_settings.dart';
import '../../core/singbox/singbox_config_builder.dart';
import '../engine_base.dart';
import 'singbox_process.dart';
import 'singbox_stats.dart';
import 'system_proxy.dart';
import 'tun/singbox_router_windows.dart';
import 'tun/tun_router.dart';
import 'xray_paths.dart';
import 'xray_process.dart';
import 'xray_stats.dart';

/// Реализация движка для Windows: запускает xray.exe / sing-box.exe и включает
/// захват трафика (системный прокси или TUN).
///
/// Платформо-независимая половина — сессия, поколения, автовосстановление,
/// выбор конфига и ядра — живёт в [VpnEngineBase].
class WindowsEngine extends VpnEngineBase {
  XrayProcess? _process;

  /// Второе прокси-ядро: sing-box для протоколов, которых нет в Xray (hysteria2).
  /// Одновременно с [_process] не работает — какое ядро поднимать, решает
  /// [VpnServer.core]. TUN-инстанс sing-box считается отдельно (`_tunRouter`).
  SingboxProcess? _singbox;
  Timer? _statsTimer;
  StreamSubscription<int>? _exitWatch;
  final TunRouter _tunRouter = SingboxRouterWindows();
  bool _tunActive = false;
  bool _proxySet = false; // чистим системный прокси только если ставили его сами

  /// Идёт ли сейчас опрос счётчиков (Timer.periodic async-колбэки не сериализует).
  bool _polling = false;

  XrayTrafficSnapshot _lastSnapshot = XrayTrafficSnapshot.zero;
  DateTime _lastSampleTime = DateTime.now();

  WindowsEngine({super.ports}) {
    // Восстановление после аварийного выхода прошлого запуска.
    SystemProxy.recoverIfDirty();
  }

  /// Один запуск текущей сессии (первичный или повторный при восстановлении).
  @override
  Future<void> startSession() async {
    final session = this.session;
    if (session == null) return;
    final configJson = session.configJson;
    final options = session.options;
    final servers = session.servers;

    // Метка этого запуска: пока мы ждём (подъём ядра, автоподбор TUN — до минут),
    // пользователь мог нажать «Отключить». Тогда поколение сменится, и всё, что
    // мы успели поднять после этого, нужно немедленно погасить, иначе туннель
    // остаётся жить при выключенном на вид VPN.
    final gen = newGeneration();
    bool aborted() => isStale(gen);

    // message: null затирал бы уже выставленное базой «Пробую другой сервер: …»
    // — она ставит его прямо перед этим вызовом, и подпись жила меньше секунды.
    setStatus(
      VpnConnectionState.connecting,
      message: attempt > 0
          ? 'Переподключение (попытка $attempt)…'
          : (status.state == VpnConnectionState.connecting
              ? status.message
              : null),
    );

    final singboxCore = session.core == ProxyCore.singbox;
    final location = XrayPaths.locate();
    final singboxExe = singboxCore ? SingboxProcess.locate() : null;
    if (singboxCore && singboxExe == null) {
      // _cleanup обязателен: при kill switch захват трафика мог остаться с
      // прошлой попытки, и без него интернет остался бы заблокированным.
      await cleanup();
      setStatus(
        VpnConnectionState.error,
        message: 'Для Hysteria2 нужен sing-box.exe рядом с xray.exe.\n'
            'Запустите tools/fetch-singbox.ps1',
      );
      return;
    }
    if (!singboxCore && location == null) {
      await cleanup();
      setStatus(
        VpnConnectionState.error,
        message: 'Не найден xray.exe. Запустите tools/fetch-xray.ps1',
      );
      return;
    }

    // Порты проверяем ДО запуска: если их занял другой VPN-клиент, ядро просто
    // упадёт, и раньше пользователь видел бесполезное «Ядро завершилось при запуске».
    final conflict =
        await PortCheck.describeConflict([ports.socks, ports.http, ports.api]);
    if (conflict != null) {
      AppLog.e('Конфликт портов: ${conflict.split("\n").first}');
      await cleanup();
      setStatus(VpnConnectionState.error, message: conflict);
      return;
    }
    if (aborted()) return;

    try {
      final configPath =
          await _writeConfigJson(configJson, singbox: singboxCore);

      // Одно из двух ядер: Xray или (для hysteria2) sing-box.
      String Function() tailOf;
      bool Function() alive;
      Future<int>? exited;
      if (singboxCore) {
        final process = SingboxProcess();
        // Пишем вывод в файл: у прокси-ядра (hysteria2) диагностики не было
        // вообще — «конфиг валиден, процесс жив, трафика нет» не оставляло
        // ни байта, по которому можно понять причину.
        await process.start(
          executable: singboxExe!,
          configPath: configPath,
          logPath: SingboxProcess.logPathFor(await AppPaths.supportDir()),
        );
        _singbox = process;
        tailOf = () => process.tail;
        alive = () => process.isRunning;
        exited = process.exitCode;
      } else {
        final process = XrayProcess();
        await process.start(
          executable: location!.executable,
          configPath: configPath,
          assetDir: location.assetDir,
        );
        _process = process;
        tailOf = () => process.tail;
        alive = () => process.isRunning;
        exited = process.exitCode;
      }

      // Следим за неожиданным падением ядра.
      _exitWatch = exited?.asStream().listen((code) {
        if (status.isConnected || status.state == VpnConnectionState.connecting) {
          onCoreDied(code);
        }
      });

      // Небольшая пауза на инициализацию ядра.
      await Future.delayed(const Duration(milliseconds: 500));
      if (!alive()) {
        // Показываем реальную причину из вывода ядра, а не голое «завершилось».
        final tail = tailOf().trim();
        AppLog.e('Ядро не стартовало. Вывод:\n$tail');
        throw StateError(tail.isEmpty
            ? 'Ядро завершилось при запуске (вывод пуст)'
            : 'Ядро завершилось при запуске:\n$tail');
      }

      if (aborted()) {
        await _stopCoreProcesses();
        return;
      }

      if (options.captureMode == CaptureMode.tun) {
        // Туннель мог остаться поднятым с прошлой попытки (kill switch не гасит
        // захват между попытками). Перезапускаем его: иначе элевейтнутый хелпер
        // продолжит работать по СТАРОМУ конфигу — со старым IP сервера в
        // правиле «мимо туннеля», то есть с риском петли и мёртвой сети.
        if (_tunActive) {
          await _tunRouter.stop();
          _tunActive = false;
          await Future.delayed(const Duration(milliseconds: 600));
        }
        // TUN: sing-box поднимает туннель и заворачивает прокси-трафик в SOCKS Xray.
        // start() бросит TunStartException, если туннель реально не поднялся.
        _tunActive = true; // чтобы _cleanup погасил недоподнятый туннель
        await _tunRouter.start(
          options.split,
          xraySocksPort: ports.socks,
          options: TunOptions.fromSettings(
            options.settings,
            blockPagePort: await startBlockPage(options),
            serverIps: await resolveServerIps(servers),
            // Снимаем ДО подъёма туннеля: после него системный резолвер уже
            // указывает на сам туннель, и «Прямо» резолвилось бы через VPN.
            directDnsUpstream: await _systemDnsServer(),
          ),
          // Автоподбор стека/MTU может занять время — показываем, что происходит
          // (#8: отдельная фаза → прогресс-тост, не только строка статуса).
          onProgress: (m) => setStatus(VpnConnectionState.connecting,
              message: m, phase: VpnPhase.tunAutotune),
          // #5 — прекратить перебор, если пользователь отключился за время подбора.
          abort: aborted,
        );
        // Подбор стека/MTU идёт до двух минут — за это время пользователь мог
        // отключиться. Туннель, поднятый уже «после отмены», гасим сразу.
        if (aborted()) {
          await _tunRouter.stop();
          _tunActive = false;
          await _stopCoreProcesses();
          return;
        }
      } else {
        await SystemProxy.set('127.0.0.1:${ports.http}');
        _proxySet = true;
      }

      // #4 — пользователь мог нажать «Отключить», пока поднимались ядро и
      // прокси/туннель. Без этой проверки в режиме системного прокси прокси
      // оставался прописанным, а статус вставал в «Подключено» уже ПОСЛЕ отмены.
      if (aborted()) {
        await cleanup();
        return;
      }

      _lastSnapshot = XrayTrafficSnapshot.zero;
      _lastSampleTime = DateTime.now();
      _startStatsPolling(
          singboxCore ? null : location!.executable, singbox: singboxCore);

      // Читаем ДО markConnected(): он и обнуляет счётчик попыток.
      if (attempt > 0) AppLog.i('Соединение восстановлено (попытка $attempt)');
      markConnected(); // сбрасывает счётчик попыток и запускает grace смены сети
      setStatus(VpnConnectionState.connected);
    } on TunStartException catch (e) {
      // Честная причина из лога sing-box вместо ложного «Подключено».
      AppLog.e('TUN не поднялся: $e');
      // #6 — если пользователь сам отменил (aborted), НЕ затираем его
      // «Отключено» статусом «Ошибка». Проверяем ДО _cleanup (он ++_generation).
      final wasAborted = aborted();
      await cleanup();
      if (!wasAborted) {
        setStatus(VpnConnectionState.error, message: e.toString());
      }
    } catch (e) {
      AppLog.e('Подключение не удалось: $e');
      final wasAborted = aborted();
      // Сеть могла быть ещё не готова (например, сразу после пробуждения) —
      // это как раз случай для повторной попытки.
      if (!wasAborted &&
          await scheduleRetry('не удалось подключиться: $e')) {
        return;
      }
      await cleanup();
      if (!wasAborted) {
        setStatus(VpnConnectionState.error,
            message: 'Не удалось подключиться: $e');
      }
    }
  }

  /// Погасить ядро (и, если [keepCapture] == false, снять захват трафика).
  ///
  /// При включённом kill switch между попытками восстановления захват НЕ снимается:
  /// системный прокси остаётся прописанным на мёртвый порт, TUN продолжает держать
  /// маршрут — приложения получают ошибку соединения вместо утечки мимо VPN.
  @override
  Future<void> teardownCore({bool keepCapture = false}) async {
    _statsTimer?.cancel();
    _statsTimer = null;
    await _exitWatch?.cancel();
    _exitWatch = null;
    await _stopCoreProcesses();

    if (keepCapture) return;

    if (_tunActive) {
      await _tunRouter.stop();
      _tunActive = false;
    }
    // Не сбрасываем чужой прокси (например, корпоративный): чистим только свой.
    if (_proxySet) {
      await SystemProxy.clear();
      _proxySet = false;
    }
  }

  /// Платформенная часть полной остановки. Счётчик поколений и таймер повтора
  /// живут в базе — [VpnEngineBase.cleanup] увеличивает поколение ДО вызова
  /// этого метода, поэтому проверки «была ли отмена» делаются раньше.
  @override
  Future<void> platformCleanup() async {
    _polling = false;
    _statsTimer?.cancel();
    _statsTimer = null;
    await _exitWatch?.cancel();
    _exitWatch = null;
    if (_tunActive) {
      await _tunRouter.stop();
      _tunActive = false;
    }
    // Не сбрасываем чужой прокси (например, корпоративный): чистим только свой.
    if (_proxySet) {
      await SystemProxy.clear();
      _proxySet = false;
    }
    await _stopCoreProcesses();
  }

  /// Гасим оба прокси-ядра: какое из них живо, зависит от протокола сессии.
  Future<void> _stopCoreProcesses() async {
    await _process?.stop();
    _process?.dispose();
    _process = null;
    await _singbox?.stop();
    _singbox?.dispose();
    _singbox = null;
  }

  /// Счётчики трафика: у Xray — `api statsquery`, у sing-box — Clash API.
  void _startStatsPolling(String? executable, {bool singbox = false}) {
    final xrayStats = singbox
        ? null
        : XrayStats(executable: executable!, apiPort: ports.api);
    final singboxStats = singbox ? SingboxStats(apiPort: ports.api, secret: singboxApiSecret) : null;
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      // Timer.periodic не сериализует async-колбэки: опрос Xray идёт через
      // Process.run и на нагруженной машине легко перекрывает секунду, а два
      // такта разом дают неверную разницу по времени.
      if (_polling) return;
      _polling = true;
      try {
      final snap =
          await (singboxStats?.query() ?? xrayStats!.query());
      // Опрос не удался — такт ПРОПУСКАЕМ целиком. Раньше сюда приезжал ноль,
      // и он затирал базу: скорость на следующем удачном опросе взлетала до
      // «всего трафика за секунду», а счётчик сессии удваивался.
      if (snap == null) return;
      final now = DateTime.now();
      final dt = now.difference(_lastSampleTime).inMilliseconds / 1000.0;
      final upSpeed = dt > 0 ? ((snap.uplink - _lastSnapshot.uplink) / dt).round() : 0;
      final downSpeed =
          dt > 0 ? ((snap.downlink - _lastSnapshot.downlink) / dt).round() : 0;
      _lastSnapshot = snap;
      _lastSampleTime = now;

      emitStats(TrafficStats(
        uplinkBytes: snap.uplink,
        downlinkBytes: snap.downlink,
        uplinkSpeed: upSpeed < 0 ? 0 : upSpeed,
        downlinkSpeed: downSpeed < 0 ? 0 : downSpeed,
      ));
      } finally {
        _polling = false;
      }
    });
  }

  /// Конфиги ядер лежат рядом, но в разных файлах: TUN-инстанс sing-box пишет
  /// свой (`singbox_config.json`), поэтому прокси-конфиг — `singbox_proxy.json`.
  /// DNS-сервер физического адаптера — резолвер для доменов «Прямо».
  ///
  /// Нужен явным адресом: транспорт `local` в sing-box на Windows означает
  /// системный резолвер, а тот под поднятым TUN закольцовывается сам на себя,
  /// и домен «Прямо» не резолвится вовсе (подтверждено живым тестом).
  ///
  /// Берём ПЕРВЫЙ адрес не-туннельного адаптера. Свой туннель узнаём по
  /// собственным адресам (172.19.0.x / fdfe:dcba:9876::), а не по имени: имя
  /// адаптера на Windows приходит не то — на этом уже обжигались в 0.8.3.
  /// Не нашли — `null`, поведение остаётся прежним.
  Future<String?> _systemDnsServer() async {
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'(Get-DnsClientServerAddress -AddressFamily IPv4 |'
            r' Where-Object { $_.ServerAddresses.Count -gt 0 } |'
            r' Select-Object -ExpandProperty ServerAddresses) -join ","',
      ]).timeout(const Duration(seconds: 5));
      final list = (r.stdout as String)
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .where((e) => InternetAddress.tryParse(e) != null)
          // Отбрасываем адреса самого туннеля и заглушки.
          .where((e) => !e.startsWith('172.19.0.'))
          .where((e) => e != '0.0.0.0' && e != '127.0.0.1')
          .toList();
      if (list.isEmpty) {
        AppLog.w('DNS физического адаптера не найден — домены «Прямо» '
            'будут резолвиться системным резолвером');
        return null;
      }
      AppLog.i('Резолвер для «Прямо»: ${list.first}');
      return list.first;
    } catch (e) {
      AppLog.w('Не удалось определить DNS адаптера: $e');
      return null;
    }
  }

  Future<String> _writeConfigJson(String json, {bool singbox = false}) async {
    final dir = await AppPaths.supportDir();
    final name = singbox ? 'singbox_proxy.json' : 'xray_config.json';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsString(json);
    return file.path;
  }

}
