import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// ⚠️ ПРИВЯЗКИ TOOLHELP ОБЪЯВЛЕНЫ ЗДЕСЬ, А НЕ ВЗЯТЫ ИЗ `package:win32`: снимка
// процессов в пакете нет вовсе (проверено на 5.15.0). Объявление узкое — ровно три
// функции и одна структура, нужные наблюдению за выбранными именами.
const _th32SnapProcess = 0x00000002;
const _invalidHandle = -1;
const _maxPath = 260;

final class _ProcessEntry32 extends Struct {
  @Uint32()
  external int dwSize;
  @Uint32()
  external int cntUsage;
  @Uint32()
  external int th32ProcessID;
  @IntPtr()
  external int th32DefaultHeapID;
  @Uint32()
  external int th32ModuleID;
  @Uint32()
  external int cntThreads;
  @Uint32()
  external int th32ParentProcessID;
  @Int32()
  external int pcPriClassBase;
  @Uint32()
  external int dwFlags;
  @Array(_maxPath)
  external Array<Uint16> szExeFile;
}

// ⚠️ Открывается ЛЕНИВО: файл собирается и под Android, где `kernel32.dll` нет.
// Пока никто не спросил снимок, библиотека не трогается.
final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _createSnapshot = _kernel32.lookupFunction<
    IntPtr Function(Uint32 flags, Uint32 pid),
    int Function(int flags, int pid)>('CreateToolhelp32Snapshot');

final _process32First = _kernel32.lookupFunction<
    Int32 Function(IntPtr snap, Pointer<_ProcessEntry32> entry),
    int Function(int snap, Pointer<_ProcessEntry32> entry)>('Process32FirstW');

final _process32Next = _kernel32.lookupFunction<
    Int32 Function(IntPtr snap, Pointer<_ProcessEntry32> entry),
    int Function(int snap, Pointer<_ProcessEntry32> entry)>('Process32NextW');

class RunningProcess {
  final int pid;
  final String name; // имя exe (basename)
  final String path; // полный путь
  const RunningProcess(this.pid, this.name, this.path);
}

final RegExp _versionedOldExeRe =
    RegExp(r'^(.+\.exe)\.old\.[0-9a-z_-]+$', caseSensitive: false);

/// Общие системные/рантайм-имена, которые не должны превращаться в широкую
/// маску каталога `\<stem>\` (чтобы `python.exe` или `cmd.exe` не захватывали
/// чужие программы).
const Set<String> _genericExeStems = <String>{
  'app',
  'audiodg',
  'bin',
  'cli',
  'client',
  'cmd',
  'conhost',
  'csrss',
  'ctfmon',
  'dllhost',
  'dwm',
  'explorer',
  'fontdrvhost',
  'game',
  'helper',
  'host',
  'java',
  'javaw',
  'launcher',
  'lsass',
  'main',
  'msedge',
  'msedgewebview2',
  'msiexec',
  'node',
  'notepad',
  'powershell',
  'pwsh',
  'python',
  'pythonw',
  'regedit',
  'run',
  'rundll32',
  'runtimebroker',
  'searchhost',
  'server',
  'service',
  'services',
  'setup',
  'shell',
  'sihost',
  'smss',
  'spoolsv',
  'start',
  'svchost',
  'system',
  'taskhostw',
  'test',
  'uninstall',
  'update',
  'updater',
  'user',
  'wininit',
  'winlogon',
  'wmiprvse',
  'worker',
  'wscript',
};

/// Системные процессы Windows, для которых при поиске каталогов приложений
/// не нужно открывать дескриптор `QueryFullProcessImageName`.
const Set<String> _systemSkipExeNames = <String>{
  'system',
  'registry',
  'smss.exe',
  'csrss.exe',
  'wininit.exe',
  'services.exe',
  'lsass.exe',
  'svchost.exe',
  'fontdrvhost.exe',
  'winlogon.exe',
  'dwm.exe',
  'spoolsv.exe',
  'wmiprvse.exe',
  'sihost.exe',
  'taskhostw.exe',
  'runtimebroker.exe',
  'ApplicationFrameHost.exe',
  'dllhost.exe',
  'conhost.exe',
  'audiodg.exe',
  'ctfmon.exe',
  'explorer.exe',
};

