import 'package:flutter/services.dart';

/// Выбранный файл: имя для журнала и содержимое.
class PickedTextFile {
  final String name;
  final String text;
  const PickedTextFile({required this.name, required this.text});
}

/// Выбор текстового файла системным окном на Android — для импорта настроек.
///
/// ⚠️ Не `file_selector`: его ответ теряется, если система пересоздала
/// Activity, пока открыто окно выбора («Не сохранять действия», агрессивные
/// прошивки). Подробности и нативная сторона — `platform/TextFilePicker.kt`.
///
/// Ошибки канала (`busy`, `too_big`, `read_failed`) приходят как
/// [PlatformException], отсутствие обработчика — [MissingPluginException];
/// что показать человеку, решает вызывающий.
class TextFilePickerAndroid {
  final MethodChannel _channel;

  TextFilePickerAndroid({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('lol.silentgate/files');

  /// Файл экспорта с несколькими подписками — единицы мегабайт; предел
  /// с запасом, но не даёт затащить в память случайно выбранное видео.
  static const defaultMaxBytes = 32 * 1024 * 1024;

  /// `null` — человек ничего не выбрал.
  Future<PickedTextFile?> pickText({int maxBytes = defaultMaxBytes}) async {
    final r = await _channel
        .invokeMapMethod<String, Object?>('pickText', {'maxBytes': maxBytes});
    if (r == null) return null;
    return PickedTextFile(
      name: r['name'] as String? ?? '',
      text: r['text'] as String? ?? '',
    );
  }
}
