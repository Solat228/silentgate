import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/tun/app_alive_mutex.dart';

/// «ЖИВ ЛИ ИНТЕРФЕЙС» — ПРЕДОХРАНИТЕЛЬ ПЕРЕД ВКЛЮЧЕНИЕМ KILL SWITCH.
///
/// ⚠️ РАДИ ЧЕГО. Фильтры WFP держит элевейтнутый помощник TUN, и его смерть —
/// штатный сигнал снять блокировку. Но с интерфейсом он не связан ничем:
/// закройте приложение — помощник останется работать, а блокировка стоять, и
/// снять её будет некому. Машина без сети.
///
/// ⚠️ ЧЕГО ЗДЕСЬ ПРОВЕРИТЬ НЕЛЬЗЯ, И ПОЧЕМУ. Положительный случай («владелец
/// жив») в одном процессе не воспроизводится: мьютекс, взятый этим же потоком,
/// захватывается ПОВТОРНО, и `WaitForSingleObject` возвращает `WAIT_OBJECT_0`,
/// а не `WAIT_TIMEOUT`. То есть тест увидел бы «умер» там, где помощник —
/// отдельный процесс — увидит «жив». Врать себе зелёным тестом хуже, чем не
/// иметь его: проверяем то, что проверяется, а остальное — живым прогоном в VM.
void main() {
  group('Имя сессии', () {
    test('⚠️ у каждой сессии своё имя, а не номер процесса', () {
      // Номер процесса Windows переиспользует — помощник начал бы следить за
      // посторонним. Имя случайное и длинное: совпадение исключено на практике.
      final a = AppAliveMutex.tokenForTest();
      final b = AppAliveMutex.tokenForTest();
      expect(a, isNot(b));
      expect(a, startsWith('SilentGateAlive-'));
      expect(a.length, greaterThan('SilentGateAlive-'.length + 20));
    });
  });

  group('⚠️ «Не знаю» ведёт себя как «нельзя»', () {
    test('пустое имя — наблюдения нет', () {
      // Помощник без наблюдения не имеет права поднимать блокировку: снять её
      // будет некому. Поэтому неизвестность обязана давать null, а не объект.
      expect(AppAliveMutex.watch(''), isNull);
    });

    test('несуществующее имя — наблюдения нет', () {
      expect(AppAliveMutex.watch(r'Local\SilentGateAlive-нетакого0000'), isNull,
          reason: 'приложения с таким мьютексом нет — значит его нет вовсе');
    }, skip: !Platform.isWindows);
  });

  group('⚠️ Стражи по исходнику', () {
    String code(String path) => File(path)
        .readAsLinesSync()
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///');
        })
        .join(String.fromCharCode(10));

    test('⚠️ мьютекс НИКОГДА не отпускается', () {
      // Отпущенный мьютекс перестаёт быть признаком жизни: ожидающий тут же
      // получит WAIT_OBJECT_0 и решит, что приложение умерло, — то есть снимет
      // защиту посреди рабочей сессии.
      final s = code('lib/engine/windows/tun/app_alive_mutex.dart');
      expect(s.contains('ReleaseMutex'), isFalse,
          reason: 'признак жизни держится ровно на невозвращённом владении');
      expect(s, contains('_createMutex(nullptr, 1,'),
          reason: 'мьютекс обязан браться ВО ВЛАДЕНИЕ (initialOwner = 1)');
    });

    test('⚠️ помощник выходит, когда интерфейс умер', () {
      final s = code('lib/engine/windows/tun/tun_helper.dart');
      expect(s, contains('alive.appAlive'),
          reason: 'без этой проверки помощник переживает приложение');
      expect(s, contains('AppAliveMutex.watch('));
    });

    test('⚠️ имя передаётся ДО запуска помощника', () {
      // Помощник читает имя один раз, на старте. Положив файл позже, мы
      // получили бы помощника без слежения — ровно того, кто переживёт падение.
      final s = code('lib/engine/windows/tun/singbox_router_windows.dart');
      final acquireAt = s.indexOf('AppAliveMutex.acquire()');
      final launchAt = s.indexOf('TunScheduledTask.exists()');
      expect(acquireAt, greaterThan(0));
      expect(launchAt, greaterThan(acquireAt),
          reason: 'признак жизни обязан лечь на диск раньше запуска');
    });

    test('⚠️ stop-файл больше не стирается в начале попытки', () {
      // Это и была гонка: неудачная комбинация ставит stop-файл, а следующая
      // стирала его раньше, чем помощник успевал прочитать (400 мс опрос против
      // окна в 393–515 мс). Промах = живой помощник, которого не остановить.
      final s = code('lib/engine/windows/tun/singbox_router_windows.dart');
      final waitAt = s.indexOf('waitStopConsumed');
      final clearAt = s.indexOf('clearStopAt');
      expect(waitAt, greaterThan(0), reason: 'ожидание должно появиться');
      expect(clearAt, greaterThan(waitAt),
          reason: 'стирание допустимо только ПОСЛЕ неудачного ожидания');
    });
  });
}
