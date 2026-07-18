import 'package:flutter/foundation.dart';

import '../core/probe/service_check.dart';
import '../core/settings/app_settings.dart';

/// Хранит результаты живой проверки сервисов у кнопки Connect. Проверка —
/// ТОЛЬКО вручную (тап по сервису) и только при активном VPN. Результаты
/// привязаны к текущему соединению ([bind]) и сбрасываются при его смене.
class ServiceCheckController extends ChangeNotifier {
  final Map<ProbeService, ServiceCheckOutcome> _results = {};
  String _epoch = '';

  ServiceCheckOutcome resultFor(ProbeService s) =>
      _results[s] ?? ServiceCheckOutcome.idle;

  bool get anyChecking =>
      _results.values.any((o) => o.state == ServiceCheckState.checking);

  /// Привязать к текущему соединению. Иная сигнатура (сменили сервер/переподключились)
  /// сбрасывает прежние результаты — они относятся к старому выходу.
  void bind(String epoch) {
    if (epoch == _epoch) return;
    _epoch = epoch;
    if (_results.isNotEmpty) {
      _results.clear();
      notifyListeners();
    }
  }

  void reset() {
    _epoch = '';
    if (_results.isEmpty) return;
    _results.clear();
    notifyListeners();
  }

  /// Проверить один сервис через активный http-прокси уже поднятого VPN.
  Future<void> check(ProbeService s, int httpPort) async {
    if (resultFor(s).state == ServiceCheckState.checking) return;
    final epoch = _epoch; // к какому соединению относится эта проверка
    _results[s] = ServiceCheckOutcome.checking;
    notifyListeners();
    final out = await ServiceChecker.check(httpPort, s);
    // Проба идёт до ~16 с. Если за это время сменили сервер/переподключились
    // ([bind]/[reset]), результат относится к СТАРОМУ выходу — не пишем его.
    if (_epoch != epoch) return;
    _results[s] = out;
    notifyListeners();
  }
}
