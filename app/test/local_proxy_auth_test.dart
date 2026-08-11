import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/engine_base.dart';

/// Пароль на локальные прокси ядра.
///
/// ⚠️ ЗАЧЕМ ЭТО СТЕРЕЖЁТСЯ. Локальный порт ядра — полноценный прокси в VPN
/// пользователя. Без пароля к нему подключается что угодно на той же машине и
/// получает туннель целиком: выходной IP, квоту подписки и обход раздельного
/// туннелирования, включая приложения с действием «Блок».
///
/// Ошибиться здесь можно ровно двумя способами, и оба МОЛЧАЛИВЫЕ:
///  * пароль не поставился — дыра, но всё работает;
///  * пароль поставился там, где нельзя (системный прокси Windows) — WinINET
///    креденшелов не передаёт, и весь интернет получает 407.
class _Engine extends VpnEngineBase {
  @override
  Future<void> startSession() async {}
  @override
  Future<void> teardownCore({bool keepCapture = false}) async {}
  @override
  Future<void> platformCleanup() async {}
}

void main() {
  _Engine engine() => _Engine();

  group('Умолчание — пароль ВКЛючён', () {
    test('новая установка получает пароль без единой настройки', () {
      expect(const AppSettings().localProxyAuth, isTrue);
      final e = engine();
      e.applyLocalProxyAuth(const AppSettings(), systemProxyMode: false);
      expect(e.localInboundUser, isNotEmpty);
      expect(e.localInboundPassword, isNotEmpty);
    });

    test('пароль РАЗНЫЙ на каждую сессию', () {
      // Посессионный пароль не переживает перезапуск и не попадает
      // в резервные копии — в этом и смысл умолчания.
      final e = engine();
      e.applyLocalProxyAuth(const AppSettings(), systemProxyMode: false);
      final first = e.localInboundPassword;
      e.applyLocalProxyAuth(const AppSettings(), systemProxyMode: false);
      expect(e.localInboundPassword, isNot(first));
    });

    test('пароль длинный: подобрать перебором нереально', () {
      final e = engine();
      e.applyLocalProxyAuth(const AppSettings(), systemProxyMode: false);
      expect(e.localInboundPassword.length, greaterThanOrEqualTo(32));
    });
  });

  group('⚠️ Системный прокси — пароля быть НЕ ДОЛЖНО', () {
    test('в режиме системного прокси креды не выдаются', () {
      // WinINET их не передаёт: каждый запрос получил бы 407, и интернет лёг бы
      // целиком. Настройка уступает режиму захвата, а не ломает подключение.
      final e = engine();
      e.applyLocalProxyAuth(const AppSettings(), systemProxyMode: true);
      expect(e.localInboundUser, isEmpty);
      expect(e.localInboundPassword, isEmpty);
    });

    test('даже заданный вручную пароль там не применяется', () {
      final e = engine();
      e.applyLocalProxyAuth(
          const AppSettings(localProxyUser: 'me', localProxyPassword: 'pw'),
          systemProxyMode: true);
      expect(e.localInboundUser, isEmpty);
    });
  });

  group('Пользователь задал свои значения', () {
    test('логин и пароль применяются как есть', () {
      // Нужно, чтобы прописать наш прокси в стороннюю программу.
      final e = engine();
      e.applyLocalProxyAuth(
          const AppSettings(localProxyUser: 'me', localProxyPassword: 'pw'),
          systemProxyMode: false);
      expect(e.localInboundUser, 'me');
      expect(e.localInboundPassword, 'pw');
    });

    test('свой логин без пароля — пароль всё равно случайный', () {
      // Полупустая пара означала бы инбаунд без защиты: логин без пароля
      // проверять нечем.
      final e = engine();
      e.applyLocalProxyAuth(
          const AppSettings(localProxyUser: 'me'), systemProxyMode: false);
      expect(e.localInboundUser, 'me');
      expect(e.localInboundPassword.length, greaterThanOrEqualTo(32));
    });

    test('пробелы вокруг логина срезаются', () {
      final e = engine();
      e.applyLocalProxyAuth(
          const AppSettings(localProxyUser: '  me  ', localProxyPassword: 'pw'),
          systemProxyMode: false);
      expect(e.localInboundUser, 'me');
    });
  });

  group('Пользователь выключил пароль осознанно', () {
    test('креды не выдаются', () {
      final e = engine();
      e.applyLocalProxyAuth(
          const AppSettings(localProxyAuth: false), systemProxyMode: false);
      expect(e.localInboundUser, isEmpty);
      expect(e.localInboundPassword, isEmpty);
    });

    test('выключение сильнее заданных вручную значений', () {
      // Иначе галочка «выключено» не выключала бы ничего.
      final e = engine();
      e.applyLocalProxyAuth(
          const AppSettings(
              localProxyAuth: false,
              localProxyUser: 'me',
              localProxyPassword: 'pw'),
          systemProxyMode: false);
      expect(e.localInboundUser, isEmpty);
    });
  });

  group('Настройки переживают сохранение', () {
    test('все три поля доезжают через JSON', () {
      // Класс багов «поле пишется, но не читается» — самый частый в этом
      // проекте; общий страж есть в settings_roundtrip_test.
      const s = AppSettings(
          localProxyAuth: false,
          localProxyUser: 'me',
          localProxyPassword: 'pw');
      final back = AppSettings.fromJson(s.toJson());
      expect(back.localProxyAuth, isFalse);
      expect(back.localProxyUser, 'me');
      expect(back.localProxyPassword, 'pw');
    });

    test('старые настройки получают пароль ВКЛ, а не выкл', () {
      // Ключа у них нет. Умолчание обязано быть безопасным: обновление не
      // должно молча оставить порт открытым.
      final back = AppSettings.fromJson({});
      expect(back.localProxyAuth, isTrue);
      expect(back.localProxyUser, isEmpty);
      expect(back.localProxyPassword, isEmpty);
    });
  });
}
