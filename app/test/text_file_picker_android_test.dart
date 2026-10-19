import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/text_file_picker_android.dart';

/// Выбор файла для импорта настроек на Android (P11).
///
/// Своё окно выбора вместо `file_selector`: ответ плагина терялся, если
/// система пересоздавала Activity, пока окно открыто (живьём в эмуляторе с
/// «Не сохранять действия», 20.10.2026).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lol.silentgate/files');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void mock(Future<Object?> Function(MethodCall) h) =>
      messenger.setMockMethodCallHandler(channel, h);

  test('выбранный файл приходит именем и текстом', () async {
    MethodCall? seen;
    mock((call) async {
      seen = call;
      return {'name': 'SilentGate-settings.sgsettings', 'text': '{"a":1}'};
    });
    final f = await TextFilePickerAndroid().pickText();
    expect(f!.name, 'SilentGate-settings.sgsettings');
    expect(f.text, '{"a":1}');
    expect(seen!.method, 'pickText');
    expect(seen!.arguments,
        {'maxBytes': TextFilePickerAndroid.defaultMaxBytes});
  });

  test('ничего не выбрано — null', () async {
    mock((_) async => null);
    expect(await TextFilePickerAndroid().pickText(), isNull);
  });

  test('отказ нативной стороны доходит исключением, а не тишиной', () async {
    mock((_) async => throw PlatformException(code: 'too_big'));
    await expectLater(TextFilePickerAndroid().pickText(maxBytes: 10),
        throwsA(isA<PlatformException>()));
  });

  test('нет обработчика (старая сборка) — исключение', () async {
    await expectLater(TextFilePickerAndroid().pickText(),
        throwsA(isA<MissingPluginException>()));
  });

  // Страж нативной стороны: ожидание ответа обязано жить в companion object
  // и разбираться в MainActivity — иначе ответ новой Activity снова потеряется.
  test('Kotlin: ожидание в companion, MainActivity передаёт ответ', () {
    const dir = 'android/app/src/main/kotlin/lol/silentgate';
    final picker = File('$dir/platform/TextFilePicker.kt').readAsStringSync();
    final companion = picker.substring(
        picker.indexOf('companion object'), picker.indexOf('private val main'));
    expect(companion, contains('private var pending: MethodChannel.Result?'));
    expect(picker, contains('"lol.silentgate/files"'));
    final activity = File('$dir/MainActivity.kt').readAsStringSync();
    expect(activity, contains('TextFilePicker.CHANNEL'));
    expect(activity, contains('files.onActivityResult(requestCode, resultCode, data)'));
  });

  test('импорт настроек на Android не зовёт file_selector', () {
    final src = File('lib/ui/widgets/settings_backup_actions.dart')
        .readAsStringSync();
    expect(src,
        contains('if (Platform.isAndroid) return TextFilePickerAndroid().pickText();'));
  });
}
