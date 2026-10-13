import 'dart:async';
import 'dart:io';

/// Сквозная проверка КАНАЛА: реально ли через туннель проходит трафик.
///
/// ## Зачем это существует — и чем отличается от сторожа зависания
///
/// Сторож туннеля спрашивает у ядра «ты отвечаешь по своему API?». Это проверка
/// ПРОЦЕССА: порт слушает, ядро живо. Но ядро прекрасно отвечает на свой API и
/// при этом может не пропускать НИ БАЙТА — отвалился сервер, умерла TLS-сессия,
/// сломался маршрут. Снаружи это выглядит как «Подключено» и мёртвый интернет,
/// а в журнале приложения — тишина.
///
/// ⚠️ Ровно это и случилось у владельца 08.08.2026: между «сторож вооружён» в
/// 13:44 и отчётом в 19:52 приложение не записало ничего, потому что ядро всё
/// это время исправно отвечало по API. Отказ прошёл мимо нас целиком.
///
/// Здесь задаётся ДРУГОЙ вопрос: доходит ли запрос до внешнего адреса ЧЕРЕЗ
/// локальный прокси-порт ядра — то есть тем же путём, которым идёт трафик
/// пользователя.
///
/// ## Почему несколько неудач подряд, а не одна
///
/// Одиночный сбой — норма: сеть моргнула, сервер отбросил соединение, мишень
/// прилегла. Реагировать на него значит переподключаться по пустякам, а каждое
/// переподключение рвёт ВСЕ живые TCP-сессии пользователя. Поэтому канал
/// считается мёртвым только после [failuresToDeclareDown] промахов подряд.
class TunnelHealth {
  TunnelHealth({
    required this.proxyPort,
    this.proxyUser = '',
    this.proxyPassword = '',
    this.interval = const Duration(seconds: 45),
    this.timeout = const Duration(seconds: 8),
    Duration suspectInterval = const Duration(seconds: 5),
    this.suspectTimeout = const Duration(seconds: 4),
    this.failuresToDeclareDown = 3,
    this.targets = const [
      // ⚠️ МИШЕНИ РАЗНЫХ ВЛАДЕЛЬЦЕВ И БЕЗ ТЕЛА ОТВЕТА.
      //
      // Одна мишень означала бы, что её плановые работы мы примем за смерть
      // канала. Все отдают 204 без содержимого — это десятки байт на проверку,
      // то есть на мобильном тарифе цена незаметна.
      'http://cp.cloudflare.com/generate_204',
      'http://www.gstatic.com/generate_204',
      // ⚠️ ПОСЛЕДНЯЯ — ПО «ГОЛОМУ» АДРЕСУ, БЕЗ ИМЕНИ. И это не запасная копия
      // предыдущих, а ЕДИНСТВЕННЫЙ способ отличить две разные беды.
      //
      // Проба идёт через локальный порт ядра, а значит имя мишени резолвит САМО
      // ЯДРО туннельным DNS. Пока все мишени заданы именами, «канал не
      // пропускает трафик» и «в туннеле сломался DNS» выглядят одинаково —
      // приложение переподключается, хотя транспорт исправен, и человек
      // получает разрыв на ровном месте. У владельца такие циклы шли по шесть
      // раз за ночь с периодом ровно в три минуты (`docs/BACKLOG.md` #31).
      //
      // 1.1.1.1 отвечает 204 на этот путь и не требует резолва вовсе.
      'http://1.1.1.1/generate_204',
    ],
  }) : suspectInterval =
            suspectInterval < interval ? suspectInterval : interval;

  /// Локальный HTTP-порт ядра — тот же, через который ходит трафик.
  final int proxyPort;

  /// Креды локального прокси. Пусто — инбаунд без аутентификации.
  ///
  /// ⚠️ БЕЗ НИХ ПРОВЕРКА ДЕЛАЕТ ХУЖЕ, ЧЕМ ЕЁ ОТСУТСТВИЕ. С тех пор как пароль
  /// на локальных прокси ставится по умолчанию, инбаунд отвечает `407 Proxy
  /// Authentication Required`. `HttpClient.findProxy` креды сам НЕ передаёт,
  /// поэтому проба падала бы всегда — три промаха подряд, и приложение
  /// переподключалось бы по кругу на СОВЕРШЕННО ИСПРАВНОМ туннеле. То есть
  /// сторож, поставленный ловить обрывы, сам стал бы их источником.
  final String proxyUser;
  final String proxyPassword;

  final Duration interval;
  final Duration timeout;

