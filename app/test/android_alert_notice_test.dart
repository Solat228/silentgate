import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ОБРЫВ СВЯЗИ НА ANDROID ОБЯЗАН БЫТЬ ВИДЕН ПРИ ЗАКРЫТОМ ПРИЛОЖЕНИИ.
///
/// ⚠️ РАДИ ЧЕГО. На Windows системное уведомление сделали в 1.3.0 после прямой
/// жалобы: сторож канала отработал, туннель переподнялся за шесть секунд,
/// карточка показалась — и владелец её не увидел, потому что окно висело в
/// трее. На Android то же самое, только приложение свёрнуто не «почти всегда»,
/// а ВСЕГДА, и до 20.08.2026 обрыв не показывался нигде: `DesktopNotice.show`
/// на не-Windows писал строку в журнал и выходил.
///
/// ⚠️ ПОЧЕМУ ПРОВЕРКА ПО ИСХОДНИКУ. Всё, что здесь важно, живёт в Kotlin и в
/// системных сервисах Android: канал уведомлений, его важность, PendingIntent.
/// В `flutter test` этого нет вовсе. Зато можно удержать ровно те решения,
/// потеря которых ломает механизм молча, — и каждое из них ниже названо.
void main() {
  String read(String path) => File(path).readAsStringSync();

  String code(String path) => File(path)
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .join(String.fromCharCode(10));

  const alert = 'android/app/src/main/kotlin/lol/silentgate/vpn/AlertNotice.kt';
  const service =
      'android/app/src/main/kotlin/lol/silentgate/vpn/SilentGateVpnService.kt';
  const activity = 'android/app/src/main/kotlin/lol/silentgate/MainActivity.kt';
  const prefs = 'android/app/src/main/kotlin/lol/silentgate/vpn/NativePrefs.kt';
  const notice = 'lib/core/platform/desktop_notice.dart';

  group('⚠️ Dart доносит уведомление до Android', () {
    test('ветка Android стоит ВЫШЕ раннего выхода «показать нечем»', () {
      // Иначе она недостижима: `!Platform.isWindows` истинно и на Android, и
      // весь механизм остался бы ровно там, где был.
      final s = code(notice);
      final android = s.indexOf('Platform.isAndroid');
      final giveUp = s.indexOf('показать нечем на этой платформе');
      expect(android, greaterThan(0), reason: 'ветки Android нет вовсе');
      expect(giveUp, greaterThan(android),
          reason: 'ранний выход обязан стоять НИЖЕ ветки Android');
    });

    test('зовётся метод alert по тому же каналу, что и остальные команды', () {
      final s = code(notice);
      expect(s, contains("MethodChannel('lol.silentgate/vpn')"));
      expect(s, contains("invokeMethod<void>(\n            'alert'"));
    });

    test('⚠️ отказ канала не молчит и называет САМО событие', () {
      // Строка «не удалось показать» без текста уведомления бесполезна: по
      // отчёту поддержки нельзя понять, чего именно человек не увидел.
      final s = code(notice);
      final at = s.indexOf('Не удалось показать уведомление Android');
      expect(at, greaterThan(0));
      expect(s.substring(at, at + 90), contains(r'$title'));
      expect(s.substring(at, at + 90), contains(r'$body'));
    });

    test('нативный обработчик такой метод знает', () {
      expect(code(activity), contains('"alert" ->'),
          reason: 'Dart звал бы метод, которого нет — MissingPluginException');
    });
  });

  group('⚠️ Канал и номер — ОТДЕЛЬНЫЕ от постоянного уведомления', () {
    test('идентификатор канала другой', () {
      expect(code(alert), contains('"silentgate_alerts"'));
      expect(code(service), contains('"silentgate_vpn"'));
    });

    test('⚠️ важность HIGH — иначе сообщение не всплывёт', () {
      // У постоянного IMPORTANCE_LOW, и это НЕ недосмотр: там раз в секунду
      // переписывается строка скорости. Повысив её, мы получили бы звук раз в
      // секунду; понизив наш канал — потеряли бы единственное сообщение,
      // которое человеку важно увидеть.
      expect(code(alert), contains('IMPORTANCE_HIGH'));
      expect(code(service), contains('IMPORTANCE_LOW'));
    });

    test('⚠️ НОМЕР УВЕДОМЛЕНИЯ ДРУГОЙ', () {
      // С одинаковым номером наше сообщение подменило бы строку состояния
      // сервиса — и было бы стёрто следующим тактом счётчиков, то есть меньше
      // чем через секунду.
      final a = RegExp(r'NOTIFICATION_ID\s*=\s*(\d+)').firstMatch(code(alert));
      final s = RegExp(r'NOTIFICATION_ID\s*=\s*(\d+)').firstMatch(code(service));
      expect(a, isNotNull);
      expect(s, isNotNull);
      expect(a!.group(1), isNot(s!.group(1)),
          reason: 'номера совпали — уведомления затирают друг друга');
    });

    test('⚠️ код запроса PendingIntent не совпадает с чужими', () {
      // Android возвращает СУЩЕСТВУЮЩИЙ PendingIntent при совпадении кода: у
      // постоянного уведомления это 0 («открыть»), 1 («отключить») и
      // 2 («свернуть»). Совпади наш — нажатие на сообщение об обрыве
      // отключало бы VPN.
      final used = RegExp(r'PendingIntent\.get\w+\(\s*(?:this|app),\s*(\d+)')
          .allMatches(code(service))
          .map((m) => m.group(1))
          .toSet();
      final ours = RegExp(r'PendingIntent\.get\w+\(\s*app,\s*(\d+)')
          .allMatches(code(alert))
          .map((m) => m.group(1))
          .toSet();
      expect(ours, isNotEmpty, reason: 'переход в приложение пропал');
      expect(ours.intersection(used), isEmpty,
          reason: 'код запроса занят кнопкой постоянного уведомления');
    });

    test('разовое: гаснет по нажатию', () {
      expect(code(alert), contains('setAutoCancel(true)'),
          reason: 'иначе шторка копила бы историю всех обрывов за сутки');
    });

    test('⚠️ длинный текст не обрезается одной строкой', () {
      // В теле — причина обрыва, ради которой уведомление и посылается.
      expect(code(alert), contains('BigTextStyle'));
    });
  });

  group('⚠️ Уведомление постится БЕЗ живого сервиса', () {
    test('это объект, а не метод сервиса', () {
      expect(code(alert), contains('object AlertNotice'));
    });

    test('⚠️ обработчик НЕ спрашивает SilentGateVpnService.instance', () {
      // «Восстановить связь не удалось» приходит ровно тогда, когда сервис уже
      // погашен: спроси мы instance — самое важное сообщение не показывалось бы
      // НИКОГДА. Соседние ветки канала (`showBlocked`, `setNotificationDetail`)
      // именно так и устроены, поэтому ошибиться здесь легко.
      final s = code(activity);
      final at = s.indexOf('"alert" ->');
      expect(at, greaterThan(0));
      final branch = s.substring(at, at + 300);
      expect(branch.contains('SilentGateVpnService.instance'), isFalse,
          reason: 'через instance сообщение о провале не дойдёт никогда');
      expect(branch, contains('AlertNotice.post('));
    });

    test('ошибка внутри не выпускается наружу', () {
      // Отказ в разрешении на уведомления (Android 13+), заблокированный
      // пользователем канал, экзотическая прошивка — законные исходы. Падать
      // ради уведомления нельзя: этот путь идёт по живому обрыву связи.
      expect(code(alert), contains('catch (_: Throwable)'));
    });
  });

  group('⚠️ Язык уведомления — один источник на весь нативный слой', () {
    test('разбор языка живёт в NativePrefs', () {
      final s = code(prefs);
      expect(s, contains('object NativePrefs'));
      expect(s, contains('fun localized('));
      expect(s, contains('"silentgate_native"'));
    });

    test('⚠️ имя хранилища больше нигде не написано литералом', () {
      // Оно было записано дважды — константой в сервисе и строкой в активности.
      // Разъедься они на букву, язык молча перестал бы доезжать до уведомления,
      // и заметить это можно было бы только глазами на телефоне с непривычным
      // языком системы.
      for (final f in [service, activity, alert]) {
        expect(read(f).contains('"silentgate_native"'), isFalse,
            reason: '$f держит вторую копию имени хранилища');
      }
    });

    test('и сервис, и разовое уведомление берут язык оттуда же', () {
      expect(code(service), contains('NativePrefs.'));
      expect(code(alert), contains('NativePrefs.localized('));
    });
  });

  group('⚠️ Имя канала переведено везде', () {
    test('строка есть во всех локалях нативного слоя', () {
      // Имя канала показывает САМА система, в настройках уведомлений
      // приложения: непереведённое, оно выглядит там чужой строкой.
      final res = Directory('android/app/src/main/res');
      final locales = res
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.split(Platform.pathSeparator).last)
          .where((n) => n == 'values' || n.startsWith('values-'))
          // values-night — это тема, а не язык.
          .where((n) => n != 'values-night')
          .toList();
      expect(locales.length, greaterThanOrEqualTo(10),
          reason: 'локалей стало меньше — проверьте, не потеряли ли перевод');
      for (final l in locales) {
        final f = File('${res.path}/$l/strings.xml');
        expect(f.existsSync(), isTrue, reason: 'нет strings.xml в $l');
        expect(f.readAsStringSync(), contains('name="alerts_channel_name"'),
            reason: 'в $l не переведено имя канала оповещений');
      }
    });

    test('строка, которую спрашивает код, и есть эта', () {
      expect(code(alert), contains('R.string.alerts_channel_name'));
    });
  });
}
