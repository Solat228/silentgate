import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../../core/platform/app_log.dart';
import '../../core/platform/app_paths.dart';
import '../../core/platform/port_check.dart';
import '../../core/models/traffic_stats.dart';
import '../../core/models/vpn_server.dart';
import '../../core/models/vpn_status.dart';
import '../../core/settings/app_settings.dart';
import '../../core/singbox/singbox_config_builder.dart';
import '../../core/singbox/singbox_proxy_config_builder.dart';
import '../../core/settings/split_tunnel.dart';
import '../../core/xray/override_normalizer.dart';
import '../../core/xray/panel_direct_reroute.dart';
import '../../core/xray/xray_config_builder.dart';
import '../vpn_engine.dart';
import 'singbox_process.dart';
import 'singbox_stats.dart';
import 'system_proxy.dart';
import 'tun/singbox_router_windows.dart';
import 'tun/tun_router.dart';
import 'xray_paths.dart';
import 'xray_process.dart';
import 'xray_stats.dart';

/// Реализация [VpnEngine] для Windows: запускает xray.exe и ставит системный прокси.
class WindowsEngine implements VpnEngine {
  final XrayPorts _ports;
  late final XrayConfigBuilder _configBuilder;

  final _statusController = StreamController<VpnStatus>.broadcast();
  final _statsController = StreamController<TrafficStats>.broadcast();

  VpnStatus _status = const VpnStatus.disconnected();
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

  // ── Автовосстановление ─────────────────────────────────────────────────────
  /// Задержки между попытками. Первая короткая: чаще всего достаточно перезапустить
  /// ядро, а при включённом kill switch трафик всё это время заблокирован — тянуть нельзя.
  static const _backoff = [
    Duration(milliseconds: 800),
    Duration(seconds: 3),
    Duration(seconds: 8),
    Duration(seconds: 20),
  ];
  static const _maxAttempts = 8;

  /// Столько после успешного подключения не реагируем на «смену сети»: подъём TUN
  /// сам перестраивает маршруты (страховка поверх паузы в NetworkWatcher).
  static const _networkGrace = Duration(seconds: 15);

  _Session? _session; // чем подключались — чтобы повторить
  bool _userStopped = false; // отключение по кнопке: не восстанавливаем

  /// Номер текущего запуска. Отключение/очистка его увеличивают, и запущенный
  /// ранее _startSession по возвращении из долгого await видит, что он устарел,
  /// и убирает за собой. Без этого TUN, поднятый уже ПОСЛЕ нажатия «Отключить»
  /// (автоподбор стека идёт до двух минут), оставался жить навсегда.
  int _generation = 0;
  int _attempt = 0;
  Timer? _retryTimer;
  DateTime? _connectedAt;

  /// Запасные серверы для режима «Авто (лучший сервер)» — см. [fallbackServers].
  List<VpnServer> _fallbacks = [];

  @override
  set fallbackServers(List<VpnServer> servers) => _fallbacks = [...servers];

  XrayTrafficSnapshot _lastSnapshot = XrayTrafficSnapshot.zero;
  DateTime _lastSampleTime = DateTime.now();

  /// Пароль Clash API текущей sing-box-сессии: новый на каждое подключение,
  /// только в памяти. Без него статистику и управление прокси мог бы дёргать
  /// любой процесс и любая открытая веб-страница (sing-box отдаёт CORS `*`).
  String _singboxApiSecret = '';

  /// Конфиг sing-box-прокси строится на ТЕХ ЖЕ портах, что и Xray: остальной
  /// код (системный прокси, TUN, проверка занятости) не должен знать, кто внизу.
  String _buildSingboxJson(List<VpnServer> servers) {
    _singboxApiSecret = _newApiSecret();
    return SingboxProxyConfigBuilder(
      ports: SingboxProxyPorts(
          socks: _ports.socks, http: _ports.http, api: _ports.api),
      apiSecret: _singboxApiSecret,
    ).buildJson(servers);
  }

