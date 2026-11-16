import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/qr_scanner_android.dart';

/// QR-код подписки на Android (ANDROID.md п.60а): камера и картинка.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lol.silentgate/qr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void mock(Future<Object?> Function(MethodCall) h) =>
      messenger.setMockMethodCallHandler(channel, h);

  test('распознанный текст приходит обрезанным', () async {
    MethodCall? seen;
    mock((call) async {
      seen = call;
      return '  https://panel.example/sub/abc \n';
    });
    final text = await QrScannerAndroid().scanCamera(prompt: 'Наведите');
    expect(text, 'https://panel.example/sub/abc');
    expect(seen!.method, 'scanCamera');
    expect(seen!.arguments, {'prompt': 'Наведите'});
  });

  test('отмена — null, а не ошибка', () async {
    mock((_) async => null);
    expect(await QrScannerAndroid().scanImage(), isNull);
    mock((_) async => '   ');
    expect(await QrScannerAndroid().scanImage(), isNull);
  });

  test('коды ошибок канала → причины', () async {
    for (final (code, reason) in [
      ('camera_denied', QrScanFailure.cameraDenied),
      ('no_qr', QrScanFailure.noQr),
      ('busy', QrScanFailure.busy),
      ('read_failed', QrScanFailure.readFailed),
      ('что-то новое', QrScanFailure.readFailed),
    ]) {
      mock((_) async => throw PlatformException(code: code));
      await expectLater(
          QrScannerAndroid().scanImage(),
          throwsA(isA<QrScanException>()
              .having((e) => e.reason, 'reason', reason)));
    }
  });

  test('нет обработчика (старая сборка) — readFailed', () async {
    await expectLater(
        QrScannerAndroid().scanImage(),
        throwsA(isA<QrScanException>()
            .having((e) => e.reason, 'reason', QrScanFailure.readFailed)));
  });

  test('сбой канала у проверок камеры — «нет»', () async {
    mock((_) async => throw PlatformException(code: 'x'));
    expect(await QrScannerAndroid().hasCamera(), isFalse);
    expect(await QrScannerAndroid().cameraGranted(), isFalse);
    mock((call) async => call.method == 'hasCamera');
    expect(await QrScannerAndroid().hasCamera(), isTrue);
  });

  test('вне Android кнопок нет', () {
    expect(QrScannerAndroid.isSupported, Platform.isAndroid);
  });

  test('проводка: Kotlin, манифест, Gradle, экран импорта', () {
    final kt = File(
            'android/app/src/main/kotlin/lol/silentgate/platform/QrScanner.kt')
        .readAsStringSync();
    for (final m in ['"hasCamera"', '"cameraGranted"', '"scanCamera"', '"scanImage"']) {
      expect(kt, contains(m), reason: m);
    }
    // Коды ошибок обязаны совпадать с разбором в Dart.
    for (final c in ['"camera_denied"', '"no_qr"', '"read_failed"', '"busy"']) {
      expect(kt, contains(c), reason: c);
    }
    expect(kt, contains("CHANNEL = \"lol.silentgate/qr\""));
    // Разбор картинки — не на главном потоке.
    expect(kt, contains('Thread {'));
    // ⚠️ С inJustDecodeBounds decodeStream ВСЕГДА возвращает null. Проверка
    // `?: throw` по результату чтения размеров отвергала любую картинку —
    // QR с картинки не работал ни разу (живой прогон 10.10.2026).
    expect(
        RegExp(r'decodeStream\(it, null, bounds\)\s*\}\s*\?:').hasMatch(kt),
        isFalse,
        reason: 'null от чтения размеров — норма, а не отказ');
    // Распознанный текст — ссылка-подписка с токеном, в logcat его нет.
    expect(kt, isNot(contains(r'QR прочитан: $text')));

    final main = File('android/app/src/main/kotlin/lol/silentgate/MainActivity.kt')
        .readAsStringSync();
    expect(main, contains('QrScanner.CHANNEL'));
    expect(main, contains('qr.onActivityResult('));

    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.CAMERA'));
    // Без камеры приложение обязано ставиться.
    expect(
        manifest,
        contains(
            '<uses-feature android:name="android.hardware.camera" android:required="false"/>'));
    expect(manifest, contains('com.journeyapps.barcodescanner.CaptureActivity'));
    expect(manifest, contains('tools:replace="android:screenOrientation"'));

    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('com.journeyapps:zxing-android-embedded:'));
    // ML Kit — закрытый бинарь, в GPL-клиент его не тянем.
    expect(gradle, isNot(contains('mlkit')));

    // Концы строк в рабочей копии зависят от core.autocrlf: после checkout
    // файл бывает с CRLF, и проверка многострочного куска падала не по делу.
    final screen = File('lib/ui/import_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(screen, contains('QrScannerAndroid.isSupported'));
    // Распознанное идёт тем же путём, что и вставка из буфера.
    expect(screen, contains('_controller.text = text;\n      await _import();'));
  });
}
