import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/network_error_hint.dart';

/// ОШИБКА СЕТИ ОБЪЯСНЯЕТСЯ ЧЕЛОВЕКУ, А НЕ ПЕРЕСКАЗЫВАЕТСЯ ЕМУ ИСХОДНИКОМ.
///
/// ⚠️ ОТКУДА ЗАДАЧА. Живой клиент 05.09.2026 при импорте подписки получил на
/// экран вот это:
///
///   HandshakeException: Handshake error in client (OS Error:
///   CERTIFICATE_VERIFY_FAILED: certificate is not yet valid
///   (../../../flutter/third_party/boringssl/src/ssl/handshake.cc:298))
///
/// Человеку тут нечего делать: ни одного слова о том, что случилось и как это
/// починить, зато есть путь к файлу внутри BoringSSL. А починка при этом
/// тривиальная и полностью на его стороне.
///
/// ⚠️ КЛЮЧЕВОЕ СЛОВО — «NOT YET VALID», И ОНО НЕ ОЗНАЧАЕТ «ПРОСРОЧЕН».
/// Сертификат ещё НЕ НАЧАЛ действовать: его срок начинается позже, чем
/// показывают часы компьютера. То есть часы отстают — севшая батарейка,
/// сбитая дата после переустановки, отключённая синхронизация времени. Сервер
/// и подписка тут ни при чём, и советовать «попробуйте позже» бессмысленно.
void main() {
  group('⚠️ Сертификат ещё не действителен — виноваты часы', () {
    test('распознаём настоящий текст исключения с машины клиента', () {
      const raw = 'HandshakeException: Handshake error in client (OS Error: '
          'CERTIFICATE_VERIFY_FAILED: certificate is not yet valid'
          '(../../../flutter/third_party/boringssl/src/ssl/handshake.cc:298))';
      final hint = networkErrorHint(raw);
      expect(hint, isNotNull, reason: 'ошибка не распознана — человек снова '
          'увидит путь к boringssl');
      expect(hint!.kind, NetworkErrorKind.clockBehind);
    });

    test('подсказка называет ПРИЧИНУ и ДЕЙСТВИЕ, а не пересказывает ошибку',
        () {
      final hint = networkErrorHint(
          'CERTIFICATE_VERIFY_FAILED: certificate is not yet valid')!;
      // Текст обязан говорить про время: это единственное, что человек может
      // сделать сам.
      expect(hint.text.toLowerCase(), contains('врем'));
      // И не должен тащить в интерфейс потроха.
      expect(hint.text, isNot(contains('boringssl')));
      expect(hint.text, isNot(contains('CERTIFICATE_VERIFY_FAILED')));
    });

    test('⚠️ «истёк» — ДРУГОЙ случай и другой совет', () {
      // Часы могут и спешить, но у истёкшего сертификата есть вторая причина:
      // он правда истёк на сервере. Валить оба случая в один совет значит
      // отправить человека крутить часы там, где чинить нужно панель.
      final hint = networkErrorHint(
          'CERTIFICATE_VERIFY_FAILED: certificate has expired')!;
      expect(hint.kind, NetworkErrorKind.certExpired);
      expect(hint.text, isNot(equals(networkErrorHint(
              'CERTIFICATE_VERIFY_FAILED: certificate is not yet valid')!
          .text)));
    });

    test('имя хоста не совпадает — тоже свой случай', () {
      final hint = networkErrorHint(
          'HandshakeException: Handshake error in client (OS Error: '
          'CERTIFICATE_VERIFY_FAILED: Hostname mismatch)')!;
      expect(hint.kind, NetworkErrorKind.hostnameMismatch);
    });

    test('нет сети — самый частый случай, и он не про сертификаты', () {
      final hint = networkErrorHint(
          'SocketException: Failed host lookup: silentgate.lol')!;
      expect(hint.kind, NetworkErrorKind.noNetwork);
      expect(hint.text.toLowerCase(), contains('интернет'));
    });

    test('незнакомую ошибку НЕ выдумываем', () {
      // ⚠️ Подсказка на всё подряд опаснее её отсутствия: человек поверит
      // совету и пойдёт чинить не то. Не узнали — показываем как есть.
      expect(networkErrorHint('Странная ошибка от панели: 502'), isNull);
      expect(networkErrorHint(''), isNull);
    });
  });

  test('⚠️ подсказка ВЫЗЫВАЕТСЯ импортом, а не просто существует', () {
    // В этом проекте «написано и не вызывается» случалось четыре раза, и
    // каждый раз юнит-тесты оставались зелёными: они проверяли САМ КОД, а не
    // его вызов. Здесь цена такой ошибки — человек снова видит путь к
    // boringssl вместо совета проверить часы.
    final src = File('lib/state/app_state.dart').readAsStringSync();
    expect(src, contains('networkErrorHint('),
        reason: 'импорт подписки не переводит ошибку в человеческую');
    // И именно на том месте, где раньше стоял сырой текст.
    expect(src, isNot(contains(r'_error = e.toString();')),
        reason: 'сырой текст исключения снова уходит в интерфейс');
  });
}
