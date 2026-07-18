import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Автообновление подписки:
///  1) полная переустановка по интервалу панели (profile-update-interval, по умолч. 12ч);
///  2) поллинг version-эндпоинта сайта — при смене version подписка обновляется сразу.
///
/// Формат version-эндпоинта (реализовать на сайте): GET → `{"version":"<str>","message":"<опц.>"}`.
class SubscriptionUpdater {
  final Future<void> Function() onRefresh;
  final void Function(String message)? onMessage;
  final String versionUrl;

  Timer? _intervalTimer;
  Timer? _versionTimer;
  String? _lastVersion;

  SubscriptionUpdater({
    required this.onRefresh,
    this.onMessage,
    this.versionUrl = 'https://silentgate.lol/api/version',
  });

  void start({required int intervalHours}) {
    stop();
    final interval = Duration(hours: intervalHours <= 0 ? 12 : intervalHours);
    _intervalTimer = Timer.periodic(interval, (_) => onRefresh());
    _versionTimer =
        Timer.periodic(const Duration(minutes: 10), (_) => _checkVersion());
    _checkVersion();
  }

  Future<void> _checkVersion() async {
    try {
      final r =
          await http.get(Uri.parse(versionUrl)).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final data = jsonDecode(r.body);
      if (data is! Map) return;
      final version = '${data['version'] ?? ''}';
      if (version.isEmpty) return;
      if (_lastVersion != null && version != _lastVersion) {
        await onRefresh();
        final msg = '${data['message'] ?? ''}';
        if (msg.isNotEmpty) onMessage?.call(msg);
      }
      _lastVersion = version;
    } catch (_) {
      // сайт недоступен — интервальное обновление продолжает работать
    }
  }

  void stop() {
    _intervalTimer?.cancel();
    _intervalTimer = null;
    _versionTimer?.cancel();
    _versionTimer = null;
  }
}
