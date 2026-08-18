import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/windows/windows_engine.dart';

/// СМЕНА СПОСОБА ЗАХВАТА ОБЯЗАНА СНИМАТЬ ПРЕЖНИЙ ЗАХВАТ.
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ. Бесшовная смена сервера удерживает туннель между
/// подключениями — это её смысл. Но «Способ захвата» тоже причина
/// переподключения, и та же ветка срабатывала при переходе
/// TUN → «Системный прокси» / «Только прокси».
///
/// Цена ошибки конкретная: в «Только прокси» пользователь считает, что машина
/// целиком идёт мимо VPN, а живой TUN-адаптер с `0.0.0.0/0` продолжает забирать
/// весь её трафик. Обратный переход оставлял в реестре запись WinINET на
/// локальный порт, который новая сессия могла поднять уже с другим паролем —
/// 407 на каждый запрос.
///
/// Наружу тест не ходит и туннель не поднимает: проверяется РЕШЕНИЕ движка,
/// а не его исполнение.
void main() {
  group('Движок отказывается удерживать захват при смене режима', () {
    // Туннеля в тесте нет, поэтому `_tunActive == false` и ответ всегда «нет» —
    // это и есть безопасное умолчание, которое стережём.
    final engine = WindowsEngine(recoverSystemProxy: false);

    tearDownAll(() async => engine.dispose());

    test('⚠️ без живого туннеля удерживать нечего ни в одном режиме', () {
      for (final m in CaptureMode.values) {
        expect(engine.canKeepCaptureFor(AppSettings(captureMode: m)), isFalse,
            reason: 'режим $m');
      }
    });

    test('смешанный режим тоже под запретом', () {
      // Вместе с адаптером удержался бы и системный прокси на локальный порт.
      expect(
          engine.canKeepCaptureFor(const AppSettings(
              captureMode: CaptureMode.tun, alsoSetSystemProxy: true)),
          isFalse);
    });
  });
}
