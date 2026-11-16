import 'dart:io';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import 'app_log.dart';

/// Абстракция встроенного окна капчи/мини-браузера для детерминированных модульных тестов.
abstract interface class CaptchaWebViewLauncher {
  Future<bool> open(String url, {String? title, String mode = 'captcha'});
  Future<void> close();
}

CaptchaWebViewLauncher? _testOverride;

@visibleForTesting
void setCaptchaWebViewForTests(CaptchaWebViewLauncher? fake) {
  _testOverride = fake;
}

/// Мост к нативному встроенному WebView для прохождения капчи БС и окна поддержки
/// внутри приложения (`WebView2` на Windows, системный `android.webkit.WebView` на Android).
///
/// В режиме `captcha` первые ~2.6 секунды рендер идёт в невидимом слое с отправкой
/// доверенного системного клика по чекбоксу «Я не робот». В режиме `support`
/// окно открывается сразу поверх приложения и автоматически раскрывает чат
/// поддержки (`#support-modal`) на странице подписки.
///
/// При отсутствии системного компонента (`WebView2 Runtime` на Windows LTSC /
/// вырезанный `Android System WebView`) возвращает `false`, позволяя вызывающему
/// коду откатиться на запасной вариант.
abstract final class CaptchaWebViewBridge {
  static const MethodChannel _channel = MethodChannel('lol.silentgate/captcha');

  static Future<bool> open(
    String url, {
    String title = 'Подтверждение подключения ВК',
    String mode = 'captcha',
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty ||
        (!trimmed.startsWith('http://') && !trimmed.startsWith('https://'))) {
      return false;
    }

    final override = _testOverride;
    if (override != null) {
      return override.open(trimmed, title: title, mode: mode);
    }

    if (!Platform.isWindows && !Platform.isAndroid) {
      return false;
    }

    try {
      final ok = await _channel.invokeMethod<bool>('open', <String, dynamic>{
        'url': trimmed,
        'title': title,
        'mode': mode,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      AppLog.w('Встроенный WebView недоступен, откат на запасной вариант: $e');
      return false;
    }
  }

  /// Открыть встроенный мини-браузер со страницей подписки и чатом поддержки.
  static Future<bool> openSupport(
    String url, {
    required String title,
  }) =>
      open(url, title: title, mode: 'support');

  static Future<void> close() async {
    final override = _testOverride;
    if (override != null) {
      await override.close();
      return;
    }

    if (!Platform.isWindows && !Platform.isAndroid) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('close');
    } catch (_) {
      // Игнорируем ошибку закрытия, если окно уже уничтожено или плагин не подключён.
    }
  }
}
