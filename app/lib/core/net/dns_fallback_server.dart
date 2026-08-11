import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../platform/app_log.dart';

/// Локальный DNS-форвардер с ЗАПАСНЫМ резолвером.
///
/// ## Зачем это существует
///
/// При включённом «DNS всех приложений через туннель» имена для ВСЕГО трафика —
/// включая тот, что идёт мимо VPN, — спрашиваются через туннель. Пока туннель
/// здоров, это правильно: провайдер не видит, куда вы ходите. Но стоит
/// туннельному резолверу споткнуться, и без имён остаётся ВСЁ, в том числе
/// прямой трафик, которому VPN вообще не нужен. В журнале ядра это выглядит
/// сотнями строк `dns: exchange failed for … EOF` и
/// `wsarecv: An existing connection was forcibly closed`, а для пользователя —
/// «интернет пропал, хотя VPN подключён».
///
/// ⚠️ САМО ЯДРО ТАК НЕ УМЕЕТ. Проверено настоящим sing-box 1.11.15: поля
/// `address_fallback`, `fallback` и список в `address` отвергаются с
/// `FATAL decode config`. Встроенного запасного резолвера в легаси-формате DNS
/// нет вовсе, поэтому запас приходится держать здесь.
///
/// ## Как устроено
///
/// Слушаем UDP на локальном порту. Ядро ходит сюда напрямую (`detour: direct`),
/// поэтому петли не возникает: запрос к 127.0.0.1 не заворачивается в туннель.
/// Дальше по каждому запросу:
///
///  1. спрашиваем ТУННЕЛЬНЫЙ резолвер — DNS поверх TCP через локальный SOCKS
///     ядра (тот же, куда ходит весь проксируемый трафик);
///  2. не ответил за [tunnelTimeout] или ответил ошибкой — доспрашиваем
///     локальный апстрим напрямую.
///
/// Порядок важен: сначала защищённый путь, локальный — только как запас.
/// Обратный порядок означал бы, что провайдер видит все имена всегда.
class DnsFallbackServer {
  DnsFallbackServer({
    required this.socksPort,
    required this.tunnelDns,
    required this.localDns,
    this.socksUser = '',
    this.socksPassword = '',
    this.tunnelTimeout = const Duration(seconds: 3),
    this.localTimeout = const Duration(seconds: 3),
  });

  /// Локальный SOCKS ядра — через него идёт запрос к туннельному резолверу.
  final int socksPort;

  /// Креды локального SOCKS. Пусто — инбаунд без аутентификации (Windows).
  ///
  /// ⚠️ На Android они ОБЯЗАТЕЛЬНЫ. Loopback там не изолирован между
  /// приложениями, поэтому наш локальный инбаунд закрыт паролем; форвардер без
  /// кредов получил бы отказ на рукопожатии и молча уходил бы в запас на каждом
  /// запросе — то есть весь DNS шёл бы мимо туннеля, а выглядело бы это как
  /// «работает».
  final String socksUser;
  final String socksPassword;

  /// Резолвер, который спрашиваем через туннель (например `1.1.1.1`).
  final String tunnelDns;

  /// Запасной резолвер, доступный напрямую (обычно DNS роутера).
  final String localDns;

  final Duration tunnelTimeout;
  final Duration localTimeout;

  RawDatagramSocket? _socket;

  /// Порт, на котором слушаем. 0 — не запущены.
  int get port => _socket?.port ?? 0;

  bool get isRunning => _socket != null;

  /// Сколько раз туннельный резолвер НЕ ответил и пришлось идти в запас.
  ///
  /// ⚠️ Это «туннель промолчал», а НЕ «запас ответил»: запасной резолвер тоже
  /// может не ответить. Разница важна при разборе — иначе цифра читалась бы
  /// как «столько имён утекло провайдеру», что неверно. Для второго есть
  /// [fallbackAnsweredCount].
  int get fallbackCount => _fallbackCount;
  int _fallbackCount = 0;

  /// Сколько раз запасной резолвер ДЕЙСТВИТЕЛЬНО ответил, то есть столько имён
  /// ушло к провайдеру мимо туннеля.
  int get fallbackAnsweredCount => _fallbackAnswered;
  int _fallbackAnswered = 0;

