import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// Разбор НАСТОЯЩИХ настроек владельца: какие пути ведут трафик мимо туннеля.
void main() {
  test('аудит утечек на реальных настройках', () {
    final f = File('build/user_settings.json');
    if (!f.existsSync()) {
      fail('нет build/user_settings.json — положить копию боевых настроек');
    }
    final s = AppSettings.fromJson(
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
    final cfg = SingboxConfigBuilder(
      options: TunOptions.fromSettings(s,
          serverIps: const ['203.0.113.7'], directDnsUpstream: '192.168.1.1'),
    ).buildMap(s.splitTunnel);

    final rules = ((cfg['route'] as Map)['rules'] as List)
        .cast<Map<String, dynamic>>();
    final buf = StringBuffer();
    buf.writeln('final (куда идёт всё неописанное): ${(cfg['route'] as Map)['final']}');
    buf.writeln('правил всего: ${rules.length}');
    for (var i = 0; i < rules.length; i++) {
      final r = rules[i];
      final dest = r['action'] == 'reject'
          ? 'БЛОК'
          : (r['outbound'] ?? r['action'] ?? '?');
      final what = r.entries
          .where((e) => !['action', 'outbound'].contains(e.key))
          .map((e) => '${e.key}=${_short(e.value)}')
          .join(' ');
      buf.writeln('  [$i] -> $dest   $what');
    }
    final dns = ((cfg['dns'] as Map)['rules'] as List).cast<Map>();
    buf.writeln('DNS final: ${(cfg['dns'] as Map)['final']}');
    for (final r in dns) {
      buf.writeln('  DNS -> ${r['server'] ?? r['action']}   '
          '${r.entries.where((e) => !['server', 'action'].contains(e.key)).map((e) => '${e.key}=${_short(e.value)}').join(' ')}');
    }
    File('build/leak_audit.txt').writeAsStringSync(buf.toString());
    // ignore: avoid_print
    print(buf.toString());
  }, skip: !File('build/user_settings.json').existsSync());

  _leakGuards();
}

String _short(Object? v) {
  final s = '$v';
  return s.length > 70 ? '${s.substring(0, 70)}…' : s;
}

/// Утечка, о которой сообщил владелец: часть трафика к сайту, помеченному
/// «Туннель», уходит мимо VPN.
///
/// Причина не в правилах, а в том, что правило по САЙТУ матчится по имени, а
/// имя берётся из сниффинга. HTTP/3 (QUIC) имени не оставляет, правило не
/// срабатывает, и в режиме «только отмеченные» соединение уходит по базовому
/// маршруту — НАПРЯМУЮ, под реальным IP.
void _leakGuards() {
  List<Map<String, dynamic>> rules(Map<String, dynamic> c) =>
      ((c['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

  bool quicBlocked(Map<String, dynamic> c) => rules(c).any((r) =>
      r['network'] == 'udp' &&
      (r['port'] as List?)?.contains(443) == true &&
      r['action'] == 'reject');

  Map<String, dynamic> build(SplitTunnelConfig split) => SingboxConfigBuilder(
        options: const TunOptions(serverIps: ['203.0.113.1']),
      ).buildMap(split);

  group('Утечка домена мимо туннеля через QUIC', () {
    test('правило по сайту само включает запрет QUIC', () {
      final cfg = build(const SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [SiteRule('example.com', action: AppAction.tunnel)],
      ));
      expect(quicBlocked(cfg), isTrue,
          reason: 'иначе HTTP/3 обходит доменное правило и утекает напрямую');
    });

    test('правила только по приложениям QUIC не трогают', () {
      final cfg = build(const SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        apps: [AppRule('chrome.exe', byName: true, action: AppAction.tunnel)],
      ));
      expect(quicBlocked(cfg), isFalse,
          reason: 'процесс матчится независимо от протокола — глушить незачем');
    });

    test('в режиме «всё через VPN» правил нет и глушить нечего', () {
      final cfg = build(const SplitTunnelConfig(
        mode: SplitMode.all,
        sites: [SiteRule('example.com', action: AppAction.tunnel)],
      ));
      expect(quicBlocked(cfg), isFalse);
    });

    test('запрет QUIC стоит НИЖЕ правила с IP сервера', () {
      // У hysteria2 транспорт — тот же QUIC на 443. Если запрет окажется выше,
      // подключение к самому серверу будет зарезано этим же правилом.
      final r = rules(build(const SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [SiteRule('example.com', action: AppAction.tunnel)],
      )));
      final quic = r.indexWhere((x) =>
          x['network'] == 'udp' && (x['port'] as List?)?.contains(443) == true);
      final server = r.indexWhere((x) =>
          (x['ip_cidr'] as List?)?.any((c) => '$c'.startsWith('203.0.113.1')) ==
          true);
      expect(server, lessThan(quic));
    });
  });
}
