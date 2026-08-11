import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/probe/tunnel_health.dart';

/// Сквозная проверка канала — та, которой не хватило 08.08.2026.
///
/// ⚠️ ЧТО ИМЕННО СТЕРЕЖЁМ. Сторож зависания спрашивает у ядра «жив ли ты» и
/// получает «да» даже тогда, когда через туннель не проходит ни байта. У
/// владельца между «сторож вооружён» (13:44) и отчётом (19:52) приложение не
/// записало НИЧЕГО, хотя VPN не работал. Проверка процесса не заменяет проверку
/// канала — и наоборот.
///
/// Тесты поднимают НАСТОЯЩИЙ локальный HTTP-прокси, потому что проверять надо
/// именно путь «через прокси-порт ядра». Мок вернул бы зелёный и на коде,
/// который в прокси не ходит вовсе.
void main() {
  /// Минимальный HTTP-прокси: отвечает [status] на любой запрос.
  /// [onRequest] позволяет считать обращения и менять поведение на лету.
  Future<({HttpServer server, int port})> fakeProxy({
    int status = 204,
    bool Function()? healthy,
    void Function()? onRequest,
  }) async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((req) async {
      onRequest?.call();
      if (healthy != null && !healthy()) {
        // ⚠️ Канал «мёртв» = ОБРЫВ соединения, а не пустой ответ.
        //
        // Первая версия здесь просто закрывала response — а это HTTP 200, то
        // есть проба честно считала «мёртвый» канал живым, и три теста падали
        // на ровном месте. Ядро без выхода ведёт себя иначе: соединение
        // рвётся. Воспроизводим именно это.
        try {
          final sock = await req.response.detachSocket(writeHeaders: false);
          sock.destroy();
        } catch (_) {}
        return;
      }
      req.response.statusCode = status;
      await req.response.close();
    });
    return (server: s, port: s.port);
  }

  group('Одиночная проба', () {
    test('прокси отвечает — канал жив', () async {
      final p = await fakeProxy();
      addTearDown(() => p.server.close(force: true));
      final h = TunnelHealth(proxyPort: p.port);
      expect(await h.probeOnce(), isTrue);
    });

    test('прокси не слушает — канал мёртв', () async {
      // Свободный порт: занимаем и сразу отпускаем.
      final tmp = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final dead = tmp.port;
      await tmp.close(force: true);
      final h = TunnelHealth(
          proxyPort: dead, timeout: const Duration(milliseconds: 700));
      expect(await h.probeOnce(), isFalse);
    });

    test('проба идёт ИМЕННО через прокси-порт', () async {
      // Иначе проверялась бы обычная сеть машины, и смысл терялся бы целиком:
      // при мёртвом туннеле проба всё равно была бы зелёной.
      var hits = 0;
      final p = await fakeProxy(onRequest: () => hits++);
      addTearDown(() => p.server.close(force: true));
      await TunnelHealth(proxyPort: p.port).probeOnce();
      expect(hits, greaterThan(0), reason: 'запрос мимо прокси не считается');
    });

    test('ошибка 5xx засчитывается как отказ', () async {
      final p = await fakeProxy(status: 502);
      addTearDown(() => p.server.close(force: true));
      final h = TunnelHealth(proxyPort: p.port);
      expect(await h.probeOnce(), isFalse);
    });
  });

  group('Прокси с паролем', () {
    /// Прокси, требующий Basic-аутентификацию: без креды отвечает 407.
    Future<({HttpServer server, int port})> authProxy(
        String user, String pass) async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final want = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
      s.listen((req) async {
        final got = req.headers.value(HttpHeaders.proxyAuthorizationHeader);
        if (got != want) {
          req.response.statusCode = HttpStatus.proxyAuthenticationRequired;
          req.response.headers
              .set(HttpHeaders.proxyAuthenticateHeader, 'Basic realm="sg"');
          await req.response.close();
          return;
        }
        req.response.statusCode = 204;
        await req.response.close();
      });
      return (server: s, port: s.port);
    }

    test('с кредами проба проходит', () async {
      // ⚠️ ЭТОТ ТЕСТ ПОЯВИЛСЯ ПОТОМУ, ЧТО БЕЗ НЕГО ПРОВЕРКА ДЕЛАЛА БЫ ХУЖЕ.
      //
      // Пароль на локальных прокси стал умолчанием, а `HttpClient.findProxy`
      // креды не передаёт. Проба получала бы 407 на КАЖДОМ запросе, три
      // промаха подряд — и приложение переподключалось бы по кругу на
      // совершенно исправном туннеле. Сторож, поставленный ловить обрывы, сам
      // стал бы их источником.
      final p = await authProxy('sg', 'pw');
      addTearDown(() => p.server.close(force: true));
      final h = TunnelHealth(
          proxyPort: p.port, proxyUser: 'sg', proxyPassword: 'pw');
      expect(await h.probeOnce(), isTrue);
    });

    test('без креда — честный отказ, а не молчаливый успех', () async {
      final p = await authProxy('sg', 'pw');
      addTearDown(() => p.server.close(force: true));
      final h = TunnelHealth(proxyPort: p.port);
      expect(await h.probeOnce(), isFalse);
    });

    test('неверный пароль не считается живым каналом', () async {
      final p = await authProxy('sg', 'pw');
      addTearDown(() => p.server.close(force: true));
      final h = TunnelHealth(
          proxyPort: p.port, proxyUser: 'sg', proxyPassword: 'НЕВЕРНЫЙ');
      expect(await h.probeOnce(), isFalse);
    });
  });

  group('Условие отмены', () {
    test('⚠️ наблюдение глохнет, если aborted истинно СРАЗУ', () async {
      // ЭТОТ ТЕСТ — ИЗ ЖИВОГО ПРОГОНА В VM, ГДЕ СТОРОЖ МОЛЧАЛ ТРИ МИНУТЫ.
      //
      // На Windows вооружение стояло рядом с подъёмом туннеля, а условие
      // отмены — `aborted() || !status.isConnected`. В тот момент статус был
      // ещё `connecting`, и наблюдение глушило себя на ПЕРВОЙ пробе: ни строчки
      // в журнале, ни одного переподключения. Выглядело как «проба не
      // работает», хотя проба исправна — неверен был ПОРЯДОК ВЫЗОВА.
      //
      // На Android вызов изначально стоял после статуса, поэтому там всё
      // работало, и расхождение платформ пряталось до живого теста.
      final p = await fakeProxy(healthy: () => false);
      addTearDown(() => p.server.close(force: true));
      var down = 0;
      final h = TunnelHealth(
        proxyPort: p.port,
        interval: const Duration(milliseconds: 80),
        timeout: const Duration(milliseconds: 300),
        failuresToDeclareDown: 2,
      );
      h.start(onDown: () async => down++, aborted: () => true);
      addTearDown(h.stop);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(down, 0, reason: 'при aborted наблюдение обязано молчать');
      expect(h.isRunning, isFalse,
          reason: 'иначе таймер тикает впустую до конца сессии');
    });

    test('при aborted=false наблюдение работает — контроль', () async {
      // Парный тест: без него предыдущий проходил бы и на сломанной пробе.
      final p = await fakeProxy(healthy: () => false);
      addTearDown(() => p.server.close(force: true));
      var down = 0;
      final h = TunnelHealth(
        proxyPort: p.port,
        interval: const Duration(milliseconds: 80),
        timeout: const Duration(milliseconds: 300),
        failuresToDeclareDown: 2,
      );
      h.start(onDown: () async => down++, aborted: () => false);
      addTearDown(h.stop);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(down, 1);
    });
  });

  group('Серия промахов', () {
    test('одиночный сбой НЕ считается смертью канала', () async {
      // Реагировать на первый промах значило бы рвать все живые TCP-сессии
      // пользователя из-за одного моргнувшего пакета.
      var ok = false; // первая проба провалится, дальше — успех
      final p = await fakeProxy(healthy: () => ok);
      addTearDown(() => p.server.close(force: true));

      var down = 0;
      var recovered = -1;
      final h = TunnelHealth(
        proxyPort: p.port,
        interval: const Duration(milliseconds: 120),
        timeout: const Duration(milliseconds: 700),
        failuresToDeclareDown: 3,
      );
      h.start(
        onDown: () async => down++,
        onRecovered: (missed) => recovered = missed,
      );
      addTearDown(h.stop);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      ok = true;
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(down, 0, reason: 'канал объявлен мёртвым по одному промаху');
      expect(recovered, greaterThan(0),
          reason: 'восстановление после промахов должно быть замечено');
    });

    test('три промаха подряд — канал мёртв, сообщаем ОДИН раз', () async {
      final p = await fakeProxy(healthy: () => false);
      addTearDown(() => p.server.close(force: true));

      var down = 0;
      final h = TunnelHealth(
        proxyPort: p.port,
        interval: const Duration(milliseconds: 100),
        timeout: const Duration(milliseconds: 500),
        failuresToDeclareDown: 3,
      );
      h.start(onDown: () async => down++);
      addTearDown(h.stop);

      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(down, 1,
          reason: 'повторные вызовы устроили бы шторм переподключений');
      expect(h.isRunning, isFalse, reason: 'после приговора наблюдение стоит');
    });

    test('счётчик промахов обнуляется удачной пробой', () async {
      var ok = false;
      final p = await fakeProxy(healthy: () => ok);
      addTearDown(() => p.server.close(force: true));
      final h = TunnelHealth(
        proxyPort: p.port,
        interval: const Duration(milliseconds: 100),
        timeout: const Duration(milliseconds: 500),
        failuresToDeclareDown: 5,
      );
      h.start(onDown: () async {});
      addTearDown(h.stop);

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(h.consecutiveFailures, greaterThan(0));
      ok = true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(h.consecutiveFailures, 0);
    });

    test('отмена сессии останавливает наблюдение', () async {
      // Сторож прошлой сессии не должен переподключать следующую — на этом
      // в проекте уже обжигались с автоподбором TUN.
      final p = await fakeProxy(healthy: () => false);
      addTearDown(() => p.server.close(force: true));
      var down = 0;
      var stale = false;
      final h = TunnelHealth(
        proxyPort: p.port,
        interval: const Duration(milliseconds: 100),
        timeout: const Duration(milliseconds: 400),
        failuresToDeclareDown: 2,
      );
      h.start(onDown: () async => down++, aborted: () => stale);
      addTearDown(h.stop);
      stale = true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(down, 0);
    });
  });
}
