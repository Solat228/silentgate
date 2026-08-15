import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/engine/android/app_heartbeat.dart';

/// ТИШИНА В ЖУРНАЛЕ ДОЛЖНА ЧТО-ТО ЗНАЧИТЬ.
///
/// ⚠️ ОТКУДА ЭТО. 15.08.2026 владелец: «на мобилке у меня внезапно зависло
/// приложение». В отчёте `app.log` обрывается на 12:18:42, отчёт снят в
/// 13:00:54 — сорок две минуты пустоты. По ним нельзя сказать НИЧЕГО: журнал
/// пишется только по событиям, и «приложение стояло» неотличимо от «ничего не
/// происходило». Это отдельный дефект — до него у отчёта поддержки не было
/// ответа на главный вопрос, ради которого его и присылают.
///
/// Ни один тест здесь не ходит в платформу и не поднимает таймер: подменены
/// часы, проба канала и источник записей журнала.
void main() {
  // ── Отметка живости ────────────────────────────────────────────────────────

  group('отметка «приложение живо»', () {
    test('⚠️ ГЛАВНОЕ: тишина дольше срока — отметка появляется', () async {
      final log = _Log();
      final clock = _Clock(DateTime(2026, 8, 15, 12, 0));
      final hb = AppHeartbeat(
        reportEvery: const Duration(minutes: 30),
        probe: () async {},
        clock: clock.now,
        logEntries: () => [log.entryAt(clock.at(const Duration(minutes: -31)))],
      );

      final before = AppLog.entries.length;
      await hb.tick();
      final written = AppLog.entries.skip(before).toList();
      expect(written, hasLength(1),
          reason: 'без этой строки провал в журнале ничего не доказывает');
      expect(written.single.message, contains('Приложение живо'));
      expect(written.single.level, LogLevel.info);
    });

    test('журнал не молчал — отметки нет', () async {
      final clock = _Clock(DateTime(2026, 8, 15, 12, 0));
      final log = _Log();
      final hb = AppHeartbeat(
        reportEvery: const Duration(minutes: 30),
        probe: () async {},
        clock: clock.now,
        // Строка была минуту назад: подключение, пинг, разбор обрыва — там
        // записей и без нас хватает, и отметка была бы шумом.
        logEntries: () => [log.entryAt(clock.at(const Duration(minutes: -1)))],
      );

      final before = AppLog.entries.length;
      await hb.tick();
      expect(AppLog.entries.length, before);
    });

    test('журнал пуст — отметку не ставим (тишины ещё не было)', () async {
      final clock = _Clock(DateTime(2026, 8, 15, 12, 0));
      final hb = AppHeartbeat(
        probe: () async {},
        clock: clock.now,
        logEntries: () => const [],
      );
      final before = AppLog.entries.length;
      await hb.tick();
      expect(AppLog.entries.length, before);
    });
  });

  // ── Провал в работе ────────────────────────────────────────────────────────

  group('перерыв между тактами', () {
    test('⚠️ опоздание такта названо, и причина НЕ выдумана', () async {
      final clock = _Clock(DateTime(2026, 8, 15, 12, 0));
      final log = _Log();
      final hb = AppHeartbeat(
        interval: const Duration(minutes: 1),
        reportEvery: const Duration(hours: 99), // отметку сюда не подмешиваем
        probe: () async {},
        clock: clock.now,
        logEntries: () => [log.entryAt(clock.now())],
      );

      await hb.tick(); // задаёт точку отсчёта
      clock.advance(const Duration(minutes: 40));
      final before = AppLog.entries.length;
      await hb.tick();

      final written = AppLog.entries.skip(before).toList();
      expect(written, hasLength(1));
      expect(written.single.level, LogLevel.warn);
      expect(written.single.message, contains('40 мин'));
      // ⚠️ Честность формулировки — часть требования: таймер, не сработавший
      // вовремя, одинаково объясняется сном процесса и остановкой изолята.
      // Назвать одну причину значило бы увести следующий разбор в сторону.
      expect(written.single.message, contains('Doze'));
    });

    test('такт в срок молчит', () async {
      final clock = _Clock(DateTime(2026, 8, 15, 12, 0));
      final log = _Log();
      final hb = AppHeartbeat(
        interval: const Duration(minutes: 1),
        reportEvery: const Duration(hours: 99),
        probe: () async {},
        clock: clock.now,
        logEntries: () => [log.entryAt(clock.now())],
      );
      await hb.tick();
      clock.advance(const Duration(minutes: 1));
      final before = AppLog.entries.length;
      await hb.tick();
      expect(AppLog.entries.length, before);
    });
  });

  // ── Отзывчивость главного потока ───────────────────────────────────────────

  group('главный поток Android', () {
    test('⚠️ ГЛАВНОЕ: долгий ответ канала объявляется застреванием', () async {
      final clock = _Clock(DateTime(2026, 8, 15, 12, 0));
      final log = _Log();
      final hb = AppHeartbeat(
        stall: const Duration(seconds: 1),
        reportEvery: const Duration(hours: 99),
        // Часы двигаем ВНУТРИ пробы: так замеряется ровно тот отрезок, который
        // на устройстве занимает занятый главный поток.
        probe: () async => clock.advance(const Duration(seconds: 4)),
        clock: clock.now,
        logEntries: () => [log.entryAt(clock.now())],
      );

      final before = AppLog.entries.length;
      await hb.tick();
      final written = AppLog.entries.skip(before).toList();
      expect(written, hasLength(1));
      expect(written.single.level, LogLevel.warn);
      expect(written.single.message, contains('Главный поток Android'));
    });

    test('быстрый ответ ничего не пишет', () async {
      final clock = _Clock(DateTime(2026, 8, 15, 12, 0));
      final log = _Log();
      final hb = AppHeartbeat(
        stall: const Duration(seconds: 1),
        reportEvery: const Duration(hours: 99),
        probe: () async {},
        clock: clock.now,
        logEntries: () => [log.entryAt(clock.now())],
      );
      final before = AppLog.entries.length;
      await hb.tick();
      expect(AppLog.entries.length, before);
    });

    test('жалоба не повторяется на каждом такте', () async {
      // Главный поток может стоять минутами — такты один за другим увидят одно
      // и то же, и без ограничителя жалоба заняла бы весь журнал. Ровно этим
      // болел вывод ошибок VPN-сервиса до 1.4.x.
      final clock = _Clock(DateTime(2026, 8, 15, 12, 0));
      final log = _Log();
      final hb = AppHeartbeat(
        // Такт длинный намеренно: иначе перемотка на шесть минут ниже сама
        // сошла бы за пропуск такта и добавила вторую, постороннюю строку.
        interval: const Duration(minutes: 5),
        stall: const Duration(seconds: 1),
        stallReportEvery: const Duration(minutes: 5),
        reportEvery: const Duration(hours: 99),
        probe: () async => clock.advance(const Duration(seconds: 4)),
        clock: clock.now,
        logEntries: () => [log.entryAt(clock.now())],
      );

      final before = AppLog.entries.length;
      await hb.tick(); // 12:00 — жалоба
      await hb.tick(); // +4 с — молчим
      await hb.tick(); // +8 с — молчим
      expect(AppLog.entries.length - before, 1);

      clock.advance(const Duration(minutes: 6));
      await hb.tick();
      expect(AppLog.entries.length - before, 2, reason: 'через 5 мин — снова');
    });

    test('канал недоступен — это не застревание', () async {
      // Обработчика может не быть вовсе (Windows-сборка, движок ещё не поднят).
      // Выдать отказ канала за «интерфейс стоял» значило бы врать в отчёте.
      final clock = _Clock(DateTime(2026, 8, 15, 12, 0));
      final log = _Log();
      final hb = AppHeartbeat(
        stall: const Duration(seconds: 1),
        reportEvery: const Duration(hours: 99),
        probe: () async {
          clock.advance(const Duration(seconds: 9));
          throw Exception('MissingPluginException');
        },
        clock: clock.now,
        logEntries: () => [log.entryAt(clock.now())],
      );
      final before = AppLog.entries.length;
      await hb.tick();
      expect(AppLog.entries.length, before);
    });
  });

  // ── Такты не наслаиваются ──────────────────────────────────────────────────

  test('пока такт идёт, следующий не начинается', () async {
    // Иначе на застрявшем главном потоке очередь замеров сама стала бы
    // нагрузкой: каждую минуту плюс один висящий вызов канала.
    final clock = _Clock(DateTime(2026, 8, 15, 12, 0));
    final log = _Log();
    var calls = 0;
    final gate = Completer<void>();
    final hb = AppHeartbeat(
      reportEvery: const Duration(hours: 99),
      probe: () async {
        calls++;
        await gate.future;
      },
      clock: clock.now,
      logEntries: () => [log.entryAt(clock.now())],
    );

    final first = hb.tick();
    await Future<void>.delayed(Duration.zero);
    await hb.tick();
    expect(calls, 1);
    gate.complete();
    await first;
    await hb.tick();
    expect(calls, 2);
  });
}

// ── Обвязка ──────────────────────────────────────────────────────────────────

class _Clock {
  _Clock(this._at);
  DateTime _at;
  DateTime now() => _at;
  DateTime at(Duration d) => _at.add(d);
  void advance(Duration d) => _at = _at.add(d);
}

class _Log {
  LogEntry entryAt(DateTime at) => LogEntry(at, LogLevel.info, 'прочее');
}
