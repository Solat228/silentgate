import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/platform/app_log.dart';

/// Отметка «приложение живо» в журнале — и замер отзывчивости главного потока
/// Android.
///
/// ⚠️ ЗАЧЕМ ЭТО ВООБЩЕ ПОЯВИЛОСЬ. 15.08.2026 владелец прислал отчёт с телефона:
/// «внезапно зависло приложение». В `app.log` последняя строка — 12:18:42, отчёт
/// снят в 13:00:54. Сорок две минуты тишины — и **ответить по ним нельзя ни да,
/// ни нет**: журнал пишется только по событиям, а сторож канала и наблюдатель
/// сети молчат, пока всё исправно. То есть ровно на главный вопрос отчёт
/// поддержки не отвечал, и это отдельный дефект — не менее важный, чем само
/// зависание.
///
/// Что даёт эта отметка:
///
///  * **пропуск в журнале теперь значит что-то определённое.** Пока приложение
///    живо, строка появляется не реже [reportEvery]; её отсутствие — это уже
///    улика, а не «нечего было писать»;
///  * **следующий такт называет длину провала.** Таймер не сработал вовремя —
///    пишем, на сколько опоздал. Причин две, и обе полезны: процесс усыпили
///    (Doze, выгрузка), либо изолят действительно стоял;
///  * **отдельно меряется ГЛАВНЫЙ ПОТОК ANDROID.** Dart живёт на своём потоке, и
///    работающий таймер сам по себе НЕ доказывает, что интерфейс отвечает:
///    Flutter получает vsync и касания через `Choreographer` главного потока
///    платформы. Поэтому такт ходит в канал `lol.silentgate/device` (его
///    обработчики исполняются именно там) и засекает время ответа.
///
/// ⚠️ ЖУРНАЛ НЕ ЗАСОРЯЕТСЯ. Отметка пишется, ТОЛЬКО если в журнале и без неё
/// [reportEvery] ничего не появилось: во время подключения, пинга и обрывов
/// строк и так хватает, а дорога отметка ровно в тишине. В штатной работе это
/// десятки строк в сутки, при активной — ноль.
class AppHeartbeat {
  AppHeartbeat({
    this.interval = const Duration(minutes: 1),
    this.reportEvery = const Duration(minutes: 30),
    this.stall = const Duration(seconds: 1),
    this.stallReportEvery = const Duration(minutes: 5),
    Future<void> Function()? probe,
    DateTime Function()? clock,
    List<LogEntry> Function()? logEntries,
  })  : _probe = probe ?? _platformPing,
        _now = clock ?? DateTime.now,
        _entries = logEntries ?? (() => AppLog.entries);

  /// Как часто просыпаемся. Такт дешёвый: один вызов канала.
  final Duration interval;

  /// Как долго журнал может молчать, прежде чем мы поставим отметку.
  final Duration reportEvery;

  /// С какого времени ответа считаем, что главный поток стоял.
  final Duration stall;

  /// Не чаще этого жалуемся на застревания: если главный поток занят надолго,
  /// такты один за другим увидят одно и то же, и жалоба заняла бы весь журнал.
  final Duration stallReportEvery;

  final Future<void> Function() _probe;
  final DateTime Function() _now;
  final List<LogEntry> Function() _entries;

  Timer? _timer;
  DateTime? _lastTick;
  DateTime? _lastStallReport;

  /// Худший ответ главного потока с прошлой отметки — он и едет в журнал.
  Duration _worst = Duration.zero;

  /// Идёт ли такт: канал может отвечать дольше, чем [interval], и накладывать
  /// такты друг на друга нельзя — очередь замеров сама стала бы нагрузкой.
  bool _busy = false;

  bool get running => _timer != null;

  void start() {
    if (_timer != null) return;
    _lastTick = _now();
    _timer = Timer.periodic(interval, (_) => unawaited(tick()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Один такт. Публичный ради теста: подменять таймер в тесте — значит
  /// проверять не тот код, который работает у пользователя.
  @visibleForTesting
  Future<void> tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final started = _now();
      // ⚠️ ПРОВАЛ СЧИТАЕМ ДО ЗАМЕРА, А НЕ ПОСЛЕ. Опоздание такта — это отдельная
      // новость от «главный поток думал»: таймер Dart не сработал вовсе, то есть
      // стоял (или спал) сам изолят.
      final prev = _lastTick;
      _lastTick = started;
      if (prev != null) {
        final late = started.difference(prev);
        // Втрое против такта — уже не дрожание планировщика.
        if (late >= interval * 3) {
          AppLog.w('Перерыв в работе приложения: ${_human(late)} без единого '
              'такта. Либо система усыпила процесс (Doze, выгрузка из памяти), '
              'либо изолят стоял — по журналу это неразличимо, но сам перерыв '
              'теперь виден.');
        }
      }

      var answered = true;
      // ⚠️ ЧАСЫ, А НЕ `Stopwatch`. Секундомер идёт по монотонному времени
      // процесса и подменить его в тесте нечем — а проверять надо ровно то, что
      // здесь считается. Разница для боевого пути нулевая: обе величины меряют
      // один и тот же отрезок.
      try {
        await _probe();
      } catch (_) {
        // Канала может не быть вовсе (нет активности, движок ещё не поднят).
        // Это не застревание — молчим и не выдаём его за отзывчивость.
        answered = false;
      }
      final took = _now().difference(started);

      if (answered) {
        if (took > _worst) _worst = took;
        if (took >= stall) {
          final last = _lastStallReport;
          if (last == null || started.difference(last) >= stallReportEvery) {
            _lastStallReport = started;
            AppLog.w('Главный поток Android не отвечал ${took.inMilliseconds} '
                'мс. Всё это время интерфейс не перерисовывался и не принимал '
                'касаний — снаружи это выглядит как зависание.');
          }
        }
      }

      // ⚠️ Отметку ставим, только если журнал и так молчит. Иначе она лезла бы
      // в середину подключения и разбора обрыва, где строк хватает и без неё.
      final quiet = _quietFor(started);
      if (quiet == null || quiet < reportEvery) return;
      AppLog.i('Приложение живо: тишина в журнале ${_human(quiet)}, '
          'ответ главного потока ${answered ? "до ${_worst.inMilliseconds} мс" : "не получен"}.');
      _worst = Duration.zero;
    } finally {
      _busy = false;
    }
  }

  /// Сколько журнал молчит. `null` — записей нет вовсе (только что запустились),
  /// и отметку ставить рано: она соврала бы про тишину, которой не было.
  Duration? _quietFor(DateTime now) {
    final entries = _entries();
    if (entries.isEmpty) return null;
    return now.difference(entries.last.at);
  }

  static String _human(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds} с';
    if (d.inMinutes < 60) return '${d.inMinutes} мин';
    return '${d.inHours} ч ${d.inMinutes % 60} мин';
  }

  /// ⚠️ КАНАЛ ВЫБРАН НЕ СЛУЧАЙНО: обработчики `lol.silentgate/device` идут на
  /// ГЛАВНОМ потоке Android (в отличие от `apps` и `probe`, которые уводят
  /// работу в фон). Значит время этого вызова и есть отзывчивость интерфейса.
  static Future<void> _platformPing() =>
      const MethodChannel('lol.silentgate/device').invokeMethod<bool>('alive');
}
