import 'dart:io';

import '../../core/dpi/dpi_bypass_proxy.dart';
import '../../core/platform/app_log.dart';
import '../../core/platform/app_paths.dart';

/// Опциональный раннер `winws.exe` (`WinDivert`) на Windows для узкого
/// перехвата **только Discord UDP Voice (`19294-19344, 50000-50100`) и QUIC (`443`)**.
///
/// Ключевая защита от конфликта с VPN:
/// перед запуском автоматически формирует файл `ipset-vpn-exclude.txt` со
/// всеми IP-адресами серверов подписки пользователя (плюс локальные подсети и
/// подсеть `silentgate-tun`), передавая его в каждый фильтр через
/// `--ipset-exclude=...`. Благодаря этому `WinDivert` никогда не инжектит
/// фейковые пакеты в VPN-туннель (Hysteria2, VLESS Reality, XHTTP, WireGuard).
class ZapretWinwsRunner {
  Process? _process;

  bool get isRunning => _process != null;

  /// Сформировать файл `ipset-vpn-exclude.txt` со всеми известными IP серверов
  /// VPN и приватными диапазонами.
  static Future<File> writeVpnExcludeIpset(
    Directory supportDir,
    Iterable<String> vpnServerIps,
  ) async {
    if (!supportDir.existsSync()) {
      supportDir.createSync(recursive: true);
    }
    final ips = <String>{
      '127.0.0.0/8',
      '10.0.0.0/8',
      '172.16.0.0/12',
      '192.168.0.0/16',
      '100.64.0.0/10',
      '169.254.0.0/16',
    };
    for (final raw in vpnServerIps) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      // Принимаем IPv4/IPv6 адреса или CIDR
      final addrPart = trimmed.contains('/') ? trimmed.split('/').first : trimmed;
      if (InternetAddress.tryParse(addrPart) != null) {
        ips.add(trimmed);
      }
    }
    final file = File('${supportDir.path}${Platform.pathSeparator}ipset-vpn-exclude.txt');
    await file.writeAsString('${ips.join('\n')}\n', flush: true);
    return file;
  }

  /// Построить аргументы запуска `winws.exe` для узкого UDP-режима
  /// (Discord Voice `19294-19344, 50000-50100` + QUIC `443`) с обязательным
  /// исключением всех IP серверов VPN (`--ipset-exclude`).
  static List<String> buildArgs({
    required String excludeIpsetPath,
    String? fakeQuicBinPath,
    String? fakeDiscordBinPath,
  }) {
    final args = <String>[
      '--wf-udp=443,19294-19344,50000-50100',
      // Профиль 1: Discord Voice UDP
      '--filter-udp=19294-19344,50000-50100',
      '--filter-l7=discord,stun',
      '--ipset-exclude=$excludeIpsetPath',
      '--dpi-desync=fake',
      '--dpi-desync-repeats=6',
      if (fakeDiscordBinPath != null && fakeDiscordBinPath.isNotEmpty)
        '--dpi-desync-fake-discord=$fakeDiscordBinPath',
      if (fakeDiscordBinPath != null && fakeDiscordBinPath.isNotEmpty)
        '--dpi-desync-fake-stun=$fakeDiscordBinPath',
      '--new',
      // Профиль 2: QUIC Initial (UDP 443)
      '--filter-udp=443',
      '--ipset-exclude=$excludeIpsetPath',
      '--dpi-desync=fake',
      '--dpi-desync-repeats=6',
      if (fakeQuicBinPath != null && fakeQuicBinPath.isNotEmpty)
        '--dpi-desync-fake-quic=$fakeQuicBinPath',
    ];
    return args;
  }

  /// Найти исполняемый файл `winws.exe` в каталоге бинарников приложения.
  static Future<File?> locateWinwsBinary() async {
    if (!Platform.isWindows) return null;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final supportDir = (await AppPaths.supportDir()).path;
      final candidates = <String>[
        '$exeDir${Platform.pathSeparator}bin${Platform.pathSeparator}zapret${Platform.pathSeparator}winws.exe',
        '$exeDir${Platform.pathSeparator}bin${Platform.pathSeparator}winws.exe',
        '$supportDir${Platform.pathSeparator}bin${Platform.pathSeparator}zapret${Platform.pathSeparator}winws.exe',
      ];
      for (final p in candidates) {
        final f = File(p);
        if (f.existsSync()) return f;
      }
    } catch (_) {}
    return null;
  }

  /// Запустить `winws.exe` в узком режиме Discord UDP + QUIC с исключением VPN IP.
  Future<bool> start({required Iterable<String> vpnServerIps}) async {
    if (!Platform.isWindows) return false;
    await stop();
    final exe = await locateWinwsBinary();
    DpiRuntimeRegistry.winwsBinaryPath = exe?.path;
    if (exe == null) {
      DpiRuntimeRegistry.winwsRunning = false;
      AppLog.w(
        'Zapret winws.exe не найден в bin/zapret/winws.exe — '
        'используется встроенный TLS-фрагментатор SilentGate без WinDivert',
      );
      return false;
    }

    try {
      final supportPath = (await AppPaths.supportDir()).path;
      final supportDir = Directory('$supportPath${Platform.pathSeparator}dpi_lists');
      final excludeFile = await writeVpnExcludeIpset(supportDir, vpnServerIps);
      final exeDir = exe.parent.path;
      final quicBin = File('$exeDir${Platform.pathSeparator}quic_initial_www_google_com.bin');
      final discordBin = File('$exeDir${Platform.pathSeparator}tls_clienthello_www_google_com.bin');

      final args = buildArgs(
        excludeIpsetPath: excludeFile.path,
        fakeQuicBinPath: quicBin.existsSync() ? quicBin.path : null,
        fakeDiscordBinPath: discordBin.existsSync() ? discordBin.path : null,
      );

      _process = await Process.start(
        exe.path,
        args,
        workingDirectory: exeDir,
        runInShell: false,
      );
      DpiRuntimeRegistry.winwsRunning = true;
      AppLog.i(
        'Zapret winws.exe запущен (PID ${_process?.pid}, '
        'исключено VPN IP: ${vpnServerIps.length})',
      );
      _process!.exitCode.then((code) {
        if (_process != null) {
          AppLog.i('Zapret winws.exe завершился с кодом $code');
          _process = null;
          DpiRuntimeRegistry.winwsRunning = false;
        }
      });
      return true;
    } catch (e) {
      AppLog.w('Не удалось запустить Zapret winws.exe: $e');
      _process = null;
      DpiRuntimeRegistry.winwsRunning = false;
      return false;
    }
  }

  /// Остановить `winws.exe`.
  Future<void> stop() async {
    final proc = _process;
    _process = null;
    DpiRuntimeRegistry.winwsRunning = false;
    if (proc != null) {
      try {
        proc.kill();
      } catch (_) {}
    }
  }
}
