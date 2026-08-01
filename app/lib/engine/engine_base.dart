import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/app_info.dart';
import '../core/i18n/localizations_loader.dart';
import '../core/models/traffic_stats.dart';
import '../core/net/block_page_server.dart';
import '../core/models/vpn_server.dart';
import '../core/models/vpn_status.dart';
import '../core/platform/app_log.dart';
import '../core/settings/split_tunnel.dart';
import '../core/singbox/singbox_proxy_config_builder.dart';
import '../core/xray/override_normalizer.dart';
import '../core/xray/panel_direct_reroute.dart';
import '../core/xray/xray_config_builder.dart';
import 'vpn_engine.dart';

/// Снимок «чем подключались»: готовый конфиг, настройки, серверы и ядро.
///
/// Хранится именно СОБРАННЫЙ json: повторная попытка не должна пересобирать
/// конфиг (иначе теряются профиль панели и правка пользователя). Переход на
/// запасной сервер — наоборот, собирает конфиг заново через `configFor`.
class EngineSession {
  final String configJson;
  final ConnectionOptions options;
  final List<VpnServer> servers;
  final ProxyCore core;
  const EngineSession(this.configJson, this.options, this.servers, this.core);
}

/// Платформо-независимая часть движка: жизненный цикл сессии, автовосстановление,
/// счётчик поколений, выбор конфига и ядра, потоки статуса и статистики.
///
/// Здесь нет ни одного обращения к ОС — всё, что зависит от платформы (подъём
/// ядра, захват трафика, статистика, уборка), объявлено абстрактным и живёт в
/// наследниках: `engine/windows/windows_engine.dart` и, начиная с фазы 3,
/// `engine/android/android_engine.dart`.
///
/// Вынесено сюда ~60 % прежнего `WindowsEngine` — вместе с граблями, которые
/// стоили живых тестов: гварды поколений, снятие `wasAborted` ДО очистки,
/// удержание захвата при kill switch, grace-период на смену сети.
abstract class VpnEngineBase implements VpnEngine {
  VpnEngineBase({XrayPorts ports = const XrayPorts()}) : ports = ports {
    configBuilder = XrayConfigBuilder(ports: ports);
  }

  /// Порты локальных inbound'ов. Общие для ОБОИХ ядер: верхние слои (захват
  /// трафика, проверка занятости, сервис-чипы) не должны знать, кто внизу.
  final XrayPorts ports;
  late final XrayConfigBuilder configBuilder;

  final _statusController = StreamController<VpnStatus>.broadcast();
  final _statsController = StreamController<TrafficStats>.broadcast();

  VpnStatus _status = const VpnStatus.disconnected();

  // ── Автовосстановление ─────────────────────────────────────────────────────
  /// Задержки между попытками. Первая короткая: чаще всего достаточно перезапустить
  /// ядро, а при включённом kill switch трафик всё это время заблокирован — тянуть нельзя.
  static const backoff = [
    Duration(milliseconds: 800),
    Duration(seconds: 3),
    Duration(seconds: 8),
    Duration(seconds: 20),
  ];
  static const maxAttempts = 8;

  /// Столько после успешного подключения не реагируем на «смену сети»: подъём TUN
  /// сам перестраивает маршруты (страховка поверх паузы в NetworkWatcher).
  static const networkGrace = Duration(seconds: 15);

  EngineSession? _session; // чем подключались — чтобы повторить
  bool _userStopped = false; // отключение по кнопке: не восстанавливаем

  /// Номер текущего запуска. Отключение/очистка его увеличивают, и запущенный
  /// ранее `startSession` по возвращении из долгого await видит, что он устарел,
  /// и убирает за собой. Без этого туннель, поднятый уже ПОСЛЕ нажатия
  /// «Отключить» (автоподбор стека идёт до двух минут), оставался жить навсегда.
  int _generation = 0;
  int _attempt = 0;

  /// С какого момента kill switch держит трафик. `null` — не держит.
  ///
  /// Нужен ради ОДНОЙ строки в отчёте поддержки: «держал 6 ч 12 мин». Разбирать
  /// жалобы «интернет пропал сам по себе» иначе нечем — в логе видны попытки
  /// переподключения, но не видно, что всё это время трафик был заблокирован
  /// намеренно, и сколько это длилось.
  DateTime? _blockingSince;
  Timer? _retryTimer;
  DateTime? _connectedAt;

