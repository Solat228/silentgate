import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../engine/windows/elevation.dart';
import '../geo/sha256.dart';
import '../platform/app_env.dart';
import '../platform/app_log.dart';
import '../platform/app_paths.dart';
import 'update_installer.dart';

/// УСТАНОВЩИК ВНУТРИ ПРИЛОЖЕНИЯ — WINDOWS.
///
/// Ставим через контракт 1.13.0 с `installer/silentgate.iss`: тихий режим,
/// `/FORCEQUIT` вместо вопроса про живой VPN, `/FORCEDOWNGRADE` для
/// осознанного отката, `ShouldRelaunch` поднимает приложение обратно. Сам
/// `.iss` этот файл не меняет; литералы аргументов сверяет
/// `test/installer_test.dart`, читая оба файла.
///
/// ⚠️ ТОЛЬКО ДЛЯ УСТАНОВЛЕННОЙ КОПИИ. Признак — `InstallLocation` из ключа
/// удаления Inno в HKCU совпадает с каталогом `Platform.resolvedExecutable`.
/// Портативная, изолированная и возвышенная копии получают ссылку с
/// объяснением (см. [InstallCapability]).
///
/// ⚠️ ПРОЦЕСС УСТАНОВЩИКА НЕ РЕГИСТРИРУЕТСЯ В `CoreCleanup`: он обязан
/// ПЕРЕЖИТЬ нас — мы закроемся по его просьбе, а он заменит наши файлы.
/// Зарегистрированный ребёнок был бы убит вместе с ядрами при выходе.

/// Аргументы тихой установки. Литералы вынесены, чтобы страж мог сверить их
/// с `.iss`: `/FORCEQUIT` и `/FORCEDOWNGRADE` Inno сам не знает, их разбирает
/// секция `[Code]` по точному тексту.
abstract final class SetupArgs {
  /// `/SILENT`, не `/VERYSILENT`: человек видит полосу установки и понимает,
  /// почему приложение сейчас закроется.
  static const silent = '/SILENT';
  static const suppressMsgBoxes = '/SUPPRESSMSGBOXES';
  static const noRestart = '/NORESTART';
  static const noCancel = '/NOCANCEL';

  /// Согласие на разрыв живого туннеля дано заранее (наш ключ, `[Code]`).
  static const forceQuit = '/FORCEQUIT';

  /// Осознанный откат на прежнюю версию (наш ключ, `[Code]`).
  static const forceDowngrade = '/FORCEDOWNGRADE';

  static const dirPrefix = '/DIR=';
  static const logPrefix = '/LOG=';
}

/// GUID установки — тот же, что `MyAppId` в `.iss` (страж сверяет).
const kInnoAppId = '{B7F3B2A1-5C2E-4E7A-9F1D-51E4C0DE0001}';

/// Ключ удаления Inno per-user (`PrivilegesRequired=lowest`). HKLM не
/// смотрим: оттуда путь мог бы задать администратор, а ставить туда мы всё
/// равно не смогли бы без прав.
const kUninstallKey =
    'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\${kInnoAppId}_is1';

/// Имя значения с каталогом установки — его же читает `[Code]` в `.iss`.
const kInstallLocationValue = 'InstallLocation';

/// Текст вывода `reg query` (уже раскодированный) либо `null`, если запрос
/// не удался вовсе.
typedef RegQuery = Future<String?> Function();

/// Запуск процесса установщика: путь и аргументы СПИСКОМ.
typedef ProcessStarter = Future<void> Function(String exe, List<String> args);

/// Итог проверки «можно ли ставить самим» — чистая функция от входов.
class WindowsInstallState {
  final InstallCapability capability;

  /// Каталог установки из реестра, как записал Inno (с хвостовым `\`), либо
  /// `null`, если записи нет.
  final String? installLocation;

  const WindowsInstallState(this.capability, this.installLocation);

