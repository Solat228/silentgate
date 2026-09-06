import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/network_error_hint.dart';
import 'package:silentgate/core/platform/time_sync_windows.dart';

/// СИНХРОНИЗАЦИЯ ВРЕМЕНИ ПРЕДЛАГАЕТСЯ КНОПКОЙ, А НЕ СОВЕТОМ.
///
/// ⚠️ ОТКУДА. Живой клиент 05.09.2026 не смог импортировать подписку:
/// `certificate is not yet valid` — часы его компьютера отставали, и
/// сертификат сервера считался ещё не начавшим действовать. Решение владельца:
/// не отправлять человека в настройки Windows, а предложить кнопку и сделать
/// это за него.
void main() {
  group('⚠️ Когда предлагать синхронизацию', () {
    test('расхождение меньше минуты не мешает сертификату — кнопки нет', () {
      // Иначе кнопка появлялась бы у всех подряд: пара секунд расхождения есть
      // на любой машине, а сертификату они не мешают ничем.
      expect(TimeSyncWindows.worthSyncing(const Duration(seconds: 40)), isFalse);
      expect(TimeSyncWindows.worthSyncing(Duration.zero), isFalse);
      expect(TimeSyncWindows.worthSyncing(null), isFalse);
    });

    test('серьёзное расхождение — предлагаем', () {
      expect(TimeSyncWindows.worthSyncing(const Duration(hours: 5)), isTrue);
      // ⚠️ И в ОБЕ стороны: часы могут спешить, и тогда сертификат выглядит
      // истёкшим. Знак расхождения на вывод не влияет.
      expect(TimeSyncWindows.worthSyncing(const Duration(days: -400)), isTrue);
    });
  });

  group('Расхождение считается по ответу сервера', () {
    test('битый или пустой заголовок не притворяется нулём', () {
      // ⚠️ Ноль означал бы «часы верны» — то есть противоположное «мы не
      // знаем». На таком молчаливом подлоге кнопка не появилась бы там, где
      // она как раз нужна.
      expect(TimeSyncWindows.skewFrom(null), isNull);
      expect(TimeSyncWindows.skewFrom(''), isNull);
      expect(TimeSyncWindows.skewFrom('вчера вечером'), isNull);
    });

    test('настоящий заголовок разбирается', () {
      final past = HttpDate.format(
          DateTime.now().toUtc().subtract(const Duration(hours: 3)));
      final skew = TimeSyncWindows.skewFrom(past);
      expect(skew, isNotNull);
      // Часы компьютера ВПЕРЕДИ серверных на три часа.
      expect(skew!.inMinutes, closeTo(180, 2));
    });
  });

  test('⚠️ подсказка про часы и кнопка говорят об одном и том же случае', () {
    // Кнопка обязана появляться ровно там, где подсказка советует проверить
    // время. Разъехавшись, они дали бы худшее из двух: совет без действия либо
    // действие без объяснения.
    final hint = networkErrorHint(
        'CERTIFICATE_VERIFY_FAILED: certificate is not yet valid')!;
    expect(hint.kind, NetworkErrorKind.clockBehind);
    expect(NetworkErrorKind.values, contains(NetworkErrorKind.certExpired));
  });

  test('на не-Windows синхронизация не предлагается', () {
    // На Android часы синхронизирует система, и своей кнопки там быть не
    // должно: она вела бы в никуда.
    expect(TimeSyncWindows.isSupported, Platform.isWindows);
  });

  test('⚠️ отказ в правах не тупик: есть ручной путь', () {
    // Решение владельца 05.09.2026 — «оба»: и кнопка, и инструкция. Отказ от
    // UAC законен, и человек, уже понявший, что виноваты часы, обязан узнать,
    // куда идти руками. Там прав администратора не нужно.
    expect(TimeSyncWindows.manualHint, contains('Время и язык'));
    expect(TimeSyncWindows.manualHint, contains('автоматически'));
    // И это НЕ тот же текст, что при успехе: путать их — значит сказать
    // «готово» там, где ничего не сделано.
    expect(TimeSyncWindows.manualHint, isNot(TimeSyncWindows.okText));
  });

  test('⚠️ ручной путь ПОКАЗЫВАЕТСЯ, а не просто объявлен', () {
    final src = File('lib/ui/import_screen.dart').readAsStringSync();
    expect(src, contains('TimeSyncWindows.manualHint'),
        reason: 'при отказе в правах человек упрётся в тупик');
  });
}
