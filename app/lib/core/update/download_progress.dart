/// Ход закачки обновления в байтах: сколько скачано, сколько всего, сколько
/// осталось и примерно за сколько.
///
/// Просьба владельца 12.10.2026: на телефоне вместо одного процента видеть
/// «12,3 из 38,1 МБ, осталось 25,8 МБ, ~20 с» — с обновляющимися цифрами.
/// Процент на медленной мобильной сети стоит на месте минутами, и неясно,
/// идёт закачка или зависла.
class DownloadProgress {
  const DownloadProgress({
    required this.received,
    required this.total,
    this.eta,
  });

  final int received;
  final int total;

  /// Оценка оставшегося времени; `null` — скорость ещё не ясна.
  final Duration? eta;

  int get remaining => total > received ? total - received : 0;

  double get fraction =>
      total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : 0.0;
}

/// Считает [DownloadProgress] по ходу закачки.
///
/// Скорость — средняя от начала, а не мгновенная: мгновенная на мобильной сети
/// прыгает в разы между кусками, и оценка времени скакала бы «~5 с» → «~3 мин»
/// → «~10 с». Средняя сглаживает это сама и не требует подбирать коэффициент.
class DownloadRateMeter {
  DownloadRateMeter({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DateTime? _startedAt;

  /// Сколько ждём, прежде чем называть время: первые куски приходят из буфера
  /// и дают нереальную скорость.
  static const warmUp = Duration(seconds: 1);

  DownloadProgress update(int received, int total) {
    final now = _clock();
    final started = _startedAt ??= now;
    final elapsed = now.difference(started);
    Duration? eta;
    if (elapsed >= warmUp && received > 0 && total > received) {
      final perMs = received / elapsed.inMilliseconds;
      if (perMs > 0) {
        eta = Duration(milliseconds: ((total - received) / perMs).round());
      }
    }
    return DownloadProgress(received: received, total: total, eta: eta);
  }
}
