import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_log.dart';

/// Удержание процессора на время долгого прогона (Android).
///
/// ⚠️ ЗАЧЕМ. Пинг сотни серверов и замер скорости идут минуты. Человек кладёт
/// телефон, экран гаснет, и через несколько секунд система усыпляет процессор:
/// таймеры проб не срабатывают, сокеты не читаются, а по пробуждению каждая
/// проба уже «истекла». Живые серверы метятся мёртвыми — и это выглядит как
/// беда подписки, а не телефона. Foreground-сервис VPN от этого не спасает:
/// он не даёт убить процесс, но процессор не держит.
///
/// Держится `PARTIAL_WAKE_LOCK` (экран может гаснуть, процессор — нет) с
/// таймаутом на стороне Kotlin — 10 минут: зависший прогон не посадит
/// батарею. Каждое новое удержание продлевает таймаут.
///
/// Счётчик держателей — здесь: пинг и замер скорости могут идти один за
/// другим внахлёст (замер стартует в `finally` пинга), и снятие удержания
/// пингом не должно усыпить уже начатый замер.
///
/// На других платформах — пустышка.
abstract final class WakeGuard {
  @visibleForTesting
  static MethodChannel channel = const MethodChannel('lol.silentgate/device');

  /// Принудительно включить или выключить (тесты). `null` — по платформе.
  @visibleForTesting
  static bool? debugEnabled;

  static bool get _enabled => debugEnabled ?? Platform.isAndroid;

  static int _holders = 0;

  @visibleForTesting
  static int get holders => _holders;

  @visibleForTesting
  static void resetForTests() => _holders = 0;

  /// Взять удержание. Снимается [WakeHold.release] — ровно один раз.
  static WakeHold acquire(String reason) {
    if (!_enabled) return WakeHold._(null);
    if (_holders++ == 0) _call('wakeHold', reason);
    return WakeHold._(reason);
  }

  static void _drop(String reason) {
    if (_holders == 0) return;
    if (--_holders == 0) _call('wakeRelease', reason);
  }

  /// Ошибка канала не должна ронять прогон: без удержания пинг всё равно
  /// работает, пока экран включён. Но молчать о ней нельзя — иначе «ночью
  /// всё мёртвое» снова не объяснить.
  static void _call(String method, String reason) {
    unawaited(channel.invokeMethod<bool>(method).then((ok) {
      if (ok != true) AppLog.w('Удержание процессора ($reason): $method → $ok');
    }, onError: (Object e) {
      AppLog.w('Удержание процессора ($reason): $method не удался — $e');
    }));
  }
}

/// Одно удержание. Повторный [release] ничего не делает.
class WakeHold {
  String? _reason;
  WakeHold._(this._reason);

  void release() {
    final r = _reason;
    if (r == null) return;
    _reason = null;
    WakeGuard._drop(r);
  }
}