  /// Пауза между пробами после первого промаха.
  ///
  /// ⚠️ ЗАЧЕМ ОТДЕЛЬНО ОТ [interval]. Раньше все пробы шли раз в 45 секунд, и
  /// приговор выносился после трёх промахов — до двух с половиной минут.
  /// Владелец 13.10.2026 выдернул кабель из роутера и не увидел ничего: короткий
  /// обрыв не попадал в окно вовсе, а длинный замечался, когда человек уже сам
  /// всё понял. Решение владельца: после первого промаха проверять каждые
  /// 5 секунд, итог — около 15 секунд. Пока канал исправен, проба по-прежнему
  /// раз в 45 секунд: частить на живом канале значит будить радио телефона
  /// без повода.
  ///
  /// Не больше [interval]: тесты задают его миллисекундами, и пауза «после
  /// промаха» длиннее обычной ломала бы им время.
  final Duration suspectInterval;

  /// Таймаут мишени после первого промаха — короче обычного, иначе пять
  /// секунд паузы терялись бы на фоне восьми секунд ожидания.
  final Duration suspectTimeout;

  final int failuresToDeclareDown;
  final List<String> targets;

  Timer? _timer;
  int _fails = 0;
  bool _busy = false;

  /// Сколько промахов подряд накопилось. 0 — последняя проба удалась.
  int get consecutiveFailures => _fails;

  bool get isRunning => _timer != null;

  /// Запустить наблюдение.
  ///
  /// [onDown] зовётся ОДИН раз на серию: канал уже признан мёртвым, и звать
  /// повторно каждые 45 секунд значило бы устраивать шторм переподключений.
  /// [onRecovered] — когда проба снова прошла после промахов, но до объявления
  /// смерти: это ровно тот случай, о котором стоит сказать в журнале, а
  /// дёргать соединение не надо.
  ///
  /// [onOk] — на КАЖДУЮ удачную пробу. Движку нужно знать, что канал этой
  /// сессии хоть раз пропустил трафик: только тогда провал пробы после
  /// восстановления — довод, а не особенность мишеней (см.
  /// `VpnEngineBase.confirmRecoveredChannel`).
  void start({
    required Future<void> Function() onDown,
    void Function(int missed)? onRecovered,
    void Function()? onOk,
    bool Function()? aborted,
  }) {
    stop();
    _fails = 0;
    // ⚠️ ОДНОРАЗОВЫЙ ТАЙМЕР, ЗАВОДИМЫЙ ЗАНОВО, А НЕ `Timer.periodic`. Пауза
    // теперь зависит от исхода прошлой пробы (45 с на живом канале, 5 с после
    // промаха), а у периодического таймера её не поменять. Заодно пробы не
    // могут наложиться: следующая заводится только после конца предыдущей.
    late void Function(Duration) schedule;
    var alive = true;
    void halt() {
      alive = false;
      _timer = null;
    }

    Future<void> tick() async {
      if (aborted?.call() ?? false) {
        halt();
        return;
      }
      if (_busy) {
        schedule(_nextPause);
        return;
      }
      _busy = true;
      try {
        if (await probeOnce()) {
          final missed = _fails;
          _fails = 0;
          onOk?.call();
          if (missed > 0) onRecovered?.call(missed);
        } else {
          _fails++;
          if (_fails >= failuresToDeclareDown) {
            halt();
            await onDown();
            return;
          }
        }
      } finally {
        _busy = false;
      }
      // Пока шла проба, сторож могли остановить или перезапустить — тогда в
      // поле уже чужой таймер, и заводить свой поверх него нельзя.
      if (alive && identical(_owner, schedule)) schedule(_nextPause);
    }

    schedule = (pause) {
      if (!alive) return;
      _timer = Timer(pause, () => unawaited(tick()));
    };
    _owner = schedule;
    schedule(interval);
  }

  /// Чей цикл сейчас владеет [_timer]: перезапуск [start] меняет владельца, и
  /// проба прошлого цикла, досчитавшись, свой таймер уже не заводит.
  Object? _owner;

  Duration get _nextPause => _fails > 0 ? suspectInterval : interval;

  void stop() {
    _timer?.cancel();
    _timer = null;
    _owner = null;
  }

  /// Считать канал подозрительным: дальше [probeOnce] спрашивает все мишени
  /// разом и с коротким таймаутом.
  ///
  /// Нужен ожиданию сети в движке: оно зовёт пробу каждые 5 секунд, и
  /// обычная проба (одна мишень, 8 секунд) не уложилась бы в этот шаг.
  void markSuspect() {
    if (_fails == 0) _fails = 1;
  }