String _baseName(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? path : path.substring(i + 1);
}

/// Привести имя исполняемого файла к базовому `.exe` в нижнем регистре,
/// схлопывая версионные суффиксы самообновления вида `agy.exe.old.b01ba04f` →
/// `agy.exe`.
String normalizeVersionedExeName(String rawNameOrPath) {
  final lower = _baseName(rawNameOrPath.trim()).toLowerCase();
  final m = _versionedOldExeRe.firstMatch(lower);
  return m != null ? m.group(1)! : lower;
}

/// Выделить значимое имя каталога приложения из имени его `.exe`
/// (например, `antigravity.exe` → `antigravity`, `cursor.exe` → `cursor`).
/// Для слишком коротких или общих системных имён возвращает `null`.
String? exeStemForAppDir(String rawExeName) {
  final norm = normalizeVersionedExeName(rawExeName);
  if (!norm.endsWith('.exe')) return null;
  final stem = norm.substring(0, norm.length - 4).trim();
  if (stem.length < 3 || _genericExeStems.contains(stem)) return null;
  return stem;
}

/// Проверить, лежит ли [processPath] внутри каталога приложения `\<stem>\`
/// или `\.<stem>\` для хотя бы одного из выбранных имён [selectedNames].
bool _matchesAppDirFromNames(Set<String> selectedNames, String processPath) {
  final lowerPath = processPath.toLowerCase();
  for (final sel in selectedNames) {
    final stem = exeStemForAppDir(sel);
    if (stem == null) continue;
    final re = RegExp(
      r'[\\/]\.?' + RegExp.escape(stem) + r'[\\/]',
      caseSensitive: false,
    );
    if (re.hasMatch(lowerPath)) return true;
  }
  return false;
}

/// Проверить, подпадает ли процесс [processName] (и при наличии [processPath])
/// под набор выбранных имён [selectedNames] (пропущенных через
/// [normalizeVersionedExeName]).
///
/// Универсально учитывает:
///  * прямое совпадение имени `.exe`;
///  * версионные самообновляющиеся бинари `<имя>.exe.old.<хэш>`;
///  * вспомогательные и дочерние `.exe`, лежащие в каталоге выбранной
///    программы `\<stem>\` или `\.<stem>\` (например, языковые серверы,
///    CLI-помощники и воркеры внутри папки приложения).
bool matchesSelectedAppName(
  Set<String> selectedNames,
  String processName, {
  String? processPath,
}) {
  if (selectedNames.isEmpty) return false;
  final norm = normalizeVersionedExeName(processName);
  if (norm.isEmpty) return false;
  if (selectedNames.contains(norm)) return true;
  if (processPath != null &&
      processPath.isNotEmpty &&
      _matchesAppDirFromNames(selectedNames, processPath)) {
    return true;
  }
  return false;
}

/// Перечень запущенных процессов с полными путями exe (для выбора приложений в split-tunnel).
/// Пути элевейтнутых процессов могут быть недоступны без прав — они пропускаются.
class ProcessListWindows {
  static const _bufLen = 1024;
  static const _nameLen = 128; // базовому имени модуля больше не нужно

