import 'dart:async';
import 'dart:io';

import '../settings/app_settings.dart';
import 'dpi_bypass_proxy.dart';
import 'dpi_strategy.dart';
import 'physical_nic_socket_windows.dart';

enum DpiProbeOutcome {
  /// Рукопожатие TLS и чтение потока успешно прошли напрямую мимо VPN.
  ok,

  /// TLS прошёл, но поток оборвался/замер на 1–24 КБ (блокировка ТСПУ по объёму;
  /// в режиме «Zapret → VPN» такой хост автоматически уйдёт в VPN).
  tspuFreeze,

  /// Соединение сброшено (RST), заблокировано по IP или истёк таймаут.
  blocked,
}

/// Цель живой проверки работы обхода DPI.
class DpiProbeTarget {
  final String title;
  final String url;
  final int minStreamBytes;

  const DpiProbeTarget({
    required this.title,
    required this.url,
    this.minStreamBytes = 0,
  });

  String get host => Uri.parse(url).host;
}

/// Результат проверки одной цели.
class DpiProbeTargetResult {
  final DpiProbeTarget target;
  final DpiProbeOutcome outcome;
  final int elapsedMs;
  final int? statusCode;
  final int bytesRead;
  final String detail;

  const DpiProbeTargetResult({
    required this.target,
    required this.outcome,
    required this.elapsedMs,
    required this.bytesRead,
    required this.detail,
    this.statusCode,
  });

  bool get isOk => outcome == DpiProbeOutcome.ok;
}

/// Сводный отчёт проверки одной стратегии.
class DpiStrategyReport {
  final DpiDesyncConfig strategy;
  final List<DpiProbeTargetResult> results;
  final String? gatewayLabel;

  const DpiStrategyReport({
    required this.strategy,
    required this.results,
    this.gatewayLabel,
  });

  int get okCount => results.where((r) => r.isOk).length;
  int get freezeCount =>
      results.where((r) => r.outcome == DpiProbeOutcome.tspuFreeze).length;
  int get totalCount => results.length;

  int get averageOkMs {
    final oks = results.where((r) => r.isOk).toList();
    if (oks.isEmpty) return 9999;
    final sum = oks.fold<int>(0, (acc, r) => acc + r.elapsedMs);
    return (sum / oks.length).round();
  }

  /// Числовой рейтинг для ранжирования в автоподборе.
  int get score => okCount * 1000 + freezeCount * 150 - (averageOkMs ~/ 10);
}

/// Результат полного автоподбора стратегий Zapret.
class DpiAutoTuneSummary {
  final List<DpiStrategyReport> reports;
  final DpiStrategyReport? best;
  final String? gatewayLabel;

  const DpiAutoTuneSummary({
    required this.reports,
    required this.best,
    this.gatewayLabel,
  });
}

/// Движок живой проверки и автоподбора стратегий встроенного `Zapret`.
///
/// Выполняет настоящие TLS 1.3 + HTTP запросы с чтением потока `> 32 КБ`
/// напрямую через физический сетевой адаптер (`IP_UNICAST_IF`), даже когда
/// VPN-туннель (`silentgate-tun`) включён.
class DpiProbeEngine {
  DpiProbeEngine._();

  static const List<DpiProbeTarget> defaultTargets = [
    DpiProbeTarget(
      title: 'YouTube Web (поток 32+ КБ)',
      url: 'https://www.youtube.com/',
      minStreamBytes: 32 * 1024,
    ),
    DpiProbeTarget(
      title: 'YouTube Media (i.ytimg.com)',
      url: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      minStreamBytes: 12 * 1024,
    ),
    DpiProbeTarget(
      title: 'YouTube Video API (googlevideo)',
      url: 'https://manifest.googlevideo.com/',
      minStreamBytes: 0,
    ),
    DpiProbeTarget(
      title: 'Discord API / CDN',
      url: 'https://discord.com/api/v9/experiments',
      minStreamBytes: 0,
    ),
    DpiProbeTarget(
      title: 'RuTracker (General)',
      url: 'https://rutracker.org/forum/index.php',
      minStreamBytes: 16 * 1024,
    ),
  ];

  static List<DpiProbeTarget> buildTargets({String? customDomain}) {
    final list = <DpiProbeTarget>[...defaultTargets];
    final cleaned = (customDomain ?? '')
        .trim()
        .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
        .split('/')
        .first
        .trim();
    if (cleaned.isNotEmpty && cleaned.contains('.')) {
      list.add(DpiProbeTarget(
        title: 'Свой домен ($cleaned)',
        url: 'https://$cleaned/',
        minStreamBytes: 0,
      ));
    }
    return list;
  }

  /// Проверить конкретную стратегию [strategy] по списку [targets].
  static Future<DpiStrategyReport> verifyStrategy(
    DpiDesyncConfig strategy, {
    List<DpiProbeTarget>? targets,
    Duration timeout = const Duration(milliseconds: 4200),
  }) async {
    final effectiveTargets = targets ?? defaultTargets;
    final gw = Platform.isWindows
        ? PhysicalNicSocketManager.instance.currentGateway(forceRefresh: true)
        : null;

    final proxy = LocalDpiBypassProxy(
      allowVpnFallback: false,
      strategy: strategy,
      bindToPhysicalNic: Platform.isWindows,
    );
    final proxyPort = await proxy.start();
    try {
      final results = await Future.wait(
        effectiveTargets.map(
          (t) => _probeSingleTarget(
            target: t,
            proxyPort: proxyPort,
            timeout: timeout,
          ),
        ),
      );
      return DpiStrategyReport(
        strategy: strategy,
        results: results,
        gatewayLabel: gw?.displayLabel,
      );
    } finally {
      await proxy.stop();
    }
  }