  static String _newApiSecret() {
    final rnd = Random.secure();
    return List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  WindowsEngine({XrayPorts ports = const XrayPorts()}) : _ports = ports {
    _configBuilder = XrayConfigBuilder(ports: _ports);
    // Восстановление после аварийного выхода прошлого запуска.
    SystemProxy.recoverIfDirty();
  }

  @override
  Stream<VpnStatus> get statusStream => _statusController.stream;

  @override
  Stream<TrafficStats> get statsStream => _statsController.stream;

  @override
  VpnStatus get status => _status;

  @override
  int get httpProxyPort => _ports.http;

  void _setStatus(VpnConnectionState state,
      {String? message, VpnPhase phase = VpnPhase.normal}) {
    _status = VpnStatus(state, message: message, phase: phase);
    if (!_statusController.isClosed) _statusController.add(_status);
  }

  /// Конфиг и ядро для одного сервера — **единственный** источник истины.
  ///
  /// Приоритет источников:
  ///  1) правка пользователя (JSON-редактор);
  ///  2) полный профиль от панели («Авто …»: balancer + burstObservatory + десятки
  ///     серверов) — применяется ЦЕЛИКОМ, иначе теряется весь автовыбор;
  ///  3) сборка из полей / авторитетного outbound соответствующим ядром.
  /// Порты inbound'ов подгоняются под захват (системный прокси → http, TUN → socks),
  /// недостающие дописываются: у профилей панели есть только socks-inbound.
  ///
  /// Используется и при переходе на запасной сервер: раньше там конфиг собирался
  /// заново из полей, и профиль панели терял свой balancer, а JSON-правка — смысл.
  ({String json, ProxyCore core}) _configFor(
      VpnServer server, ConnectionOptions options) {
    final full = (server.rawJsonOverride ?? '').isNotEmpty
        ? server.rawJsonOverride!
        : (server.rawPanelConfig ?? '');

    if (full.isNotEmpty) {
      // JSON панели/редактора — это ВСЕГДА конфиг Xray. Подсунуть его hysteria2-
      // серверу нельзя: Xray такого протокола не знает и просто не стартует.
      if (server.core == ProxyCore.singbox) {
        AppLog.w('У ${server.displayName} есть Xray-JSON, но это hysteria2 — '
            'правка игнорируется, поднимаю sing-box');
      } else {
        var json = full;
        // Утечка реального IP: панельный профиль сам рулит часть трафика direct
        // (RU-routing). Если пользователь хочет «Всё через VPN» ИЛИ включил «не
        // выходить под реальным IP» — переписываем внутренний direct → через VPN.
        final s = options.settings;
        if (s.splitTunnel.mode == SplitMode.all || s.noRealIp) {
          json = rerouteDirectThroughVpn(json);
        }
        final norm = normalizeOverridePorts(json,
            socksPort: _ports.socks, httpPort: _ports.http);
        // #5 — у панельного профиля обычно нет StatsService, поэтому трафик
        // показывался как 0. Дописываем api/stats, если их нет.
        final withStats = ensureXrayStats(norm.json, apiPort: _ports.api);
        return (json: withStats, core: ProxyCore.xray);
      }
    }
    if (server.core == ProxyCore.singbox) {
      // hysteria2 — Xray такого не умеет, поднимаем sing-box.
      return (json: _buildSingboxJson([server]), core: ProxyCore.singbox);
    }
    return (
      json: _configBuilder.buildJson(server, variant: options.variant),
      core: ProxyCore.xray,
    );
  }

  @override
  Future<void> connect(VpnServer server,
      {ConnectionOptions options = const ConnectionOptions()}) async {
    final cfg = _configFor(server, options);
    await _connectWith(cfg.json, options, [server], core: cfg.core);
  }

  @override
  Future<void> connectBalancer(List<VpnServer> servers,
      {ConnectionOptions options = const ConnectionOptions()}) async {
    if (servers.isEmpty) return;
    // Одно ядро на сессию: смешать hysteria2 и VLESS в одном балансировщике
    // нельзя. Xray-серверы идут в его balancer, иначе — urltest в sing-box.
    final xrayOnes =
        servers.where((s) => s.core == ProxyCore.xray).toList(growable: false);
    if (xrayOnes.isNotEmpty) {
      await _connectWith(
          _configBuilder.buildBalancerJson(xrayOnes), options, xrayOnes);
      return;
    }
    await _connectWith(_buildSingboxJson(servers), options, servers,
        core: ProxyCore.singbox);
  }

  /// IP-адреса серверов — чтобы увести их мимо TUN. Резолвим ДО поднятия туннеля
  /// (обычным DNS): без этого исключения трафик самого Xray к серверу вернулся бы
  /// в Xray — петля, и сеть умирает целиком.
  Future<List<String>> _resolveServerIps(List<VpnServer> servers) async {
    final ips = <String>{};
    for (final s in servers) {
      final host = s.address.trim();
      if (host.isEmpty) continue;
      final parsed = InternetAddress.tryParse(host);
      if (parsed != null) {
        ips.add(parsed.address);
        continue;
      }
      try {
        final found = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 5));
        ips.addAll(found.map((a) => a.address));
      } catch (_) {
        // Не отвалились: остаются process-правило и приватные адреса.
      }
    }
    return ips.toList();
  }

  Future<void> _connectWith(String configJson, ConnectionOptions options,
      List<VpnServer> servers,
      {ProxyCore core = ProxyCore.xray}) async {
    if (_status.isConnected || _status.state == VpnConnectionState.connecting) {
      return;
    }
    // Запоминаем сессию — по ней восстанавливаемся при обрыве и смене сети.
    _session = _Session(configJson, options, servers, core);
    _userStopped = false;
    _attempt = 0;
    await _startSession();
  }

  /// Один запуск текущей сессии (первичный или повторный при восстановлении).
  Future<void> _startSession() async {
    final session = _session;
    if (session == null) return;
    final configJson = session.configJson;
    final options = session.options;
    final servers = session.servers;

    // Метка этого запуска: пока мы ждём (подъём ядра, автоподбор TUN — до минут),
    // пользователь мог нажать «Отключить». Тогда поколение сменится, и всё, что
    // мы успели поднять после этого, нужно немедленно погасить, иначе туннель
    // остаётся жить при выключенном на вид VPN.
    final gen = ++_generation;
    bool aborted() => gen != _generation;

    _setStatus(VpnConnectionState.connecting,
        message: _attempt > 0 ? 'Переподключение (попытка $_attempt)…' : null);

    final singboxCore = session.core == ProxyCore.singbox;
    final location = XrayPaths.locate();
    final singboxExe = singboxCore ? SingboxProcess.locate() : null;
    if (singboxCore && singboxExe == null) {
      // _cleanup обязателен: при kill switch захват трафика мог остаться с
      // прошлой попытки, и без него интернет остался бы заблокированным.
      await _cleanup();
      _setStatus(
        VpnConnectionState.error,
        message: 'Для Hysteria2 нужен sing-box.exe рядом с xray.exe.\n'
            'Запустите tools/fetch-singbox.ps1',
      );
      return;
    }
    if (!singboxCore && location == null) {
      await _cleanup();
      _setStatus(
        VpnConnectionState.error,
        message: 'Не найден xray.exe. Запустите tools/fetch-xray.ps1',
      );
      return;
    }

    // Порты проверяем ДО запуска: если их занял другой VPN-клиент, ядро просто
    // упадёт, и раньше пользователь видел бесполезное «Ядро завершилось при запуске».
    final conflict =
        await PortCheck.describeConflict([_ports.socks, _ports.http, _ports.api]);
    if (conflict != null) {
      AppLog.e('Конфликт портов: ${conflict.split("\n").first}');
      await _cleanup();
      _setStatus(VpnConnectionState.error, message: conflict);
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
        await process.start(executable: singboxExe!, configPath: configPath);
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
        if (_status.isConnected || _status.state == VpnConnectionState.connecting) {
          _onCoreDied(code);
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
          xraySocksPort: _ports.socks,
          options: TunOptions.fromSettings(
            options.settings,
            serverIps: await _resolveServerIps(servers),
          ),
          // Автоподбор стека/MTU может занять время — показываем, что происходит
          // (#8: отдельная фаза → прогресс-тост, не только строка статуса).
          onProgress: (m) => _setStatus(VpnConnectionState.connecting,
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
        await SystemProxy.set('127.0.0.1:${_ports.http}');
        _proxySet = true;
      }

      // #4 — пользователь мог нажать «Отключить», пока поднимались ядро и
      // прокси/туннель. Без этой проверки в режиме системного прокси прокси
      // оставался прописанным, а статус вставал в «Подключено» уже ПОСЛЕ отмены.
      if (aborted()) {
        await _cleanup();
        return;
      }

      _lastSnapshot = XrayTrafficSnapshot.zero;
      _lastSampleTime = DateTime.now();
      _startStatsPolling(
          singboxCore ? null : location!.executable, singbox: singboxCore);

      if (_attempt > 0) AppLog.i('Соединение восстановлено (попытка $_attempt)');
      _attempt = 0; // следующий обрыв начнёт отсчёт заново
      _connectedAt = DateTime.now();
      _setStatus(VpnConnectionState.connected);
    } on TunStartException catch (e) {
      // Честная причина из лога sing-box вместо ложного «Подключено».
      AppLog.e('TUN не поднялся: $e');
      // #6 — если пользователь сам отменил (aborted), НЕ затираем его
      // «Отключено» статусом «Ошибка». Проверяем ДО _cleanup (он ++_generation).
      final wasAborted = aborted();
      await _cleanup();
      if (!wasAborted) {
        _setStatus(VpnConnectionState.error, message: e.toString());
      }
    } catch (e) {
      AppLog.e('Подключение не удалось: $e');
      final wasAborted = aborted();
      // Сеть могла быть ещё не готова (например, сразу после пробуждения) —
      // это как раз случай для повторной попытки.
      if (!wasAborted &&
          await _scheduleRetry('не удалось подключиться: $e')) {
        return;
      }
      await _cleanup();
      if (!wasAborted) {
        _setStatus(VpnConnectionState.error,
            message: 'Не удалось подключиться: $e');
      }
    }
  }

  // ── Автовосстановление ─────────────────────────────────────────────────────
  /// Запланировать повторную попытку, если включено автопереподключение и
  /// пользователь не отключался сам. Возвращает true, если попытка запланирована.
  Future<bool> _scheduleRetry(String reason) async {
    final session = _session;
    if (session == null || _userStopped) return false;
    if (!session.options.settings.autoReconnect) return false;
    if (_attempt >= _maxAttempts) {
      AppLog.e('Автопереподключение: исчерпаны попытки ($_maxAttempts)');
      return false;
    }

    // Попытки на текущем сервере исчерпаны — пробуем следующий (только в режиме
    // «Авто (лучший сервер)»: там пользователь и просил «выбери рабочий»).
    if (_attempt >= _maxAttempts - 1 && _fallbacks.isNotEmpty) {
      final next = _fallbacks.removeAt(0);
      AppLog.w('Переключаюсь на запасной сервер: ${next.displayName}');
      await _teardownCore(keepCapture: session.options.settings.killSwitch);
      _attempt = 0;
      // Через тот же _configFor: у запасного сервера может быть свой профиль
      // панели или JSON-правка, и собирать его «из полей» — значит их потерять.
      final cfg = _configFor(next, session.options);
      _session = _Session(cfg.json, session.options, [next], cfg.core);
      _setStatus(VpnConnectionState.connecting,
          message: 'Пробую другой сервер: ${next.displayName}…');
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 1), () async {
        if (!_userStopped) await _startSession();
      });
      return true;
    }

    _attempt++;
    final delay = _backoff[_attempt.clamp(1, _backoff.length) - 1];
    AppLog.w('Автопереподключение: $reason → попытка $_attempt через '
        '${delay.inSeconds} с');

    // Kill switch: НЕ снимаем захват трафика между попытками — иначе на время
    // паузы трафик пошёл бы напрямую, мимо VPN.
    await _teardownCore(keepCapture: session.options.settings.killSwitch);

    _setStatus(VpnConnectionState.connecting,
        message: 'Переподключение через ${delay.inSeconds} с '
            '(попытка $_attempt из $_maxAttempts)…');

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () async {
      if (_userStopped) return;
      await _startSession();
    });
    return true;
  }

  /// Внешний сигнал: сетевое окружение изменилось (Wi-Fi ↔ кабель, сон, новый IP).
  /// Туннель поверх старого адаптера уже мёртв, даже если процессы живы.
  @override
  Future<void> onNetworkChanged() async {
    if (_session == null || _userStopped) return;
    if (!_status.isConnected) return;
    if (!_session!.options.settings.autoReconnect) return;
    // Страховка от цикла: сразу после подключения «смена сети» — это почти всегда
    // наш же туннель, а не реальное изменение.
    final since = _connectedAt;
    if (since != null && DateTime.now().difference(since) < _networkGrace) {
      AppLog.i('Смена сети проигнорирована: прошло меньше '
          '${_networkGrace.inSeconds} с после подключения');
      return;
    }
    AppLog.w('Смена сети — восстанавливаю подключение');
    _attempt = 0;
    await _scheduleRetry('сменилось сетевое окружение');
  }

  @override
  Future<void> disconnect() async {
    // Явное отключение всегда отменяет автовосстановление, даже если оно уже идёт.
    _userStopped = true;
    _generation++; // всё, что поднимется после этого момента, будет погашено
    _session = null;
    _attempt = 0;
    _fallbacks = [];
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_status.state == VpnConnectionState.disconnected) {
      // Kill switch мог оставить захват при неудачном восстановлении — снимаем.
      await _cleanup();
      return;
    }
    _setStatus(VpnConnectionState.disconnecting);
    await _cleanup();
    _setStatus(VpnConnectionState.disconnected);
    _statsController.add(TrafficStats.zero);
  }

  Future<void> _onCoreDied(int code) async {
    // Имя ядра важно: по нему пользователь понимает, куда смотреть —
    // в xray_config.json или в singbox_proxy.json.
    final name = _session?.core == ProxyCore.singbox ? 'sing-box' : 'Xray';
    AppLog.e('Ядро $name остановилось (код $code)');
    if (await _scheduleRetry('ядро $name остановилось (код $code)')) return;
    await _cleanup();
    _setStatus(VpnConnectionState.error,
        message: 'Ядро $name остановилось (код $code)');
  }

  /// Погасить ядро (и, если [keepCapture] == false, снять захват трафика).
  ///
  /// При включённом kill switch между попытками восстановления захват НЕ снимается:
  /// системный прокси остаётся прописанным на мёртвый порт, TUN продолжает держать
  /// маршрут — приложения получают ошибку соединения вместо утечки мимо VPN.
  Future<void> _teardownCore({bool keepCapture = false}) async {
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

  Future<void> _cleanup() async {
    _generation++; // запущенный сейчас _startSession считается устаревшим
    _retryTimer?.cancel();
    _retryTimer = null;
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
        : XrayStats(executable: executable!, apiPort: _ports.api);
    final singboxStats = singbox ? SingboxStats(apiPort: _ports.api, secret: _singboxApiSecret) : null;
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final snap =
          await (singboxStats?.query() ?? xrayStats!.query());
      final now = DateTime.now();
      final dt = now.difference(_lastSampleTime).inMilliseconds / 1000.0;
      final upSpeed = dt > 0 ? ((snap.uplink - _lastSnapshot.uplink) / dt).round() : 0;
      final downSpeed =
          dt > 0 ? ((snap.downlink - _lastSnapshot.downlink) / dt).round() : 0;
      _lastSnapshot = snap;
      _lastSampleTime = now;

      if (!_statsController.isClosed) {
        _statsController.add(TrafficStats(
          uplinkBytes: snap.uplink,
          downlinkBytes: snap.downlink,
          uplinkSpeed: upSpeed < 0 ? 0 : upSpeed,
          downlinkSpeed: downSpeed < 0 ? 0 : downSpeed,
        ));
      }
    });
  }

  /// Конфиги ядер лежат рядом, но в разных файлах: TUN-инстанс sing-box пишет
  /// свой (`singbox_config.json`), поэтому прокси-конфиг — `singbox_proxy.json`.
  Future<String> _writeConfigJson(String json, {bool singbox = false}) async {
    final dir = await AppPaths.supportDir();
    final name = singbox ? 'singbox_proxy.json' : 'xray_config.json';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsString(json);
    return file.path;
  }

  @override
  Future<void> dispose() async {
    await _cleanup();
    await _statusController.close();
    await _statsController.close();
  }
}

/// Параметры текущей сессии подключения — чтобы повторить её при восстановлении.
class _Session {
  final String configJson;
  final ConnectionOptions options;
  final List<VpnServer> servers;

  /// Каким ядром поднята сессия — от этого зависит и перезапуск, и статистика.
  final ProxyCore core;
  const _Session(this.configJson, this.options, this.servers, this.core);
}