  /// Сколько запросов обслужено всего.
  int get queryCount => _queryCount;
  int _queryCount = 0;

  Future<void> start() async {
    if (_socket != null) return;
    // Порт назначает система (0): фиксированный номер пришлось бы сверять с
    // обоими ядрами, а на этом в проекте уже горели дважды (10085 и 10809).
    final sock =
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _socket = sock;
    sock.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = sock.receive();
      if (dg == null) return;
      // Обрабатываем каждый запрос отдельно и НЕ ждём его: DNS-запросы идут
      // пачками, и последовательная обработка превратила бы задержку одного
      // в задержку всех.
      unawaited(_handle(sock, dg));
    });
    AppLog.i('Запасной DNS: слушаю 127.0.0.1:${sock.port}, '
        'основной резолвер $tunnelDns через туннель, запасной $localDns');
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
  }

  Future<void> _handle(RawDatagramSocket sock, Datagram dg) async {
    _queryCount++;
    Uint8List? answer;
    try {
      // Таймауты живут ВНУТРИ обоих путей (иначе не закрывались бы сокеты);
      // здесь оставлен внешний предел с запасом — на случай, если внутренний
      // почему-то не сработает. Без запаса он срезал бы честный медленный
      // ответ и уводил в запас там, где туннель просто небыстрый.
      answer = await _askThroughTunnel(dg.data)
          .timeout(tunnelTimeout + const Duration(seconds: 2));
    } catch (_) {
      answer = null;
    }
    if (answer == null) {
      _fallbackCount++;
      try {
        answer = await _askLocal(dg.data)
            .timeout(localTimeout + const Duration(seconds: 2));
      } catch (_) {
        answer = null;
      }
      if (answer != null) _fallbackAnswered++;
    }
    if (answer == null) return; // молчим: клиент переспросит сам
    try {
      sock.send(answer, dg.address, dg.port);
    } catch (_) {
      // Сокет мог закрыться, пока ждали ответ.
    }
  }

  /// DNS поверх TCP через локальный SOCKS ядра.
  ///
  /// TCP, а не UDP: у части серверов UDP через туннель не проксируется вовсе —
  /// ровно та причина, по которой туннельный резолвер в конфиге задан как
  /// `tcp://…`. Формат DNS-over-TCP отличается от UDP двухбайтовой длиной
  /// впереди — её тут и добавляем.
  Future<Uint8List?> _askThroughTunnel(Uint8List query) async {
    Socket? s;
    _ByteReader? reader;
    try {
      s = await Socket.connect(InternetAddress.loopbackIPv4, socksPort,
          timeout: tunnelTimeout);
      // ⚠️ ОДНА ПОДПИСКА НА ВЕСЬ ОБМЕН. `Socket` — поток с ОДНИМ подписчиком:
      // первая версия читала рукопожатие через свой `StreamIterator`, а ответ
      // DNS — отдельным `await for` по тому же сокету. Второй подписчик кидает
      // `Bad state: Stream has already been listened to`, исключение ловилось
      // catch'ем ниже, и туннельный путь НЕ РАБОТАЛ НИКОГДА: каждый запрос
      // молча уходил в запасной резолвер. Снаружи это выглядело бы как
      // «работает», а на деле весь DNS шёл бы мимо туннеля — ровно тот
      // молчаливый отказ, ради которого этот класс и написан.
      reader = _ByteReader(s);
      if (!await _socksHandshake(s, reader, tunnelDns, 53,
          user: socksUser, password: socksPassword)) {
        return null;
      }
      final framed = Uint8List(query.length + 2)
        ..[0] = (query.length >> 8) & 0xff
        ..[1] = query.length & 0xff
        ..setRange(2, query.length + 2, query);
      s.add(framed);
      await s.flush();
      // Длина ответа, затем сам ответ. Таймаут — здесь, а не только у
      // вызывающего: иначе сокет висел бы до конца жизни форвардера.
      final head = await reader.read(2, tunnelTimeout);
      if (head == null) return null;
      final len = (head[0] << 8) | head[1];
      if (len <= 0 || len > 65535) return null;
      final body = await reader.read(len, tunnelTimeout);
      return body == null ? null : Uint8List.fromList(body);
    } catch (_) {
      return null;
    } finally {
      await reader?.cancel();
      try {
        s?.destroy();
      } catch (_) {}
    }
  }

  /// Обычный UDP-запрос к локальному резолверу, мимо туннеля.
  ///
  /// ⚠️ ОТВЕТ ПРОВЕРЯЕТСЯ, А НЕ ПРИНИМАЕТСЯ НА ВЕРУ. Сокет открыт на всех
  /// интерфейсах (иначе не достучаться до роутера), поэтому датаграмму на его
  /// порт может прислать кто угодно. Первая версия брала ПЕРВУЮ пришедшую — то
  /// есть подменить ответ мог любой, кто успеет раньше резолвера, даже не
  /// перехватывая трафик. Поэтому сверяем и отправителя, и идентификатор
  /// запроса (первые два байта DNS-сообщения).
  Future<Uint8List?> _askLocal(Uint8List query) async {
    if (query.length < 2) return null;
    final addr = InternetAddress.tryParse(localDns);
    if (addr == null) return null;
    RawDatagramSocket? s;
    Timer? deadline;
    try {
      // ⚠️ СЕМЕЙСТВО СОКЕТА — ПО АДРЕСУ РЕЗОЛВЕРА. С жёстким `anyIPv4` отправка
      // на IPv6-резолвер падала SocketException, его глотал catch, и функция
      // возвращала null. Наружу это выглядело так: на IPv6-only сети запас
      // молча не отвечал НИ РАЗУ, ни одно имя не резолвилось, а в журнале
      // стояло «ушло к провайдеру 0» — то есть «запас не понадобился».
      // Резолвер физической сети приходит IPv6-адресом штатно: и Android, и
      // Windows лишь СОРТИРУЮТ IPv4 вперёд, но отдают IPv6, когда IPv4 нет.
      s = await RawDatagramSocket.bind(
          addr.type == InternetAddressType.IPv6
              ? InternetAddress.anyIPv6
              : InternetAddress.anyIPv4,
          0);
      final done = Completer<Uint8List?>();
      final sock = s;
      sock.listen((e) {
        if (e != RawSocketEvent.read) return;
        final dg = sock.receive();
        if (dg == null || done.isCompleted) return;
        if (dg.address.address != addr.address) return; // не тот отправитель
        if (dg.port != 53) return; // ответ обязан прийти с порта резолвера
        if (dg.data.length < 2) return;
        if (dg.data[0] != query[0] || dg.data[1] != query[1]) return; // чужой id
        done.complete(Uint8List.fromList(dg.data));
      }, onError: (_) {
        if (!done.isCompleted) done.complete(null);
      });
      // ⚠️ Таймаут ВНУТРИ, а не только у вызывающего. Раньше `.timeout` стоял
      // снаружи, и при его срабатывании `finally` здесь не выполнялся никогда:
      // UDP-сокет и подписка жили до конца процесса. На каждом неудачном
      // запросе — по сокету; за час активного серфинга это тысячи.
      deadline = Timer(localTimeout, () {
        if (!done.isCompleted) done.complete(null);
      });
      sock.send(query, addr, 53);
      return await done.future;
    } catch (_) {
      return null;
    } finally {
      deadline?.cancel();
      s?.close();
    }
  }

  /// SOCKS5 без аутентификации: приветствие и CONNECT по адресу-строке.
  ///
  /// Адрес отправляем ДОМЕНОМ/строкой в формате ATYP=1 (IPv4), потому что
  /// туннельный резолвер у нас всегда задан адресом — разбирать доменные имена
  /// здесь не нужно и незачем усложнять.
  Future<bool> _socksHandshake(
      Socket s, _ByteReader reader, String host, int port,
      {String user = '', String password = ''}) async {
    final ip = InternetAddress.tryParse(host);
    if (ip == null || ip.type != InternetAddressType.IPv4) return false;

    // Предлагаем обе схемы, если есть креды: часть инбаундов принимает только
    // ту, что настроена, и лишний вариант в списке не мешает.
    final withAuth = user.isNotEmpty;
    s.add(withAuth ? [0x05, 0x02, 0x00, 0x02] : [0x05, 0x01, 0x00]);
    await s.flush();
    final greet = await reader.read(2, tunnelTimeout);
    if (greet == null || greet[0] != 0x05) return false;

    if (greet[1] == 0x02) {
      if (!withAuth) return false;
      final u = utf8.encode(user);
      final p = utf8.encode(password);
      if (u.length > 255 || p.length > 255) return false;
      // RFC 1929: версия подпереговоров = 1, затем длина и байты логина/пароля.
      s.add([0x01, u.length, ...u, p.length, ...p]);
      await s.flush();
      final ok = await reader.read(2, tunnelTimeout);
      if (ok == null || ok[1] != 0x00) return false;
    } else if (greet[1] != 0x00) {
      return false; // сервер не принял ни одной предложенной схемы
    }

    s.add([0x05, 0x01, 0x00, 0x01, ...ip.rawAddress, (port >> 8) & 0xff, port & 0xff]);
    await s.flush();
    // Ответ CONNECT: заголовок 4 байта, затем адрес по типу и 2 байта порта.
    // Разбираем по типу, а не фиксированной длиной: для ATYP=3 (домен) длина
    // переменная, и жёсткие 10 байт «съели» бы часть ответа DNS.
    final head = await reader.read(4, tunnelTimeout);
    if (head == null || head[1] != 0x00) return false;
    final int addrLen;
    switch (head[3]) {
      case 0x01:
        addrLen = 4;
        break;
      case 0x04:
        addrLen = 16;
        break;
      case 0x03:
        final n = await reader.read(1, tunnelTimeout);
        if (n == null) return false;
        addrLen = n[0];
        break;
      default:
        return false;
    }
    return await reader.read(addrLen + 2, tunnelTimeout) != null;
  }
}

