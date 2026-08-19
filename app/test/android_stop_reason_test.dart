import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// «КТО ОСТАНОВИЛ ТУННЕЛЬ» — ЧЕЛОВЕК ИЛИ МЫ САМИ.
///
/// ⚠️ ЧТО СЛОМАЛОСЬ И КАК ЭТО ВЫГЛЯДЕЛО. Сервис помечал остановку
/// пользовательской на ЛЮБОЙ `ACTION_STOP`. А ту же команду шлёт наше
/// собственное восстановление связи: сторож канала решает переподключиться,
/// гасит ядро — сервис рапортует «остановил пользователь», Dart честно
/// отменяет запланированное восстановление, и туннель больше не возвращается.
///
/// Поймано живым прогоном на эмуляторе 19.08.2026. В журнале приложения две
/// строки стоят в ОДНУ СЕКУНДУ:
///
/// ```
/// 10:19:36 [WARN] Автопереподключение: канал не пропускает трафик → попытка 1 через 800 мс
/// 10:19:36 [INFO] Туннель снят пользователем из уведомления
/// ```
///
/// ⚠️ ПОЧЕМУ СТРАЖ ЧИТАЕТ ИСХОДНИК, А НЕ ПРОВЕРЯЕТ ПОВЕДЕНИЕ. Это Kotlin:
/// `flutter test` его не компилирует и не запускает вовсе. В этом проекте уже
/// был случай, когда ошибку в Kotlin поймала ТОЛЬКО сборка APK — то есть на
/// полчаса позже и без единой подсказки, что именно сломалось. Чтение текста —
/// единственная проверка, доступная здесь до сборки.
void main() {
  const svc = 'android/app/src/main/kotlin/lol/silentgate/vpn/SilentGateVpnService.kt';
  const tile = 'android/app/src/main/kotlin/lol/silentgate/QuickTileService.kt';
  const main = 'android/app/src/main/kotlin/lol/silentgate/MainActivity.kt';

  /// Текст файла без строк-комментариев: страж не должен ловить сам себя на
  /// собственных пояснениях — такой страж отключают в первый же день.
  String code(String path) => File(path)
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join(String.fromCharCode(10));

  group('⚠️ Признак приходит извне, а не выводится сервисом', () {
    test('обработчик ACTION_STOP читает EXTRA_BY_USER и не ставит true сам', () {
      final s = code(svc);
      expect(s, contains('getBooleanExtra(EXTRA_BY_USER'),
          reason: 'сервис обязан спрашивать, кто просит остановку');
      expect(s.contains('stoppedByUser = true'), isFalse,
          reason: 'безусловная пометка и была дефектом: своё же '
              'переподключение выдавало себя за нажатие человека');
      expect(s, contains('stoppedByUser = byUser'));
    });

    test('константа объявлена ровно одна', () {
      expect(RegExp(r'const val EXTRA_BY_USER').allMatches(code(svc)).length, 1,
          reason: 'две константы с разными значениями — тихое расхождение');
    });
  });

  group('⚠️ КАЖДЫЙ отправитель ACTION_STOP называет себя', () {
    /// Отправителей ровно три, и молчание любого из них — это либо отменённое
    /// восстановление связи (если промолчал наш канал), либо VPN, который не
    /// выключается кнопкой (если промолчала шторка или плитка).
    const senders = <String, bool>{
      // файл : ожидаемое значение признака
      svc: true, // кнопка «Отключить» в шторке
      tile: true, // плитка быстрых настроек
      main: false, // канал из Dart — там намерение знает сама Dart-сторона
    };

    for (final e in senders.entries) {
      test('${e.key.split('/').last}: ставит EXTRA_BY_USER = ${e.value}', () {
        final s = code(e.key);
        final at = s.indexOf('setAction(');
        expect(at, greaterThan(0), reason: 'в файле нет отправки ACTION_STOP — '
            'страж смотрит не туда');
        // Признак обязан стоять В ТОМ ЖЕ выражении построения интента, а не
        // где-то в файле: иначе страж зеленел бы на упоминании в комментарии.
        final tail = s.substring(at, (at + 400).clamp(0, s.length));
        expect(tail, contains('EXTRA_BY_USER'),
            reason: 'интент уходит без признака — остановку не отличить');
        expect(tail, contains('EXTRA_BY_USER, ${e.value}'),
            reason: 'ожидалось ${e.value}');
      });
    }

    test('⚠️ третьего значения не бывает: только true и false', () {
      // Появление, скажем, переменной вместо литерала означало бы, что
      // намерение снова ВЫЧИСЛЯЕТСЯ, а не передаётся, — то есть возврат к
      // исходному дефекту, только замаскированный.
      for (final path in senders.keys) {
        for (final m
            in RegExp(r'EXTRA_BY_USER,\s*([A-Za-z]+)').allMatches(code(path))) {
          expect(['true', 'false'], contains(m.group(1)),
              reason: '$path: признак вычисляется, а не задан явно');
        }
      }
    });
  });

  group('⚠️ Кнопка в шторке переживает пересоздание PendingIntent', () {
    test('FLAG_UPDATE_CURRENT стоит у остановки', () {
      // Без него Android вернул бы РАНЕЕ созданный PendingIntent со старыми
      // extras — признак не доехал бы, и кнопка «Отключить» перестала бы
      // отменять автовосстановление, то есть VPN поднимался бы обратно сам.
      final s = code(svc);
      final at = s.indexOf('setAction(ACTION_STOP)');
      expect(at, greaterThan(0));
      final around = s.substring(at, (at + 400).clamp(0, s.length));
      expect(around, contains('FLAG_UPDATE_CURRENT'));
    });
  });
}
