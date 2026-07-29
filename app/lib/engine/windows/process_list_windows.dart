import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class RunningProcess {
  final int pid;
  final String name; // имя exe (basename)
  final String path; // полный путь
  const RunningProcess(this.pid, this.name, this.path);
}

/// Перечень запущенных процессов с полными путями exe (для выбора приложений в split-tunnel).
/// Пути элевейтнутых процессов могут быть недоступны без прав — они пропускаются.
class ProcessListWindows {
  static const _bufLen = 1024;
  static const _nameLen = 128; // базовому имени модуля больше не нужно

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