  /// Запасные серверы для режима «Авто (лучший сервер)» — см. [fallbackServers].
  List<VpnServer> _fallbacks = [];

  /// Пароль Clash API текущей sing-box-сессии: новый на каждое подключение,
  /// только в памяти. Без него статистику и управление прокси мог бы дёргать
  /// любой процесс и любая открытая веб-страница (sing-box отдаёт CORS `*`).
  String singboxApiSecret = '';

  // ── Контракт для наследников ───────────────────────────────────────────────

  /// Поднять текущую сессию: ядро + захват трафика. Реализация обязана
  /// сверяться с [isStale] после каждого долгого await и гасить поднятое,
  /// если поколение сменилось.
  Future<void> startSession();

  /// Погасить ядро. При [keepCapture] == true захват трафика НЕ снимается:
  /// это kill switch между попытками — приложения получают ошибку соединения
  /// вместо утечки мимо VPN.
  Future<void> teardownCore({bool keepCapture = false});

  /// Полная остановка: ядро, захват, таймеры. Поколение инкрементирует [cleanup].
  Future<void> platformCleanup();

  // ── Состояние и потоки ─────────────────────────────────────────────────────

  @override
  Stream<VpnStatus> get statusStream => _statusController.stream;

  @override
  Stream<TrafficStats> get statsStream => _statsController.stream;

  @override
  VpnStatus get status => _status;

  @override
  int get httpProxyPort => ports.http;

  @override
  set fallbackServers(List<VpnServer> servers) => _fallbacks = [...servers];

  /// Имена ВСЕЙ нашей инфраструктуры: серверы подписки и её собственный хост.
  ///
  /// ⚠️ Нужен именно ПОЛНЫЙ список, а не выбранный сервер. Резолв идёт через
  /// туннель, и пока туннель поднимается, любое обращение к имени другого
  /// сервера (пинг списка, автообновление подписки, панельный профиль с
  /// десятками узлов) уходит в круг: адрес спрашивается у сервера, к которому
  /// ещё нет соединения. В логе владельца это было десятками строк
  /// «dns: exchange failed for …silentgate.lol», а снаружи — «ничего не
  /// работает».
  List<String> _knownDomains = const [];

  set knownServerDomains(List<String> domains) {
    // Только имена: адреса и так уводятся мимо туннеля отдельным правилом,
    // а `domain_suffix` с IP ядро молча не сматчит.
    final out = <String>{};
    for (final d in domains) {
      final host = d.trim().toLowerCase();
      if (host.isEmpty) continue;
      if (InternetAddress.tryParse(host) != null) continue;
      out.add(host);
    }
    _knownDomains = out.toList();
  }

  List<String> get knownServerDomains => _knownDomains;

  /// Текущая сессия (нужна наследникам для подъёма).
  EngineSession? get session => _session;

  /// Пользователь нажал «Отключить» — восстанавливать не нужно.
  bool get userStopped => _userStopped;

  void setStatus(VpnConnectionState state,
      {String? message, VpnPhase phase = VpnPhase.normal, bool blocking = false}) {
    _status = VpnStatus(state, message: message, phase: phase, blocking: blocking);
    if (!_statusController.isClosed) _statusController.add(_status);
  }

  void emitStats(TrafficStats stats) {
    if (!_statsController.isClosed) _statsController.add(stats);
  }

  /// Отменить отложенную попытку переподключения.
  ///
  /// Нужен тестам: они проверяют РЕШЕНИЕ «повторять или сдаться», а живой таймер
  /// держал бы прогон открытым. В рабочем коде отмена идёт через cleanup.
  @visibleForTesting
  void cancelRetryTimer() => _retryTimer?.cancel();

  /// Отметить успешное подключение (запускает отсчёт grace-периода смены сети).
  void markConnected() {
    _connectedAt = DateTime.now();
    _attempt = 0;
    final since = _blockingSince;
    if (since != null) {
      final held = DateTime.now().difference(since);
      AppLog.i('Kill switch: трафик разблокирован, держал '
          '${_humanDuration(held)} — соединение восстановлено');
      _blockingSince = null;
    }
  }

