import 'package:flutter/foundation.dart';

import '../core/settings/app_settings.dart';
import '../data/settings_storage.dart';

/// Хранит и персистит [AppSettings]. UI подписывается через Provider.
class SettingsController extends ChangeNotifier {
  final SettingsStorage _storage;
  AppSettings _settings = AppSettings.defaults;

  SettingsController({SettingsStorage? storage})
      : _storage = storage ?? SettingsStorage();

  AppSettings get settings => _settings;

  Future<void> init() async {
    _settings = await _storage.load();
    notifyListeners();
  }

  /// Изменить настройки: mutate -> persist -> notify.
  Future<void> update(AppSettings Function(AppSettings current) mutate) async {
    _settings = mutate(_settings);
    notifyListeners();
    await _storage.save(_settings);
  }
}
