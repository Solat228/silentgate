import 'dart:convert';
import 'dart:io';

/// Снимок счётчиков трафика outbound "proxy".
class XrayTrafficSnapshot {
  final int uplink;
  final int downlink;
  const XrayTrafficSnapshot(this.uplink, this.downlink);
  static const zero = XrayTrafficSnapshot(0, 0);
}

/// Опрашивает StatsService ядра через CLI: `xray api statsquery`.
/// Отдельный gRPC-клиент не нужен — используем встроенную api-команду xray.
class XrayStats {
  final String executable;
  final int apiPort;
  const XrayStats({required this.executable, this.apiPort = 10085});

  /// `null` — опрос НЕ УДАЛСЯ (ядро не ответило, ненулевой код возврата).
  ///
  /// ⚠️ Ноль здесь означал бы «трафика нет», и движок принимал бы это за
  /// настоящий отсчёт: счётчик падал до нуля, следующая удачная выборка давала
  /// фальшивый всплеск скорости, а `AppState` считал падение перезапуском ядра
  /// и удваивал трафик «за сессию». Пропуск такта таких последствий не имеет.
  Future<XrayTrafficSnapshot?> query() async {
    try {
      final result = await Process.run(
        executable,
        ['api', 'statsquery', '--server=127.0.0.1:$apiPort'],
      ).timeout(const Duration(seconds: 2));
      if (result.exitCode != 0) return null;

      return sumStatsQuery(result.stdout as String);
    } catch (_) {
      return null;
    }
  }

  /// Разбор ответа `xray api statsquery` (чистая функция — тестируется без ядра).
  ///
  /// Суммирует трафик по ВСЕМ прокси-outbound'ам, а не только по тегу `proxy`:
  /// у панельных «Авто»-профилей outbound'ы называются тегами серверов (через
  /// balancer), поэтому строгий `proxy` давал 0 (#5). Исключаются служебные
  /// direct/block/dns/api. Битый ввод → нули.
  static XrayTrafficSnapshot sumStatsQuery(String stdout) {
    try {
      final decoded = jsonDecode(stdout);
      final stat = (decoded is Map && decoded['stat'] is List)
          ? decoded['stat'] as List
          : const [];

      final re = RegExp(r'^outbound>>>(.+?)>>>traffic>>>(uplink|downlink)$');
      const skip = {'direct', 'block', 'dns', 'api'};
      int up = 0, down = 0;
      for (final entry in stat) {
        if (entry is! Map) continue;
        final name = entry['name']?.toString() ?? '';
        final m = re.firstMatch(name);
        if (m == null) continue;
        final tag = m.group(1)!;
        if (skip.contains(tag)) continue;
        final value = int.tryParse(entry['value']?.toString() ?? '0') ?? 0;
        if (m.group(2) == 'uplink') {
          up += value;
        } else {
          down += value;
        }
      }
      return XrayTrafficSnapshot(up, down);
    } catch (_) {
      return XrayTrafficSnapshot.zero;
    }
  }
}