  /// Порядок проверок — от «этой копии установка не касается вовсе» к
  /// «установка есть, но не эта». Портативность старше изоляции старше
  /// возвышения: объяснение человеку начинается с самого простого.
  static WindowsInstallState detect({
    required String? regQueryOutput,
    required String exePath,
    required bool portable,
    required bool isolated,
    required bool elevated,
  }) {
    if (portable) return const WindowsInstallState(InstallCapability.portable, null);
    if (isolated) return const WindowsInstallState(InstallCapability.isolated, null);
    if (elevated) return const WindowsInstallState(InstallCapability.elevated, null);

    final location =
        regQueryOutput == null ? null : parseRegSz(regQueryOutput, kInstallLocationValue);
    if (location == null) {
      return const WindowsInstallState(InstallCapability.notInstalled, null);
    }

    final exeDir = File(exePath).parent.path;
    if (!sameDirectory(location, exeDir)) {
      return WindowsInstallState(InstallCapability.locationMismatch, location);
    }
    return WindowsInstallState(InstallCapability.ready, location);
  }
}

/// Значение REG_SZ из вывода `reg query`.
///
/// Строка выглядит как `    InstallLocation    REG_SZ    C:\Users\…\`; отступ
/// бывает пробелами и табуляцией, значение — с пробелами и кириллицей, до
/// конца строки. Имя сравнивается без учёта регистра (реестр его не
/// различает), но ЦЕЛИКОМ: `InstallLocationOld` не подходит.
String? parseRegSz(String regOut, String valueName) {
  final re = RegExp(
    '^[ \\t]*${RegExp.escape(valueName)}[ \\t]+REG_SZ[ \\t]+(.*?)[ \\t]*\$',
    multiLine: true,
    caseSensitive: false,
  );
  for (final line in regOut.split(RegExp(r'\r?\n'))) {
    final m = re.firstMatch(line);
    if (m == null) continue;
    final v = m.group(1)!;
    return v.isEmpty ? null : v;
  }
  return null;
}

