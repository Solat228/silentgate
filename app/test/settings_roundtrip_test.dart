import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';

/// Класс багов «поле пишется в файл, но не читается обратно».
///
/// Компилятор его не видит: `toJson` и `fromJson` — независимые списки, и
/// забытая строка в одном из них проявляется только тем, что настройка молча
/// возвращается к умолчанию при следующем запуске, хотя в файле лежит выбор
/// пользователя. Так уже потерялась настройка DNS `tunnelDnsForAll`.
///
/// Тест не перечисляет поля руками (такой список устаревает ровно так же) —
/// он берёт ВСЕ ключи из `toJson` и проверяет каждый.
void main() {
  test('каждое булево поле переживает сохранение и загрузку', () {
    const base = AppSettings();
    final json = base.toJson();

    for (final entry in json.entries) {
      final v = entry.value;
      if (v is! bool) continue;

      final flipped = Map<String, dynamic>.of(json)..[entry.key] = !v;
      final loaded = AppSettings.fromJson(flipped).toJson();

      expect(loaded[entry.key], !v,
          reason: 'настройка «${entry.key}» сохраняется, но не читается обратно:'
              ' fromJson её пропускает, и выбор пользователя теряется');
    }
  });

  test('каждое числовое поле переживает сохранение и загрузку', () {
    const base = AppSettings();
    final json = base.toJson();

    for (final entry in json.entries) {
      final v = entry.value;
      if (v is! int) continue;
      // Значения-перечисления хранятся строкой, а не числом, так что здесь
      // только настоящие числа (порты, размеры, интервалы).
      final changed = Map<String, dynamic>.of(json)..[entry.key] = v + 1;
      final loaded = AppSettings.fromJson(changed).toJson();

      expect(loaded[entry.key], v + 1,
          reason: 'настройка «${entry.key}» сохраняется, но не читается обратно');
    }
  });
}
