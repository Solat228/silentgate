import 'dart:convert';

/// Один файл со всеми настройками и подписками — для переноса на другой
/// компьютер или телефон и для резервной копии (P11, решение владельца
/// 19.10.2026: экспорт/импорт файлом, Android Auto Backup, галочка в
/// деинсталляторе Windows).
///
/// Модуль чистый: на входе и выходе — разобранный JSON файлов данных. Чтение
/// и запись диска (с шифрованием DPAPI на Windows) делает [SettingsBackup].
///
/// ⚠️ В ФАЙЛЕ С ПОДПИСКАМИ ЛЕЖАТ СЕКРЕТЫ. Адрес подписки — это токен доступа,
/// ключ сервера — share-ссылка с UUID. Кто получил файл, тот получил VPN.
/// Поэтому подписки — отдельная галочка, а интерфейс об этом предупреждает.
///
/// Что НЕ переезжает никогда — [deviceOnlyKeys]: пароль локальных портов и
/// токен API (секреты этой машины: на новой они свои, а чужой токен открыл бы
/// порт по старому паролю), ответ на окно согласия (его даёт человек на
/// каждом устройстве сам — так требуют магазины) и автозапуск (он живёт в
/// реестре или системе, флаг без самой записи соврал бы).
///
/// Исключение — копия ТОГО ЖЕ устройства ([sameDevice]): копия пакета Store в
/// «Документах» зашифрована ключом этой учётной записи Windows и читается
/// только ею. Там [sameDeviceKeys] сохраняются — иначе переустановка молча
/// ломала бы скрипты локального API (новый токен) и выключала автозапуск.
abstract final class SettingsBundle {
  static const format = 'silentgate-settings';
  static const version = 1;

  /// Расширение файла экспорта.
  static const extension = 'sgsettings';

  static const settingsFile = 'silentgate_settings.json';
  static const subscriptionsFile = 'subscriptions.json';
  static const pinnedFile = 'pinned_servers.json';
  static const overridesFile = 'server_overrides.json';
  static const panelFile = 'panel_outbounds.json';

  /// Файлы, которые относятся к подпискам и серверам: без галочки «подписки»
  /// они не экспортируются и не импортируются.
  static const subscriptionFiles = [
    subscriptionsFile,
    pinnedFile,
    overridesFile,
    panelFile,
  ];

  static const allFiles = [settingsFile, ...subscriptionFiles];

  /// Ключи настроек, которые принадлежат этому устройству.
  static const deviceOnlyKeys = {
    'localProxyUser',
    'localProxyPassword',
    'apiToken',
    'deviceInfoConsent',
    'deviceInfoNoticeShown',
    'launchAtLogin',
  };

  /// Ключи из [deviceOnlyKeys], которые копия того же устройства сохраняет.
  ///
  /// ⚠️ Ответа на окно согласия здесь нет: после переустановки его
  /// спрашивают заново — одно нажатие, зато решение о данных устройства
  /// всегда свежее. Автозапуск честен: `AutostartWindows.sync` на старте
  /// приводит запись в реестре к флагу.
  static const sameDeviceKeys = {
    'localProxyUser',
    'localProxyPassword',
    'apiToken',
    'deviceInfoNoticeShown',
    'launchAtLogin',
  };

  /// Ключи, у которых смысл зависит от платформы: режим захвата, параметры
  /// TUN Windows, локальный API, трей, вид уведомления Android. При переносе
  /// между Windows и Android они остаются местными.
  static const platformKeys = {
    'captureMode',
    'tunProvider',
    'tunStack',
    'tunMtu',
    'tunStrictRoute',
    'tunIpv6',
    'tunEndpointIndependentNat',
    'tunBypassLan',
    'tunExcludeCidrs',
    'tunRouteOnlyCidrs',
    'tunnelExcludeScope',
    'tunWatchdogSeconds',
    'alsoSetSystemProxy',
    'apiEnabled',
    'apiExitServerKeys',
    'applyRulesInProxyOnly',
    'compactNotification',
    'closeToTray',
    'dontAskOnClose',
    'connectOnAutostart',
    'geoAutoDownloadWifi',
    'seamlessKeepTun',
  };

  /// Ключи настроек, которые ссылаются на серверы подписки. Без подписок
  /// ссылаться им не на что.
  static const serverRefKeys = {'apiExitServerKeys'};

  /// Собрать пакет из содержимого файлов данных.
  ///
  /// [files] — имя файла → разобранный JSON (отсутствующие файлы просто не
  /// передаются). [platform] — `windows` или `android`.
  static Map<String, dynamic> build({
    required Map<String, Object?> files,
    required bool includeSubscriptions,
    required String platform,
    required String appVersion,
    DateTime? now,
    bool sameDevice = false,
  }) {
    final out = <String, Object?>{};
    final settings = files[settingsFile];
    if (settings is Map) {
      out[settingsFile] = _cleanSettings(settings,
          includeSubscriptions: includeSubscriptions, sameDevice: sameDevice);
    }
    if (includeSubscriptions) {
      for (final name in subscriptionFiles) {
        final v = files[name];
        if (v == null) continue;
        out[name] = name == subscriptionsFile ? _cleanSubscriptions(v) : v;
      }
    }
    return {
      'format': format,
      'version': version,
      'createdAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'platform': platform,
      'appVersion': appVersion,
      'subscriptions': includeSubscriptions && out.containsKey(subscriptionsFile),
      'files': out,
    };
  }

  /// Текст файла экспорта.
  static String encode(Map<String, dynamic> bundle) =>
      const JsonEncoder.withIndent('  ').convert(bundle);

