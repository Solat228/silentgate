import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Шина входящих ссылок silentgate:// (из deep link'а браузера).
/// Первичный экземпляр приложения кладёт сюда полученные URL; [AppState] их слушает.
class IncomingLinks {
  static final StreamController<String> _controller =
      StreamController<String>.broadcast();

  static Stream<String> get stream => _controller.stream;

  static void add(String url) {
    if (url.trim().isNotEmpty) _controller.add(url.trim());
  }

  static const _channel = MethodChannel('lol.silentgate/links');
  static bool _bound = false;

  /// Подписаться на ссылки от Android.
  ///
  /// На Windows ссылки приносит механизм единственного экземпляра, а на Android
  /// они приходят интентом в Activity — и до этой привязки не приходили НИКУДА.
  /// Схемы были объявлены в манифесте, приложение по ссылке запускалось, но
  /// ничего не импортировало: Flutter принимал `silentgate://import?url=…` за
  /// имя маршрута, шёл в `onUnknownRoute` и падал с «Null check operator used
  /// on a null value». Снаружи это выглядело как «ссылки на Android не
  /// работают», причём молча.
  ///
  /// Ссылку холодного старта забираем отдельным вызовом: интент приходит
  /// РАНЬШЕ, чем Dart успевает подписаться, и без этого первая — самая частая —
  /// ссылка терялась бы.
  static Future<void> bindPlatform() async {
    if (_bound || !Platform.isAndroid) return;
    _bound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'link') add('${call.arguments}');
    });
    try {
      final initial = await _channel.invokeMethod<String>('consumeInitial');
      if (initial != null) add(initial);
    } catch (_) {
      // Канала нет (старая сборка) — не повод падать на старте.
    }
  }
}
