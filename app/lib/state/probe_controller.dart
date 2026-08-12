import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/models/vpn_server.dart';
import '../core/probe/cancel_token.dart';
import '../core/probe/ping_result.dart';
import '../core/probe/proxy_probe.dart';
import '../core/probe/tcp_ping.dart';
import '../core/platform/app_log.dart';
import '../core/probe/probe_harness.dart';
import '../core/settings/app_settings.dart';
// HarnessRealism не входит в реэкспорт probe_harness.dart (там только сущности
// самого харнесса), поэтому берём его из первоисточника.
import '../core/xray/harness_config_builder.dart' show HarnessRealism;
import '../core/xray/outbound_variant.dart';
import '../data/results_store.dart';
import '../engine/probe_factory.dart';

/// Пинг серверов. Модель проверки — как просил пользователь:
///   1. **TCP до всех** серверов (быстро, без ядра). Кто не ответил — «мёртв»,
///      из дальнейшей проверки исключается.
///   2. **GET/HEAD-верификация** оставшихся (через проброс-харнесс): отделяет
///      по-настоящему рабочие сервера от тех, что просто отвечают на TCP-порт.
/// **Показываемая задержка — всегда TCP.** hysteria2 — исключение: TCP у него
/// нет (QUIC/UDP), поэтому он идёт сразу на верификацию, а число берётся оттуда.
/// Системный прокси не трогается.
///
/// ⚠️ ЧЕРЕЗ ЧТО ИДЁТ ФАЗА 2 — ЗАВИСИТ ОТ СЕРВЕРА:
///   * **подключённый сервер при живом канале** — через ЖИВОЕ ядро, тем же
///     путём, что и трафик браузера. Это буквально «включил VPN и открыл сайт»;
///   * **остальные** — через проброс-харнесс, конфиг которого теперь несёт
///     боевые правила по сайтам и DNS ([HarnessRealism]).
/// ⚠️ Честная граница: для НЕАКТИВНЫХ серверов это всё равно проверка через
/// прокси-порт, а не через TUN-адаптер. Поломку самого TUN такая проба не
/// увидит — её видно только на активном сервере.
///
/// ⚠️ ФАЗА 1 НЕ ОБЪЯВЛЯЕТ СЕРВЕР РАБОЧИМ. TCP-ответ даёт только достижимость
/// ([PingOutcome.ok]); итог проверки живёт отдельно в [PingResult.verification]
/// и до фазы 2 стоит в `pending` (проверка идёт) либо `notRun` (её не будет).
/// Прежний код ставил «рабочий» авансом — на сервере, через который не работало
/// ничего, плашка горела зелёным всё время фазы 2. Не возвращать аванс.
class ProbeController extends ChangeNotifier {
  final ProbeHarness Function() _harnessFactory;

  final Map<String, PingResult> _results = {};
  bool _running = false;
  CancelToken? _cancel;

  /// Порт ЖИВОГО соединения и ключ сервера, который сейчас поднят.
  ///
  /// ⚠️ ИСПОЛЬЗУЮТСЯ НА ВСЕХ ПЛАТФОРМАХ, а не только там, где нет харнесса.
  /// Раньше живой канал был запасным вариантом для Android; теперь это ОСНОВНОЙ
  /// путь проверки подключённого сервера везде — харнесс с голым конфигом
  /// проходил там, где боевое подключение не работает.
  ///
  /// Через живой туннель честно проверяется РОВНО ОДИН сервер — тот, что сейчас
  /// подключён; для остальных такая проба измеряла бы чужой канал и давала
  /// одинаковые цифры всему списку, что хуже честного «не проверен».
  ///
  /// [liveProxyPort] обязан отдавать 0, пока канал не «Подключено» (так и
  /// сделано в `home_screen`): «подключается» — не «живой».
  int Function()? liveProxyPort;
  String? Function()? activeServerKey;

  ProbeController({
    ProbeHarness Function()? harnessFactory,
    this.liveProxyPort,
    this.activeServerKey,
  }) : _harnessFactory = harnessFactory ?? createProbeHarness;

  bool get running => _running;
  PingResult resultFor(VpnServer s) => _results[s.key] ?? PingResult.untested;

  // ── Прогресс для уведомления слева снизу ───────────────────────────────────
  List<VpnServer> _batch = const [];

