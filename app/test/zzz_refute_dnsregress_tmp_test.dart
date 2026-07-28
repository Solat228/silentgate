import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// Проверка находки regress-dns на РЕАЛЬНЫХ настройках пользователя.
/// Ничего не запускает — только строит конфиг и выгружает его на диск.
void main() {
  test('post-fix конфиг из реального silentgate_settings.json', () {
    final raw = File(
            r'C:\Users\User\AppData\Roaming\SilentGate\silentgate_settings.json')
        .readAsStringSync();
    final s = AppSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>);
    expect(s.noRealIp, isFalse, reason: 'у пользователя noRealIp=false');
    expect(s.dnsMode, DnsMode.vpn);
    expect(s.splitTunnel.mode, SplitMode.onlySelected);

    final json = SingboxConfigBuilder(
      options: TunOptions.fromSettings(s, serverIps: const ['77.110.126.51']),
    ).buildJson(s.splitTunnel);

    final out = Directory('build/split-configs')..createSync(recursive: true);
    File('${out.path}/zz_refute_dns_real.json').writeAsStringSync(json);

    final cfg = jsonDecode(json) as Map<String, dynamic>;
    final dns = cfg['dns'] as Map<String, dynamic>;
    // ignore: avoid_print
    print('DNS SECTION:\n${const JsonEncoder.withIndent('  ').convert(dns)}');

    final dnsRules = (dns['rules'] as List).cast<Map<String, dynamic>>();
    // Куда попадает домен по зеркальным правилам (первое совпадение).
    String resolve(String host) {
      for (final r in dnsRules) {
        final suf = (r['domain_suffix'] as List?)?.cast<String>();
        if (suf == null) continue;
        final hit = suf.any((d) => host == d || host.endsWith('.$d'));
        if (hit) return (r['action'] as String?) ?? r['server'] as String;
      }
      return 'FINAL:${dns['final']}';
    }

    for (final h in [
      'youtube.com',
      'www.youtube.com',
      'rr3---sn-abc.googlevideo.com',
      'youtubei.googleapis.com',
      'i.ytimg.com',
      'example.com',
      'example.org',
      'site.com',
      'example.org',
    ]) {
      // ignore: avoid_print
      print('DNS  $h -> ${resolve(h)}');
    }

    // Маршрут (route.rules) для тех же имён — для сверки с DNS.
    final routeRules =
        ((cfg['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();
    String route(String host, String? proc) {
      for (final r in routeRules) {
        final suf = (r['domain_suffix'] as List?)?.cast<String>();
        if (suf != null && suf.any((d) => host == d || host.endsWith('.$d'))) {
          return (r['outbound'] as String?) ?? r['action'] as String;
        }
        final pn = (r['process_name'] as List?)?.cast<String>();
        if (proc != null && pn != null && pn.contains(proc)) {
          return (r['outbound'] as String?) ?? r['action'] as String;
        }
        final pp = (r['process_path_regex'] as List?)?.cast<String>();
        if (proc != null &&
            pp != null &&
            pp.any((re) => RegExp(re).hasMatch(
                r'C:\Program Files\Google\Chrome\Application\' '$proc'))) {
          return (r['outbound'] as String?) ?? r['action'] as String;
        }
      }
      return 'FINAL:${(cfg['route'] as Map)['final']}';
    }

    for (final h in [
      'youtube.com',
      'rr3---sn-abc.googlevideo.com',
      'i.ytimg.com',
    ]) {
      // ignore: avoid_print
      print('ROUTE(chrome.exe) $h -> ${route(h, 'chrome.exe')}');
    }
  });
}
