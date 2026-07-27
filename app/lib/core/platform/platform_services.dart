/// Платформенные сервисы, которые нужны интерфейсу.
///
/// UI обязан работать против этих контрактов, а не импортировать
/// `engine/windows/*` напрямую: иначе Android-сборка просто не компилируется,
/// а сами экраны оказываются привязаны к Windows-механике (реестр, schtasks,
/// перечисление процессов).
///
/// Реализации: `engine/windows/platform_services_windows.dart` и
/// `engine/android/platform_services_android.dart` (появится в фазе 3).
/// Регистрация — в `main` через [registerPlatformServices].
library;

import 'dart:io';
import 'dart:typed_data';

import '../settings/app_settings.dart';
import 'support_context.dart';

export 'support_context.dart';

/// Приложение, которое пользователь может выбрать в раздельном туннелировании.
///
/// На Windows это исполняемый файл (ключ — путь к exe), на Android — пакет
/// (ключ — `packageName`). Поле [key] и есть то, что уходит в правило.
class CatalogApp {
  /// Ключ правила: путь к exe (Windows) либо packageName (Android).
  final String key;

  /// Человекочитаемое имя для списка.
  final String label;

  const CatalogApp({required this.key, required this.label});
}

/// Каталог приложений для экрана раздельного туннелирования.
abstract interface class AppCatalog {
  /// Список приложений, доступных для добавления в правила.
  ///
  /// Windows — запущенные процессы; Android — установленные приложения
  /// (`PackageManager.getInstalledApplications`).
  Future<List<CatalogApp>> list();

  /// Может ли пользователь добавить приложение вручную, минуя список
  /// (на Windows — выбором .exe через диалог файлов; на Android смысла нет).
  bool get supportsManualPick;
}

/// Иконки приложений для списков правил и схемы маршрута.
abstract interface class AppIconLoader {
  /// Готовая иконка из кэша (синхронно, для отрисовки без мигания).
  Uint8List? cached(String key);

  /// Есть ли ключ в кэше — включая закэшированную неудачу
  /// («не удалось» ≠ «ещё не грузили»).
  bool isCached(String key);

  /// Загрузить иконку. Реализация обязана дедуплицировать параллельные
  /// запросы и кэшировать в том числе отрицательный результат.
  Future<Uint8List?> load(String key);
}

/// Версии ядер для раздела «О программе» и отчёта поддержки.
abstract interface class CoreVersionInfo {
  /// Версия Xray или локализуемый маркер недоступности.
  Future<String> xray();
}

/// Чтение лога движка туннеля (экран «Логи», диагностика TUN).
abstract interface class TunLogReader {
  /// Последние [lines] строк лога; пустая строка — лога ещё нет.
  Future<String> tail({int lines});
}

/// Подготовка прав на подъём туннеля.
///
/// Windows: задача Планировщика, дающая старт без UAC при каждом подключении.
/// Android: согласие `VpnService.prepare()` — системный диалог, один раз.
/// Контракт намеренно общий («настроено / настроить / снять»), чтобы экран
/// настроек не знал, что именно под ним.
abstract interface class PrivilegeSetup {
  /// Нужен ли этот блок на текущей платформе вообще.
  bool get isApplicable;

  /// Настроено ли уже.
  Future<bool> isConfigured();

  /// Настроить. `true` — успех.
  Future<bool> configure();

  /// Снять настройку. `true` — успех.
  Future<bool> remove();
}

/// Отчёт для поддержки.
abstract interface class SupportReporter {
  /// Собрать отчёт и вернуть путь к файлу.
  Future<String> generate({
    required AppSettings settings,
    required SupportContext ctx,
  });

  /// Показать/отдать пользователю готовый отчёт: на Windows — открыть папку и
  /// файл, на Android — системный диалог «Поделиться».
  Future<void> reveal(String path);
}

/// Набор платформенных сервисов, доступный интерфейсу.
class PlatformServices {
  final AppCatalog appCatalog;
  final AppIconLoader appIcons;
  final CoreVersionInfo coreVersions;
  final TunLogReader tunLog;
  final PrivilegeSetup privileges;
  final SupportReporter support;

  const PlatformServices({
    required this.appCatalog,
    required this.appIcons,
    required this.coreVersions,
    required this.tunLog,
    required this.privileges,
    required this.support,
  });
}

PlatformServices? _services;

/// Зарегистрировать реализации (вызывается из `main` до построения UI).
void registerPlatformServices(PlatformServices s) => _services = s;

/// Текущие платформенные сервисы.
///
/// Бросает, если регистрация не выполнена: молча отдавать заглушки нельзя —
/// это выглядело бы как «функции просто не работают».
PlatformServices get platform {
  final s = _services;
  if (s != null) return s;
  throw StateError(
    'registerPlatformServices() не был вызван: платформенные сервисы для '
    '${Platform.operatingSystem} не зарегистрированы. Вызовите его в main() '
    'до runApp.',
  );
}

/// Зарегистрированы ли сервисы (для тестов и защитных проверок в UI).
bool get hasPlatformServices => _services != null;