/// Побайтовое чтение из сокета с ОДНОЙ подпиской и таймаутом на каждое чтение.
///
/// ⚠️ ЗАЧЕМ ОТДЕЛЬНЫЙ КЛАСС. `Socket` в Dart — поток с ОДНИМ подписчиком.
/// Рукопожатие SOCKS и чтение ответа DNS — это два последовательных чтения из
/// одного сокета, и подписаться на него дважды нельзя: второй `listen` кидает
/// `Bad state: Stream has already been listened to`. В первой версии это
/// исключение молча ловилось, и туннельный путь не работал НИКОГДА — каждый
/// запрос уходил в запасной резолвер, то есть весь DNS шёл мимо туннеля, а
/// снаружи всё выглядело исправным. Один подписчик на весь обмен снимает
/// вопрос по построению.
class _ByteReader {
  _ByteReader(Stream<List<int>> stream) {
    _sub = stream.listen(
      (chunk) {
        _buf.addAll(chunk);
        _wake();
      },
      onError: (_) {
        _closed = true;
        _wake();
      },
      onDone: () {
        _closed = true;
        _wake();
      },
      cancelOnError: true,
    );
  }

  late final StreamSubscription<List<int>> _sub;
  final List<int> _buf = [];
  bool _closed = false;
  Completer<void>? _waiter;

  void _wake() {
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  /// Ровно [want] байт, либо null — поток кончился или вышло время.
  ///
  /// Остаток сохраняется между вызовами: байты рукопожатия и начало ответа DNS
  /// часто приезжают одним пакетом, и «добирать заново» означало бы терять их.
  Future<List<int>?> read(int want, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_buf.length < want) {
      if (_closed) return null;
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) return null;
      final w = Completer<void>();
      _waiter = w;
      try {
        await w.future.timeout(left);
      } on TimeoutException {
        _waiter = null;
        return null;
      }
    }
    final out = _buf.sublist(0, want);
    _buf.removeRange(0, want);
    return out;
  }

  Future<void> cancel() async {
    _wake();
    try {
      await _sub.cancel();
    } catch (_) {}
  }
}
