import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ПОДХВАТ ЖИВОГО ТУННЕЛЯ ОБЯЗАН ВООРУЖАТЬ СТОРОЖ КАНАЛА.
///
/// ⚠️ РАДИ ЧЕГО. На Android это самый обычный сценарий, а не редкость: человек
/// смахнул приложение — туннель продолжил работать в своём сервисе; открыл
/// заново — поднялся НОВЫЙ изолят, который этот туннель не поднимал. До
/// 20.08.2026 сторож вооружался только в `startSession`, поэтому после возврата
/// обрыв канала было некому заметить: «Подключено» висело бы при мёртвом
/// туннеле сколько угодно долго.
///
/// ⚠️ ПОЧЕМУ ПРОВЕРКА ПО ИСХОДНИКУ. Поведение упирается в нативный канал
/// (`isRunning`), в файлы приватного каталога и в живой VpnService — в тесте
/// этого нет. Зато можно удержать сам порядок: креды прочитаны, и только потом
/// сторож вооружён.
void main() {
  String code(String path) => File(path)
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///');
      })
      .join(String.fromCharCode(10));

  late String engine;
  setUp(() => engine = code('lib/engine/android/android_engine.dart'));

  String adoptBody() {
    final at = engine.indexOf('Future<void> adoptRunningTunnel()');
    expect(at, greaterThan(0), reason: 'метод подхвата пропал');
    return engine.substring(at, at + 2200);
  }

  group('⚠️ Сторож вооружается при подхвате', () {
    test('в подхвате есть вооружение сторожа', () {
      expect(adoptBody(), contains('startHealthWatch('),
          reason: 'без него обрыв подхваченного туннеля некому заметить');
    });

    test('⚠️ ТОЛЬКО ПОСЛЕ восстановления кредов проб', () {
      // Без кредов проба получает 407 и объявляет ИСПРАВНЫЙ туннель мёртвым —
      // сторож стал бы источником обрывов, а не защитой от них.
      final body = adoptBody();
      final creds = body.indexOf('_restoreProbeSecret()');
      final arm = body.indexOf('startHealthWatch(');
      expect(creds, greaterThan(0), reason: 'креды не восстанавливаются вовсе');
      expect(arm, greaterThan(creds),
          reason: 'вооружение обязано стоять ПОСЛЕ проверки кредов');
    });

    test('⚠️ нет кредов — молчать нельзя, причина называется', () {
      // Молчаливое невооружение неотличимо от исправной работы: человек считает
      // себя под присмотром, а его нет.
      expect(adoptBody(), contains('Сторож канала НЕ вооружён после подхвата'));
    });

    test('сторож подхвата привязан к поколению', () {
      // Иначе он останется сторожем ЧУЖОЙ сессии и заглушит сторожа новой.
      final body = adoptBody();
      expect(body, contains('newGeneration()'));
      expect(body, contains('isStale(gen)'));
    });
  });

  group('⚠️ Креды проб переживают смерть изолята', () {
    test('пароль проб кладётся на диск при подъёме', () {
      final at = engine.indexOf('ProxyProbe.password = _randomSecret()');
      expect(at, greaterThan(0));
      expect(engine.substring(at, at + 400), contains('_saveProbeSecret()'),
          reason: 'без записи следующий запуск не сможет опросить туннель');
    });

    test('⚠️ пустой пароль не принимается за годный', () {
      // Пустой хуже отсутствующего: проба пошла бы без кредов и получила 407,
      // то есть объявила бы исправный туннель мёртвым.
      final at = engine.indexOf('Future<bool> _restoreProbeSecret()');
      expect(at, greaterThan(0));
      final body = engine.substring(at, at + 900);
      expect(body, contains('user.isEmpty || pass.isEmpty'));
    });

    test('⚠️ перевод строки задан кодом, а не байтом', () {
      // Класс багов из CLAUDE.md: невидимый управляющий символ в исходнике
      // глазами не увидеть, ловит только тест.
      expect(engine, contains('String.fromCharCode(10)'));
    });
  });
}