  /// Разобрать файл экспорта. `null` — это не наш файл или он испорчен.
  ///
  /// Версия новее нашей — тоже `null`: читать формат, которого не знаешь,
  /// значит молча потерять то, что в нём появилось.
  static BundleContents? parse(String text) {
    var t = text;
    if (t.isNotEmpty && t.codeUnitAt(0) == 0xFEFF) t = t.substring(1);
    Object? j;
    try {
      j = jsonDecode(t);
    } catch (_) {
      return null;
    }
    if (j is! Map || j['format'] != format) return null;
    final v = j['version'];
    if (v is! int || v < 1 || v > version) return null;
    final files = j['files'];
    if (files is! Map) return null;
    final known = <String, Object?>{};
    for (final name in allFiles) {
      if (files.containsKey(name)) known[name] = files[name];
    }
    if (known[settingsFile] is! Map? || known[subscriptionsFile] is! Map?) {
      return null;
    }
    return BundleContents(
      platform: '${j['platform'] ?? ''}',
      appVersion: '${j['appVersion'] ?? ''}',
      createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}'),
      files: known,
    );
  }

  /// Что записать на диск при импорте.
  ///
  /// [localSettings] — текущие настройки этого устройства (разобранный JSON,
  /// может быть пустым). Из них берутся [deviceOnlyKeys] всегда и
  /// [platformKeys] — при другой платформе. Списки приложений раздельного
  /// туннелирования тоже платформенные (путь exe против имени пакета): при
  /// другой платформе остаются местными, сайты и режим приходят из файла.
  ///
  /// Без [includeSubscriptions] файлы подписок не трогаются вовсе — остаются
  /// местные; ссылки настроек на серверы (выход правила, порты API) тоже
  /// остаются местными, потому что указывают на местные серверы.
  static Map<String, Object?> merge(
    BundleContents bundle, {
    required Map<String, Object?> localSettings,
    required String platform,
    required bool includeSubscriptions,
    bool sameDevice = false,
  }) {
    final out = <String, Object?>{};
    final imported = bundle.files[settingsFile];
    final samePlatform = bundle.platform == platform;
    final useSubs = includeSubscriptions && bundle.hasSubscriptions;
    if (imported is Map) {
      final s = Map<String, Object?>.from(imported);
      for (final k in deviceOnlyKeys) {
        if (sameDevice && sameDeviceKeys.contains(k) && s.containsKey(k)) {
          continue;
        }
        s.remove(k);
        if (localSettings.containsKey(k)) s[k] = localSettings[k];
      }
      if (!samePlatform) {
        for (final k in platformKeys) {
          s.remove(k);
          if (localSettings.containsKey(k)) s[k] = localSettings[k];
        }
      }
      if (!useSubs) {
        for (final k in serverRefKeys) {
          s.remove(k);
          if (localSettings.containsKey(k)) s[k] = localSettings[k];
        }
      }
      s['splitTunnel'] = _mergeSplit(
        imported['splitTunnel'],
        localSettings['splitTunnel'],
        keepLocalApps: !samePlatform,
        dropServerRefs: !useSubs,
      );
      out[settingsFile] = s;
    }
    if (useSubs) {
      for (final name in subscriptionFiles) {
        if (bundle.files.containsKey(name)) out[name] = bundle.files[name];
      }
    }
    return out;
  }

  static Map<String, Object?> _cleanSettings(Map settings,
      {required bool includeSubscriptions, bool sameDevice = false}) {
    final s = Map<String, Object?>.from(settings);
    for (final k in deviceOnlyKeys) {
      if (sameDevice && sameDeviceKeys.contains(k)) continue;
      s.remove(k);
    }
    if (!includeSubscriptions) {
      for (final k in serverRefKeys) {
        s.remove(k);
      }
      s['splitTunnel'] = _mergeSplit(s['splitTunnel'], null,
          keepLocalApps: false, dropServerRefs: true);
    }
    return s;
  }

  /// Путь к логотипу — файл этого устройства, на другом его нет.
  static Object? _cleanSubscriptions(Object? v) {
    if (v is! Map) return v;
    final m = Map<String, Object?>.from(v);
    final items = m['items'];
    if (items is List) {
      m['items'] = [
        for (final p in items)
          if (p is Map) (Map<String, Object?>.from(p)..remove('logoPath')) else p
      ];
    }
    return m;
  }

  static Object? _mergeSplit(Object? imported, Object? local,
      {required bool keepLocalApps, required bool dropServerRefs}) {
    if (imported is! Map) return local ?? imported;
    final out = Map<String, Object?>.from(imported);
    if (keepLocalApps) {
      out['apps'] = local is Map ? local['apps'] ?? const [] : const [];
    }
    if (dropServerRefs) {
      List<Object?> strip(Object? list) => [
            if (list is List)
              for (final r in list)
                if (r is Map) (Map<String, Object?>.from(r)..remove('serverKey')) else r
          ];
      // Местные приложения уже ссылаются на местные серверы — их не трогаем.
      if (!keepLocalApps) out['apps'] = strip(out['apps']);
      out['sites'] = strip(out['sites']);
    }
    return out;
  }
}

/// Разобранный файл экспорта.
class BundleContents {
  final String platform;
  final String appVersion;
  final DateTime? createdAt;
  final Map<String, Object?> files;

  const BundleContents({
    required this.platform,
    required this.appVersion,
    required this.createdAt,
    required this.files,
  });

  bool get hasSettings => files[SettingsBundle.settingsFile] is Map;

  bool get hasSubscriptions => files[SettingsBundle.subscriptionsFile] is Map;

  /// Сколько подписок в файле — для окна подтверждения.
  int get subscriptionCount {
    final s = files[SettingsBundle.subscriptionsFile];
    final items = s is Map ? s['items'] : null;
    return items is List ? items.length : 0;
  }
}
