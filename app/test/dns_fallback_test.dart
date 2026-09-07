import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/dns_fallback_server.dart';

/// Запасной резолвер: туннельный основной, локальный — на случай его отказа.
///
/// ⚠️ ЗАЧЕМ ЭТО ВООБЩЕ ПОНАДОБИЛОСЬ. Само ядро так не умеет — проверено
/// настоящим sing-box 1.11.15: `address_fallback`, `fallback` и список в
/// `address` отвергаются с `FATAL decode config`. Значит запас держим мы, и
/// значит его надо стеречь тестами: молчаливо неработающий запас хуже, чем его
/// отсутствие — на него будут рассчитывать.
void main() {
  /// Минимальный DNS-ответ: копируем идентификатор запроса и метим ответом.
  /// Настоящий разбор пакета здесь не нужен — проверяем МАРШРУТ запроса, а не
  /// умение готовить DNS.
  Uint8List reply(Uint8List query, {int marker = 0xAA}) {
    final out = Uint8List(query.length + 1);
    out.setRange(0, query.length, query);
    out[2] = 0x81; // QR=1
    out[query.length] = marker; // метка «кто ответил»
    return out;
  }

  /// Поддельный локальный резолвер на UDP.
  Future<({RawDatagramSocket sock, int port})> fakeLocal(int marker) async {
    final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((e) {
      if (e != RawSocketEvent.read) return;
      final dg = s.receive();
      if (dg == null) return;
      s.send(reply(dg.data, marker: marker), dg.address, dg.port);
    });
    return (sock: s, port: s.port);
  }

  /// Отправить запрос форвардеру и дождаться ответа.
  Future<Uint8List?> ask(int port, Uint8List query,
      {Duration timeout = const Duration(seconds: 6)}) async {
    final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final done = Completer<Uint8List?>();
    s.listen((e) {
      if (e != RawSocketEvent.read) return;
      final dg = s.receive();
      if (dg != null && !done.isCompleted) done.complete(dg.data);
    });
    s.send(query, InternetAddress.loopbackIPv4, port);
    try {
      return await done.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      s.close();
    }
  }

  final query = Uint8List.fromList([0x12, 0x34, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]);

  /// Поддельный SOCKS5-сервер, который «резолвит» сам: принимает рукопожатие,
  /// CONNECT и отвечает на DNS-over-TCP заранее заданной меткой.
  ///
  /// ⚠️ ЭТОТ ТЕСТ ПОЯВИЛСЯ ПОТОМУ, ЧТО ПЕРВЫЕ ПЯТЬ НИЧЕГО НЕ ЛОВИЛИ.
  /// Они проверяли только путь ОТКАЗА, поэтому не заметили дефекта, из-за
  /// которого туннельный путь не работал НИКОГДА: `Socket` в Dart — поток с
  /// одним подписчиком, а код подписывался на него дважды. Исключение
  /// проглатывалось, и каждый запрос молча уходил в запас — то есть весь DNS
  /// шёл мимо туннеля, а тесты были зелёными. Проверять надо УСПЕХ, иначе
  /// «запас» незаметно превращается в «всегда запас».
  Future<({ServerSocket sock, int port})> fakeSocks({
    required int marker,
    String user = '',
    String password = '',
  }) async {
    final srv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((client) async {
      final chunks = StreamIterator<List<int>>(client);
      final buf = <int>[];
      Future<List<int>?> take(int n) async {
        while (buf.length < n) {
          if (!await chunks.moveNext()) return null;
          buf.addAll(chunks.current);
        }
        final out = buf.sublist(0, n);
        buf.removeRange(0, n);
        return out;
      }

      final greet = await take(2);
      if (greet == null) return;
      final methods = await take(greet[1]);
      if (methods == null) return;
      final wantAuth = user.isNotEmpty;
      client.add([0x05, wantAuth ? 0x02 : 0x00]);
      if (wantAuth) {
        final head = await take(2);
        if (head == null) return;
        final u = await take(head[1]);
        final plen = await take(1);
        if (u == null || plen == null) return;
        final p = await take(plen[0]);
        if (p == null) return;
        final ok = utf8.decode(u) == user && utf8.decode(p) == password;
        client.add([0x01, ok ? 0x00 : 0x01]);
        if (!ok) return;
      }
      // CONNECT: заголовок + IPv4 + порт.
      final req = await take(10);
      if (req == null) return;
      client.add([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      // Запрос DNS: два байта длины, затем сообщение.
      final lenBytes = await take(2);
      if (lenBytes == null) return;
      final q = await take((lenBytes[0] << 8) | lenBytes[1]);
      if (q == null) return;
      final answer = reply(Uint8List.fromList(q), marker: marker);
      client.add([(answer.length >> 8) & 0xff, answer.length & 0xff, ...answer]);
      await client.flush();
    });
    return (sock: srv, port: srv.port);
  }

  group('Туннельный путь РАБОТАЕТ (а не только запас)', () {
    test('ответ приходит через туннель, запас не трогается', () async {
      final socks = await fakeSocks(marker: 0x77);
      final srv = DnsFallbackServer(
        socksPort: socks.port,
        tunnelDns: '1.1.1.1',
        localDns: '127.0.0.1',
        tunnelTimeout: const Duration(seconds: 3),
      );
      await srv.start();
      addTearDown(() async {
        await srv.stop();
        await socks.sock.close();
      });

      final answer = await ask(srv.port, query);
      expect(answer, isNotNull, reason: 'туннельный путь обязан отвечать');
      expect(answer!.last, 0x77, reason: 'ответ пришёл НЕ от туннеля');
      expect(srv.fallbackCount, 0,
          reason: 'запас сработал там, где туннель был исправен — значит '
              'туннельный путь молча не работает');
    });

    test('SOCKS с паролем: креды доезжают', () async {
      // На Android локальный инбаунд закрыт паролем. Без кредов рукопожатие
      // отвергается, и весь DNS ушёл бы мимо туннеля — молча.
      final socks = await fakeSocks(marker: 0x55, user: 'sg', password: 'pw');
      final srv = DnsFallbackServer(
        socksPort: socks.port,
        socksUser: 'sg',
        socksPassword: 'pw',
        tunnelDns: '1.1.1.1',
        localDns: '127.0.0.1',
      );
      await srv.start();
      addTearDown(() async {
        await srv.stop();
        await socks.sock.close();
      });

      final answer = await ask(srv.port, query);
      expect(answer, isNotNull);
      expect(answer!.last, 0x55);
      expect(srv.fallbackCount, 0);
    });

    test('неверный пароль — уходим в запас, а не притворяемся рабочими', () async {
      final socks = await fakeSocks(marker: 0x55, user: 'sg', password: 'pw');
      final srv = DnsFallbackServer(
        socksPort: socks.port,
        socksUser: 'sg',
        socksPassword: 'НЕВЕРНЫЙ',
        tunnelDns: '1.1.1.1',
        localDns: '127.0.0.1',
        tunnelTimeout: const Duration(milliseconds: 700),
        localTimeout: const Duration(milliseconds: 700),
      );
      await srv.start();
      addTearDown(() async {
        await srv.stop();
        await socks.sock.close();
      });

      await ask(srv.port, query, timeout: const Duration(seconds: 4));
      expect(srv.fallbackCount, 1);
    });
  });

  group('Запасной резолвер', () {
    test('туннель мёртв — имя всё равно резолвится локально', () async {
      // Ровно тот случай, из-за которого всё и затевалось: у владельца
      // туннельный резолвер падал сотнями ошибок, и вместе с ним оставался без
      // имён ПРЯМОЙ трафик, которому VPN не нужен вовсе.
      final local = await fakeLocal(0x11);
      // SOCKS-порт, на котором никто не слушает: обращение к туннелю провалится.
      final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = dead.port;
      await dead.close();

      final srv = DnsFallbackServer(
        socksPort: deadPort,
        tunnelDns: '1.1.1.1',
        localDns: '127.0.0.1',
        tunnelTimeout: const Duration(milliseconds: 400),
      );
      await srv.start();
      addTearDown(() async {
        await srv.stop();
        local.sock.close();
      });

      // Локальный резолвер слушает на своём порту, а форвардер ходит на 53 —
      // поэтому проверяем сам факт ухода в запас, а не байты ответа.
      final answer = await ask(srv.port, query,
          timeout: const Duration(seconds: 4));
      expect(srv.queryCount, 1, reason: 'запрос обязан быть учтён');
      expect(srv.fallbackCount, 1,
          reason: 'туннель недоступен — обязаны были уйти в запас');
      expect(answer, anything); // ответа может не быть: настоящий 53 недоступен
    });

    test('порт назначает система, а не мы', () async {
      // Фиксированный номер пришлось бы сверять с ОБОИМИ ядрами — на этом в
      // проекте уже горели дважды (10085 и 10809).
      final srv = DnsFallbackServer(
          socksPort: 1, tunnelDns: '1.1.1.1', localDns: '127.0.0.1');
      await srv.start();
      addTearDown(srv.stop);
      expect(srv.port, greaterThan(0));
      expect(srv.isRunning, isTrue);
    });

    test('повторный start не поднимает второй сокет', () async {
      final srv = DnsFallbackServer(
          socksPort: 1, tunnelDns: '1.1.1.1', localDns: '127.0.0.1');
      await srv.start();
      final first = srv.port;
      await srv.start();
      addTearDown(srv.stop);
      expect(srv.port, first,
          reason: 'второй сокет означал бы утечку порта при переподключении');
    });

    test('после stop порт освобождается', () async {
      final srv = DnsFallbackServer(
          socksPort: 1, tunnelDns: '1.1.1.1', localDns: '127.0.0.1');
      await srv.start();
      final p = srv.port;
      await srv.stop();
      expect(srv.isRunning, isFalse);
      // Порт обязан отдаваться обратно: иначе быстрое «выкл→вкл» упрётся
      // в собственный остаток — ровно та поломка, что была с портами ядра.
      final again = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, p);
      addTearDown(again.close);
      expect(again.port, p);
    });

    test('битый адрес запасного резолвера не роняет форвардер', () async {
      // Пустой или мусорный адрес приходит из настроек и не должен приводить
      // к исключению в обработчике: молчание лучше падения.
      final srv = DnsFallbackServer(
        socksPort: 1,
        tunnelDns: '1.1.1.1',
        localDns: 'не-адрес',
        tunnelTimeout: const Duration(milliseconds: 200),
        localTimeout: const Duration(milliseconds: 200),
      );
      await srv.start();
      addTearDown(srv.stop);
      final answer = await ask(srv.port, query,
          timeout: const Duration(milliseconds: 900));
      expect(answer, isNull);
      expect(srv.isRunning, isTrue, reason: 'форвардер обязан пережить это');
    });
  });

/// ЗАПАСНОЙ ПУТЬ ДЛЯ ПРЯМОГО РЕЗОЛВА (BACKLOG #34).
///
/// ⚠️ ОТКУДА ЗАДАЧА. В журнале клиента, работающего круглосуточно, отказы DNS
/// составляют 65 % всех ошибок ядра (23 261 строка) и к концу сессии растут
/// вдвое, тогда как признаки проблем с самими прямыми соединениями убывают.
/// Пользователь измерил: непроксируемым программам 5–15 % потерь и пинг
/// 60–210 мс, проксируемым — 0–1 % и 70–80. Причина в том, что у трафика
/// «Прямо» резолвер один и без запаса: не ответил провайдерский DNS — запрос
/// просто провалился, а человеку это неотличимо от потери пакетов.
///
/// ⚠️ ПОЧЕМУ НЕЛЬЗЯ ПРОСТО ПЕРЕИСПОЛЬЗОВАТЬ СУЩЕСТВУЮЩИЙ ФОРВАРДЕР. Он
/// спрашивает ТУННЕЛЬ ПЕРВЫМ. Направив туда имена «Прямо», мы в исправном
/// случае отправили бы 100 % из них через VPN — ровно то, от чего пользователь
/// эти имена и уводил. Поэтому нужен ВТОРОЙ порядок: локальный резолвер
/// первым, запасной прямой апстрим вторым, и SOCKS не трогается вовсе.

  group('⚠️ Прямой запас: локальный первым, туннель не трогаем', () {
    test('в прямом режиме SOCKS не нужен вовсе', () {
      // Гейт подъёма у прямого запаса свой и не зависит ни от режима захвата,
      // ни от галочки «весь DNS через туннель»: прямой резолв существует в
      // любой конфигурации, значит и запас ему нужен всегда.
      final s = DnsFallbackServer.direct(
        localDns: '192.0.2.1',
        secondaryDns: '192.0.2.2',
      );
      expect(s.socksPort, 0,
          reason: 'прямому запасу локальный SOCKS не нужен — он и есть тот '
              'путь, который мы обходим');
      expect(s.preferLocal, isTrue);
    });

    test('без второго апстрима запас не имеет смысла и не поднимается', () {
      // Один и тот же резолвер, спрошенный дважды, — это не запас, а удвоенное
      // ожидание: провайдерский DNS не ответил один раз, не ответит и второй.
      expect(
        DnsFallbackServer.direct(localDns: '192.0.2.1', secondaryDns: '')
            .usefulAsDirectFallback,
        isFalse,
      );
      expect(
        DnsFallbackServer.direct(localDns: '192.0.2.1', secondaryDns: '192.0.2.1')
            .usefulAsDirectFallback,
        isFalse,
        reason: 'второй апстрим совпал с первым — это не запас',
      );
      expect(
        DnsFallbackServer.direct(localDns: '192.0.2.1', secondaryDns: '192.0.2.2')
            .usefulAsDirectFallback,
        isTrue,
      );
    });
  });

  group('⚠️ Прямой запас и kill switch несовместимы', () {
    test('под kill switch запас НЕ поднимается', () {
      // Kill switch закрывает 53-й порт мимо туннеля правилом `blockDns`
      // именно затем, чтобы провайдер не видел список доменов. Наши бинари
      // разрешены правилом ВЫШЕ, и форвардер — это `silentgate.exe`: подняв
      // его, мы вынесли бы весь прямой DNS наружу через дырку, оставленную
      // для себя, и защита стала бы декоративной.
      //
      // ⚠️ Оговорка была записана ЗАРАНЕЕ (память `rejected-approaches`), и я
      // всё равно потерял её при реализации #34. Нашлась случайно, при сжатии
      // памяти. Теперь она проверяется, а не помнится.
      final src =
          File('lib/engine/windows/windows_engine.dart').readAsStringSync();
      // Ищем ОПРЕДЕЛЕНИЕ, а не вызов: первое вхождение имени — это место
      // вызова, и гейт там искать бессмысленно.
      final i = src.indexOf('Future<int> _startDirectFallbackDns(');
      expect(i, greaterThan(0), reason: 'подъём прямого запаса не найден');
      final body = src.substring(i, i + 1800);
      expect(body, contains('s.killSwitch'),
          reason: 'прямой запас снова поднимается под kill switch — это дыра '
              'в собственном правиле blockDns');
      expect(body, contains('s.noRealIp'),
          reason: 'прямой запас снова поднимается в режиме без реального IP');
    });
  });
}
