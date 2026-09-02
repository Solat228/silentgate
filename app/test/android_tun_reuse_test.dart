import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ПЕРЕПОДКЛЮЧЕНИЕ НЕ ДОЛЖНО ПЛОДИТЬ TUN-ИНТЕРФЕЙСЫ.
///
/// ⚠️ ЧТО СЛОМАЛОСЬ И КАК ЭТО ВЫГЛЯДЕЛО. Живой прогон на эмуляторе
/// 02.09.2026: ОДНО переподключение дало ТРИ записи
/// `Vpn: Established by lol.silentgate` за 1,1 секунды (tun1, tun2, tun3);
/// за прогон накопилось девять интерфейсов tun0…tun8 в состоянии DOWN, каждый
/// со своим 172.19.0.1/30, живой — только tun9.
///
/// Механизм: `startOrReloadWithRetry` повторяет `startOrReloadService` при
/// занятом порте, каждый повтор идёт через колбэк libbox `OpenTun` → новый
/// `establish()` → НОВЫЙ интерфейс. Go-сторона при этом делает `dup()` нашего
/// fd (libbox `platform.go`), и на неудачном старте этот дубликат ядро отдаёт
/// не всегда — интерфейс переживает и закрытие нашего ParcelFileDescriptor.
///
/// Лечение: `openTun` считает отпечаток запрошенных TunOptions и, если
/// параметры НЕ изменились, а живой fd на руках, — возвращает его же, не
/// трогая `establish()`. Нет нового интерфейса — нечему копиться.
///
/// ⚠️ ПОЧЕМУ СТРАЖ ЧИТАЕТ ИСХОДНИК, А НЕ ПРОВЕРЯЕТ ПОВЕДЕНИЕ. Это Kotlin:
/// `flutter test` его не компилирует и не запускает вовсе (тот же приём, что в
/// `android_stop_reason_test.dart`). Настоящее доказательство — только живой
/// прогон на эмуляторе: переподключение и `ip link` без новых tunN.
void main() {
  const svc =
      'android/app/src/main/kotlin/lol/silentgate/vpn/SilentGateVpnService.kt';

  /// Текст файла без строк-комментариев: страж не должен ловить сам себя на
  /// собственных пояснениях — такой страж отключают в первый же день.
  String code(String path) => File(path)
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join(String.fromCharCode(10));

  /// Тело `openTun` — от объявления до следующего override-метода.
  String openTunBody(String s) {
    final from = s.indexOf('override fun openTun');
    expect(from, greaterThanOrEqualTo(0), reason: 'openTun не найден');
    final to = s.indexOf('override fun autoDetectInterfaceControl', from);
    expect(to, greaterThan(from),
        reason: 'граница openTun не найдена — метод переехал? поправь стража');
    return s.substring(from, to);
  }

  group('⚠️ Повтор подъёма с теми же параметрами НЕ создаёт новый интерфейс', () {
    test('у сервиса есть отпечаток параметров живого туннеля', () {
      expect(code(svc), contains('tunFingerprint'),
          reason: 'без отпечатка нечем узнать, что запрошен ТОТ ЖЕ туннель, — '
              'и каждый повтор startOrReloadService создаёт новый интерфейс');
    });

    test('openTun сверяет отпечаток и возвращает живой fd ДО establish()', () {
      final body = openTunBody(code(svc));
      final establishAt = body.indexOf('.establish()');
      expect(establishAt, greaterThanOrEqualTo(0));
      final before = body.substring(0, establishAt);
      expect(before, contains('tunFingerprint'),
          reason: 'сверка отпечатка обязана стоять РАНЬШЕ establish(): '
              'после него интерфейс уже создан и копится');
      expect(before, contains('return'),
          reason: 'при совпадении параметров openTun обязан вернуть '
              'существующий fd, не доходя до establish()');
    });

    test('новый establish() запоминает отпечаток применённых параметров', () {
      final body = openTunBody(code(svc));
      final after = body.substring(body.indexOf('.establish()'));
      expect(after, contains('tunFingerprint ='),
          reason: 'без записи отпечатка следующий повтор не узнает туннель '
              'и снова уйдёт в establish()');
    });

    test('отпечаток строится из тех же данных, что уходят в Builder', () {
      final body = openTunBody(code(svc));
      final establishAt = body.indexOf('.establish()');
      final before = body.substring(0, establishAt);
      // Если отпечаток считать по ОДНИМ полям, а Builder наполнять по ДРУГИМ,
      // они разойдутся молча — и туннель со сменившимися правилами приложений
      // был бы «узнан» как прежний. Минимальная проверка: до establish()
      // сняты все шесть групп параметров.
      for (final probe in [
        'inet4Address',
        'inet6Address',
        'inet4RouteAddress',
        'inet6RouteAddress',
        'includePackage',
        'excludePackage',
      ]) {
        expect(before, contains(probe),
            reason: '$probe обязан быть снят до решения о переиспользовании — '
                'иначе отпечаток слеп к этой части параметров');
      }
    });
  });

  group('⚠️ Порядок закрытия прежнего fd — инвариант из CHANGELOG 1.0.3', () {
    test('прежний fd закрывается ПОСЛЕ establish(), не до', () {
      final body = openTunBody(code(svc));
      final establishAt = body.indexOf('.establish()');
      final closeAt = body.indexOf('previous?.close()');
      expect(closeAt, greaterThan(establishAt),
          reason: 'закрыть старый fd ДО establish() = снять туннель на миг — '
              'ровно то окно утечки, которое kill switch закрывает');
    });

    test('до establish() в openTun никто ничего не закрывает', () {
      final body = openTunBody(code(svc));
      final before = body.substring(0, body.indexOf('.establish()'));
      expect(before.contains('.close('), isFalse,
          reason: 'любое закрытие до establish() открывает окно утечки '
              'трафика мимо туннеля');
    });
  });

  group('⚠️ Отпечаток живёт ровно столько, сколько живёт fd', () {
    test('stopTunnelLocked обнуляет отпечаток вместе с tunFd', () {
      final s = code(svc);
      final from = s.indexOf('private fun stopTunnelLocked');
      expect(from, greaterThanOrEqualTo(0));
      final body = s.substring(from, s.indexOf('private fun cancelNotification', from));
      expect(body, contains('tunFingerprint = null'),
          reason: 'пережиток отпечатка после закрытия fd — состояние врозь: '
              'fd нет, а сервис «помнит» живой туннель');
    });
  });
}