  /// ТОЛЬКО ПРОЦЕССЫ С ВЫБРАННЫМИ ИМЕНАМИ — ДЛЯ ПОСТОЯННОГО НАБЛЮДЕНИЯ.
  ///
  /// ⚠️ ПОЧЕМУ НЕ [enumerate]. Тот открывает дескриптор и спрашивает полный путь у
  /// КАЖДОГО процесса: на трёх сотнях процессов это три сотни пар системных вызовов.
  /// Один раз при выборе программы это незаметно, но kill switch пересматривает список
  /// всю сессию — и цена превращается в постоянный фон.
  ///
  /// Снимок `CreateToolhelp32Snapshot` отдаёт пару «номер процесса + имя файла» СРАЗУ,
  /// без единого дескриптора. Дескриптор открывается только для тех, чьё имя совпало,
  /// а таких единицы. Имя из снимка — то же самое `szExeFile`, что и basename пути.
  ///
  /// ⚠️ НАСТОЯЩИХ СОБЫТИЙ «ПРОЦЕСС ЗАПУСТИЛСЯ» ЗДЕСЬ НЕ БУДЕТ. Их даёт либо подписка
  /// WMI (`__InstanceCreationEvent`), либо сессия ETW: и то и другое из Dart означает
  /// собственный слой COM/ETW и отдельный поток, который обязан пережить элевацию и
  /// падение. Снимок раз в пару секунд стоит дешевле этого слоя и не может застрять.
  ///
  /// [lowerNames] — имена файлов в НИЖНЕМ регистре и без пути. Пустое множество —
  /// пустой ответ без единого системного вызова.
  static List<RunningProcess> matching(Set<String> lowerNames) {
    final result = <RunningProcess>[];
    if (lowerNames.isEmpty) return result;
    final normalizedNames = lowerNames.map(normalizeVersionedExeName).toSet();
    final hasDirStems =
        normalizedNames.any((n) => exeStemForAppDir(n) != null);

    final snap = _createSnapshot(_th32SnapProcess, 0);
    if (snap == _invalidHandle || snap == 0) return result;
    final entry = calloc<_ProcessEntry32>()
      ..ref.dwSize = sizeOf<_ProcessEntry32>();
    try {
      if (_process32First(snap, entry) == 0) return result;
      final rows = <({int pid, int ppid, String name})>[];
      do {
        final name = _wideName(entry.ref.szExeFile);
        if (name.isEmpty) continue;
        rows.add((
          pid: entry.ref.th32ProcessID,
          ppid: entry.ref.th32ParentProcessID,
          name: name,
        ));
      } while (_process32Next(snap, entry) != 0);

      // 1) Прямые совпадения по имени (включая `<имя>.exe.old.<хэш>`).
      final matchedPids = <int>{};
      for (final r in rows) {
        if (r.pid <= 4) continue;
        if (normalizedNames.contains(normalizeVersionedExeName(r.name))) {
          matchedPids.add(r.pid);
        }
      }

      // 2) Дочерние процессы, порождённые найденными приложениями (по цепочке
      //    `th32ParentProcessID`).
      if (matchedPids.isNotEmpty) {
        var added = true;
        while (added) {
          added = false;
          for (final r in rows) {
            if (r.pid <= 4 || matchedPids.contains(r.pid)) continue;
            if (r.ppid > 4 &&
                matchedPids.contains(r.ppid) &&
                !_systemSkipExeNames.contains(r.name.toLowerCase())) {
              matchedPids.add(r.pid);
              added = true;
            }
          }
        }
      }

      // 3) Сборка полных путей для прямых, дочерних и лежащих в каталоге
      //    приложения `\<stem>\` / `\.<stem>\` процессов.
      final seen = <String>{};
      for (final r in rows) {
        final isPidMatch = matchedPids.contains(r.pid);
        if (!isPidMatch) {
          if (!hasDirStems ||
              r.pid <= 4 ||
              _systemSkipExeNames.contains(r.name.toLowerCase())) {
            continue;
          }
        }
        final path = _pathOf(r.pid);
        if (path == null) continue;
        if (!isPidMatch &&
            !matchesSelectedAppName(normalizedNames, r.name,
                processPath: path)) {
          continue;
        }
        if (seen.add(path.toLowerCase())) {
          result.add(RunningProcess(r.pid, r.name, path));
        }
      }
    } finally {
      free(entry);
      CloseHandle(snap);
    }
    return result;
  }

