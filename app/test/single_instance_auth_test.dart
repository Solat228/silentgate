import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/instance_secret.dart';
import 'package:silentgate/core/platform/single_instance.dart';

/// Порт single-instance (47654) и его секрет.
///
/// ⚠️ Это тот самый «путь БЕЗ подтверждения пользователя», который владелец
/// сам записал условием пересмотра принятого риска url-схем: через браузер
/// переход подтверждает человек, а через сокет — никто. Любой локальный
/// процесс мог переключить сервер или подменить подписку.
///
/// ⚠️ ФИНАЛЬНОЕ РЕВЬЮ, НАХОДКИ 1 и 2 — обе про одно. Прежняя схема
/// («управляющие команды требуют `AppSettings.apiToken`, импорт не требует
/// ничего») была сломана с двух концов сразу:
///
/// 1. `forward` слал ГОЛУЮ ссылку — секрет не подставлял никто. Токен API по
///    умолчанию пуст, значит `connect|disconnect|toggle|update` отбрасывались
///    ВСЕГДА: приложение запущено, человек кликает ссылку, в журнале
///    «отвергнута», в интерфейсе тишина.
/// 2. Импорт (`silentgate://import?url=…`) при этом проходил свободно — то
///    есть закрыто было переключение между СВОИМИ серверами, а полная подмена
///    VPN-провайдера чужой подпиской (плюс автоподключение к ней) — нет.
///
/// Теперь у сокета СВОЙ постоянный секрет (`InstanceSecret`), он существует
/// независимо от настроек API, и требуется он для ЛЮБОГО сообщения.
void main() {
  group('Разбор сообщения', () {
    test('строка с секретом разбирается на две части', () {
      final m = SingleInstance.splitMessage('sek123\nsilentgate://connect');
      expect(m.secret, 'sek123');
      expect(m.url, 'silentgate://connect');
    });

    test('строка без перевода строки — это сообщение без секрета', () {
      // Так выглядит сообщение чужого процесса или нашей старой сборки.
      // Разбор обязан его пережить и отдать проверке, а не упасть.
      final m = SingleInstance.splitMessage('silentgate://import?url=https://x');
      expect(m.secret, isNull);
      expect(m.url, 'silentgate://import?url=https://x');
    });
  });

  group('InstanceSecret: постоянный секрет рядом с данными', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sg_instance_secret');
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

    test('ensure() создаёт файл и возвращает тот же секрет повторно', () async {
      final first = await InstanceSecret.ensure();
      expect(first, isNotEmpty);
      expect(first.length, 32, reason: '32 hex-символа, как у прочих секретов');
      final file = File('${tmp.path}${Platform.pathSeparator}'
          '${InstanceSecret.fileName}');
      expect(file.existsSync(), isTrue, reason: 'секрет обязан лечь на диск');
      expect(file.readAsStringSync().trim(), first);

      // Второй запуск приложения (кэш сброшен, файл на месте) обязан
      // ПРОЧИТАТЬ прежний, а не выдать новый: иначе ссылки, отправленные
      // вторым экземпляром, перестали бы приниматься после перезапуска.
      InstanceSecret.resetForTests();
      expect(await InstanceSecret.ensure(), first);
    });

    test('read() у второго экземпляра видит секрет первого', () async {
      final primary = await InstanceSecret.ensure();
      InstanceSecret.resetForTests(); // «другой процесс»
      expect(await InstanceSecret.read(), primary);
    });

    test('read() без файла возвращает пусто и НЕ создаёт его', () async {
      final file = File('${tmp.path}${Platform.pathSeparator}'
          '${InstanceSecret.fileName}');
      expect(file.existsSync(), isFalse);
      expect(await InstanceSecret.read(), isEmpty);
      // ⚠️ Создать здесь файл значило бы записать секрет, которого первичный
      // экземпляр не знает: он уже слушает со своим значением.
      expect(file.existsSync(), isFalse);
    });

    test('⚠️ секрет не зависит от токена API', () async {
      // Смысл всей правки: канал закрыт и при выключенном API. Проверяем это
      // буквально — генератор секрета вообще не спрашивает настроек.
      final s = await InstanceSecret.ensure();
      expect(s, isNotEmpty);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(s), isTrue);
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

    test('ВСЕ сообщения без секрета отвергаются, с верным — исполняются',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final received = <String>[];
      const secret = 'secret-of-this-instance';
      SingleInstance.listen(server, received.add, secret: secret);

      // 1. Управляющая команда БЕЗ секрета (голая ссылка, как её слал прежний
      // `forward`) — отказ.
      await send(server.port, 'silentgate://connect');
      expect(received, isEmpty);

      // 2. Неверный секрет — отказ.
      await send(server.port, 'wrong\nsilentgate://connect');
      expect(received, isEmpty);

      // 3. ⚠️ НАХОДКА 2: импорт тоже закрыт. Раньше эта строка проходила и
      // подменяла подписку целиком.
      await send(server.port, 'silentgate://import?url=https://evil.example/sub');
      expect(received, isEmpty,
          reason: 'импорт без секрета обязан быть отвергнут');
      await send(
          server.port, 'wrong\nsilentgate://import?url=https://evil.example/sub');
      expect(received, isEmpty);

      // 4. Формы обхода разбора (решётка, тройной слэш, регистр) — отдельного
      // разбора ссылки больше нет вовсе, значит и обходить нечего.
      for (final u in const [
        'silentgate://connect#x',
        'silentgate:///connect',
        'SILENTGATE://CONNECT',
        'silentgate://Connect/',
        'silentgate://disconnect#anything',
        'silentgate:///toggle/',
      ]) {
        await send(server.port, u);
        expect(received, isEmpty, reason: u);
      }

      // 5. ⚠️ НАХОДКА 1: с верным секретом работают ВСЕ четыре управляющие
      // команды. Именно они молча не работали никогда.
      for (final a in const ['connect', 'disconnect', 'toggle', 'update']) {
        await send(server.port, '$secret\nsilentgate://$a');
      }
      expect(received, [
        'silentgate://connect',
        'silentgate://disconnect',
        'silentgate://toggle',
        'silentgate://update',
      ]);

      // 6. Импорт с верным секретом — штатный путь второго экземпляра, он
      // обязан продолжать работать.
      await send(server.port,
          '$secret\nsilentgate://import?url=https://example.org/sub');
      expect(received.last, 'silentgate://import?url=https://example.org/sub');
    });

    test('пустой секрет отклоняет ВСЁ, а не пропускает без проверки', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final received = <String>[];
      // Так выглядит отказ файловой системы: секрет создать не удалось.
      // «Пусто» обязано значить «закрыто», а не «открыто всем».
      SingleInstance.listen(server, received.add, secret: '');

      await send(server.port, '\nsilentgate://connect');
      await send(server.port, 'silentgate://import?url=https://x');
      await send(server.port, 'anything\nsilentgate://toggle');
      expect(received, isEmpty);
    });
  });
}
