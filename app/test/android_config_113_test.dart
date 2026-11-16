import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// Ядро на Android — libbox 1.14.3, собранный нами; на Windows — официальная
/// сборка sing-box 1.14.3 (до 1.15.0 была 1.11.15, до 1.15.2 — 1.13.14).
/// Версия одна, но сборки
/// РАЗНЫЕ и ведут себя по-разному: наша на устаревшем поле только
/// предупреждает, официальная отвергает конфиг целиком (так прятался старый
/// формат DNS-серверов). Поэтому проверяем обеими.
///
/// `sing-box check` нашей сборки лежит в C:\dev\android\out.
void main() {
  const split = SplitTunnelConfig(
    mode: SplitMode.exceptSelected,
    sites: [
      SiteRule('ads.example', action: AppAction.block),
      SiteRule('direct.example'),
      SiteRule('tunnel.example', action: AppAction.tunnel),
    ],
    apps: [AppRule('com.example.blocked', action: AppAction.block)],
  );

  /// Конфиг ровно такой, какой строит `AndroidEngine`: платформенный туннель,
  /// заглушка, запрет QUIC и шифрованного DNS, проба через живой туннель.
  String androidJson() => SingboxConfigBuilder(
        xraySocksPort: 10808,
        probePort: 10811,
        options: const TunOptions(
          platformTun: true,
          clashApiPort: 19090,
          clashApiSecret: 'test-secret',
          blockQuic: true,
          blockEncryptedDns: true,
          serverIps: ['203.0.113.5'],
          directDnsUpstream: '192.168.1.1',
          logOutput: '/data/data/lol.silentgate/files/singbox.log',
        ),
      ).buildJson(split);

  Future<void> checkWith(String exe, String label) async {
    final f = File('build/emit/android-113.json');
    await f.parent.create(recursive: true);
    await f.writeAsString(androidJson());
    final r = await Process.run(exe, ['check', '-c', f.path]);
    expect(r.exitCode, 0, reason: '$label отверг конфиг:\n${r.stdout}${r.stderr}');
  }

  test('ядро 1.14.3 (Android) принимает конфиг', () async {
    const exe = r'C:\dev\android\out\sing-box-1.14.3.exe';
    if (!File(exe).existsSync()) {
      fail('нет $exe — проверить нечем, а расхождение версий уже ломало сборку');
    }
    await checkWith(exe, 'sing-box 1.14.3');
  });

  test('официальное ядро Windows принимает тот же набор полей', () async {
    final exe = File('../engine/windows/bin/sing-box.exe');
    if (!exe.existsSync()) return;
    await checkWith(exe.path, 'официальный sing-box (Windows)');
  });
}
