import 'dart:typed_data';

import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/platform/app_log.dart';
import '../../core/platform/app_paths.dart';
import '../../core/platform/rotating_log.dart';
import '../../core/platform/platform_services.dart';
import 'support_report_android.dart';

/// Платформенные сервисы Android — **каркас фазы 3**.
///
/// Реализованы те, что не требуют нативного слоя (лог движка читается из
/// файла, как на Windows). Остальные честно отвечают «нечего показать» и ждут
/// своих задач плана `docs/platforms/ANDROID.md`:
///
///  * каталог приложений и иконки — задача 44 (`PackageManager` через
///    `MethodChannel`, обязательно с `<queries>` в манифесте, иначе список
///    окажется пустым);
///  * версия ядра — задача 24 (появится вместе с `libxray.aar`);
///  * разрешение на VPN — задача 33 (`VpnService.prepare()`);
///  * отчёт поддержки — задача 6 фазы 6 (генератор общий, отдача через
///    системное «Поделиться» вместо Проводника).
///
/// Заглушки намеренно пустые, а не «правдоподобные»: пустой список приложений
/// виден пользователю сразу, а выдуманные данные — нет.
PlatformServices buildAndroidPlatformServices() => PlatformServices(
      appCatalog: const _AndroidAppCatalog(),
      appIcons: const _AndroidAppIcons(),
      coreVersions: const _AndroidCoreVersions(),
      tunLog: const _AndroidTunLog(),
      privileges: const _AndroidPrivileges(),
      support: const AndroidSupportReporter(),
    );

/// Канал каталога приложений (нативная часть — `PlatformChannels.APPS_CHANNEL`).
const _appsChannel = MethodChannel('lol.silentgate/apps');

class _AndroidAppCatalog implements AppCatalog {
  const _AndroidAppCatalog();

  /// Установленные приложения с доступом в интернет.
  ///
  /// ⚠️ Пока этого не было, раздельное туннелирование на Android было
  /// недоступно ЦЕЛИКОМ: правило задаётся именем пакета, а взять его
  /// пользователю неоткуда — «выбрать файл», как на Windows, здесь невозможно.
  /// Фильтрация и сортировка сделаны на нативной стороне: там это один проход
  /// по уже загруженным данным, а не вторая сортировка тысячи строк в Dart.
  @override
  Future<List<CatalogApp>> list() async {
    try {
      final raw = await _appsChannel.invokeListMethod<Object?>('list');
      if (raw == null) return const [];
      final apps = raw.whereType<Map>().map((m) {
        final pkg = '${m['package'] ?? ''}';
        return CatalogApp(
          // На Android ключ правила — имя пакета (на Windows это путь к exe).
          key: pkg,
          label: '${m['name'] ?? pkg}',
        );
      }).where((a) => a.key.isNotEmpty).toList();
      // Список уже принёс метки — раскладываем их в кэш, чтобы строки правил
      // не дёргали канал по разу на приложение после закрытия выбора.
      warmLabels({for (final a in apps) a.key: a.label});
      return apps;
    } catch (e) {
      AppLog.w('Каталог приложений недоступен: $e');
      return const [];
    }
  }

  /// На Android выбирать «файл приложения» негде — правила задаются пакетом.
  @override
  bool get supportsManualPick => false;

  /// Кэш меток. Статика по той же причине, что и у иконок: список правил
  /// перестраивается на каждый кадр прокрутки.
  static final Map<String, String?> _labels = {};

  @override
  String? cachedLabel(String key) => _labels[key];

  @override
  Future<String?> labelFor(String key) async {
    if (_labels.containsKey(key)) return _labels[key];
    try {
      return _labels[key] =
          await _appsChannel.invokeMethod<String>('label', {'package': key});
    } catch (_) {
      // Отрицательный ответ тоже в кэш: удалённое приложение иначе дёргало бы
      // канал на каждой перерисовке.
      return _labels[key] = null;
    }
  }

  /// Прогреть кэш меток из уже полученного списка.
  static void warmLabels(Map<String, String> byPackage) =>
      _labels.addAll(byPackage);
}

class _AndroidAppIcons implements AppIconLoader {
  const _AndroidAppIcons();

