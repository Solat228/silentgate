import 'dart:async';
import 'dart:io';

/// Объём пробы. Трафик расходуется из подписки, поэтому размер выбирает пользователь.
enum SpeedTestSize {
  /// ~5 МБ: дёшево, годится прогнать много серверов подряд; на быстрых каналах
  /// не успевает разогнаться и занижает результат.
  light,

  /// ~20 МБ: основной режим, точнее на 100+ Мбит/с.
  full,
}

extension SpeedTestSizeInfo on SpeedTestSize {
  int get bytes => this == SpeedTestSize.full ? 20000000 : 5000000;
  String get label => this == SpeedTestSize.full ? '20 МБ' : '5 МБ';
}

class SpeedResult {
  /// Скорость скачивания, бит/с.
  final double bitsPerSecond;
  final int bytes;
  final Duration elapsed;
  final String? error;

  const SpeedResult({
    required this.bitsPerSecond,
    required this.bytes,
    required this.elapsed,
    this.error,
  });

  const SpeedResult.failed(String message)
      : bitsPerSecond = 0,
        bytes = 0,
        elapsed = Duration.zero,
        error = message;

  bool get ok => error == null && bitsPerSecond > 0;

  /// Скорость в БАЙТАХ — так же, как её показывают браузеры и торренты,
  /// и так же, как считается расход трафика подписки. Мегабиты не показываем.
  double get bytesPerSecond => bitsPerSecond / 8;

  /// «10.9 МБ/с» / «870 КБ/с».
  String get label {
    if (!ok) return '—';
    final mbs = bytesPerSecond / 1000000;
    if (mbs >= 1) return '${mbs.toStringAsFixed(1)} МБ/с';
    return '${(bytesPerSecond / 1000).toStringAsFixed(0)} КБ/с';
  }
}

/// Замер скорости скачивания — напрямую или через локальный прокси сервера.
///
/// Запускается ТОЛЬКО вручную: проба реально качает данные и расходует трафик
/// подписки. Источник — Cloudflare (отдаёт ровно запрошенный объём).
class SpeedTest {
  static const _endpoint = 'https://speed.cloudflare.com/__down?bytes=';

  /// [proxyPort] — локальный http-прокси харнесса; null = мимо VPN.
  static Future<SpeedResult> download({
    required SpeedTestSize size,
    int? proxyPort,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    if (proxyPort != null) {
      client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    }
    final sw = Stopwatch();
    try {
      final req = await client
          .getUrl(Uri.parse('$_endpoint${size.bytes}'))
          .timeout(timeout);
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) {
        return SpeedResult.failed('Сервер замера ответил ${resp.statusCode}');
      }

      // Время считаем с первого байта: TCP/TLS-рукопожатие к скорости не относится.
      var received = 0;
      await for (final chunk in resp.timeout(timeout)) {
        if (!sw.isRunning) sw.start();
        received += chunk.length;
      }
      sw.stop();

      final seconds = sw.elapsedMicroseconds / 1000000;
      if (received == 0 || seconds <= 0) {
        return const SpeedResult.failed('Данные не получены');
      }
      return SpeedResult(
        bitsPerSecond: received * 8 / seconds,
        bytes: received,
        elapsed: sw.elapsed,
      );
    } on TimeoutException {
      return const SpeedResult.failed('Таймаут — канал слишком медленный');
    } catch (e) {
      return SpeedResult.failed('$e');
    } finally {
      client.close(force: true);
    }
  }
}
