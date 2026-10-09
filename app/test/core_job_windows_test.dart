import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/core_job_windows.dart';

/// Ядра умирают вместе с приложением, даже при аварии (см. `CoreJob`).
void main() {
  test('раскладка JOBOBJECT_EXTENDED_LIMIT_INFORMATION: один флаг на месте',
      () {
    final b = CoreJob.extendedLimitInfo();
    expect(b.length, 144, reason: 'размер структуры на x64');
    final d = ByteData.sublistView(b);
    expect(d.getUint32(16, Endian.little), 0x2000,
        reason: 'LimitFlags = KILL_ON_JOB_CLOSE, после двух LARGE_INTEGER');
    var nonZero = 0;
    for (final x in b) {
      if (x != 0) nonZero++;
    }
    expect(nonZero, 1, reason: 'остальные лимиты не задаём');
  });

  test('CoreCleanup.register кладёт ядро в задание', () {
    // Регистрация — единственная точка, через которую проходят ВСЕ ядра
    // (Xray, sing-box-прокси, харнессы пинга). Страж на её содержимое.
    final src =
        File('lib/core/platform/core_cleanup.dart').readAsStringSync();
    expect(src, contains('CoreJob.adopt(p.pid)'));
  });

  test('⚠️ закрытие задания убивает процесс внутри — то, ради чего всё это',
      () async {
    // Безвредный долгоживущий процесс: ping на loopback, сеть не нужна.
    final p = await Process.start('ping', ['-n', '60', '127.0.0.1']);
    final job = CoreJob.createKillOnCloseJob();
    try {
      expect(job, isNot(0), reason: 'задание не создано');
      expect(CoreJob.assignTo(job, p.pid), isTrue,
          reason: 'процесс не помещён в задание');
      // Так ОС закрывает хендл при смерти приложения.
      CoreJob.closeForTests(job);
      final code = await p.exitCode.timeout(const Duration(seconds: 10),
          onTimeout: () => -999);
      expect(code, isNot(-999),
          reason: 'процесс пережил закрытие задания — ядро осталось бы '
              'сиротой после аварии приложения');
    } finally {
      p.kill(ProcessSignal.sigkill);
    }
  }, skip: !Platform.isWindows);

  test('несуществующий pid — false, без исключения', () {
    final job = CoreJob.createKillOnCloseJob();
    try {
      expect(CoreJob.assignTo(job, 0x7ffffff0), isFalse);
    } finally {
      CoreJob.closeForTests(job);
    }
  }, skip: !Platform.isWindows);
}