  /// Одна проба: успех, если ХОТЯ БЫ одна мишень ответила.
  ///
  /// На живом канале сначала спрашиваем ОДНУ мишень: она отвечает за доли
  /// секунды, и платить тремя запросами за тот же ответ незачем. Не ответила —
  /// остальные спрашиваются разом.
  ///
  /// ⚠️ ПОСЛЕ ПРОМАХА — ВСЕ МИШЕНИ СРАЗУ И С КОРОТКИМ ТАЙМАУТОМ. По очереди
  /// мёртвый канал отвечал бы молчанием 3 × 8 = 24 секунды на пробу, и
  /// «нет интернета за 15 секунд» было бы недостижимо при любой паузе.
  Future<bool> probeOnce() => _probe(suspect: _fails > 0);

  /// Проба «под подозрением» вне очереди: все мишени разом, короткий
  /// таймаут, счётчик промахов не трогается.
  ///
  /// Зовёт её движок, когда пропал прямой интернет (`NetworkLossWatch`):
  /// ждать очередной пробы до 45 секунд незачем, а записать промах в счёт
  /// нельзя — у таймера сторожа может идти своя проба.
  Future<bool> probeNow() => _probe(suspect: true);

  Future<bool> _probe({required bool suspect}) async {
    final wait = suspect ? suspectTimeout : timeout;
    final first = suspect ? <String>[] : targets.take(1).toList();
    for (final url in first) {
      if (await _get(url, wait)) {
        _lastOkTarget = url;
        return true;
      }
    }
    final rest = targets.skip(first.length).toList();
    final ok = await firstSuccess(rest, (url) => _get(url, wait));
    _lastOkTarget = ok ?? '';
    return ok != null;
  }

  /// Первый из [items], для которого [check] ответил `true`, — проверки идут
  /// разом. `null` — не ответил никто.
  ///
  /// Ждать остальных после первого успеха незачем: ответ «канал жив» уже есть.
  static Future<String?> firstSuccess(
      List<String> items, Future<bool> Function(String) check) {
    if (items.isEmpty) return Future.value(null);
    final done = Completer<String?>();
    var left = items.length;
    for (final item in items) {
      check(item).then((ok) {
        if (ok && !done.isCompleted) done.complete(item);
      }, onError: (_) {}).whenComplete(() {
        left--;
        if (left == 0 && !done.isCompleted) done.complete(null);
      });
    }
    return done.future;
  }

  /// Мишень, ответившая последней. Пусто — не ответил никто.
  ///
  /// ⚠️ НУЖНО ДЛЯ РАЗБОРА, А НЕ ДЛЯ КРАСОТЫ. Если отвечает только мишень по
  /// адресу, а по именам — нет, значит транспорт жив и сломан именно DNS в
  /// туннеле. Без этой различалки обе беды пишутся в журнал одной строкой, и
  /// причину ищут не там.
  String get lastOkTarget => _lastOkTarget;
  String _lastOkTarget = '';

  /// Работает ли ХОТЬ ЧТО-ТО по имени: отдельная проба именно резолва.
  ///
  /// Зовётся только в момент приговора — платить за неё на каждом такте
  /// незачем.
  Future<bool> nameResolutionWorks() async {
    for (final url in targets) {
      if (Uri.parse(url).host.contains(RegExp(r'[a-zA-Z]')) &&
          await _get(url, timeout)) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _get(String url, Duration timeout) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = timeout
        // Идём ЧЕРЕЗ локальный порт ядра — иначе проверялась бы обычная сеть
        // машины, а не туннель, и смысл пробы терялся бы полностью.
        ..findProxy = ((_) => 'PROXY 127.0.0.1:$proxyPort')
        ..userAgent = null;
      if (proxyUser.isNotEmpty) {
        final creds = HttpClientBasicCredentials(proxyUser, proxyPassword);
        // Оба пути сразу: заранее заданные креды покрывают обычный случай, а
        // колбэк — когда инбаунд объявляет realm, под который заготовка не
        // подошла. Лишним ни один не бывает: без креды ответ 407, и проба
        // объявила бы исправный туннель мёртвым.
        client.addProxyCredentials('127.0.0.1', proxyPort, '', creds);
        client.authenticateProxy = (host, port, scheme, realm) {
          client!.addProxyCredentials(host, port, realm ?? '', creds);
          return Future.value(true);
        };
      }
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final res = await req.close().timeout(timeout);
      await res.drain<void>().timeout(timeout);
      // 204 — ожидаемый ответ мишени. Прочие коды 2xx/3xx тоже означают, что
      // канал жив: важен факт ответа, а не его содержимое.
      return res.statusCode >= 200 && res.statusCode < 400;
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }
}
