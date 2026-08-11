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

  /// Подождать, пока порты освободятся. `true` — дождались.
  ///
  /// ⚠️ ЗАЧЕМ ЭТО НУЖНО И ПОЧЕМУ ОДНОЙ ПРОВЕРКИ МАЛО.
  ///
  /// Быстрое «Отключить → Подключить» — это гонка с САМИМ СОБОЙ: прежнее ядро
  /// получило `kill`, но Windows освобождает его слушающий сокет не мгновенно.
  /// Новое ядро стартует, не может забиндиться и умирает с кодом 1. Дальше
  /// включается kill switch — и пользователь видит не «подождите секунду», а
  /// «весь интернет лёг», причём в журнале одна строка «код 1».
  ///
  /// Ждать нужно ИМЕННО ЗДЕСЬ, а не гасить симптом задержкой перед стартом:
  /// фиксированная пауза либо слишком коротка на медленной машине, либо зря
  /// задерживает подключение на быстрой.
  static Future<bool> waitFree(
    Iterable<int> ports, {
    Duration timeout = const Duration(seconds: 6),
    Duration step = const Duration(milliseconds: 200),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (await findConflict(ports) == null) return true;
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future.delayed(step);
    }
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

  /// Порт держит НАШЕ ЖЕ ядро — то есть это остаток прошлой сессии, а не
  /// чужой клиент. Разница принципиальна: чужого закрывает пользователь, наш
  /// уйдёт сам, надо лишь подождать.
  bool get heldByOwnCore {
    final h = (holder ?? '').toLowerCase();
    return h == 'xray.exe' || h == 'sing-box.exe' || h == 'silentgate.exe';
  }

  String get fallbackMessage {
    // ⚠️ НЕ НАЗЫВАЕМ КЛИЕНТОВ ПО ИМЕНИ НАУГАД. Раньше здесь стояло «обычно это
    // Happ, v2rayTun, NekoBox» — список, который у половины пользователей не
    // имеет отношения к делу и уводит разбор в сторону. Имя занявшего процесса
    // мы и так определяем; если не удалось — честнее сказать «не удалось», чем
    // предложить угадывать из списка.
    if (heldByOwnCore) {
      return 'Порт $port ещё занят нашим ядром ($holder) от прошлой сессии.\n\n'
          'Так бывает, если выключить и сразу включить VPN. Подождите несколько '
          'секунд и попробуйте снова.';
    }
    if (holder == null) {
      return 'Порт $port уже занят другой программой, определить её не удалось.\n\n'
          'Чаще всего это другой VPN-клиент: он слушает те же локальные порты. '
          'Закройте его полностью, в том числе из трея, и попробуйте снова.';
    }
    return 'Порт $port уже занят программой $holder.\n\n'
        'Закройте её полностью, в том числе из трея, и попробуйте снова.';
  }
}
