import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/instance_secret.dart';
import 'package:silentgate/core/platform/quit_protocol.dart';
import 'package:silentgate/core/platform/single_instance.dart';
import 'package:silentgate/core/url_scheme.dart';

/// УСТАНОВЩИК ПРОСИТ ПРИЛОЖЕНИЕ ЗАКРЫТЬСЯ.
///
/// ⚠️ ЗАЧЕМ ЭТОТ ФАЙЛ СУЩЕСТВУЕТ. Обновление поверх запущенного клиента
/// упиралось в человека: установщик показывал «обнаружен запущенный экземпляр»
/// и ждал, пока тот пойдёт в трей. А с треем приложение запущено почти всегда,
/// то есть ручное действие требовалось на самом частом пути обновления.
/// Открывая ради этого ответ в локальном сокете, мы трогаем канал, который до
/// сих пор ЗА ВСЮ СВОЮ ЖИЗНЬ не отдал наружу ни байта, — и цена ошибки здесь
/// не «неудобно», а «чужой процесс гасит VPN» либо «по ответу подбирают
/// секрет». Отсюда все проверки ниже.
void main() {
  group('Слово протокола — литерал, а не ссылка', () {
    // ⚠️ ПРИЧИНА ГЛУБЖЕ, ЧЕМ «СХЕМУ МОЖНО КЛИКНУТЬ С САЙТА».
    //
    // `main.dart` берёт из аргументов запуска ЛЮБУЮ поддерживаемую ссылку, а
    // наш же второй экземпляр пересылает её первичному, САМ ПОДСТАВИВ ВЕРНЫЙ
    // СЕКРЕТ (`SingleInstance.forward`). То есть секрет от ссылки не защищает
    // вовсе: курьером выступаем мы сами. Была бы команда выхода ссылкой —
    // достаточно было бы уговорить человека кликнуть по ней.
    test('quit НЕ является управляющим действием url-схемы', () {
      expect(AppUrlScheme.controlActions, isNot(contains('quit')));
      expect(AppUrlScheme.controlActions, isNot(contains('quit-force')));
      expect(AppUrlScheme.controlAction('silentgate://quit'), isNull);
      expect(AppUrlScheme.controlAction('silentgate:///quit-force/'), isNull);
    });

    test('разбор просьбы сравнивает с литералом и ничего не толкует', () {
      expect(QuitProtocol.parseRequest('quit'), isFalse);
      expect(QuitProtocol.parseRequest(' quit-force '), isTrue);
      // Всё остальное — не просьба выйти, и это ровно то, что нужно: любой
      // «умный» разбор был бы вторым парсером одной строки, а два ответа на
      // вопрос «что это было» в этом проекте уже дважды оказывались дырой.
      for (final s in const [
        'silentgate://quit',
        'silentgate://quit-force',
        'QUIT',
        'quit?force=1',
        'quit\nquit',
        '',
      ]) {
        expect(QuitProtocol.parseRequest(s), isNull, reason: s);
      }
    });

    test('аргумент запуска разбирается, посторонние не считаются', () {
      expect(QuitProtocol.forceFromArgs(const ['--quit']), isFalse);
      expect(QuitProtocol.forceFromArgs(const ['--quit-force']), isTrue);
      expect(QuitProtocol.forceFromArgs(const []), isNull);
      expect(QuitProtocol.forceFromArgs(const ['--cleanup']), isNull);
      expect(QuitProtocol.forceFromArgs(const ['silentgate://connect']), isNull);
    });

    test('коды возврата по ответу', () {
      expect(QuitProtocol.codeForAnswer('bye'), QuitProtocol.exitBye);
      expect(QuitProtocol.codeForAnswer('busy\n'), QuitProtocol.exitBusy);
      // Пусто = ответа не было. ⚠️ Считать это успехом нельзя: ровно так
      // выглядит и старая сборка, и чужой процесс, занявший порт.
      expect(QuitProtocol.codeForAnswer(''), QuitProtocol.exitNoContact);
      expect(QuitProtocol.codeForAnswer('HTTP/1.1 200 OK'),
          QuitProtocol.exitForeignAnswer);
    });
  });

  group('Сквозная проверка через настоящий сокет', () {
    const secret = 'secret-of-this-instance';

    /// Клиент протокола: пишем, ПОЛУзакрываем, читаем ответ.
    ///
    /// Повторяет то, что делает `requestQuit`, но на произвольном порту и без
    /// файла секрета — чтобы проверять серверную половину отдельно.
    Future<String> ask(int port, String message,
        {Duration wait = const Duration(milliseconds: 500)}) async {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      final buf = <int>[];
      final got = Completer<String>();
      void settle() {
        if (!got.isCompleted) {
          got.complete(utf8.decode(buf, allowMalformed: true).trim());
        }
      }

      socket.listen((c) {
        buf.addAll(c);
        if (buf.contains(0x0a)) settle();
      }, onDone: settle, onError: (_) => settle(), cancelOnError: true);
      socket.add(utf8.encode(message));
      await socket.flush();
      await socket.close();
      String raw;
      try {
        raw = await got.future.timeout(wait);
      } catch (_) {
        raw = '';
      }
      socket.destroy();
      return raw;
    }

    test('⚠️ БЕЗ СЕКРЕТА — НИ БАЙТА В ОТВЕТ', () async {
      // Появление ответа не имеет права стать оракулом: по нему чужой процесс
      // отличал бы наш порт от занятого кем угодно и подбирал бы секрет по
      // реакции. Путь отказа обязан остаться прежним — обрыв и молчание.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      var quitCalled = 0;
      SingleInstance.listen(server, (_) {},
          secret: secret,
          isVpnActive: () => false,
          onQuit: () async => quitCalled++);

      for (final m in const [
        'quit',
        'quit-force',
        'wrong\nquit',
        '\nquit-force',
      ]) {
        expect(await ask(server.port, m), isEmpty, reason: m);
      }
      expect(quitCalled, 0, reason: 'без секрета приложение гасить нельзя');
    });

    test('VPN активен: busy, приложение НЕ гаснет', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      var quitCalled = 0;
      SingleInstance.listen(server, (_) {},
          secret: secret,
          isVpnActive: () => true,
          onQuit: () async => quitCalled++);

      expect(await ask(server.port, '$secret\nquit'), QuitProtocol.answerBusy);
      expect(quitCalled, 0,
          reason: 'рвать живой туннель без согласия человека нельзя');
    });

    test('quit-force гасит и при живом туннеле', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      var quitCalled = 0;
      SingleInstance.listen(server, (_) {},
          secret: secret,
          isVpnActive: () => true,
          onQuit: () async => quitCalled++);

      expect(
          await ask(server.port, '$secret\nquit-force'), QuitProtocol.answerBye);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(quitCalled, 1, reason: 'согласие уже дано — гасим');
    });

    test('⚠️ КЛЮЧЕВОЕ: ответ уходит ДО того, как приложение начнёт умирать',
        () async {
      // В бою `onQuit` заканчивается `exit(0)` — то есть будущее, которое не
      // завершится НИКОГДА. Дождись мы его перед записью в сокет, ответ так и
      // остался бы в буфере: установщик получил бы таймаут при исправно
      // закрывающемся приложении и ушёл бы на ручной диалог. Здесь `exit(0)`
      // изображает Completer, который не завершается.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final dying = Completer<void>();
      var entered = false;
      SingleInstance.listen(server, (_) {},
          secret: secret, isVpnActive: () => false, onQuit: () {
        entered = true;
        return dying.future; // никогда
      });

      expect(await ask(server.port, '$secret\nquit'), QuitProtocol.answerBye);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(entered, isTrue, reason: 'гасить приложение всё-таки надо');
      expect(dying.isCompleted, isFalse);
    });

    test('обычная ссылка ответа не получает и приложение не гасит', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final urls = <String>[];
      var quitCalled = 0;
      SingleInstance.listen(server, urls.add,
          secret: secret,
          isVpnActive: () => false,
          onQuit: () async => quitCalled++);

      expect(await ask(server.port, '$secret\nsilentgate://connect'), isEmpty,
          reason: 'канал ссылок как молчал, так и молчит');
      expect(urls, ['silentgate://connect']);
      expect(quitCalled, 0);
    });

    test('⚠️ silentgate://quit уходит в onUrl и НИЧЕГО не гасит', () async {
      // Тот самый обход, который был бы возможен, будь команда выхода ссылкой:
      // человека уговаривают кликнуть, наш второй экземпляр прикладывает
      // верный секрет, первичный послушно выключается вместе с туннелем.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final urls = <String>[];
      var quitCalled = 0;
      SingleInstance.listen(server, urls.add,
          secret: secret,
          isVpnActive: () => false,
          onQuit: () async => quitCalled++);

      for (final u in const [
        'silentgate://quit',
        'silentgate://quit-force',
        'silentgate:///quit',
        'SILENTGATE://QUIT#x',
      ]) {
        expect(await ask(server.port, '$secret\n$u'), isEmpty, reason: u);
      }
      expect(quitCalled, 0,
          reason: 'ссылка не имеет права гасить приложение НИКОГДА');
      expect(urls.length, 4, reason: 'она остаётся обычной ссылкой');
    });

    test('без обработчика выхода — молчание, а не ложное обещание', () async {
      // Так выглядит сборка, где обслуживать просьбу некому. Ответ «bye» был
      // бы обещанием, которое никто не выполнит, и установщик снёс бы файлы
      // из-под живого процесса.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      SingleInstance.listen(server, (_) {}, secret: secret);
      expect(await ask(server.port, '$secret\nquit'), isEmpty);
    });
  });

  group('Помощник --quit (клиентская половина)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sg_quit_helper');
      AppPaths.overrideRoot(tmp);
      InstanceSecret.resetForTests();
    });

    tearDown(() async {
      InstanceSecret.resetForTests();
      AppPaths.resetForTests();
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('bye → 0, busy → 10, молчание → «не достучались»', () async {
      final secret = await InstanceSecret.ensure();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      var vpn = true;
      var quitCalled = 0;
      SingleInstance.listen(server, (_) {},
          secret: secret,
          isVpnActive: () => vpn,
          onQuit: () async => quitCalled++);

      expect(await SingleInstance.requestQuit(port: server.port),
          QuitProtocol.exitBusy);
      expect(quitCalled, 0);

      expect(await SingleInstance.requestQuit(force: true, port: server.port),
          QuitProtocol.exitBye);

      vpn = false;
      expect(await SingleInstance.requestQuit(port: server.port),
          QuitProtocol.exitBye);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(quitCalled, 2);
    });

    test('чужой процесс на порту: не «bye» — значит не наш', () async {
      final foreign = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(foreign.close);
      foreign.listen((s) {
        s.add(utf8.encode('HTTP/1.1 404 Not Found\r\n'));
        s.flush().whenComplete(s.destroy);
      });
      await InstanceSecret.ensure();
      expect(await SingleInstance.requestQuit(port: foreign.port),
          QuitProtocol.exitForeignAnswer);
    });

    test('молчаливый порт закрывается по таймауту, а не ждёт вечно', () async {
      final mute = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(mute.close);
      final held = <Socket>[];
      mute.listen(held.add); // принимаем и молчим
      addTearDown(() {
        for (final s in held) {
          s.destroy();
        }
      });
      await InstanceSecret.ensure();
      expect(
          await SingleInstance.requestQuit(
              port: mute.port, timeout: const Duration(milliseconds: 200)),
          QuitProtocol.exitNoContact);
    });

    test('без файла секрета — свой код, а не молчаливый успех', () async {
      // Бытовой случай: установщик запустили «от имени другого администратора»,
      // и `%APPDATA%` у него чужой. Установщик обязан отличать это от «закрыл».
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      SingleInstance.listen(server, (_) {},
          secret: 'anything', isVpnActive: () => false, onQuit: () async {});
      expect(await SingleInstance.requestQuit(port: server.port),
          QuitProtocol.exitNoSecret);
    });

    test('никто не слушает — «не достучались»', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final free = probe.port;
      await probe.close();
      await InstanceSecret.ensure();
      expect(await SingleInstance.requestQuit(port: free),
          QuitProtocol.exitNoContact);
    });
  });

  group('Стражи на ВЫЗОВ, а не на существование кода', () {
    // ⚠️ В этом проекте четырежды ловили «код написан и не вызывается»: связка
    // провайдеров без `lazy: false`, гейт пинга, порт «Прямо», описанный до
    // реализации. Проверять наличие функции недостаточно.
    final main = File('lib/main.dart').readAsStringSync();
    final tray =
        File('lib/core/platform/tray_window.dart').readAsStringSync();
    final si =
        File('lib/core/platform/single_instance.dart').readAsStringSync();

    test('⚠️ ветка --quit отрабатывает ДО AppInstanceMutex.acquire()', () {
      // Помощник не имеет права держать мьютекс, по которому установщик судит
      // о запущенности: он сам стал бы «работающим приложением» и вечно ждал
      // бы освобождения самого себя.
      //
      // ⚠️ Проверяется ПОРЯДОК ИСПОЛНЕНИЯ, а не порядок строк в файле:
      // `_runWindowsCliMode` объявлена в самом низу, а зовётся первой — по
      // тексту она «после» acquire, по делу до него. Первый вариант этого
      // стража сравнивал смещения в файле и ловил ровно эту иллюзию.
      final cliCall = main.indexOf('await _runWindowsCliMode(args)');
      final acquireAt = main.indexOf('AppInstanceMutex.acquire()');
      expect(cliCall, greaterThan(0));
      expect(acquireAt, greaterThan(0));
      expect(cliCall, lessThan(acquireAt),
          reason: 'служебные режимы обязаны отрабатывать до захвата мьютекса');

      // А сама ветка обязана жить именно внутри этого режима — и заканчивать
      // процесс своим кодом возврата, по нему установщик и принимает решение.
      final cliAt = main.indexOf('Future<bool> _runWindowsCliMode(');
      expect(cliAt, greaterThan(0));
      final cli = main.substring(cliAt);
      expect(cli, contains('QuitProtocol.forceFromArgs(args)'));
      expect(cli, contains('exit(await SingleInstance.requestQuit('));
      // Первой, до TUN-хелпера: он поднимает туннель, а нас просят закрыться.
      expect(cli.indexOf('QuitProtocol.forceFromArgs'),
          lessThan(cli.indexOf('--tun-task')));
    });

    test('⚠️ обработчик выхода действительно передан в listen()', () {
      // Без него просьба осталась бы без ответа при живом приложении, и
      // установщик молча вернулся бы к ручному диалогу.
      final listenAt = main.indexOf('SingleInstance.listen(');
      expect(listenAt, greaterThan(0));
      final call = main.substring(listenAt, listenAt + 400);
      expect(call, contains('onQuit: TrayWindow.quitNow'));
      expect(call, contains('isVpnActive: () => TrayWindow.vpnActive'));
    });

    test('⚠️ дорога наружу одна: трей выходит через quitNow()', () {
      // Разъехавшиеся копии выхода означали бы, что установщик гасит
      // приложение иначе, чем человек, — без disconnect в живых остаются
      // xray/sing-box, системный прокси и TUN-адаптер.
      expect(tray, contains('static Future<void> quitNow()'));
      final atQuitCase = tray.indexOf("case 'quit':");
      expect(atQuitCase, greaterThan(0));
      expect(tray.substring(atQuitCase, atQuitCase + 300),
          contains('await quitNow();'));
      expect(tray, contains('static bool get vpnActive'));
    });

    test('⚠️ ответ в сокет пишется ровно в одном месте', () {
      // Второе место — второй оракул. Барьер того же рода, что в
      // `LocalApiServer._write`: единственная дверь наружу.
      expect('socket.add('.allMatches(si).length, 3,
          reason: 'ожидаются ровно три записи: ответ в _answerQuit, '
              'запрос в requestQuit и пересылка ссылки в forward');
      final answerAt = si.indexOf('static Future<void> _answerQuit(');
      expect(answerAt, greaterThan(0));
      // Порядок внутри: ответ → flush → destroy. Иначе ответ не уедет.
      // ⚠️ Отсчёт от самой записи: выше по функции есть отдельная ветка
      // «обслуживать некому», и её `destroy()` не имеет отношения к порядку.
      final body =
          si.substring(answerAt, si.indexOf('static Future<int> requestQuit'));
      final afterWrite = body.substring(body.indexOf('socket.add('));
      expect(afterWrite.indexOf('flush()'),
          lessThan(afterWrite.indexOf('socket.destroy()')),
          reason: 'без flush() до разрыва ответ может не уехать вовсе');
    });

    test('⚠️ пределы приёма остались ДО аутентификации', () {
      // Их роль не изменилась: секрет проверяется только по закрытию
      // соединения отправителем, а закрывать его никто не обязан.
      expect(si, contains('maxMessageBytes'));
      expect(si, contains('readTimeout'));
      final limitAt = si.indexOf('if (buf.length + chunk.length > maxMessageBytes)');
      final authAt = si.indexOf('_constantTimeEquals(m.secret');
      expect(limitAt, greaterThan(0));
      expect(limitAt, lessThan(authAt));
    });

    test('⚠️ forward() пересылает только ссылки', () {
      // Секрет подставляет он сам, то есть придаёт законный вид чему угодно,
      // что в него передали. Канал ссылок и канал выхода не пересекаются.
      final at = si.indexOf('static Future<void> forward(');
      expect(at, greaterThan(0));
      expect(si.substring(at, at + 900),
          contains('if (!AppUrlScheme.isSupportedLink(url)) {'));
    });
  });
}
