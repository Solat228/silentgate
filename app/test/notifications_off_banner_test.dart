import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ОТКАЗ В УВЕДОМЛЕНИЯХ БОЛЬШЕ НЕ ПРОХОДИТ МОЛЧА (Android).
///
/// ⚠️ ЧТО ТЕРЯЕТСЯ ПРИ ОТКАЗЕ. Две вещи, и обе замечаются не сразу: постоянное
/// уведомление сервиса с кнопкой «Отключить» — единственный способ снять
/// туннель при закрытом приложении — и разовое сообщение об обрыве связи
/// (`vpn/AlertNotice.kt`, сделано 20.08.2026). Второе хуже: человек считает,
/// что за каналом следят, а сказать ему об обрыве некому.
///
/// ⚠️ ДО 21.08.2026 В КОДЕ СТОЯЛО «разрешение не критично для работы». На
/// момент, когда это писалось, так и было — уведомления об обрыве ещё не
/// существовало. Утверждение пережило появление той самой возможности, ради
/// которой уведомления и понадобились. Тот же класс, что уже дважды кусал
/// проект: комментарий, переживший изменение, за которым он не следил.
void main() {
  String code(String path) => File(path)
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .join(String.fromCharCode(10));

  const access = 'lib/core/platform/notification_access.dart';
  const home = 'lib/ui/home_screen.dart';
  const activity = 'android/app/src/main/kotlin/lol/silentgate/MainActivity.kt';

  group('⚠️ Спрашиваем ФАКТ, а не своё разрешение', () {
    test('нативная сторона зовёт areNotificationsEnabled', () {
      // `POST_NOTIFICATIONS` выдано и «уведомления показываются» — РАЗНЫЕ
      // утверждения: человек может отозвать уведомления приложению целиком или
      // заглушить канал, и разрешение при этом останется выданным. Проверка
      // своего разрешения показала бы «всё в порядке» ровно там, где ничего не
      // видно.
      final s = code(activity);
      expect(s, contains('"notificationsEnabled" ->'));
      expect(s, contains('areNotificationsEnabled()'));
      expect(s.contains('checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==\n'
          '            PackageManager.PERMISSION_GRANTED\n        if (granted) return\n        val nm'),
          isFalse);
    });

    test('⚠️ есть запасной экран, а не отказ', () {
      // На части прошивок экрана уведомлений нет, но «О приложении» есть
      // всегда. Отправить человека никуда — хуже, чем на соседний экран.
      final s = code(activity);
      final at = s.indexOf('"openNotificationSettings" ->');
      expect(at, greaterThan(0));
      final branch = s.substring(at, at + 1400);
      expect(branch, contains('ACTION_APP_NOTIFICATION_SETTINGS'));
      expect(branch, contains('ACTION_APPLICATION_DETAILS_SETTINGS'));
    });
  });

  group('⚠️ «Не знаю» ведёт себя как «разрешено»', () {
    test('пустой ответ канала не считается отказом', () {
      // Перекос осознанный и обратный тому, что принят в kill switch: плашка,
      // всплывшая из-за сбоя канала, раздражает всех и не чинит ничего.
      final s = code(access);
      expect(s, contains('return ok == false'),
          reason: 'null должен означать «не знаю», а не «выключено»');
    });

    test('на не-Android плашки нет вовсе', () {
      final s = code(access);
      final at = s.indexOf('static Future<bool> blocked()');
      expect(at, greaterThan(0));
      expect(s.substring(at, at + 160), contains('!Platform.isAndroid'));
    });

    test('ошибка канала тоже даёт «разрешено»', () {
      final s = code(access);
      final at = s.indexOf('static Future<bool> blocked()');
      // Границей берём НАЧАЛО следующего метода, а не число символов: окно в
      // символах уже один раз обрезало проверку на середине и дало ложный
      // провал — тот же способ ошибиться, что и «первые N строк лога».
      final next = s.indexOf('static ', at + 10);
      final body = s.substring(at, next > at ? next : s.length);
      expect(body, contains('catch'));
      expect(body.split('catch').last, contains('return false'),
          reason: 'сбой канала обязан читаться как «разрешено», иначе плашка '
              'всплывёт у того, у кого всё в порядке');
    });
  });

  group('⚠️ Плашка на главном', () {
    late String h;
    setUp(() => h = code(home));

    test('она вообще есть в дереве экрана', () {
      expect(h, contains('const NotificationsOffBanner()'),
          reason: 'виджет написан и не вызывается — это уже было с группировкой '
              'сервисов, и обнаружилось только глазами на устройстве');
      expect(h, contains('class NotificationsOffBanner'));
    });

    test('⚠️ перепроверяется при ВОЗВРАТЕ в приложение', () {
      // Человек уходит по нашей же кнопке в настройки и возвращается — плашка
      // обязана исчезнуть сама. Иначе она читается как «я включил, а оно не
      // заметило», и следующий её показ уже игнорируют.
      final at = h.indexOf('class _NotificationsOffBannerState');
      expect(at, greaterThan(0));
      final body = h.substring(at);
      expect(body, contains('WidgetsBindingObserver'));
      expect(body, contains('didChangeAppLifecycleState'));
      expect(body, contains('AppLifecycleState.resumed'));
    });

    test('наблюдатель снимается', () {
      final at = h.indexOf('class _NotificationsOffBannerState');
      final body = h.substring(at);
      expect(body, contains('removeObserver(this)'),
          reason: 'иначе состояние живёт после смерти виджета');
    });

    test('нажатие ведёт в системные настройки и не молчит при неудаче', () {
      final at = h.indexOf('class _NotificationsOffBannerState');
      final body = h.substring(at);
      expect(body, contains('NotificationAccess.openSettings()'));
      expect(body, contains('l.notifOffNoScreen'),
          reason: 'человек нажал и ждёт — молчать нельзя');
    });
  });

  group('⚠️ Тексты переведены во все локали', () {
    test('четыре ключа есть в каждом ARB', () {
      final dir = Directory('lib/l10n');
      final arbs = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb'))
          .toList();
      expect(arbs.length, greaterThanOrEqualTo(10),
          reason: 'локалей стало меньше — проверьте, не потеряли ли перевод');
      for (final f in arbs) {
        final s = f.readAsStringSync();
        for (final k in const [
          'notifOffTitle',
          'notifOffSub',
          'notifOffOpen',
          'notifOffNoScreen',
        ]) {
          expect(s, contains('"$k"'), reason: '${f.path}: нет ключа $k');
        }
      }
    });
  });
}
