import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Шина входящих ссылок silentgate:// (из deep link'а браузера).
/// Первичный экземпляр приложения кладёт сюда полученные URL; [AppState] их слушает.
///
/// ⚠️ ССЫЛКА БЕЗ СЛУШАТЕЛЯ ОТКЛАДЫВАЕТСЯ, А НЕ ПРОПАДАЕТ. Поток широковещательный,
/// а у такого потока нет памяти. Слушатель — [AppState], его создаёт ленивый
/// провайдер при первой отрисовке, а ссылку холодного старта [bindPlatform]
/// забирает ещё до `runApp`. Кто успеет первым, не задано ничем; проигрыш
/// выглядел как «приложение открылось, подписка не добавилась» (13.10.2026).
/// Отложенные отдаются ПЕРВОМУ слушателю и только ему: второй раз та же ссылка
/// означала бы повторный импорт.
class IncomingLinks {
  static final List<String> _pending = <String>[];

  static StreamController<String> _controller = _newController();

  static StreamController<String> _newController() =>
      StreamController<String>.broadcast(onListen: () {
        // Отдаём после того, как подписка встала: внутри `onListen` она ещё
        // может не получать событий.
        scheduleMicrotask(_flush);
      });

  static void _flush() {
    if (!_controller.hasListener) return;
    final queued = List<String>.of(_pending);
    _pending.clear();
    queued.forEach(_controller.add);
  }

  static Stream<String> get stream => _controller.stream;

  static void add(String url) {
    final v = url.trim();
    if (v.isEmpty) return;
    if (_controller.hasListener) {
      _controller.add(v);
    } else {
      _pending.add(v);
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _pending.clear();
    _controller = _newController();
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
