import 'dart:io';

import 'package:flutter/services.dart';

import 'app_log.dart';

/// Состояние СИСТЕМНОЙ защиты Android: «Постоянная VPN» и «Блокировать
/// соединения без VPN».
///
/// ## Зачем это нужно, если у нас есть свой kill switch
///
/// Наш kill switch на Android настоящий: ядро перезагружается конфигом-
/// заглушкой, туннель остаётся поднятым, а трафик умирает в `reject`. Но
/// держится это ровно до тех пор, пока **жив наш процесс**. Система убила
/// сервис (нехватка памяти, Doze, пользователь смахнул приложение из недавних)
/// — туннель снимается вместе с ним, и трафик идёт открыто.
///
/// Этот случай закрывает только сама Android: «Блокировать соединения без VPN».
/// Включить её из приложения НЕЛЬЗЯ — платформа запрещает намеренно, иначе
/// любое приложение могло бы запереть весь трафик устройства. Значит наш
/// единственный честный ход: показать пользователю, включена ли она, и увести
/// в нужный экран настроек.
///
/// ⚠️ Без этого получается обещание, которого мы не выполняем: галочка
/// «kill switch» включена, в отчёте она печатается, а после смерти сервиса
/// защиты нет. Владелец 09.08.2026 сформулировал это точно: «неизвестно
/// работает или нет без настроек в самом телефоне».
class VpnLockdown {
  const VpnLockdown({
    required this.supported,
    required this.alwaysOn,
    required this.lockdown,
  });

  /// Можно ли вообще узнать состояние.
  ///
  /// `false` — до Android 10 (геттеров нет) либо сервис ещё не поднят. Это
  /// НЕ «выключено»: разница принципиальна, потому что «не знаю» и «точно нет»
  /// требуют разных слов в интерфейсе.
  final bool supported;

  /// Приложение назначено «постоянной VPN».
  final bool alwaysOn;

  /// Включено «Блокировать соединения без VPN» — то, что реально держит трафик
  /// при мёртвом приложении.
  final bool lockdown;

  /// Защита действует и переживёт смерть приложения.
  bool get fullyProtected => supported && alwaysOn && lockdown;

  /// Неизвестное состояние — говорим об этом прямо, а не рисуем зелёную птицу.
  static const unknown =
      VpnLockdown(supported: false, alwaysOn: false, lockdown: false);

  static const _channel = MethodChannel('lol.silentgate/vpn');

  /// Спросить систему. На не-Android всегда [unknown]: там понятия нет.
  static Future<VpnLockdown> query() async {
    if (!Platform.isAndroid) return unknown;
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('lockdownState');
      if (m == null) return unknown;
      return VpnLockdown(
        supported: m['supported'] as bool? ?? false,
        alwaysOn: m['alwaysOn'] as bool? ?? false,
        lockdown: m['lockdown'] as bool? ?? false,
      );
    } catch (e) {
      AppLog.w('Состояние системной защиты недоступно: $e');
      return unknown;
    }
  }

  /// Открыть системный экран VPN. `false` — экрана нет (бывает на прошивках).
  static Future<bool> openSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openVpnSettings') ?? false;
    } catch (e) {
      AppLog.w('Не удалось открыть системные настройки VPN: $e');
      return false;
    }
  }

  @override
  String toString() =>
      'VpnLockdown(supported: $supported, alwaysOn: $alwaysOn, lockdown: $lockdown)';
}
