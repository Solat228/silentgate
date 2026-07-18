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
}
