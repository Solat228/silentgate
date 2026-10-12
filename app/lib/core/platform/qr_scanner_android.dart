import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Почему QR не прочитан. Отмена человеком — не отказ: она приходит как `null`.
enum QrScanFailure {
  /// Человек не дал доступ к камере.
  cameraDenied,

  /// На картинке QR-кода не нашлось.
  noQr,

  /// Картинка не открылась или камера не запустилась.
  readFailed,

  /// Предыдущий запрос ещё идёт.
  busy,
}

class QrScanException implements Exception {
  final QrScanFailure reason;
  final String? detail;
  const QrScanException(this.reason, [this.detail]);
  @override
  String toString() => 'QrScanException(${reason.name}: $detail)';
}

/// QR-код подписки на Android: с камеры и с картинки из галереи.
///
/// Сам разбор текста здесь не делается — распознанное уходит в тот же
/// `importSource`, что и вставка из буфера (ANDROID.md п.60а).
/// Нативная сторона — `platform/QrScanner.kt`.
class QrScannerAndroid {
  final MethodChannel _channel;

  QrScannerAndroid({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('lol.silentgate/qr');

  /// Показывать ли кнопки QR вообще.
  static bool get isSupported => debugSupported ?? Platform.isAndroid;

  @visibleForTesting
  static bool? debugSupported;

  /// Есть ли у устройства камера. Ошибка канала — «нет»: кнопка картинки
  /// остаётся, а камера, которой нет, кнопкой не притворяется.
  Future<bool> hasCamera() async {
    try {
      return await _channel.invokeMethod<bool>('hasCamera') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Выдано ли уже разрешение на камеру — от этого зависит, объяснять ли
  /// заранее, зачем она нужна.
  Future<bool> cameraGranted() async {
    try {
      return await _channel.invokeMethod<bool>('cameraGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Сканировать камерой. `null` — человек закрыл сканер.
  Future<String?> scanCamera({required String prompt}) =>
      _call('scanCamera', {'prompt': prompt});

  /// Прочитать QR с картинки из галереи. `null` — ничего не выбрано.
  Future<String?> scanImage() => _call('scanImage', null);

  Future<String?> _call(String method, Object? args) async {
    try {
      final text = await _channel.invokeMethod<String>(method, args);
      final t = text?.trim();
      return (t == null || t.isEmpty) ? null : t;
    } on PlatformException catch (e) {
      throw QrScanException(failureFromCode(e.code), e.message);
    } on MissingPluginException catch (e) {
      throw QrScanException(QrScanFailure.readFailed, e.message);
    }
  }

  /// Код ошибки канала → причина. Незнакомый код — `readFailed`, а не
  /// исключение: человеку всё равно надо что-то показать.
  @visibleForTesting
  static QrScanFailure failureFromCode(String code) => switch (code) {
        'camera_denied' => QrScanFailure.cameraDenied,
        'no_qr' => QrScanFailure.noQr,
        'busy' => QrScanFailure.busy,
        _ => QrScanFailure.readFailed,
      };
}
