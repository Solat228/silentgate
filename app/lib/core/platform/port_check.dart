import 'dart:io';

/// Кто занял локальный порт. Нужен для понятной ошибки вместо «Ядро завершилось
/// при запуске»: чаще всего это другой VPN-клиент (Happ, v2rayTun, NekoBox),
/// который слушает те же 10808/10809.
class PortCheck {
  /// Свободен ли порт на 127.0.0.1.
  static Future<bool> isFree(int port) async {
    ServerSocket? s;
    try {
      s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      return true;
    } catch (_) {
      return false;
    } finally {
      await s?.close();
    }
  }

  /// Имя процесса, слушающего порт («Happ.exe»), либо null.
  /// Best-effort: netstat + tasklist; ошибки молча игнорируются.
  static Future<String?> holderName(int port) async {
    try {
      final net = await Process.run('netstat', ['-ano', '-p', 'TCP'])
          .timeout(const Duration(seconds: 5));
      final line = '${net.stdout}'
          .split('\n')
          .map((l) => l.trim())
          .firstWhere(
            (l) =>
                l.contains('LISTENING') &&
                (l.contains('127.0.0.1:$port') || l.contains('0.0.0.0:$port')),
            orElse: () => '',
          );
      if (line.isEmpty) return null;
      final pid = line.split(RegExp(r'\s+')).last;
      if (int.tryParse(pid) == null) return null;

      final tl = await Process.run(
              'tasklist', ['/FI', 'PID eq $pid', '/NH', '/FO', 'CSV'])
          .timeout(const Duration(seconds: 5));
      final row = '${tl.stdout}'.trim();
      if (row.isEmpty || !row.startsWith('"')) return null;
      return row.split('","').first.replaceAll('"', '');
    } catch (_) {
      return null;
    }
  }

  /// Найти первый занятый порт, либо null, если все свободны.
  ///
  /// Возвращает ДАННЫЕ, а не только текст: [PortConflict.holder] на Android
  /// всегда null (там нет ни `netstat`, ни `tasklist`, а `/proc` закрыт с
  /// API 26), и интерфейс сможет подобрать подходящую формулировку.
  static Future<PortConflict?> findConflict(Iterable<int> ports) async {
    for (final port in ports) {
      if (await isFree(port)) continue;
      return PortConflict(port: port, holder: await holderName(port));
    }
    return null;
  }

  /// Готовое сообщение об ошибке, либо null. Русский фолбэк — он уходит в лог
  /// и отчёт поддержки, которые не переводятся.
  static Future<String?> describeConflict(Iterable<int> ports) async =>
      (await findConflict(ports))?.fallbackMessage;
}

/// Занятый локальный порт и (если удалось определить) программа-виновник.
class PortConflict {
  final int port;

  /// Имя программы, занявшей порт. null — определить не удалось: так всегда
  /// бывает на Android и иногда на Windows (элевейтнутый процесс).
  final String? holder;

  const PortConflict({required this.port, this.holder});

  String get fallbackMessage {
    final by = holder == null ? 'другой программой' : 'программой $holder';
    return 'Порт $port уже занят $by.\n\n'
        'Обычно это другой VPN-клиент (Happ, v2rayTun, NekoBox) — он слушает те же '
        'локальные порты. Закройте его полностью (в том числе из трея) и попробуйте снова.';
  }
}