  /// Перебрать все боевые стратегии `Zapret` / `ByeDPI` и выбрать лучшую для
  /// текущего провайдера / ТСПУ.
  static Future<DpiAutoTuneSummary> autoTune({
    List<DpiProbeTarget>? targets,
    Duration perTargetTimeout = const Duration(milliseconds: 3600),
    bool Function()? isCancelled,
    void Function(
      int index,
      int total,
      DpiStrategyPreset preset,
      DpiStrategyReport? completed,
    )? onProgress,
  }) async {
    final effectiveTargets = targets ?? defaultTargets;
    final presets = DpiDesyncConfig.autoTuneOrder;
    final reports = <DpiStrategyReport>[];
    String? gwLabel;

    for (var i = 0; i < presets.length; i++) {
      if (isCancelled?.call() == true) break;
      final preset = presets[i];
      onProgress?.call(i, presets.length, preset, null);
      final cfg = DpiDesyncConfig.fromPreset(preset);
      final report = await verifyStrategy(
        cfg,
        targets: effectiveTargets,
        timeout: perTargetTimeout,
      );
      gwLabel ??= report.gatewayLabel;
      reports.add(report);
      onProgress?.call(i + 1, presets.length, preset, report);
    }

    DpiStrategyReport? best;
    for (final r in reports) {
      if (best == null || r.score > best.score) {
        best = r;
      }
    }
    if (best != null && best.okCount == 0 && best.freezeCount == 0) {
      best = null;
    }

    return DpiAutoTuneSummary(
      reports: reports,
      best: best,
      gatewayLabel: gwLabel,
    );
  }

  static Future<DpiProbeTargetResult> _probeSingleTarget({
    required DpiProbeTarget target,
    required int proxyPort,
    required Duration timeout,
  }) async {
    final sw = Stopwatch()..start();
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = const Duration(seconds: 2)
      ..autoUncompress = false
      ..findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';

    var bytesRead = 0;
    int? statusCode;
    try {
      final uri = Uri.parse(target.url);
      final req = await client.getUrl(uri).timeout(timeout);
      req.followRedirects = false;
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      );
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');

      final resp = await req.close().timeout(timeout);
      statusCode = resp.statusCode;

      final maxToRead =
          target.minStreamBytes > 0 ? target.minStreamBytes + 4096 : 4096;
      final done = Completer<void>();
      late final StreamSubscription<List<int>> sub;
      sub = resp.listen(
        (chunk) {
          bytesRead += chunk.length;
          if (bytesRead >= maxToRead && !done.isCompleted) {
            done.complete();
          }
        },
        onError: (Object e) {
          if (!done.isCompleted) done.completeError(e);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );

      try {
        await done.future.timeout(timeout);
      } finally {
        await sub.cancel();
      }
      sw.stop();

      // Если мы просили поток >= minStreamBytes, но получили редирект 301/302/303,
      // малый размер тела законен — главное, что TLS + HTTP заголовки прошли!
      final isRedirect = statusCode >= 300 && statusCode < 400;
      if (target.minStreamBytes > 0 &&
          !isRedirect &&
          statusCode == 200 &&
          bytesRead < target.minStreamBytes &&
          bytesRead < kTspuFreezeThresholdBytes) {
        return DpiProbeTargetResult(
          target: target,
          outcome: DpiProbeOutcome.tspuFreeze,
          elapsedMs: sw.elapsedMilliseconds,
          statusCode: statusCode,
          bytesRead: bytesRead,
          detail: 'HTTP $statusCode, поток обрезан на ${_fmtBytes(bytesRead)}',
        );
      }

      return DpiProbeTargetResult(
        target: target,
        outcome: DpiProbeOutcome.ok,
        elapsedMs: sw.elapsedMilliseconds,
        statusCode: statusCode,
        bytesRead: bytesRead,
        detail: 'HTTP $statusCode · ${_fmtBytes(bytesRead)} · ${sw.elapsedMilliseconds} мс',
      );
    } catch (e) {
      sw.stop();
      if (statusCode != null || (bytesRead > 0 && bytesRead < kTspuFreezeThresholdBytes)) {
        return DpiProbeTargetResult(
          target: target,
          outcome: DpiProbeOutcome.tspuFreeze,
          elapsedMs: sw.elapsedMilliseconds,
          statusCode: statusCode,
          bytesRead: bytesRead,
          detail: 'Блок ТСПУ 16–20 КБ (${_fmtBytes(bytesRead)}) — нужен фоллбэк в VPN',
        );
      }
      return DpiProbeTargetResult(
        target: target,
        outcome: DpiProbeOutcome.blocked,
        elapsedMs: sw.elapsedMilliseconds,
        statusCode: statusCode,
        bytesRead: bytesRead,
        detail: _shortError(e),
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _fmtBytes(int b) {
    if (b >= 1024) {
      return '${(b / 1024).toStringAsFixed(1)} КБ';
    }
    return '$b Б';
  }

  static String _shortError(Object e) {
    if (e is TimeoutException) return 'Таймаут ответа (ТСПУ / IP-блок)';
    if (e is HandshakeException) return 'Сброс TLS ClientHello (DPI RST)';
    if (e is SocketException) {
      final m = e.message;
      if (m.contains('10054') || m.toLowerCase().contains('reset')) {
        return 'TCP RST от ТСПУ';
      }
      return m.length > 60 ? '${m.substring(0, 60)}…' : m;
    }
    final s = '$e';
    return s.length > 60 ? '${s.substring(0, 60)}…' : s;
  }
}
