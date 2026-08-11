import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/single_instance.dart';
import 'package:silentgate/core/url_scheme.dart';

/// Порт single-instance принимал произвольную строку без аутентификации.
///
/// ⚠️ Это тот самый «путь БЕЗ подтверждения пользователя», который владелец
/// сам записал условием пересмотра принятого риска url-схем: через браузер
/// переход подтверждает человек, а через сокет — никто. Любой локальный
/// процесс мог переключить сервер или подменить подписку.
void main() {
  group('Разбор сообщения', () {
    test('строка с токеном разбирается на две части', () {
      final m = SingleInstance.splitMessage('tok123\nsilentgate://connect');
      expect(m.token, 'tok123');
      expect(m.url, 'silentgate://connect');
    });

    test('строка без перевода строки — это просто ссылка', () {
      final m = SingleInstance.splitMessage('silentgate://import?url=https://x');
      expect(m.token, isNull);
      expect(m.url, 'silentgate://import?url=https://x');
    });
  });

  group('Что требует токена', () {
    test('команды управления требуют', () {
      for (final a in ['connect', 'disconnect', 'toggle', 'update']) {
        expect(SingleInstance.needsToken('silentgate://$a'), isTrue,
            reason: '$a обязано требовать токен');
      }
    });

    test('⚠️ импорт НЕ требует — его инициировал человек', () {
      // Второй экземпляр приложения передаёт ссылку, по которой пользователь
      // щёлкнул в браузере или проводнике. Сломать этот путь нельзя.
      expect(SingleInstance.needsToken('silentgate://import?url=https://x'),
          isFalse);
      expect(SingleInstance.needsToken('https://panel.example/sub/abc'),
          isFalse);
    });

    test('⚠️ РЕГРЕСС раунда ревью 1: формы обхода тоже требуют токен', () {
      // Раньше свой разбор (`rest == a || startsWith('$a?') || startsWith('$a/')`)
      // не узнавал ни одну из этих форм, а `AppUrlScheme.controlAction`,
      // который реально исполняет команду, узнавал их все как `connect` — и
      // команда проходила БЕЗ токена. Ровно эксплойт, воспроизведённый ревью.
      final bypasses = <String>[
        'silentgate://connect#x', // «хвост» после решётки не мешает Uri.host
        'silentgate:///connect', // тройной слэш — пустой host, action из path
        'SILENTGATE://CONNECT', // регистр схемы и действия
        'silentgate://Connect/', // хвостовой слэш + смешанный регистр
        'silentgate://connect?server=Германия', // параметры после действия
        'silentgate://disconnect#anything',
        'silentgate:///toggle/',
        '  silentgate://update  ', // пробелы вокруг строки
      ];
      for (final u in bypasses) {
        expect(SingleInstance.needsToken(u), isTrue, reason: u);
      }
    });

    test(
        '⚠️ согласованность с AppUrlScheme.controlAction — единственный источник правды',
        () {
      // Это тест, который поймал бы дыру раунда 1 автоматически: если
      // needsToken когда-нибудь снова обзаведётся СВОИМ разбором, отличным от
      // того, что реально исполняет команду, — он разойдётся с
      // controlAction и тест упадёт.
      final samples = <String>[
        'silentgate://connect',
        'silentgate://connect#x',
        'silentgate:///connect',
        'SILENTGATE://CONNECT',
        'silentgate://Connect/',
        'silentgate://disconnect?x=1',
        'silentgate://toggle',
        'silentgate://update',
        'silentgate://import?url=https://x',
        'silentgate://import',
        'silentgate://add/https://example.org/sub',
        'https://panel.example/sub/abc',
        'silentgate://unknown-action',
        'not-a-url-at-all',
        '',
        '   ',
        'happ://add/https://example.org/sub',
      ];
      for (final s in samples) {
        expect(SingleInstance.needsToken(s), AppUrlScheme.controlAction(s) != null,
            reason: 'разошлось на: "$s"');
      }
    });
  });

  group('listen(): сквозная проверка через реальный сокет', () {
    // Хелпер: отправить сырое сообщение первичному экземпляру и дать его
    // обработчику `onDone` время отработать. Задержка — не «на удачу»: сокет
    // localhost, доставка синхронная в пределах одного тика, 150 мс — щедрый
    // запас, а тест ждёт РЕЗУЛЬТАТ (пришло/не пришло в `received`), а не факт
    // отправки.
    Future<void> send(int port, String raw) async {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      socket.add(utf8.encode(raw));
      await socket.flush();
      await socket.close();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    test(
        'команда без токена отвергается, с верным токеном исполняется, '
        'импорт проходит без токена', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final received = <String>[];
      const realToken = 'secret-token';
      SingleInstance.listen(server, received.add, token: () => realToken);

      // 1. Управляющая команда БЕЗ токена (просто ссылка, без "\n") — отказ.
      await send(server.port, 'silentgate://connect');
      expect(received, isEmpty,
          reason: 'команда без токена не должна была исполниться');

      // 2. Управляющая команда с НЕВЕРНЫМ токеном — отказ.
      await send(server.port, 'wrong-token\nsilentgate://connect');
      expect(received, isEmpty,
          reason: 'команда с неверным токеном не должна была исполниться');

      // 3. Форма обхода из раунда 1 (решётка после действия) — тоже отказ
      // без токена, несмотря на то, что старый разбор её не ловил.
      await send(server.port, 'silentgate://connect#x');
      expect(received, isEmpty,
          reason: 'форма обхода не должна была проскочить без токена');

      // 4. Управляющая команда с ВЕРНЫМ токеном — исполняется.
      await send(server.port, '$realToken\nsilentgate://connect');
      expect(received, ['silentgate://connect']);

      // 5. Импортная ссылка — БЕЗ токена, штатный путь второго экземпляра.
      await send(server.port,
          'silentgate://import?url=https://example.org/sub');
      expect(received, [
        'silentgate://connect',
        'silentgate://import?url=https://example.org/sub',
      ]);
    });

    test('пустой токен в настройках отклоняет ВСЕ управляющие команды',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final received = <String>[];
      // Пустой токен — состояние по умолчанию (никто ещё не открывал
      // настройки API): «пусто» обязано отклонять, а не пропускать без
      // проверки.
      SingleInstance.listen(server, received.add, token: () => '');

      await send(server.port, '\nsilentgate://connect');
      expect(received, isEmpty);

      // Импорт по-прежнему работает даже при пустом токене в настройках.
      await send(server.port, 'silentgate://import?url=https://x');
      expect(received, ['silentgate://import?url=https://x']);
    });
  });
}
