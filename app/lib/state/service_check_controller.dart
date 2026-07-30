import 'package:flutter/foundation.dart';

import '../core/probe/service_check.dart';
import '../core/settings/app_settings.dart';

/// Хранит результаты живой проверки сервисов у кнопки Connect. Сервисы
/// проверяются ОДИН раз автоматически при подъёме туннеля ([autoCheckAll]),
/// дальше — только вручную (тап по сервису). Результаты привязаны к текущему
/// соединению ([bind]) и сбрасываются при его смене.
class ServiceCheckController extends ChangeNotifier {
  final Map<ProbeService, ServiceCheckOutcome> _results = {};

  /// Результаты, снятые БЕЗ VPN — чтобы было с чем сравнивать.
  ///
  /// Держатся отдельно и переживают подключение: смысл в том, чтобы
  /// пользователь видел «до» и «после» рядом. Сбрасываются только вручную.
  final Map<ProbeService, ServiceCheckOutcome> _baseline = {};

  ServiceCheckOutcome baselineFor(ProbeService s) =>
      _baseline[s] ?? ServiceCheckOutcome.idle;

  bool get hasBaseline => _baseline.isNotEmpty;
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

  /// Проверить один сервис.
  ///
  /// [httpPort] == 0 — проба идёт НАПРЯМУЮ, мимо VPN: это замер «до», нужный
  /// для сравнения. Результат кладётся в отдельную полку и не смешивается с
  /// замером через туннель, иначе сравнивать было бы не с чем.
  Future<void> check(ProbeService s, int httpPort) async {
    final baseline = httpPort <= 0;
    final store = baseline ? _baseline : _results;
    if (store[s]?.state == ServiceCheckState.checking) return;
    final epoch = _epoch; // к какому соединению относится эта проверка
    store[s] = ServiceCheckOutcome.checking;
    notifyListeners();
    final out = await ServiceChecker.check(httpPort, s);
    // Проба идёт до ~16 с. Если за это время сменили сервер/переподключились
    // ([bind]/[reset]), результат относится к СТАРОМУ выходу — не пишем его.
    // Замера «до» это не касается: он к соединению не привязан.
    if (!baseline && _epoch != epoch) return;
    store[s] = out;
    notifyListeners();
  }

  /// Снять замер «до подключения» — по всем сервисам сразу, напрямую.
  Future<void> checkBaseline(List<ProbeService> services) async {
    await Future.wait([for (final s in services) check(s, 0)]);
  }

  bool _baselineRan = false;

  /// Автоматический замер «до» — один раз за запуск приложения.
  ///
  /// Смысл всей пары «до → после» в сравнении, а сравнивать было не с чем:
  /// замер «до» снимался только вручную, и пользователь видел одинокий кружок
  /// «через VPN», по которому нельзя понять, VPN ли починил сервис или тот и
  /// так работал.
  ///
  /// ⚠️ Вызывать ТОЛЬКО при выключенном VPN. Если туннель уже поднят (например,
  /// приложение подхватило живое соединение при старте), проба уйдёт ЧЕРЕЗ него
  /// и запишется в графу «без VPN» — сравнение станет ложью, причём
  /// правдоподобной.
  ///
  /// Один раз за запуск, а не за экран: возврат с настроек не должен гонять
  /// шесть проб заново.
  Future<void> autoBaseline(List<ProbeService> services) async {
    if (_baselineRan) return;
    _baselineRan = true;
    await checkBaseline(services);
  }
}
