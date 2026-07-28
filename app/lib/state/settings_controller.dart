import 'dart:io';

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
    _settings = _normalize(await _storage.load());
    notifyListeners();
  }

  /// Изменить настройки: mutate -> persist -> notify.
  Future<void> update(AppSettings Function(AppSettings current) mutate) async {
    _settings = _normalize(mutate(_settings));
    notifyListeners();
    await _storage.save(_settings);
  }

  /// Приведение к тому, что платформа реально умеет.
  ///
  /// ⚠️ На Android способ захвата ровно один — `VpnService`, то есть TUN.
  /// Умолчание же общее для всех платформ и равно `systemProxy` (на Windows
  /// это верно), а переключателя на Android нет — его намеренно прячут. В
  /// результате на свежей установке значение оставалось `systemProxy`
  /// НАВСЕГДА, и весь экран раздельного туннелирования показывался серым и
  /// неактивным: он гейтится ровно по этому полю. Туннель при этом работал —
  /// движок Android поле не читает, — то есть настройка расходилась с
  /// действительностью и отбирала у пользователя целую подсистему.
  static AppSettings _normalize(AppSettings s) {
    if (Platform.isAndroid && s.captureMode != CaptureMode.tun) {
      return s.copyWith(captureMode: CaptureMode.tun);
    }
    return s;
  }
}
