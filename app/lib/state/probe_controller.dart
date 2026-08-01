import 'package:flutter/foundation.dart';

import '../core/models/vpn_server.dart';
import '../core/probe/cancel_token.dart';
import '../core/probe/ping_result.dart';
import '../core/probe/proxy_probe.dart';
import '../core/probe/tcp_ping.dart';
import '../core/platform/app_log.dart';
import '../core/probe/probe_harness.dart';
import '../core/settings/app_settings.dart';
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
class ProbeController extends ChangeNotifier {
  final ProbeHarness Function() _harnessFactory;

  final Map<String, PingResult> _results = {};
  bool _running = false;
  CancelToken? _cancel;

  /// Порт ЖИВОГО соединения и ключ сервера, который сейчас поднят.
  ///
  /// Нужны там, где отдельный харнесс поднять нельзя (Android: VpnService в
  /// приложении один). Через живой туннель честно проверяется РОВНО ОДИН
  /// сервер — тот, что сейчас подключён; для остальных такая проба измеряла бы
  /// чужой канал и давала одинаковые цифры всему списку, что хуже честного
  /// «не проверен».
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
              final ok = r.outcome == PingOutcome.ok;
              _results[s.key] = PingResult(
                outcome: r.outcome,
                latencyMs: r.latencyMs,
                lossPct: r.lossPct,
                working: ok,
                latencyMethod: PingMethod.icmp,
                measuredAt: DateTime.now(),
              );
              _done.add(s.key);
              notifyListeners();
              return;
            }
            final r = await TcpPing.measure(s.address, s.port, timeout: timeout);
            if (r.outcome == PingOutcome.ok) {
              // Достижим — показываем сразу как рабочий (оптимистично): иначе
              // на время фазы 2 все ответившие висели бы серыми. Проверка
              // GET/HEAD ниже понизит до «не проксирует» только реально не
              // прошедшие.
              //
              // ⚠️ Оптимизм ОПРАВДАН ТОЛЬКО ТЕМ, что фаза 2 будет. Если её не
              // будет (платформа без харнесса и двухфазность выключена),
              // зелёный означал бы «порт открыт», а не «проксирует» — а на
              // типичном Reality-порту открыт вообще любой. Тогда честнее
              // серый: отвечает, но не подтверждён.
              final willVerify = twoPhase && proxyProbeSupported;
              _results[s.key] = PingResult(
                outcome: PingOutcome.ok,
                latencyMs: r.latencyMs,
                working: willVerify,
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
      // Платформа без харнесса (Android): проверить «реально ли проксирует»
      // нечем — второй экземпляр ядра рядом с живым туннелем не поднять.
      // Оставляем результат одной фазы вместо падения всего пинга: раньше
      // здесь вылетал UnsupportedError и обнулял проверку всех серверов.
      if (verify.isNotEmpty && !proxyProbeSupported) {
        // Харнесса нет (Android). Но у ПОДКЛЮЧЁННОГО сервера канал уже поднят —
        // через него проба честная и осмысленная. Именно так работают
        // сервис-чипы под кнопкой Connect.
        //
        // ⚠️ Только для активного сервера. Через живой туннель идёт трафик
        // ТЕКУЩЕГО узла, поэтому для остальных такая проба показала бы чужой
        // канал — одинаковые цифры всему списку. Ложные данные хуже, чем
        // честное «не проверен».
        final livePort = liveProxyPort?.call() ?? 0;
        final activeKey = activeServerKey?.call();
        var probed = 0;
        for (final s in verify) {
          if (cancel.isCancelled) break;
          if (livePort > 0 && activeKey != null && s.key == activeKey) {
            await _applyVerify(s, livePort, settings,
                head: head, forceProxy: true);
            probed++;
          } else if (noTcp.contains(s)) {
            // Профили «Авто» и hysteria2 без пробы подтвердить нечем: TCP до
            // одного узла из десятков ничего не значит, а у QUIC его и нет.
            _results[s.key] = PingResult(
              outcome: PingOutcome.untested,
              latencyMethod: settings.pingPrimary,
            );
          }
        }
        AppLog.i('Проба через прокси: харнесс недоступен, проверен по живому '
            'соединению $probed из ${verify.length}');
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

      final ok = servers.where((s) => _results[s.key]?.isWorking == true).length;
      _lastSummary = cancel.isCancelled
          ? 'Пинг отменён: рабочих $ok из ${servers.length}'
          : 'Пинг завершён: рабочих $ok из ${servers.length} '
              '(${sw.elapsed.inSeconds} с)';
      AppLog.i('Пинг: рабочих $ok из ${servers.length} за '
          '${sw.elapsed.inSeconds} с');
    } catch (e) {
      _lastSummary = 'Пинг прерван ошибкой';
      AppLog.e('Пинг: сбой — $e');
    } finally {
      // Ни отмена, ни сбой не должны оставить сервер с крутилкой.
      for (final s in servers) {
        if (_results[s.key]?.outcome == PingOutcome.testing) {
          _results[s.key] = const PingResult(outcome: PingOutcome.failed);
        }
      }
      _running = false;
      _finishedAt = DateTime.now();
      await _persist();
      notifyListeners();
    }
  }

  /// Проба группы серверов через прокси на одном общем харнессе.
  Future<void> _verifyShared(
      List<VpnServer> servers, AppSettings settings, CancelToken cancel,
      {required bool head, required bool forceProxy}) async {
    if (servers.isEmpty) return;
    HarnessHandle? handle;
    try {
      final entries = [
        for (final s in servers)
          HarnessEntry(key: s.key, server: s, variant: _variantOf(s)),
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
              _results[server.key] = PingResult(
                outcome: PingOutcome.ok,
                latencyMs: ready,
                working: true,
                latencyMethod: settings.pingPrimary,
              );
              notifyListeners();
              return;
            }
          }
          await _applyVerify(server, port, settings,
              head: head, forceProxy: forceProxy);
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
        HarnessEntry(key: server.key, server: server, variant: _variantOf(server)),
      ]);
      final rawPort = handle.proxyPortFor(0);
      final port = rawPort <= 0 ? null : rawPort;
      if (cancel.isCancelled) return;
      // Платформа может померить сама и порта не дать (Android: LibXray.ping
      // возвращает миллисекунды). Тогда ходить через прокси нечем и незачем.
      final ready = port == null ? await handle.delayMs(0) : null;
      if (cancel.isCancelled) return;
      if (port == null && ready != null) {
        _results[server.key] = PingResult(
          outcome: PingOutcome.ok,
          latencyMs: ready,
          working: true,
          latencyMethod: settings.pingPrimary,
        );
        notifyListeners();
        return;
      }
      await _applyVerify(server, port, settings,
          head: head, forceProxy: forceProxy);
    } finally {
      await handle?.stop();
    }
  }

  /// GET/HEAD через прокси-порт и запись итога. Обычно показываемая цифра остаётся
  /// TCP; для серверов без TCP (hysteria2, полный конфиг) и при одиночном методе
  /// «через прокси» ([forceProxy]) — RTT пробы: другого числа нет.
  Future<void> _applyVerify(VpnServer s, int? port, AppSettings settings,
      {required bool head, required bool forceProxy}) async {
    final proxyLat = _proxyLatency(s) || forceProxy;
    try {
      if (port == null) {
        // ⚠️ «НЕ ПРОВЕРЕН» И «МЁРТВ» — РАЗНЫЕ НОВОСТИ, И ПУТАТЬ ИХ НЕЛЬЗЯ.
        //
        // Порт `null` значит «замерить нечем», а не «сервер не отвечает».
        // На Android харнесс не умеет hysteria2 вовсе (`ProbeHarnessAndroid`
        // кладёт для него null), и заведомо рабочий сервер красился в красное
        // «n/a» — при том, что и код, и бэклог обещают честное «не проверен».
        // Красный означает «не подключайся сюда», и человек послушно шёл на
        // худший узел.
        //
        // Отличаем по тому, была ли попытка ВООБЩЕ возможна: `forceProxy` —
        // это проба по живому каналу, её отказ настоящий.
        if (proxyLat && !forceProxy) {
          _results[s.key] = PingResult(
            outcome: PingOutcome.untested,
            latencyMethod: settings.pingPrimary,
            measuredAt: DateTime.now(),
          );
          notifyListeners();
          return;
        }
        // Обычный сервер по TCP достижим, но рабочим не подтверждён.
        _results[s.key] = proxyLat
            ? PingResult(outcome: PingOutcome.failed, measuredAt: DateTime.now())
            : PingResult(
                outcome: PingOutcome.ok,
                latencyMs: _results[s.key]?.latencyMs,
                working: false,
                latencyMethod: PingMethod.tcp,
                measuredAt: DateTime.now(),
              );
        notifyListeners();
        return;
      }

      final probe = await ProxyProbe.check(
        port,
        settings.testUrl,
        head: head,
        timeout: Duration(milliseconds: settings.pingTimeoutMs),
      );
      if (proxyLat) {
        _results[s.key] = PingResult(
          outcome: probe.ok ? PingOutcome.ok : PingOutcome.failed,
          latencyMs: probe.rttMs, // TCP нет — показываем RTT пробы
          proxyRttMs: probe.rttMs,
          working: probe.ok,
          reachableViaProxy: probe.ok,
          latencyMethod: head ? PingMethod.proxyHead : PingMethod.proxyGet,
          measuredAt: DateTime.now(),
        );
      } else {
        _results[s.key] = PingResult(
          outcome: PingOutcome.ok, // TCP уже подтвердил достижимость
          latencyMs: _results[s.key]?.latencyMs, // показываем TCP
          proxyRttMs: probe.rttMs,
          working: probe.ok,
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
