import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Запущена ли эта копия из пакета MSIX (Microsoft Store) — и чем это
/// оборачивается для приложения.
///
/// ⚠️ ПРИЗНАК — ИДЕНТИФИКАЦИЯ ПАКЕТА У ПРОЦЕССА, А НЕ ФЛАГ СБОРКИ. Один и тот
/// же exe работает и из папки установщика, и из `C:\Program Files\WindowsApps`;
/// различает их только Windows. Флаг сборки (`SILENTGATE_STORE`) отвечает за
/// другое — за окно согласия на данные устройства.
///
/// Что в пакете иначе (проверено в VM 21.10.2026, Windows 11 23H2):
/// * папка с exe меняется при КАЖДОМ обновлении (в имени версия), поэтому всё,
///   что запускает приложение снаружи — задача Планировщика, автозапуск,
///   перезапуск, — обязано идти через постоянный псевдоним [aliasPath];
/// * схему `silentgate://` объявляет манифест пакета; запись в HKCU пережила
///   бы удаление пакета и указывала бы в пустоту;
/// * обновляет Microsoft Store, а не приложение;
/// * свежая установка держит `%APPDATA%\SilentGate` в своей песочнице, и
///   Windows стирает её вместе с пакетом — отсюда копия в «Документы».
abstract final class PackageIdentity {
  /// Имя псевдонима из манифеста (`uap3:AppExecutionAlias`). Совпадение с
  /// `installer/msix/AppxManifest.xml` стережёт `test/msix_package_test.dart`.
  static const aliasName = 'silentgate.exe';

  /// Подмена для тестов: `null` — спросить Windows.
  @visibleForTesting
  static bool? debugPackaged;

  static bool? _cached;

  /// Процесс выполняется с идентификацией пакета.
  static bool get isPackaged {
    final o = debugPackaged;
    if (o != null) return o;
    return _cached ??= _detect();
  }

  /// `GetCurrentPackageFullName` с пустым буфером: у процесса пакета —
  /// ERROR_INSUFFICIENT_BUFFER (122), без пакета — APPMODEL_ERROR_NO_PACKAGE
  /// (15700). Функция есть с Windows 8; на её отсутствие и на любую ошибку
  /// ответ «не пакет» — так приложение ведёт себя как обычная установка.
  static bool _detect() {
    if (!Platform.isWindows) return false;
    try {
      final fn = DynamicLibrary.open('kernel32.dll').lookupFunction<
          Int32 Function(Pointer<Uint32>, Pointer<Utf16>),
          int Function(Pointer<Uint32>, Pointer<Utf16>)>(
          'GetCurrentPackageFullName');
      final len = calloc<Uint32>();
      try {
        return fn(len, nullptr) == 122;
      } finally {
        calloc.free(len);
      }
    } catch (_) {
      return false;
    }
  }

  /// Постоянный путь запуска пакета:
  /// `%LOCALAPPDATA%\Microsoft\WindowsApps\silentgate.exe`. Windows кладёт его
  /// при установке, не меняет при обновлениях и убирает при удалении.
  static String? aliasPath({Map<String, String>? env}) {
    final local = (env ?? Platform.environment)['LOCALAPPDATA'];
    if (local == null || local.isEmpty) return null;
    return '$local\\Microsoft\\WindowsApps\\$aliasName';
  }

  /// Чем запускать себя снаружи (задача, автозапуск, перезапуск, помощник
  /// TUN). Вне пакета — сам exe, как и раньше.
  static String launchPath() => launchPathFor(
        packaged: isPackaged,
        exe: Platform.resolvedExecutable,
        alias: aliasPath(),
      );

  @visibleForTesting
  static String launchPathFor(
          {required bool packaged, required String exe, String? alias}) =>
      packaged && alias != null ? alias : exe;
}
