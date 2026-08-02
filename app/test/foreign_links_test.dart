import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/url_scheme.dart';

/// При переходе с другого клиента человек первым делом пробует ссылку, которую
/// ему прислали. Если приложение на неё не отзовётся — он решит, что импорт
/// сломан, а не что схема чужая.
void main() {
  const sub = 'https://example.org/sub/abc123';

  group('Чужие схемы импорта', () {
    test('happ://add/<ссылка>', () {
      expect(AppUrlScheme.importPayload('happ://add/$sub'), sub);
    });

    test('clash://install-config?url=<ссылка>', () {
      expect(AppUrlScheme.importPayload(
          'clash://install-config?url=${Uri.encodeComponent(sub)}'), sub);
    });

    test('sing-box://import-remote-profile/?url=<ссылка>', () {
      expect(AppUrlScheme.importPayload(
          'sing-box://import-remote-profile/?url=${Uri.encodeComponent(sub)}'), sub);
    });

    test('streisand://import/<ссылка>', () {
      expect(AppUrlScheme.importPayload('streisand://import/$sub'), sub);
    });

    test('hiddify://import/<ссылка>', () {
      expect(AppUrlScheme.importPayload('hiddify://import/$sub'), sub);
    });
  });

  group('Своя схема — обе формы', () {
    test('историческая import?url=', () {
      expect(AppUrlScheme.importPayload(
          'silentgate://import?url=${Uri.encodeComponent(sub)}'), sub);
    });

    test('отраслевая add/<ссылка> — её строит страница подписки', () {
      expect(AppUrlScheme.importPayload('silentgate://add/$sub'), sub);
    });
  });

  group('Ссылку Happ с шифрованием мы не прочитаем никогда', () {
    // Ключи вшиты в само приложение Happ: механизм для того и сделан, чтобы
    // адрес подписки был скрыт от пользователя. Честно сказать об этом лучше,
    // чем выдать «неверный формат».
    test('crypt5 опознаётся как таковая', () {
      expect(AppUrlScheme.isHappCryptoLink('happ://crypt5/AAAA'), isTrue);
      expect(AppUrlScheme.isHappCryptoLink('happ://crypt4/AAAA'), isTrue);
    });

    test('и НЕ выдаётся за пригодный адрес подписки', () {
      expect(AppUrlScheme.importPayload('happ://crypt5/AAAA'), isNull);
    });

    test('обычная happ-ссылка криптой не считается', () {
      expect(AppUrlScheme.isHappCryptoLink('happ://add/$sub'), isFalse);
    });
  });

  test('чужая неизвестная схема не притворяется импортом', () {
    expect(AppUrlScheme.importPayload('randomapp://add/$sub'), isNull);
  });
}
