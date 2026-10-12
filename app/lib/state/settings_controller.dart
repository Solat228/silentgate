import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/platform/app_log.dart';
import '../core/settings/app_settings.dart';
import '../data/settings_storage.dart';

/// Хранит и персистит [AppSettings]. UI подписывается через Provider.
class SettingsController extends ChangeNotifier {
  final SettingsStorage _storage;
  AppSettings _settings = AppSettings.defaults;

  SettingsController({SettingsStorage? storage})
      : _storage = storage ?? SettingsStorage();

  AppSettings get settings => _settings;

  /// Зовётся, когда изменилось поле, запекаемое в конфиг ядра. Подписчик
  /// (AppState через UI) показывает «переподключитесь, чтобы применить».
  ///
  /// Без этого правка правил при живом соединении проходила МОЛЧА: конфиг
  /// собирается один раз при подъёме, и пользователь был уверен, что правило
  /// работает, хотя ядро о нём не знало.
  void Function(AppSettings before, AppSettings after)? onRequiresReconnect;

  /// Настройки прочитаны с диска ([init] отработал). До этого [settings] —
  /// умолчания, и решать по ним то, что человек мог выключить (проверка и
  /// установка обновлений), нельзя.
  bool get loaded => _loaded.isCompleted;

  /// Завершается, когда [init] прочитал настройки (или не смог — тогда
  /// остаются умолчания, но ждать дальше всё равно нечего).
  ///
  /// ⚠️ ЯВНЫЙ ПРИЗНАК, А НЕ «ПЕРВОЕ УВЕДОМЛЕНИЕ». Самообновление раньше
  /// стартовало по первому `notifyListeners` — а его шлёт и любая [update],
  /// случившаяся раньше `init` (или вместо него в тесте). Такая связь держится
  /// на порядке вызовов, который ничем не задан; признак загрузки — нет.
  Future<void> get whenLoaded => _loaded.future;
  final Completer<void> _loaded = Completer<void>();

  Future<void> init() async {
    try {
      _settings = _normalize(await _storage.load());
      _applyLogLevel();
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
    notifyListeners();
  }

  /// ⚠️ ПОРОГ ЖУРНАЛА ЖИВЁТ В СТАТИКЕ [AppLog], А НАСТРОЙКА — ЗДЕСЬ.
  ///
  /// Их надо сводить в ОДНОМ месте, и это место — единственный путь, через
  /// который настройки и загружаются, и меняются. Разложи это по вызывающим —
  /// и кто-нибудь однажды поменяет уровень, а журнал останется прежним: тихо,
  /// без ошибки, и заметить можно будет только по отсутствию строк в чужой
  /// аварии.
  ///
  /// Галочка «всё подряд» сильнее выбранного уровня — так она и задумана:
  /// один переключатель на случай, когда человеку не до настроек.
  void _applyLogLevel() {
    AppLog.minLevel = _settings.verboseLogging
        ? LogLevel.debug
        : switch (_settings.appLogLevel) {
            AppLogLevel.warn => LogLevel.warn,
            AppLogLevel.info => LogLevel.info,
            AppLogLevel.debug => LogLevel.debug,
          };
  }

  /// Изменить настройки: mutate -> persist -> notify.
  /// Отдать выбранный язык нативной стороне (она его персистит: сервис
  /// переживает смерть изолята, и спросить будет уже не у кого).
  static Future<void> _pushLanguageToNative(String code) async {
    if (!Platform.isAndroid) return;
    try {
      await const MethodChannel('lol.silentgate/vpn')
          .invokeMethod<void>('setLanguage', {'code': code});
    } catch (_) {
      // Канал недоступен — шторка останется на языке системы, не критично.
    }
  }

  Future<void> update(AppSettings Function(AppSettings current) mutate) async {
    final before = _settings;
    _settings = _normalize(mutate(_settings));
    // Порог применяем СРАЗУ, до записи на диск и уведомлений: человек, только
    // что включивший подробный журнал, ждёт подробностей уже от этого действия.
    _applyLogLevel();
    if (before.requiresReconnect(_settings)) {
      onRequiresReconnect?.call(before, _settings);
    }
    // ⚠️ Язык уходит и в нативный слой. Уведомление сервиса — единственное
    // место, которое видно при закрытом приложении, и `getString()` там берёт
    // локаль СИСТЕМЫ. Без этой строки человек, выбравший в приложении русский
    // на англоязычном телефоне, получал бы английскую шторку — то есть
    // единственный видимый ему текст выпадал бы из десятиязычности.
    if (before.languageCode != _settings.languageCode) {
      unawaited(_pushLanguageToNative(_settings.languageCode));
    }
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