  /// Полный путь exe по номеру процесса; `null` — спросить не дали.
  static String? _pathOf(int pid) {
    final h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (h == 0) return null;
    final buf = wsalloc(_bufLen);
    final size = calloc<Uint32>()..value = _bufLen;
    try {
      if (QueryFullProcessImageName(h, 0, buf, size) == 0) return null;
      final path = buf.toDartString();
      return path.isEmpty ? null : path;
    } finally {
      free(buf);
      free(size);
      CloseHandle(h);
    }
  }

  static String _wideName(Array<Uint16> chars) {
    final out = StringBuffer();
    for (var i = 0; i < _maxPath; i++) {
      final c = chars[i];
      if (c == 0) break;
      out.writeCharCode(c);
    }
    return out.toString();
  }

  static List<RunningProcess> enumerate() {
    final result = <RunningProcess>[];
    const maxCount = 2048;
    final pids = calloc<Uint32>(maxCount);
    final needed = calloc<Uint32>();
    try {
      if (EnumProcesses(pids, sizeOf<Uint32>() * maxCount, needed) == 0) {
        return result;
      }
      final count = needed.value ~/ sizeOf<Uint32>();
      final pidList = pids.asTypedList(count);
      final seen = <String>{};

      for (final pid in pidList) {
        if (pid == 0) continue;
        final h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
        if (h == 0) continue;
        final buf = wsalloc(_bufLen);
        final size = calloc<Uint32>()..value = _bufLen;
        try {
          if (QueryFullProcessImageName(h, 0, buf, size) != 0) {
            final path = buf.toDartString();
            if (path.isNotEmpty && seen.add(path.toLowerCase())) {
              final name = path.split(r'\').last;
              result.add(RunningProcess(pid, name, path));
            }
          }
        } finally {
          free(buf);
          free(size);
          CloseHandle(h);
        }
      }
    } finally {
      free(pids);
      free(needed);
    }

    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  /// Загружены ли в процесс модули с такими именами (регистр не важен).
  ///
  /// Нужно, чтобы назвать ВЛАДЕЛЬЦА чужого TUN-адаптера точно, а не гадать по
  /// списку известных названий: адаптер поднимает тот процесс, который держит
  /// `wintun.dll`. Другого способа связать адаптер с приложением из
  /// пользовательского режима нет — Windows такой связи наружу не отдаёт.
  ///
  /// ⚠️ Чтение модулей требует PROCESS_VM_READ, а VPN-клиенты обычно запущены с
  /// правами администратора: у невозвышенного приложения дескриптор не
  /// откроется, и ответ будет false. Это НЕ «модуля нет» — это «спросить не
  /// дали», поэтому вызывающий обязан иметь запасной способ опознания.
  static bool hasModule(int pid, List<String> moduleNames) {
    final wanted = moduleNames.map((e) => e.toLowerCase()).toSet();
    const maxModules = 512;
    final h = OpenProcess(
        PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (h == 0) return false;
    final mods = calloc<IntPtr>(maxModules);
    final needed = calloc<Uint32>();
    try {
      if (EnumProcessModules(h, mods.cast(), sizeOf<IntPtr>() * maxModules,
              needed) ==
          0) {
        return false;
      }
      final count = needed.value ~/ sizeOf<IntPtr>();
      // Буфер ОДИН на весь процесс, а не на каждый модуль: модулей бывает под
      // сотню, процессов — под три сотни, и выделение на каждый превращало
      // проверку в две минуты (замерено). Имя базовое, без пути: полный путь
      // здесь не нужен, а стоит дороже.
      final buf = wsalloc(_nameLen);
      try {
        for (var i = 0; i < count && i < maxModules; i++) {
          if (GetModuleBaseName(h, mods[i], buf, _nameLen) != 0 &&
              wanted.contains(buf.toDartString().toLowerCase())) {
            return true;
          }
        }
      } finally {
        free(buf);
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      free(mods);
      free(needed);
      CloseHandle(h);
    }
  }
}
