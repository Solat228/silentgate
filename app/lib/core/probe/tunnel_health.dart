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
  });

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
  void start({
    required Future<void> Function() onDown,
    void Function(int missed)? onRecovered,
    bool Function()? aborted,
  }) {
    stop();
    _fails = 0;
    _timer = Timer.periodic(interval, (t) async {
      if (aborted?.call() ?? false) {
        t.cancel();
        _timer = null;
        return;
      }
      // Таймер не сериализует асинхронные колбэки: без этого флага при
      // медленной сети пробы наложились бы одна на другую и счётчик промахов
      // рос бы вдвое быстрее реального.
      if (_busy) return;
      _busy = true;
      try {
        if (await probeOnce()) {
          final missed = _fails;
          _fails = 0;
          if (missed > 0) onRecovered?.call(missed);
          return;
        }
        _fails++;
        if (_fails < failuresToDeclareDown) return;
        t.cancel();
        _timer = null;
        await onDown();
      } finally {
        _busy = false;
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Одна проба: успех, если ХОТЯ БЫ одна мишень ответила.
  ///
  /// Мишени перебираются по очереди, а не разом: цель — понять, жив ли канал, и
  /// первого успеха для этого достаточно. Параллельный запрос ко всем трём
  /// стоил бы втрое дороже ради того же ответа.
  Future<bool> probeOnce() async {
    for (final url in targets) {
      if (await _get(url)) {
        _lastOkTarget = url;
        return true;
      }
    }
    _lastOkTarget = '';
    return false;
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
          await _get(url)) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _get(String url) async {
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
