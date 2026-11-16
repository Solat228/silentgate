import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_log.dart';

/// Безлимитная ли сейчас сеть — можно ли качать крупное без спроса.
///
/// Нужна ради полных гео-баз (около 30 МБ): на Wi-Fi они качаются сами, на
/// мобильной сети приложение только предлагает (решение владельца 14.10.2026).
///
/// Ответ знает только Android (`ConnectivityManager`, сети в обход VPN). На
/// других платформах — `null`: «не знаю», и вызывающий код ведёт себя как
/// раньше, ничего не качая сам. Windows этого и не нужно: там полные базы
/// едут в поставке.
abstract final class NetworkCost {
  @visibleForTesting
  static MethodChannel channel = const MethodChannel('lol.silentgate/device');

  /// Подмена ответа в тестах. Задана — канал не спрашивается.
  @visibleForTesting
  static Future<bool?> Function()? debugUnmetered;

  /// `true` — есть Wi-Fi/Ethernet, `false` — только тарифицируемая сеть,
  /// `null` — неизвестно (не Android или канал не ответил).
  static Future<bool?> unmetered() async {
    final fake = debugUnmetered;
    if (fake != null) return fake();
    if (!Platform.isAndroid) return null;
    try {
      return await channel.invokeMethod<bool>('unmeteredNetwork');
    } catch (e) {
      // Не узнали — не качаем: ошибиться в сторону «спросить» дешевле,
      // чем молча съесть 30 МБ мобильного трафика.
      AppLog.w('Тип сети не определён: $e');
      return null;
    }
  }
}
