/// Накопленный трафик и мгновенная скорость (байт/сек) по outbound "proxy".
class TrafficStats {
  final int uplinkBytes;
  final int downlinkBytes;
  final int uplinkSpeed; // байт/сек
  final int downlinkSpeed; // байт/сек

  const TrafficStats({
    this.uplinkBytes = 0,
    this.downlinkBytes = 0,
    this.uplinkSpeed = 0,
    this.downlinkSpeed = 0,
  });

  static const zero = TrafficStats();

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    double v = bytes / 1024;
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
  }

  static String formatSpeed(int bytesPerSec) => '${formatBytes(bytesPerSec)}/s';
}
