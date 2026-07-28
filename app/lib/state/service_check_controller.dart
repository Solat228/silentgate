import 'package:flutter/foundation.dart';

import '../core/probe/service_check.dart';
import '../core/settings/app_settings.dart';

/// Хранит результаты живой проверки сервисов у кнопки Connect. Сервисы
/// проверяются ОДИН раз автоматически при подъёме туннеля ([autoCheckAll]),
/// дальше — только вручную (тап по сервису). Результаты привязаны к текущему
/// соединению ([bind]) и сбрасываются при его смене.
class ServiceCheckController extends ChangeNotifier {
  final Map<ProbeService, ServiceCheckOutcome> _results = {};
  String _epoch = '';

  /// Соединение, для которого автопроверка уже отработала. Держим отдельно от
  /// [_results]: результат мог не сохраниться (сервис ответил ошибкой), но
  /// повторять автопрогон всё равно нельзя — дальше только ручные проверки.
  String? _autoRanEpoch;

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
    _autoRanEpoch = null;
    if (_results.isEmpty) return;
    _results.clear();
    notifyListeners();
  }

  /// Единственный автоматический прогон всех [services] — на подъёме туннеля.
  ///
  /// Повторный вызов для того же соединения игнорируется, поэтому перестроение
  /// интерфейса (смена темы, поворот экрана, возврат с другого экрана) не
  /// запускает пробы заново: после первого раза сервисы проверяются только
  /// вручную. Новое соединение = новая [bind]-сигнатура ⇒ прогон повторится.
  Future<void> autoCheckAll(int httpPort, List<ProbeService> services) async {
    if (_epoch.isEmpty || _autoRanEpoch == _epoch) return;
    _autoRanEpoch = _epoch;
    // Параллельно: пробы независимы, а последовательный прогон растянулся бы
    // на десятки секунд (у каждой — таймаут до ~16 с).
    await Future.wait([for (final s in services) check(s, httpPort)]);
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
