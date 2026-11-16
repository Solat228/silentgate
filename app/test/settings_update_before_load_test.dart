import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/data/settings_storage.dart';
import 'package:silentgate/state/settings_controller.dart';

/// Хранилище, чтение которого отпускает тест.
class _SlowStorage extends SettingsStorage {
  final Completer<AppSettings> gate = Completer<AppSettings>();
  final saved = <AppSettings>[];

  @override
  Future<AppSettings> load() => gate.future;

  @override
  Future<void> save(AppSettings settings) async => saved.add(settings);
}

/// Ревью 29.10.2026, L6: `update()` до дочитанного файла применял правку к
/// умолчаниям и мог записать их поверх настроек пользователя.
void main() {
  test('update во время init ждёт файл и правит прочитанное', () async {
    final storage = _SlowStorage();
    final c = SettingsController(storage: storage);
    final init = c.init();
    final upd = c.update((s) => s.copyWith(verboseLogging: true));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(storage.saved, isEmpty, reason: 'до загрузки ничего не пишем');

    storage.gate.complete(AppSettings.defaults.copyWith(killSwitch: true));
    await init;
    await upd;
    expect(c.settings.killSwitch, isTrue, reason: 'значение с диска цело');
    expect(c.settings.verboseLogging, isTrue, reason: 'правка не потеряна');
    expect(storage.saved.single.killSwitch, isTrue);
  });

  test('без init update не ждёт', () async {
    final storage = _SlowStorage();
    final c = SettingsController(storage: storage);
    await c
        .update((s) => s.copyWith(verboseLogging: true))
        .timeout(const Duration(seconds: 2));
    expect(storage.saved, hasLength(1));
  });
}
