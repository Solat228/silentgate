import 'dart:async';

/// Сторож ВЫХОДОВ раздельного туннелирования — по одному на каждый.
///
/// ⚠️ ЗАЧЕМ ОТДЕЛЬНО ОТ [TunnelHealth]. Тот щупает ОДИН порт — локальный прокси
/// основного туннеля (10809). Выходы (`exit-<id>`, серверы, привязанные к
/// правилам по сайтам и программам) живут внутри того же sing-box и своего
/// порта наружу не имеют. Поэтому смерть выхода в Эстонию не замечал никто:
/// ни строки в журнале, ни переподключения — правило просто переставало
/// работать, а человек считал, что лёг сайт.
///
/// Живой прогон в VM 02.09.2026 показал обратную сторону той же монеты: когда
/// умирает ОСНОВНОЙ туннель, выходы продолжают работать. Значит и здоровье у
/// них раздельное, и считать его надо раздельно.
///
/// ⚠️ ПРИГОВОР ПОСЛЕ [failuresToDeclareDown] ПРОМАХОВ ПОДРЯД, как и у канала.
/// Одиночный промах бывает у любого узла, а переподключение по нему хуже
/// болезни: оно рвёт ВСЕ выходы разом (ядро одно).
class ExitHealth {
  ExitHealth({
    required this.tags,
    required this.probe,
    this.interval = const Duration(seconds: 60),
    this.failuresToDeclareDown = 3,
    this.mainChannelAlive,
  });

  /// Теги outbound-ов выходов (`exit-<fnv32>`), как они лежат в конфиге ядра.
  final List<String> tags;

  /// Проверка одного выхода: `true` — отвечает. В приложении это запрос
  /// `GET /proxies/<tag>/delay` к Clash API туннельного sing-box.
  final Future<bool> Function(String tag) probe;

  final Duration interval;
  final int failuresToDeclareDown;

  /// Жив ли ОСНОВНОЙ канал прямо сейчас. `null` — не спрашиваем.
  ///
  /// ⚠️ ЗАЧЕМ. Выходы живут ВНУТРИ основного туннеля и своего пути наружу не
  /// имеют. Упал туннель — не отвечает ни один выход, и сторож через три такта
  /// объявляет мёртвыми ВСЕ разом, хотя не сломан ни один. Владелец получил
  /// десяток заметок подряд именно так.
  ///
  /// ⚠️ И ПОЧЕМУ ГЕЙТ ЗДЕСЬ, А НЕ У ЗАМЕТКИ. Правило «молчать, если умерли все»
  /// уже есть, но оно лишь ПОДАВЛЯЕТ вывод: счётчики всё равно накручиваются,
  /// выходы остаются помеченными мёртвыми, и после восстановления канала
  /// интерфейс продолжает врать ещё цикл проб. Промах при мёртвом канале не
  /// говорит о выходе НИЧЕГО — его надо не показывать иначе, а не засчитывать.
  final bool Function()? mainChannelAlive;

  /// Промахов подряд и «уже объявлен мёртвым» — на каждый тег свои.
  final Map<String, int> _fails = {};
  final Set<String> _down = {};

  Timer? _timer;
  bool Function()? _aborted;
  Future<void> Function(String tag)? _onDown;
  void Function(String tag, int missed)? _onRecovered;
  bool _armed = false;

  /// Вооружён ли сторож. Пустой список выходов — тикать не по чему.
  bool get isArmed => _armed;

  /// Выходы, считающиеся сейчас мёртвыми (для интерфейса и журнала).
  Set<String> get downTags => {..._down};

  void start({
    required Future<void> Function(String tag) onExitDown,
    void Function(String tag, int missed)? onExitRecovered,
    bool Function()? aborted,
  }) {
    stop();
    if (tags.isEmpty) return;
    _onDown = onExitDown;
    _onRecovered = onExitRecovered;
    _aborted = aborted;
    _armed = true;
    _timer = Timer.periodic(interval, (_) => tick());
  }

  /// Один проход по всем выходам.
  ///
  /// ⚠️ Публичный намеренно: в тестах таймер не крутят (сорок пять секунд на
  /// проверку — не тест), а логику счёта промахов проверить обязательно.
  Future<void> tick() async {
    if (_aborted?.call() ?? false) return;
    // ⚠️ ЗАМИРАЕМ, А НЕ ОБНУЛЯЕМСЯ. Сбрасывать счётчики было бы отдельным
    // дефектом: выход, который действительно умер, получал бы прощение на
    // каждом мигании основного канала и не был бы объявлен мёртвым никогда.
    if (!(mainChannelAlive?.call() ?? true)) return;
    for (final tag in tags) {
      final ok = await probe(tag);
      // Отмена могла случиться ПОКА шла проба: она длится секунды, и за это
      // время пользователь успевает отключиться. Иначе сторож прошлой сессии
      // объявил бы мёртвым выход, которого уже нет.
      if (_aborted?.call() ?? false) return;
      if (ok) {
        if (_down.remove(tag)) {
          _onRecovered?.call(tag, _fails[tag] ?? 0);
        }
        _fails[tag] = 0;
        continue;
      }
      final n = (_fails[tag] ?? 0) + 1;
      _fails[tag] = n;
      // ⚠️ РОВНО ОДИН РАЗ НА СМЕРТЬ. Без этого мёртвый выход бил бы
      // уведомлением каждый такт до конца сессии.
      if (n >= failuresToDeclareDown && _down.add(tag)) {
        await _onDown?.call(tag);
      }
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _armed = false;
    _fails.clear();
    _down.clear();
    _onDown = null;
    _onRecovered = null;
    _aborted = null;
  }
}