/// Каталог в виде, пригодном для сравнения: регистр не важен (NTFS), `/`
/// равен `\`, хвостовой разделитель не значит ничего.
String normalizeDirForCompare(String path) {
  var p = path.trim().replaceAll('/', '\\').toLowerCase();
  while (p.length > 3 && p.endsWith('\\')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

bool sameDirectory(String a, String b) =>
    normalizeDirForCompare(a) == normalizeDirForCompare(b);

/// Каталог для `/DIR=` — без хвостового `\`.
///
/// ⚠️ Dart при пробеле в аргументе оборачивает его в кавычки и удваивает
/// хвостовые обратные слэши по правилам C-рантайма (`"…\Silent Gate\\"`).
/// Inno разбирает командную строку по правилам Delphi, где обратный слэш не
/// экранирует ничего, — и получил бы каталог с `\\` на конце. Корень диска
/// (`C:\`) остаётся как есть: без слэша это уже не путь.
String setupDirArgument(String installLocation) {
  var p = installLocation.trim().replaceAll('/', '\\');
  while (p.length > 3 && p.endsWith('\\')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// Аргументы установщика — СПИСКОМ и БЕЗ КАВЫЧЕК: их расставит `Process.start`
/// по правилам платформы, а свои кавычки уехали бы в значение `/DIR=`.
List<String> buildSetupArgs({
  required String installLocation,
  required String logPath,
  required bool forceQuit,
  required bool allowDowngrade,
}) =>
    [
      SetupArgs.silent,
      SetupArgs.suppressMsgBoxes,
      SetupArgs.noRestart,
      SetupArgs.noCancel,
      if (forceQuit) SetupArgs.forceQuit,
      '${SetupArgs.dirPrefix}${setupDirArgument(installLocation)}',
      '${SetupArgs.logPrefix}$logPath',
      if (allowDowngrade) SetupArgs.forceDowngrade,
    ];

typedef _MbToWcC = Int32 Function(
    Uint32 codePage, Uint32 flags, Pointer<Uint8> src, Int32 srcLen, Pointer<Uint16> dst, Int32 dstLen);
typedef _MbToWcD = int Function(
    int codePage, int flags, Pointer<Uint8> src, int srcLen, Pointer<Uint16> dst, int dstLen);
typedef _GetOemCpC = Uint32 Function();
typedef _GetOemCpD = int Function();

/// `CP_OEMCP` — «текущая OEM-страница системы».
const _cpOem = 1;

/// OEM-кодовая страница системы (866 на русской Windows); 0 вне Windows.
int oemCodePage() {
  if (!Platform.isWindows) return 0;
  try {
    return DynamicLibrary.open('kernel32.dll')
        .lookupFunction<_GetOemCpC, _GetOemCpD>('GetOEMCP')();
  } catch (_) {
    return 0;
  }
}

/// Байты вывода консольной утилиты → текст.
///
/// ⚠️ `reg.exe` ПЕЧАТАЕТ В OEM-СТРАНИЦЕ, А `systemEncoding` ЧИТАЕТ ANSI. Замер
/// на хосте 20.09.2026: «версия» приходит байтами a2 a5 e0 e1 a8 ef (cp866),
/// `Process.run` по умолчанию отдаёт «ўҐабЁп» (cp1251). Путь установки с
/// кириллицей в имени пользователя превращался бы в мусор, сравнение с
/// каталогом exe не сходилось бы — и КАЖДЫЙ русский пользователь получал бы
/// `locationMismatch` вместо самообновления. Поэтому вывод берётся байтами и
/// раскодируется `MultiByteToWideChar(CP_OEMCP)`; вне Windows и при сбое FFI —
/// latin1 (ASCII-пути при этом целы).
String decodeOemBytes(List<int> bytes) {
  if (bytes.isEmpty) return '';
  if (!Platform.isWindows) return latin1.decode(bytes);
  try {
    final fn = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<_MbToWcC, _MbToWcD>('MultiByteToWideChar');
    final src = calloc<Uint8>(bytes.length);
    try {
      src.asTypedList(bytes.length).setAll(0, bytes);
      final n = fn(_cpOem, 0, src, bytes.length, nullptr, 0);
      if (n <= 0) return latin1.decode(bytes);
      final dst = calloc<Uint16>(n);
      try {
        final written = fn(_cpOem, 0, src, bytes.length, dst, n);
        if (written <= 0) return latin1.decode(bytes);
        return String.fromCharCodes(dst.asTypedList(written));
      } finally {
        calloc.free(dst);
      }
    } finally {
      calloc.free(src);
    }
  } catch (_) {
    return latin1.decode(bytes);
  }
}

/// Боевой запрос реестра: `reg query <ключ> /v InstallLocation`.
///
/// Нет ключа — `reg` выходит с кодом 1 и печатает `ERROR: …` (в stderr);
/// отдаём пустую строку — «записи нет». Не запустился вовсе — `null`.
Future<String?> defaultRegQuery() async {
  try {
    final r = await Process.run(
      'reg',
      ['query', kUninstallKey, '/v', kInstallLocationValue],
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    if (r.exitCode != 0) return '';
    return decodeOemBytes(r.stdout as List<int>);
  } catch (e) {
    AppLog.w('Обновление: reg query не выполнился: $e');
    return null;
  }
}

/// Боевой запуск: аргументы списком, без оболочки, отсоединённо — установщик
/// обязан пережить наш выход.
Future<void> defaultProcessStarter(String exe, List<String> args) async {
  await Process.start(exe, args, runInShell: false, mode: ProcessStartMode.detached);
}

class WindowsUpdateInstaller extends StagedUpdateInstaller {
  final RegQuery _regQuery;
  final ProcessStarter _start;
  final String _exePath;
  final bool? _portable;
  final bool? _isolated;
  final bool Function() _isElevated;

  /// Все зависимости подменяемы — тест не читает реестр и не запускает
  /// процессов. Умолчания — боевые.
  WindowsUpdateInstaller({
    RegQuery? regQuery,
    ProcessStarter? start,
    String? exePath,
    bool? portable,
    bool? isolated,
    bool Function()? isElevated,
    super.clock,
  })  : _regQuery = regQuery ?? defaultRegQuery,
        _start = start ?? defaultProcessStarter,
        _exePath = exePath ?? Platform.resolvedExecutable,
        _portable = portable,
        _isolated = isolated,
        _isElevated = isElevated ?? _defaultElevated;

  static bool _defaultElevated() => Platform.isWindows && Elevation.isElevated;

  /// Тот же признак, что у `AppInstanceMutex`: метка рядом с exe.
  bool get _portableNow {
    final known = _portable;
    if (known != null) return known;
    try {
      final dir = File(_exePath).parent.path;
      return File('$dir${Platform.pathSeparator}${AppPaths.portableMarker}').existsSync();
    } catch (_) {
      return false;
    }
  }

  bool get _isolatedNow => _isolated ?? (AppEnv.portOffset != 0);

  Future<WindowsInstallState> _detect() async {
    if (!Platform.isWindows) {
      return const WindowsInstallState(InstallCapability.unsupported, null);
    }
    return WindowsInstallState.detect(
      regQueryOutput: await _regQuery(),
      exePath: _exePath,
      portable: _portableNow,
      isolated: _isolatedNow,
      elevated: _isElevated(),
    );
  }

  @override
  Future<InstallCapability> capability() async => (await _detect()).capability;

  @override
  Future<void> launch(
    File verified, {
    required String version,
    required String expectedSha256,
    bool forceQuit = false,
    bool allowDowngrade = false,
  }) async {
    final state = await _detect();
    if (state.capability != InstallCapability.ready || state.installLocation == null) {
      throw UpdateInstallException(
          'установка самим невозможна: ${state.capability.name}');
    }

    // ⚠️ ПОВТОРНАЯ ПРОВЕРКА ТОГО ЖЕ ПУТИ ПРЯМО ПЕРЕД ЗАПУСКОМ. Хэш, посчитанный
    // при закачке, говорит о файле, который был тогда; запускаем мы файл,
    // который лежит сейчас. Каталог `updates/` доступен на запись всему, что
    // работает от имени пользователя.
    final String actual;
    try {
      actual = await Sha256.ofFile(verified);
    } catch (e) {
      throw UpdateInstallException('установщик не прочитан: $e');
    }
    if (actual.toLowerCase() != expectedSha256.trim().toLowerCase()) {
      AppLog.e('Обновление: хэш установщика изменился после проверки — запуск отменён');
      throw const UpdateInstallException('хэш установщика не совпал с проверенным');
    }

    final logPath = await logPathFor(version);
    final args = buildSetupArgs(
      installLocation: state.installLocation!,
      logPath: logPath,
      forceQuit: forceQuit,
      allowDowngrade: allowDowngrade,
    );

    // Запись — ДО запуска: установщик закроет нас через секунды, и пишущий
    // после `start` код мог бы не успеть. Не запустился — записи быть не
    // должно, иначе следующий старт покажет «установка не завершилась».
    final pending = PendingInstall(
      version: version,
      startedAt: clock().toUtc(),
      exePath: verified.path,
      logPath: logPath,
    );
    await writePending(pending);
    try {
      await _start(verified.path, args);
    } catch (e) {
      try {
        (await pendingFile()).deleteSync();
      } catch (_) {}
      AppLog.e('Обновление: установщик не запустился: $e');
      throw UpdateInstallException('установщик не запустился: $e');
    }
    AppLog.i('Обновление: запущен установщик $version '
        '(${forceQuit ? 'с разрывом VPN' : 'без разрыва VPN'}'
        '${allowDowngrade ? ', откат' : ''})');
  }
}