  /// Ключи серверов, полностью «сделанных» в текущем прогоне (мёртвые в фазе 1
  /// либо прошедшие верификацию). Считать «сделан» по outcome нельзя: в двухфазном
  /// режиме TCP-ответивший получает outcome=ok ещё до GET/HEAD, и полоска прыгала
  /// бы на 100% на всё время фазы 2 (самой долгой).
  final Set<String> _done = {};
  String? _lastSummary;
  DateTime? _finishedAt;

  /// Сколько серверов в текущем прогоне.
  int get total => _batch.length;

  /// Сколько уже полностью проверено (с учётом фазы верификации).
  int get done => _batch.where((s) => _done.contains(s.key)).length;

  /// Итог последнего прогона и момент завершения — уведомление висит ещё
  /// несколько секунд после конца, поэтому текст нужен и после `running == false`.
  String? get lastSummary => _lastSummary;
  DateTime? get finishedAt => _finishedAt;

  /// #6 — сохранённая вариация сервера (fragment/fingerprint из автонастройки).
  /// Без неё сервер, работающий только с обходом, не проходит проверку via Proxy
  /// и показывает «n/a». Хук ставит AppState (см. HomeScreen).
  OutboundVariant Function(VpnServer server)? variantFor;

  OutboundVariant _variantOf(VpnServer s) =>
      variantFor?.call(s) ?? OutboundVariant.none;

