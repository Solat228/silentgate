import 'dart:io';
import 'dart:math';

/// ПЕРЕЗАПУСК ЯДРА ТУННЕЛЯ БЕЗ СНЯТИЯ БЛОКИРОВКИ: ПРОСЬБА И ОТВЕТ ФАЙЛАМИ.
///
/// ⚠️ ЗАЧЕМ. Пересоздание туннеля раньше шло так: stop-файл → помощник снимает
/// фильтры WFP и выходит → пауза → новый помощник поднимает фильтры заново.
/// Между снятием и подъёмом — окно до нескольких секунд, в котором у машины
/// нет ни туннеля, ни блокировки, и трафик идёт под реальным IP. При kill
/// switch это ровно та утечка, ради которой он включён.
///
/// Двух помощников одновременно не бывает: задача Планировщика запускается с
/// `IgnoreNew`, второй запуск при живом первом молча теряется. Значит передать
/// блокировку «из рук в руки» другому процессу нельзя — и не нужно: тот же
/// помощник может остановить старое ядро и запустить новое, НЕ ОТПУСКАЯ свой
/// набор фильтров.
///
/// Протокол — те же файлы в каталоге данных, что и stop-файл: помощник
/// элевейтнут, интерфейс нет, другого общего канала у них нет.
///  * интерфейс пишет новый конфиг и план блокировки, затем [request];
///  * помощник забирает просьбу ([take]), делает перезапуск и пишет ответ
///    ([answer]) с тем же токеном;
///  * интерфейс ждёт ответа ([waitAnswer]). Ответ «отказ» или тишина — обычный
///    путь через stop-файл: помощник цел и продолжает работать как раньше.
abstract final class TunReload {
  static const requestName = 'tun_reload';
  static const answerName = 'tun_reload_ack';

  static String requestPathFor(Directory dir) =>
      '${dir.path}${Platform.pathSeparator}$requestName';
  static String answerPathFor(Directory dir) =>
      '${dir.path}${Platform.pathSeparator}$answerName';

  /// Попросить перезапуск. Возвращает токен, по которому узнаётся ответ.
  ///
  /// ⚠️ ТОКЕН ОБЯЗАТЕЛЕН. Ответ на прошлую, уже брошенную просьбу (интерфейс
  /// устал ждать и пошёл обычным путём) иначе был бы принят за ответ на
  /// новую — и интерфейс счёл бы туннель перезапущенным, когда его нет.
  static String request(Directory dir) {
    final token = '${DateTime.now().microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(1 << 31)}';
    _delete(answerPathFor(dir));
    File(requestPathFor(dir)).writeAsStringSync(token, flush: true);
    return token;
  }

  /// Забрать просьбу (помощник). `null` — просьбы нет.
  ///
  /// Файл удаляется сразу: просьба исполняется один раз, даже если перезапуск
  /// не удался — повторять его решает интерфейс, а не помощник.
  static String? take(Directory dir) {
    try {
      final f = File(requestPathFor(dir));
      if (!f.existsSync()) return null;
      final token = f.readAsStringSync().trim();
      f.deleteSync();
      return token.isEmpty ? null : token;
    } catch (_) {
      return null;
    }
  }

  /// Ответить на просьбу (помощник).
  static void answer(Directory dir, String token, TunReloadAnswer a) {
    try {
      File(answerPathFor(dir))
          .writeAsStringSync(a.encode(token), flush: true);
    } catch (_) {}
  }

  /// Отозвать просьбу, которую помощник так и не забрал (интерфейс).
  ///
  /// ⚠️ Без этого просьба пролежала бы до следующего помощника — а тот
  /// перезапустил бы своё только что поднятое ядро на ровном месте.
  static void cancel(Directory dir) => _delete(requestPathFor(dir));

  /// Дождаться ответа на просьбу [token]. `null` — не дождались или отменили.
  static Future<TunReloadAnswer?> waitAnswer(Directory dir, String token,
      {Duration timeout = const Duration(seconds: 20),
      bool Function()? abort,
      Duration poll = const Duration(milliseconds: 150)}) async {
    final deadline = DateTime.now().add(timeout);
    final f = File(answerPathFor(dir));
    while (DateTime.now().isBefore(deadline)) {
      if (abort?.call() ?? false) return null;
      try {
        if (f.existsSync()) {
          final a = TunReloadAnswer.decode(f.readAsStringSync(), token);
          if (a != null) {
            _delete(f.path);
            return a;
          }
        }
      } catch (_) {}
      await Future<void>.delayed(poll);
    }
    return null;
  }

  static void _delete(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

/// Ответ помощника на просьбу о перезапуске.
class TunReloadAnswer {
  const TunReloadAnswer.started() : started = true, reason = '';
  const TunReloadAnswer.refused(this.reason) : started = false;

  /// Новое ядро запущено, блокировка не снималась ни на миг.
  final bool started;

  /// Почему не вышло — для журнала интерфейса.
  final String reason;

  String encode(String token) =>
      started ? '$token\nstarted' : '$token\nrefused\n$reason';

  /// Разобрать ответ. `null` — ответ не на эту просьбу или не дописан.
  static TunReloadAnswer? decode(String raw, String token) {
    final lines = raw.split('\n');
    if (lines.length < 2 || lines[0].trim() != token) return null;
    switch (lines[1].trim()) {
      case 'started':
        return const TunReloadAnswer.started();
      case 'refused':
        return TunReloadAnswer.refused(
            lines.length > 2 ? lines.sublist(2).join('\n').trim() : '');
    }
    return null;
  }
}