  /// Кэш живёт в статике: экран правил перестраивается на каждый кадр списка,
  /// и без него канал дёргался бы по разу на строку при каждой прокрутке.
  static final Map<String, Uint8List?> _cache = {};

  @override
  Uint8List? cached(String key) => _cache[key];

  @override
  bool isCached(String key) => _cache.containsKey(key);

  @override
  Future<Uint8List?> load(String key) async {
    if (_cache.containsKey(key)) return _cache[key];
    try {
      final png = await _appsChannel
          .invokeMethod<Uint8List>('icon', {'package': key});
      // Пишем в кэш И отрицательный ответ: иначе приложение без иконки
      // заставляло бы канал работать вхолостую на каждой перерисовке.
      return _cache[key] = png;
    } catch (_) {
      return _cache[key] = null;
    }
  }
}

class _AndroidCoreVersions implements CoreVersionInfo {
  const _AndroidCoreVersions();

  /// Версия ядра — из самой библиотеки, а не из константы.
  ///
  /// Раньше здесь стоял прочерк с комментарием «придёт, когда AAR появится в
  /// сборке». AAR в сборке давно, а прочерк остался: в «О программе» вместо
  /// версии висело «н/д», и понять, на каком ядре человек сидит, было нельзя —
  /// в том числе при разборе его жалобы.
  @override
  Future<String> xray() async {
    try {
      final v = await const MethodChannel('lol.silentgate/device')
          .invokeMapMethod<String, dynamic>('coreVersions');
      final xray = '${v?['xray'] ?? ''}'.trim();
      final singbox = '${v?['singbox'] ?? ''}'.trim();
      // Показываем оба: на Android они живут в одном AAR, и знать надо оба.
      //
      // ⚠️ ДОЛЛАР ЗДЕСЬ НЕ ЭКРАНИРОВАТЬ. Стояло `'\$xray / sing-box \$singbox'`,
      // и строка печатала саму себя: в «О программе» на телефоне висело
      // «sing-box $singbox» вместо номера версии. Компилятор такое не ловит —
      // это валидная строка, — а тест на версию ядра нам взять неоткуда: она
      // приходит из нативного канала. Поймано глазами на эмуляторе.
      if (xray.isNotEmpty && singbox.isNotEmpty) return '$xray / sing-box $singbox';
      if (xray.isNotEmpty) return xray;
      if (singbox.isNotEmpty) return 'sing-box $singbox';
    } catch (_) {
      // Канал недоступен — честный прочерк лучше выдумки.
    }
    return 'н/д';
  }
}

class _AndroidTunLog implements TunLogReader {
  const _AndroidTunLog();

  /// Лог ядра: сюда `VpnService` перенаправляет вывод sing-box и — что важнее —
  /// паники Go (`Libbox.redirectStderr`). Без него причина падения туннеля не
  /// видна нигде.
  ///
  /// Если ядро ещё ни разу не запускалось, файла нет — тогда отдаём лог
  /// приложения, чтобы экран не выглядел сломанным.
  @override
  Future<String> tail({int lines = 200}) async {
    final dir = await AppPaths.supportDir();
    // Читаем хвост с конца файла: лог ядра ничем не ограничен, а прежний
    // readAsString() затягивал его целиком в память (та же беда, что подвешивала
    // Windows-версию на кнопке поддержки).
    final text = await RotatingLog.tail(
      '${dir.path}${Platform.pathSeparator}singbox.log',
      lines: lines,
    );
    if (text.trim().isNotEmpty) return text;
    // Ядро ещё не поднималось — показываем хотя бы лог приложения.
    final fallback = await AppLog.dump();
    final rows = fallback.split('\n');
    return rows.length <= lines
        ? fallback
        : rows.sublist(rows.length - lines).join('\n');
  }
}

class _AndroidPrivileges implements PrivilegeSetup {
  const _AndroidPrivileges();

  /// Блок прав на Android осмыслен (согласие `VpnService.prepare()`), но пока
  /// нечего настраивать — сервиса ещё нет. Показывать неработающую кнопку
  /// хуже, чем не показывать её вовсе.
  @override
  bool get isApplicable => false;

  @override
  Future<bool> isConfigured() async => false;

  @override
  Future<bool> configure() async => false;

  @override
  Future<bool> remove() async => false;
}