  /// Загрузка сохранённых результатов пинга.
  Future<void> init() async {
    try {
      final data = await ResultsStore.ping.load();
      if (data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            _results['$key'] = PingResult.fromJson(value.cast<String, dynamic>());
          }
        });
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    final terminal = <String, dynamic>{};
    _results.forEach((key, result) {
      if (result.isTerminal) terminal[key] = result.toJson();
    });
    await ResultsStore.ping.save(terminal);
  }

  /// #3.2 — записать готовый результат извне (автонастройка меряет задержку сама),
  /// чтобы пинг на главной сразу подменился, а не ждал отдельного прогона.
  void setResult(VpnServer server, PingResult result) {
    _results[server.key] = result;
    notifyListeners();
    _persist();
  }

  Future<void> pingAll(List<VpnServer> servers, AppSettings settings) =>
      _pingBatch(servers, settings);

  Future<void> pingOne(VpnServer server, AppSettings settings) =>
      _pingBatch([server], settings);

  void cancel() => _cancel?.cancel();

  static bool _isHy2(VpnServer s) => s.protocol == 'hysteria2';

  static bool _hasFullConfig(VpnServer s) =>
      (s.rawJsonOverride ?? '').isNotEmpty || (s.rawPanelConfig ?? '').isNotEmpty;

  /// Сервер без осмысленного одиночного TCP-адреса: hysteria2 (QUIC) и полные
  /// конфиги (профиль «Авто …» — это балансировщик; json:// — адрес может быть
  /// `config:0`). Такие НЕ пингуем по TCP: адрес одного узла ничего не значит,
  /// а по нему сервер ошибочно попадал в «мёртвые». Только через прокси.
  static bool _proxyLatency(VpnServer s) => _isHy2(s) || _hasFullConfig(s);

  /// Метод верификации: HEAD, если пользователь выбрал его в настройках; иначе GET.
  static bool _verifyHead(AppSettings s) =>
      s.pingPrimary == PingMethod.proxyHead ||
      s.pingFallback == PingMethod.proxyHead;

  Future<void> _pingBatch(List<VpnServer> servers, AppSettings settings) async {
    if (_running || servers.isEmpty) return;
    _running = true;
    _batch = List.unmodifiable(servers);
    _done.clear();
    _lastSummary = null;
    final cancel = _cancel = CancelToken();
    for (final s in servers) {
      _results[s.key] = PingResult.testing;
    }
    notifyListeners();

    final sw = Stopwatch()..start();
    final timeout = Duration(milliseconds: settings.pingTimeoutMs);
    final twoPhase = settings.pingTwoPhase;
    final method = settings.pingPrimary;
    // При отжатой галочке работает ОДИН выбранный метод (TCP/ICMP/GET/HEAD).
    final proxySingle = !twoPhase &&
        (method == PingMethod.proxyGet || method == PingMethod.proxyHead);
    final icmpSingle = !twoPhase && method == PingMethod.icmp;
    // GET/HEAD для прокси-фазы: двухфазный — из настроек; одиночный прокси — по
    // методу; иначе (добивание hy2/профилей при TCP/ICMP) — обычный GET.
    final head = twoPhase
        ? _verifyHead(settings)
        : (proxySingle ? method == PingMethod.proxyHead : false);
    // ⚠️ ВНУТРИ try. Раньше строка стояла выше него, и на платформе без ICMP
    // (Android — сырые сокеты без root недоступны) `createIcmpPinger()`
    // бросал ДО входа в try: `finally` не отрабатывал, `_running` оставался
    // `true` навсегда, и пинг больше не запускался до перезапуска приложения.
    // В интерфейсе метод скрыт, но значение персистится и приезжает из чужого
    // файла настроек — на Android этого достаточно, чтобы получить дефект.
    try {
      final icmp = icmpSingle ? createIcmpPinger() : null;
      AppLog.i('Пинг: ${servers.length} серверов — '
          '${twoPhase ? "TCP + проверка ${head ? "HEAD" : "GET"}" : "метод ${method.name}"}');

      // ── ФАЗА 1: измерение выбранным методом. Кто не ответил (TCP/ICMP) — «мёртв».
      //    hysteria2/полные конфиги и режим «через прокси» уходят сразу в фазу 2.
      final survivors = <VpnServer>[]; // ответили по TCP (для двухфазной проверки)
      final proxyPlain = <VpnServer>[]; // обычные, но меряются через прокси (GET/HEAD)
      final noTcp = <VpnServer>[]; // hy2/профили — только через прокси
      final pool = Pool(settings.pingConcurrency);
      await Future.wait([
        for (final s in servers)
          pool.run(() async {
            if (cancel.isCancelled) return;
            if (_proxyLatency(s)) {
              noTcp.add(s);
              return;
            }
            if (proxySingle) {
              proxyPlain.add(s);
              return;
            }
            if (icmp != null) {
              final r = await icmp.ping(s.address, timeout: timeout);
              // ⚠️ ICMP-ответ НЕ доказывает, что сервер проксирует (часто это
              // вообще ближайший узел CDN). Раньше здесь ставилось «рабочий» —
              // плашка зеленела по эху. Проверки не было — значит `notRun`.
              _results[s.key] = PingResult(
                outcome: r.outcome,
                latencyMs: r.latencyMs,
                lossPct: r.lossPct,
                verification: PingVerification.notRun,
                latencyMethod: PingMethod.icmp,
                measuredAt: DateTime.now(),
              );
              _done.add(s.key);
              notifyListeners();
              return;
            }
            final r = await TcpPing.measure(s.address, s.port, timeout: timeout);
            if (r.outcome == PingOutcome.ok) {
              // ⚠️ ЗДЕСЬ БЫЛ ГЛАВНЫЙ ОБМАН: сервер помечался «рабочим» авансом,
              // по признаку `twoPhase && proxyProbeSupported` — то есть «фаза 2
              // БУДЕТ», а не «фаза 2 ПРОШЛА». Плашка зеленела сразу после TCP и
              // держалась зелёной всю фазу 2 (самую долгую), в том числе на
              // сервере, через который не работало ничего.
              //
              // TCP-ответ говорит ровно одно: порт открыт — а на типичном
              // Reality-порту он открыт всегда. Поэтому итог проверки ставится
              // отдельно: `pending`, если фаза 2 будет, иначе `notRun`.
              final willVerify = twoPhase && proxyProbeSupported;
              _results[s.key] = PingResult(
                outcome: PingOutcome.ok,
                latencyMs: r.latencyMs,
                verification: willVerify
                    ? PingVerification.pending
                    : PingVerification.notRun,
                latencyMethod: PingMethod.tcp,
                measuredAt: DateTime.now(),
              );
              survivors.add(s);
              // Без фазы 2 сервер уже финализирован; иначе «сделан» — после GET/HEAD.
              if (!twoPhase) _done.add(s.key);
            } else {
              _results[s.key] = PingResult(
                outcome: PingOutcome.failed,
                latencyMethod: PingMethod.tcp,
                measuredAt: DateTime.now(),
              );
              _done.add(s.key); // мёртв — дальше не проверяем
            }
            notifyListeners();
          }),
      ]);

      // ── ФАЗА 2: проба через прокси. Для hy2/профилей — всегда; для TCP-выживших —
      //    при двухфазности; для обычных — при одиночном методе GET/HEAD.
      final verify = <VpnServer>[
        ...noTcp,
        if (twoPhase) ...survivors,
        ...proxyPlain,
      ];
      // ── АКТИВНЫЙ СЕРВЕР ПРИ ЖИВОМ КАНАЛЕ — ЧЕРЕЗ ЖИВОЕ ЯДРО, НЕ ЧЕРЕЗ ХАРНЕСС.
      //
      // ⚠️ ЭТО И ЕСТЬ «НАСТОЯЩАЯ» ПРОВЕРКА, О КОТОРОЙ ПРОСИЛ ВЛАДЕЛЕЦ: «как
      // если бы юзер включил VPN, зашёл на сайт, и у него загрузилось или нет».
      // Харнесс — отдельный процесс ядра с голым конфигом: без правил
      // пользователя, без его DNS, без блокировок. Он проходил там, где боевое
      // подключение не работает, — и ровно это объясняло жалобу: плашка пинга
      // зелёная (достучался харнесс), а сервис-чипы под кнопкой Connect в тот
      // же момент красные (они всегда ходили через живое ядро). Теперь
      // подключённый сервер проверяется тем же путём, что и трафик браузера.
      //
      // ⚠️ Ровно один сервер — подключённый. Через живой канал идёт трафик
      // ТЕКУЩЕГО узла: для остальных такая проба измеряла бы чужой канал и
      // выдала бы одинаковые цифры всему списку.
      final live = _liveTargetIn(verify);
      if (live != null && !cancel.isCancelled) {
        verify.remove(live.server);
        AppLog.i('Проверка «${live.server.remark}»: через ЖИВОЕ ядро '
            '(127.0.0.1:${live.port}) — тем же путём, что идёт обычный трафик');
        await _applyVerify(live.server, live.port, settings,
            head: head, forceProxy: proxySingle);
      }

      // Платформа без харнесса (Android): проверить «реально ли проксирует»
      // нечем — второй экземпляр ядра рядом с живым туннелем не поднять.
      // Оставляем результат одной фазы вместо падения всего пинга: раньше
      // здесь вылетал UnsupportedError и обнулял проверку всех серверов.
      if (verify.isNotEmpty && !proxyProbeSupported) {
        for (final s in verify) {
          if (cancel.isCancelled) break;
          if (noTcp.contains(s)) {
            // Профили «Авто» и hysteria2 без пробы подтвердить нечем: TCP до
            // одного узла из десятков ничего не значит, а у QUIC его и нет.
            _results[s.key] = PingResult(
              outcome: PingOutcome.untested,
              verification: PingVerification.notRun,
              latencyMethod: settings.pingPrimary,
            );
          }
        }
        // Строка условная намеренно: журнал, обещающий проверку, которой не
        // было, дороже отсутствующей строки — по нему потом ищут причину.
        AppLog.i('Проба через прокси: харнесса нет, не проверено '
            '${verify.length}'
            '${live != null ? " (подключённый сервер проверен по живому каналу)" : ""}');
        notifyListeners();
      } else if (verify.isNotEmpty && !cancel.isCancelled) {
        // Полный конфиг (правка/профиль «Авто …») — своим харнессом: у него свои
        // теги и балансировщик, в общий мешать нельзя (#8.2).
        final shared = <VpnServer>[];
        final ownConfig = <VpnServer>[];
        for (final s in verify) {
          (_hasFullConfig(s) ? ownConfig : shared).add(s);
        }
        AppLog.i('Проба через прокси ${verify.length} '
            '(общий ${shared.length}, свой конфиг ${ownConfig.length})');
        await _verifyShared(shared, settings, cancel,
            head: head, forceProxy: proxySingle);
        for (final s in ownConfig) {
          if (cancel.isCancelled) break;
          await _verifyOne(s, settings, cancel,
              head: head, forceProxy: proxySingle);
        }
      }

      final ok = _goodCount(servers);
      // ⚠️ Слово подбирается по ФАКТУ проверки, а не по галочке в настройках:
      // «рабочих» — только когда проба через сервер реально была. Иначе итог
      // обещал бы проверку, которой не делали.
      final word = _anyVerified(servers) ? 'рабочих' : 'доступных';
      _lastSummary = cancel.isCancelled
          ? 'Пинг отменён: $word $ok из ${servers.length}'
          : 'Пинг завершён: $word $ok из ${servers.length} '
              '(${sw.elapsed.inSeconds} с)';
      AppLog.i('Пинг: $word $ok из ${servers.length} за '
          '${sw.elapsed.inSeconds} с');
    } catch (e) {
      _lastSummary = 'Пинг прерван ошибкой';
      AppLog.e('Пинг: сбой — $e');
    } finally {
      // ⚠️ НЕПРОВЕРЕННОЕ ОСТАЁТСЯ НЕПРОВЕРЕННЫМ. Раньше здесь всё, что не успело
      // измериться, переводилось в `failed` — при отмене прогона или падении
      // харнесса живые серверы красились в красное «n/a» И ТАКИМИ СОХРАНЯЛИСЬ на
      // диск, а красный человек читает как «не подключайся сюда».
      for (final s in servers) {
        final r = _results[s.key];
        if (r == null) continue;
        if (r.outcome == PingOutcome.testing) {
          // Замера не было вовсе: `untested` не терминален и на диск не поедет.
          _results[s.key] = PingResult.untested;
        } else if (r.verification == PingVerification.pending) {
          // Замер есть, проверка не завершилась. Оставить `pending` нельзя:
          // прогон окончен, а плашка вечно показывала бы «проверяю».
          _results[s.key] = r.withVerification(PingVerification.notRun);
        }
      }
      _running = false;
      _finishedAt = DateTime.now();
      await _persist();
      notifyListeners();
    }
  }

  /// Подключённый сейчас сервер из списка [servers] и порт его ЖИВОГО ядра.
  /// `null` — живого канала нет либо подключён сервер не из этого прогона.
  ///
  /// ⚠️ «ЖИВОЙ», А НЕ «ПОДКЛЮЧАЕТСЯ»: [liveProxyPort] отдаёт порт только при
  /// состоянии «Подключено» и 0 во всех остальных (см. `home_screen`). Пока
  /// канал поднимается, порт уже слушает, но никуда не доставляет — проба
  /// через него дала бы ложный провал (на этом уже горели сервис-чипы, см.
  /// историю 1.0.2). Ноль здесь трактуем как «живого канала нет».
  ({VpnServer server, int port})? _liveTargetIn(List<VpnServer> servers) {
    final port = liveProxyPort?.call() ?? 0;
    final key = activeServerKey?.call();
    if (port <= 0 || key == null || key.isEmpty) return null;
    for (final s in servers) {
      if (s.key == key) return (server: s, port: port);
    }
    return null;
  }

  /// Боевые настройки, влияющие на достижимость мишени, — в конфиг харнесса.
  ///
  /// ⚠️ Правила по ПРИЛОЖЕНИЯМ сюда не попадают, и это не забывчивость: у
  /// соединения, пришедшего в локальный прокси, нет процесса-владельца —
  /// сопоставлять ядру не с чем (по той же причине правила приложений не
  /// работают у системного прокси Windows).
  static HarnessRealism _realismFor(AppSettings s) {
    // Свой резолвер — единственная DNS-настройка, которая способна СЛОМАТЬ
    // открытие сайта: режимы «системный» и «через VPN» в харнессе и так
    // воспроизводятся (имя резолвит сервер на своей стороне).
    var dns = '';
    if (s.dnsMode == DnsMode.custom) {
      final raw = s.dnsCustomServer.trim();
      // Только адрес: строку вида `https://dns.example/query` Xray не примет, а
      // конфиг, который ядро отвергло, — это ноль проверенных серверов.
      if (InternetAddress.tryParse(raw) != null) dns = raw;
    }
    // Ограничивающие стратегии переносим, «предпочитать» — нет: предпочтение
    // ничего не запрещает, а лишняя dns-секция меняла бы конфиг всем подряд.
    final strategy = switch (s.dnsStrategy) {
      DnsStrategy.ipv4Only => 'UseIPv4',
      DnsStrategy.ipv6Only => 'UseIPv6',
      DnsStrategy.preferIpv4 || DnsStrategy.preferIpv6 => null,
    };
    return HarnessRealism.fromRules(s.splitTunnel,
        dnsServer: dns, queryStrategy: strategy);
  }

  /// Сколько серверов в прогоне «хорошие».
  ///
  /// ⚠️ Считается по [PingResult.verification], а не по авансовому флагу.
  /// Раньше итог брался из `isWorking`, а он до фазы 2 стоял по признаку «будет
  /// ли проверка»: при ВЫКЛЮЧЕННОЙ двухфазности каждый прогон заканчивался
  /// «рабочих 0 из N» на полностью живой подписке. Проверка не проводилась —
  /// значит судим по достижимости, а не выдумываем провал.
  int _goodCount(List<VpnServer> servers) => servers.where((s) {
        final r = _results[s.key];
        if (r == null) return false;
        return r.isWorking || r.isReachableUnverified;
      }).length;

  /// Была ли в этом прогоне хоть одна настоящая проба через сервер.
  bool _anyVerified(List<VpnServer> servers) => servers.any((s) {
        final v = _results[s.key]?.verification;
        return v == PingVerification.passed || v == PingVerification.failed;
      });

  /// Проба группы серверов через прокси на одном общем харнессе.
  Future<void> _verifyShared(
      List<VpnServer> servers, AppSettings settings, CancelToken cancel,
      {required bool head, required bool forceProxy}) async {
    if (servers.isEmpty) return;
    HarnessHandle? handle;
    try {
      final realism = _realismFor(settings);
      final entries = [
        for (final s in servers)
          HarnessEntry(
              key: s.key,
              server: s,
              variant: _variantOf(s),
              realism: realism),
      ];
      handle = await _harnessFactory().start(entries);

      final pool = Pool(settings.pingConcurrency);
      final futures = <Future<void>>[];
      for (var i = 0; i < servers.length; i++) {
        final idx = i;
        final server = servers[i];
        futures.add(pool.run(() async {
          if (cancel.isCancelled) return;
          // -1 = кандидата обслуживало второе ядро, а оно не поднялось.
          final raw = handle?.proxyPortFor(idx);
          final port = (raw == null || raw <= 0) ? null : raw;

          // ⚠️ Платформа может померить САМА и порта не дать: на Android
          // `LibXray.ping` поднимает свой экземпляр ядра и возвращает сразу
          // миллисекунды, поэтому `proxyPortFor` там ВСЕГДА 0.
          //
          // Без этой ветки каждый сервер уходил в `_applyVerify` с port == null
          // и помечался «отвечает по TCP, но не проксирует» — то есть ВЕСЬ
          // список красился в нерабочий, включая заведомо живые серверы,
          // которыми пользователь в этот момент пользовался. В `_verifyOne`
          // (полные конфиги, профили «Авто») то же самое было учтено, а здесь —
          // на пути, по которому идут ОБЫЧНЫЕ серверы, то есть почти все, — нет.
          if (port == null) {
            final ready = await handle?.delayMs(idx);
            if (cancel.isCancelled) return;
            if (ready != null) {
              // Замер сделан ЧЕРЕЗ поднятое ядро (LibXray) — это и есть проба,
              // а не TCP-рукопожатие: состояние `passed` здесь заслуженное.
              _results[server.key] = PingResult(
                outcome: PingOutcome.ok,
                latencyMs: ready,
                proxyRttMs: ready,
                reachableViaProxy: true,
                verification: PingVerification.passed,
                latencyMethod: settings.pingPrimary,
                measuredAt: DateTime.now(),
              );
              _done.add(server.key); // иначе полоска прогресса не доходит до конца
              notifyListeners();
              return;
            }
          }
          await _applyVerify(server, port, settings,
              head: head,
              forceProxy: forceProxy,
              proxyUser: handle?.proxyUser,
              proxyPassword: handle?.proxyPassword);
        }));
      }
      await Future.wait(futures);
    } finally {
      await handle?.stop();
    }
  }

  /// Проба одного сервера с полным JSON-конфигом на отдельном харнессе (#8.2).
  Future<void> _verifyOne(
      VpnServer server, AppSettings settings, CancelToken cancel,
      {required bool head, required bool forceProxy}) async {
    HarnessHandle? handle;
    try {
      handle = await _harnessFactory().start([
        HarnessEntry(
            key: server.key,
            server: server,
            variant: _variantOf(server),
            realism: _realismFor(settings)),
      ]);
      final rawPort = handle.proxyPortFor(0);
      final port = rawPort <= 0 ? null : rawPort;
      if (cancel.isCancelled) return;
      // Платформа может померить сама и порта не дать (Android: LibXray.ping
      // возвращает миллисекунды). Тогда ходить через прокси нечем и незачем.
      final ready = port == null ? await handle.delayMs(0) : null;
      if (cancel.isCancelled) return;
      if (port == null && ready != null) {
        // Как и в `_verifyShared`: цифру дало ядро, поднятое ради этой пробы, —
        // проверка состоялась.
        _results[server.key] = PingResult(
          outcome: PingOutcome.ok,
          latencyMs: ready,
          proxyRttMs: ready,
          reachableViaProxy: true,
          verification: PingVerification.passed,
          latencyMethod: settings.pingPrimary,
          measuredAt: DateTime.now(),
        );
        _done.add(server.key);
        notifyListeners();
        return;
      }
      await _applyVerify(server, port, settings,
          head: head,
          forceProxy: forceProxy,
          proxyUser: handle.proxyUser,
          proxyPassword: handle.proxyPassword);
    } finally {
      await handle?.stop();
    }
  }

  /// GET/HEAD через прокси-порт и запись итога. Обычно показываемая цифра остаётся
  /// TCP; для серверов без TCP (hysteria2, полный конфиг) и при одиночном методе
  /// «через прокси» ([forceProxy]) — RTT пробы: другого числа нет.
  Future<void> _applyVerify(VpnServer s, int? port, AppSettings settings,
      {required bool head,
      required bool forceProxy,
      // Креды ИМЕННО ЭТОГО порта. `null` — живое ядро, у него свои сессионные
      // (ProxyProbe.user/password). У харнесса пароль свой, на прогон, и
      // подставить сюда сессионный значило бы получить 407 на каждом сервере.
      String? proxyUser,
      String? proxyPassword}) async {
    final proxyLat = _proxyLatency(s) || forceProxy;
    try {
      if (port == null) {
        // ⚠️ «НЕ ПРОВЕРЕН» И «МЁРТВ» — РАЗНЫЕ НОВОСТИ, И ПУТАТЬ ИХ НЕЛЬЗЯ.
        //
        // Порт `null` значит «замерить нечем» (харнесс не поднялся, ядро
        // кандидата не стартовало, платформа так не умеет), а не «сервер не
        // отвечает» и не «сервер не проксирует». На Android харнесс не умеет
        // hysteria2 вовсе (`ProbeHarnessAndroid` кладёт для него null), и
        // заведомо рабочий сервер красился в красное «n/a»; обычный сервер при
        // упавшем харнессе получал «отвечает, но не проксирует» — оба вердикта
        // выдуманные. Красный человек читает как «не подключайся сюда» и
        // послушно уходит на худший узел.
        //
        // Пробы НЕ БЫЛО ⇒ `notRun`. Число TCP при этом сохраняем: оно измерено.
        _results[s.key] = proxyLat
            ? PingResult(
                // TCP-цифры у таких серверов нет вовсе — показывать нечего.
                outcome: PingOutcome.untested,
                verification: PingVerification.notRun,
                latencyMethod: settings.pingPrimary,
                measuredAt: DateTime.now(),
              )
            : PingResult(
                outcome: PingOutcome.ok,
                latencyMs: _results[s.key]?.latencyMs,
                verification: PingVerification.notRun,
                latencyMethod: PingMethod.tcp,
                measuredAt: _results[s.key]?.measuredAt ?? DateTime.now(),
              );
        notifyListeners();
        return;
      }

      final probe = await ProxyProbe.check(
        port,
        settings.testUrl,
        head: head,
        timeout: Duration(milliseconds: settings.pingTimeoutMs),
        proxyUser: proxyUser,
        proxyPassword: proxyPassword,
      );
      // Проба состоялась — вот теперь вердикт настоящий.
      final verdict =
          probe.ok ? PingVerification.passed : PingVerification.failed;
      if (proxyLat) {
        _results[s.key] = PingResult(
          outcome: probe.ok ? PingOutcome.ok : PingOutcome.failed,
          latencyMs: probe.rttMs, // TCP нет — показываем RTT пробы
          proxyRttMs: probe.rttMs,
          verification: verdict,
          reachableViaProxy: probe.ok,
          latencyMethod: head ? PingMethod.proxyHead : PingMethod.proxyGet,
          measuredAt: DateTime.now(),
        );
      } else {
        _results[s.key] = PingResult(
          outcome: PingOutcome.ok, // TCP уже подтвердил достижимость
          latencyMs: _results[s.key]?.latencyMs, // показываем TCP
          proxyRttMs: probe.rttMs,
          verification: verdict,
          reachableViaProxy: probe.ok,
          latencyMethod: PingMethod.tcp,
          measuredAt: DateTime.now(),
        );
      }
      notifyListeners();
    } finally {
      // Проба завершена — этот сервер «сделан» (для прогресс-полоски).
      _done.add(s.key);
    }
  }
}