  /// «6 ч 12 мин» / «45 с» — для строки в отчёте поддержки.
  static String _humanDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours} ч ${d.inMinutes % 60} мин';
    if (d.inMinutes > 0) return '${d.inMinutes} мин ${d.inSeconds % 60} с';
    return '${d.inSeconds} с';
  }

  // ── Поколения ──────────────────────────────────────────────────────────────

  /// Начать новое поколение и получить его номер.
  int newGeneration() => ++_generation;

  /// Устарел ли запуск с номером [gen] (пользователь отключился или пошёл ретрай).
  bool isStale(int gen) => gen != _generation;

  // ── Конфиг ─────────────────────────────────────────────────────────────────

  /// Конфиг sing-box-прокси строится на ТЕХ ЖЕ портах, что и Xray: остальной
  /// код (захват трафика, проверка занятости) не должен знать, кто внизу.
  String buildSingboxJson(List<VpnServer> servers,
      {Map<String, String> resolvedIps = const {}}) {
    singboxApiSecret = _newApiSecret();
    return SingboxProxyConfigBuilder(
      ports: SingboxProxyPorts(
          socks: ports.socks, http: ports.http, api: ports.api),
      apiSecret: singboxApiSecret,
    ).buildJson(servers, resolvedIps: resolvedIps);
  }

  /// Последний УСПЕШНЫЙ резолв: хост → адреса.
  ///
  /// Нужен, потому что резолв может не удаться ровно тогда, когда он важнее
  /// всего — при переподключении с уже поднятым туннелем. Пустой результат
  /// вернул бы в конфиг доменное имя, то есть ровно ту ситуацию, от которой
  /// подстановка IP и защищает.
  final Map<String, List<String>> _resolveCache = {};

  /// Резолв адресов серверов: хост → список адресов.
  ///
  /// Отдельно от [resolveServerIps], потому что нужны ДВА разных результата:
  /// плоский список всех адресов (для правила `ip_cidr` «мимо туннеля») и
  /// соответствие «домен → адрес» (для подстановки в outbound).
  Future<Map<String, List<String>>> resolveServerHosts(
      List<VpnServer> servers) async {
    final out = <String, List<String>>{};
    for (final s in servers) {
      final host = s.address.trim();
      if (host.isEmpty || out.containsKey(host)) continue;
      final parsed = InternetAddress.tryParse(host);
      if (parsed != null) {
        out[host] = [parsed.address];
        continue;
      }
      try {
        final found = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 5));
        final ips = found.map((a) => a.address).toList();
        if (ips.isNotEmpty) {
          out[host] = ips;
          _resolveCache[host] = ips;
        }
      } catch (e) {
        // Молчать здесь было нельзя: провал резолва стоит защиты от петли, а в
        // логе не оставалось ни строчки — причину «интернет пропал» искали
        // вслепую.
        final cached = _resolveCache[host];
        if (cached != null) {
          out[host] = cached;
          AppLog.w('Не удалось отрезолвить $host ($e), беру прошлый адрес');
        } else {
          AppLog.w('Не удалось отрезолвить $host: $e');
        }
      }
    }
    return out;
  }

  /// Один адрес на хост — для подстановки в поле `server` outbound'а.
  ///
  /// Выбор детерминирован: сначала IPv4 (стратегия по умолчанию `prefer_ipv4`),
  /// иначе первый доступный. Случайный выбор здесь дал бы неповторимые баги.
  static Map<String, String> pickOneIpPerHost(Map<String, List<String>> hosts) {
    final out = <String, String>{};
    hosts.forEach((host, ips) {
      if (ips.isEmpty) return;
      final v4 = ips.firstWhere((ip) => !ip.contains(':'), orElse: () => '');
      out[host] = v4.isNotEmpty ? v4 : ips.first;
    });
    return out;
  }

  static String _newApiSecret() {
    final rnd = Random.secure();
    return List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join();
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
  /// [resolvedIps] — карта «хост сервера → адрес», полученная ДО подъёма TUN.
  /// Пустая карта = прежнее поведение бит-в-бит (в конфиг едет доменное имя).
  /// [full] — конфиг взят ЦЕЛИКОМ (панельный профиль «Авто» или правка
  /// пользователя), а не собран из полей сервера. Наследникам это важно знать:
  /// такой конфиг обязан примениться как есть, иначе теряются балансировщик,
  /// `burstObservatory`, панельный RU-routing и сама правка.
  ({String json, ProxyCore core, bool full}) configFor(
      VpnServer server, ConnectionOptions options,
      {Map<String, String> resolvedIps = const {}}) {
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
        // Третий случай — настройка «мои правила важнее правил панели». Без неё
        // сайт, помеченный «Туннель», панель может выпустить напрямую под
        // реальным IP, и понять это по интерфейсу нельзя: чип показывает
        // «Туннель», а трафик идёт мимо.
        if (s.splitTunnel.mode == SplitMode.all ||
            s.noRealIp ||
            s.myRulesOverridePanel) {
          json = rerouteDirectThroughVpn(json);
        }
        final norm = normalizeOverridePorts(json,
            socksPort: ports.socks, httpPort: ports.http);
        // #5 — у панельного профиля обычно нет StatsService, поэтому трафик
        // показывался как 0. Дописываем api/stats, если их нет.
        final withStats = ensureXrayStats(norm.json, apiPort: ports.api);
        return (json: withStats, core: ProxyCore.xray, full: true);
      }
    }
    if (server.core == ProxyCore.singbox) {
      // hysteria2 — Xray такого не умеет, поднимаем sing-box.
      return (
        json: buildSingboxJson([server], resolvedIps: resolvedIps),
        core: ProxyCore.singbox,
        full: false,
      );
    }
    return (
      json: configBuilder.buildJson(server, variant: options.variant),
      core: ProxyCore.xray,
      full: false,
    );
  }

  // ── Подключение ────────────────────────────────────────────────────────────

  @override
  Future<void> connect(VpnServer server,
      {ConnectionOptions options = const ConnectionOptions()}) async {
    // Резолвим ДО сборки конфига: с доменом в outbound'е ядро полезло бы за
    // адресом уже из-под поднятого туннеля — и упёрлось бы в собственный
    // перехват DNS (см. SingboxOutboundFactory.build).
    final s = await sessionFor(server, options);
    await connectWith(s.configJson, options, s.servers, core: s.core);
  }

  @override
  Future<void> connectBalancer(List<VpnServer> servers,
      {ConnectionOptions options = const ConnectionOptions()}) async {
    final s = await balancerSessionFor(servers, options);
    if (s == null) return;
    await connectWith(s.configJson, options, s.servers, core: s.core);
  }

  /// Сессия одиночного сервера — БЕЗ подъёма туннеля.
  ///
  /// Вынесено из [connect], чтобы ту же сессию можно было собрать для уже
  /// РАБОТАЮЩЕГО туннеля (см. [armAdoptedSession]). Дублировать сборку нельзя:
  /// разойдясь, копии дадут разное поведение при обрыве и при обычном
  /// подключении, и заметить это будет нечем.
  Future<EngineSession> sessionFor(
      VpnServer server, ConnectionOptions options) async {
    final resolved = pickOneIpPerHost(await resolveServerHosts([server]));
    final cfg = configFor(server, options, resolvedIps: resolved);
    return EngineSession(cfg.json, options, [server], cfg.core);
  }

  /// Сессия автовыбора — БЕЗ подъёма туннеля.
  Future<EngineSession?> balancerSessionFor(
      List<VpnServer> servers, ConnectionOptions options) async {
    if (servers.isEmpty) return null;
    // Одно ядро на сессию: смешать hysteria2 и VLESS в одном балансировщике
    // нельзя. Xray-серверы идут в его balancer, иначе — urltest в sing-box.
    final xrayOnes =
        servers.where((s) => s.core == ProxyCore.xray).toList(growable: false);
    if (xrayOnes.isNotEmpty) {
      return EngineSession(configBuilder.buildBalancerJson(xrayOnes), options,
          xrayOnes, ProxyCore.xray);
    }
    final resolved = pickOneIpPerHost(await resolveServerHosts(servers));
    return EngineSession(buildSingboxJson(servers, resolvedIps: resolved),
        options, servers, ProxyCore.singbox);
  }

  /// ⚠️ ВЕРНУТЬ СЕССИЮ ТУННЕЛЮ, ПОДХВАЧЕННОМУ ОТ ПРОШЛОГО ЗАПУСКА ИНТЕРФЕЙСА.
  ///
  /// На Android `VpnService` переживает смерть Activity вместе с изолятом, и
  /// [adoptRunningTunnel] показывает «Подключено» для живого туннеля. Но сессии
  /// у движка при этом НЕТ — конфиг остался в умершем изоляте, — а по ней
  /// гейтится ВСЁ автовосстановление: [scheduleRetry] выходит первой же
  /// строкой `session == null`, ещё до проверки `autoReconnect`.
  ///
  /// Последствие было тихим и опасным: пользователь свернул приложение, вернулся
  /// — обе настройки в интерфейсе включены, отчёт поддержки печатает их
  /// активными, а на первом же обрыве не происходит ни одной попытки повтора и
  /// ни секунды удержания трафика. Kill switch живёт внутри той же ветки
  /// (`teardownCore(keepCapture: …)`), поэтому трафик идёт открыто ровно тогда,
  /// когда пользователь считает себя защищённым.
  ///
  /// Данные для сессии есть у интерфейса — тот же сервер и те же настройки, из
  /// которых туннель и поднимался (выбор персистится). Поэтому не сохраняем
  /// ничего на диск: интерфейс просто отдаёт их обратно движку.
  Future<void> armAdoptedSession(
      List<VpnServer> servers, ConnectionOptions options) async {
    // Живую сессию не трогаем: она точнее любой реконструкции.
    if (_session != null || servers.isEmpty || !_status.isConnected) return;
    try {
      _session = servers.length == 1
          ? await sessionFor(servers.first, options)
          : await balancerSessionFor(servers, options);
      AppLog.i('Подхваченному туннелю возвращена сессия: '
          'автопереподключение и kill switch снова в силе');
    } catch (e) {
      // Не смогли собрать — честно в лог. Туннель работает, но автозащиты нет.
      AppLog.w('Не удалось восстановить сессию подхваченного туннеля: $e. '
          'Автопереподключение и kill switch не сработают до переподключения');
    }
  }

  Future<void> connectWith(String configJson, ConnectionOptions options,
      List<VpnServer> servers,
      {ProxyCore core = ProxyCore.xray}) async {
    if (_status.isConnected || _status.state == VpnConnectionState.connecting) {
      return;
    }
    // Запоминаем сессию — по ней восстанавливаемся при обрыве и смене сети.
    _session = EngineSession(configJson, options, servers, core);
    _userStopped = false;
    _attempt = 0;
    await startSession();
  }

  /// IP-адреса серверов — чтобы увести их мимо туннеля. Резолвим ДО его подъёма
  /// (обычным DNS): без этого исключения трафик самого ядра к серверу вернулся бы
  /// в туннель — петля, и сеть умирает целиком.
  /// Плоская проекция [resolveServerHosts]: сам резолв, кэш последнего успеха и
  /// запись в лог при провале живут там, чтобы не расходились две реализации.
  Future<List<String>> resolveServerIps(List<VpnServer> servers) async {
    final hosts = await resolveServerHosts(servers);
    return hosts.values.expand((e) => e).toSet().toList();
  }

  // ── Страница «сайт заблокирован» ───────────────────────────────────────────

  /// Поднять локальную страницу-заглушку и вернуть её порт (0 — не нужна).
  ///
  /// Общая для обеих платформ: правило маршрутизации, которое уводит сюда
  /// http-соединения, строит один и тот же [SingboxConfigBuilder], поэтому и
  /// условия включения должны быть одни. Расхождение здесь означало бы, что на
  /// одной платформе домен резолвится «в никуда».
  Future<int> startBlockPage(ConnectionOptions options) async {
    await BlockPageServer.stopCurrent();
    final s = options.settings;
    if (!s.blockPageEnabled) return 0;
    // В режиме «всё через VPN» пользовательские правила не применяются вовсе —
    // блокировать нечего, и поднимать сервер незачем.
    if (s.splitTunnel.mode == SplitMode.all) return 0;
    final hasBlocked =
        s.splitTunnel.sites.any((x) => x.action == AppAction.block);
    if (!hasBlocked) return 0;

    final l = await localizationsFor(s.languageCode);
    final srv = await BlockPageServer.start(
      texts: BlockPageTexts(
        windowTitle: l.blockPageWindowTitle(AppInfo.name),
        heading: l.blockPageHeading,
        hint: l.blockPageHint,
        note: l.blockPageNote,
        body: (host) => l.blockPageBody(host, AppInfo.name),
      ),
    );
    // Не поднялась — продолжаем без неё: блокировка важнее объяснения.
    return srv?.port ?? 0;
  }

  // ── Автовосстановление ─────────────────────────────────────────────────────

  /// Запланировать повторную попытку, если включено автопереподключение и
  /// пользователь не отключался сам. Возвращает true, если попытка запланирована.
  Future<bool> scheduleRetry(String reason) async {
    final session = _session;
    if (session == null || _userStopped) return false;
    if (!session.options.settings.autoReconnect) return false;

    // ⚠️ Повтор лечит ОБРЫВ, но не отсутствующий файл.
    //
    // Случай из жизни: файл ядра пропал из папки программы, и каждое нажатие
    // «Подключить» падало с «Не удается найти указанный файл». Приложение
    // послушно перезапускалось 31 раз подряд в течение суток, показывая
    // «Переподключение…», а настоящую причину видел только тот, кто открывал
    // лог. Пользователь всё это время считал, что «просто не работает».
    //
    // Такие отказы неустранимы повтором по своей природе: пока файла нет, ничего
    // не изменится. Останавливаемся сразу и говорим, ЧЕГО не хватает.
    if (_isUnrecoverable(reason)) {
      AppLog.e('Автопереподключение отменено: $reason. Повтор тут не поможет — '
          'не хватает файла программы, переустановите приложение.');
      _userStopped = true;
      return false;
    }

    // ОДНА попытка на один обрыв. Обрыв приходит несколькими событиями подряд:
    // при hysteria2 в TUN-режиме одновременно умирают процесс туннеля и процесс
    // прокси-ядра, у каждого свой onCoreDied, плюс сверху может прилететь смена
    // сети. Без этого стража каждое событие жгло бы отдельную попытку — в логе
    // все 8 попыток («через 0 с», «через 3 с», «через 8 с»…) отрабатывали в одну
    // миллисекунду, backoff не выдерживался вовсе, и первый же случайный сбой
    // навсегда исчерпывал лимит. Пока запланированная попытка не отработала,
    // новые события считаем тем же самым обрывом.
    //
    // ⚠️ Флаг, а не только проверка таймера: ниже стоит `await teardownCore`, и
    // на этом await управление уходит в цикл событий. Одной проверки таймера
    // мало — второе событие успевало проскочить до того, как таймер вообще
    // создан. Флаг ставится СИНХРОННО, до первого await.
    if (_retryPending || (_retryTimer?.isActive ?? false)) return true;
    _retryPending = true;
    try {
      return await _scheduleRetryLocked(reason, session);
    } finally {
      _retryPending = false;
    }
  }

  /// Обёртка для тестов: правило важное, а метод приватный.
  @visibleForTesting
  static bool isUnrecoverableForTest(String reason) => _isUnrecoverable(reason);

  /// Отказ, который повтором не лечится.
  ///
  /// Сейчас это единственный класс: не найден исполняемый файл ядра. Текст
  /// приходит от системы и локализован, поэтому смотрим и на русский вариант, и
  /// на английский, и на код ошибки Windows (2 — ERROR_FILE_NOT_FOUND,
  /// 3 — ERROR_PATH_NOT_FOUND).
  static bool _isUnrecoverable(String reason) {
    final r = reason.toLowerCase();
    return r.contains('не удается найти указанный файл') ||
        r.contains('не удаётся найти указанный файл') ||
        r.contains('cannot find the file') ||
        r.contains('the system cannot find the path') ||
        r.contains('no such file or directory') ||
        r.contains('errno = 2') ||
        r.contains('errno = 3');
  }

  bool _retryPending = false;

  Future<bool> _scheduleRetryLocked(String reason, EngineSession session) async {

    // ⚠️ ПРИ ВКЛЮЧЁННОМ KILL SWITCH ПОПЫТКИ НЕ ЗАКАНЧИВАЮТСЯ.
    //
    // Раньше их было восемь на любой случай: 0,8 + 3 + 8 + 20×5 ≈ 112 секунд.
    // Дальше `scheduleRetry` возвращал false, вызывающий шёл в `cleanup()`, а тот
    // снимает TUN и системный прокси — и с этой секунды трафик идёт открыто под
    // реальным IP, без ограничения по времени. То есть обещание «не выпущу
    // трафик мимо VPN» действовало ровно две минуты, а сценарий, ради которого
    // kill switch и включают («поставил закачку и ушёл»), им не покрывался
    // вовсе: сервер лёг ночью, две минуты приложение держало оборону, потом
    // сдалось и открыло канал до утра.
    //
    // Решение владельца: держать блокировку до вмешательства человека. Вечные
    // попытки здесь не опасны — опасно как раз их прекращение: пока они идут,
    // захват трафика не снимается, и утечки нет. Пауза при этом упирается в
    // потолок `backoff` (20 с), то есть это три попытки в минуту, а не спам.
    // Вернувшийся через час сервер подхватится сам.
    final endless = session.options.settings.killSwitch;
    if (endless && _blockingSince == null) {
      _blockingSince = DateTime.now();
      AppLog.w('Kill switch: ТРАФИК ЗАБЛОКИРОВАН до восстановления связи '
          '(причина обрыва: $reason). Попытки не прекращаются — решение '
          'владельца: держать блокировку до вмешательства пользователя.');
    }
    if (!endless && _attempt >= maxAttempts) {
      AppLog.e('Автопереподключение: исчерпаны попытки ($maxAttempts)');
      return false;
    }

    // Попытки на текущем сервере исчерпаны — пробуем следующий (только в режиме
    // «Авто (лучший сервер)»: там пользователь и просил «выбери рабочий»).
    if (_attempt >= maxAttempts - 1 && _fallbacks.isNotEmpty) {
      final next = _fallbacks.removeAt(0);
      AppLog.w('Переключаюсь на запасной сервер: ${next.displayName}');
      await teardownCore(keepCapture: session.options.settings.killSwitch);
      if (_userStopped) return false; // отключились, пока гасили ядро
      _attempt = 0;
      // Через тот же configFor: у запасного сервера может быть свой профиль
      // панели или JSON-правка, и собирать его «из полей» — значит их потерять.
      // Резолв обязателен и здесь: запасной сервер поднимается, когда туннель
      // уже стоял, то есть в самой опасной для рантайм-резолва обстановке.
      final cfg = configFor(next, session.options,
          resolvedIps: pickOneIpPerHost(await resolveServerHosts([next])));
      _session = EngineSession(cfg.json, session.options, [next], cfg.core);
      setStatus(VpnConnectionState.connecting,
          message: 'Пробую другой сервер: ${next.displayName}…');
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 1), () => _runAttempt());
      return true;
    }

    _attempt++;
    final delay = backoff[_attempt.clamp(1, backoff.length) - 1];
    AppLog.w('Автопереподключение: $reason → попытка $_attempt через '
        '${delay.inSeconds} с');

    // Kill switch: НЕ снимаем захват трафика между попытками — иначе на время
    // паузы трафик пошёл бы напрямую, мимо VPN.
    await teardownCore(keepCapture: session.options.settings.killSwitch);

    // teardownCore идёт долго (остановка процесса до 3 с + снятие TUN), и за это
    // время пользователь успевает нажать «Отключить». Без этой проверки мы
    // возвращали статус в «Подключение…» и ставили таймер уже ПОСЛЕ отключения:
    // пользователь навсегда оставался в «Подключение…», а повторный connectWith
    // отсекался гвардом «уже подключаемся».
    if (_userStopped) return false;

    // При вечных попытках «из 8» было бы враньём, а главное — надо СКАЗАТЬ, что
    // трафик сейчас заблокирован: без этого человек видит пропавший интернет и
    // не понимает, что это работает защита, а не поломка.
    setStatus(VpnConnectionState.connecting,
        message: endless
            ? 'Соединение потеряно, трафик заблокирован. '
                'Переподключение через ${delay.inSeconds} с (попытка $_attempt)…'
            : 'Переподключение через ${delay.inSeconds} с '
                '(попытка $_attempt из $maxAttempts)…',
        blocking: endless);

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => _runAttempt());
    return true;
  }

  /// Выполнить запланированную попытку.
  ///
  /// ⚠️ Исключение внутри колбэка таймера ловить НЕКОМУ: запланированная попытка
  /// была единственной, и любой сбой подъёма (занятый порт, отказ ядра, отвал
  /// прав) навсегда оставлял движок в «Подключение…» без единого сообщения.
  /// Перехватываем и планируем следующую попытку — лимит и backoff при этом
  /// продолжают работать, а при их исчерпании пользователь увидит ошибку.
  Future<void> _runAttempt() async {
    if (_userStopped) return;
    try {
      await startSession();
    } catch (e) {
      AppLog.e('Попытка восстановления не удалась: $e');
      if (!await scheduleRetry('ошибка восстановления')) {
        setStatus(VpnConnectionState.error, message: '$e');
      }
    }
  }

  /// Номер текущей попытки восстановления (0 — обычное подключение).
  ///
  /// Счётчик ведёт база; наследникам он нужен только для текста статуса. Пока
  /// его не было, `WindowsEngine` держал СВОЁ поле `_attempt`, которое никто не
  /// увеличивал, — номер попытки в статусе и в логе всегда оставался нулём.
  int get attempt => _attempt;

  /// Сколько попыток восстановления израсходовано на текущем сервере.
  @visibleForTesting
  int get attemptsUsed => _attempt;

  /// Снять ожидающую попытку, не выполняя её, — чтобы в тестах не ждать backoff
  /// по-настоящему (первая пауза 800 мс, дальше до 20 с).
  @visibleForTesting
  void dropPendingRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Внешний сигнал: сетевое окружение изменилось (Wi-Fi ↔ кабель, сон, новый IP).
  /// Туннель поверх старого адаптера уже мёртв, даже если процессы живы.
  @override
  /// Умолчание: подхватывать нечего — туннель и интерфейс живут в одном
  /// процессе. Переопределяет только Android, где `VpnService` переживает
  /// смерть Activity (см. `VpnEngine.adoptRunningTunnel`).
  @override
  Future<void> adoptRunningTunnel() async {}

  @override
  Future<void> onNetworkChanged() async {
    if (_session == null || _userStopped) return;
    if (!_status.isConnected) return;
    if (!_session!.options.settings.autoReconnect) return;
    // Страховка от цикла: сразу после подключения «смена сети» — это почти всегда
    // наш же туннель, а не реальное изменение.
    final since = _connectedAt;
    if (since != null && DateTime.now().difference(since) < networkGrace) {
      AppLog.i('Смена сети проигнорирована: прошло меньше '
          '${networkGrace.inSeconds} с после подключения');
      return;
    }
    AppLog.w('Смена сети — восстанавливаю подключение');
    _attempt = 0;
    await scheduleRetry('сменилось сетевое окружение');
  }

  /// Ядро умерло само — пробуем восстановиться, иначе показываем ошибку.
  Future<void> onCoreDied(int code) async {
    // Имя ядра важно: по нему пользователь понимает, куда смотреть —
    // в xray_config.json или в singbox_proxy.json.
    final name = _session?.core == ProxyCore.singbox ? 'sing-box' : 'Xray';
    AppLog.e('Ядро $name остановилось (код $code)');
    if (await scheduleRetry('ядро $name остановилось (код $code)')) return;
    await cleanup();
    setStatus(VpnConnectionState.error,
        message: 'Ядро $name остановилось (код $code)');
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
      await cleanup();
      return;
    }
    setStatus(VpnConnectionState.disconnecting);
    await cleanup();
    setStatus(VpnConnectionState.disconnected);
    emitStats(TrafficStats.zero);
  }

  /// Полная остановка. Поколение увеличивается ЗДЕСЬ — поэтому всё, что зависит
  /// от «была ли отмена», обязано проверяться ДО вызова (см. `wasAborted`
  /// в наследниках).
  Future<void> cleanup() async {
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _connectedAt = null;
    // Слушать порт после отключения незачем, а на Android висящий сокет ещё и
    // держит процесс живым.
    await BlockPageServer.stopCurrent();
    await platformCleanup();
  }

  @override
  Future<void> dispose() async {
    await cleanup();
    await _statusController.close();
    await _statsController.close();
  }
}
