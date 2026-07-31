import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/ipv6_support.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// Туннель не должен обещать IPv6, которого нет наружу: приложения поверят,
/// пойдут по IPv6 и упрутся в «unreachable network» на каждом двустековом
/// сайте. Снаружи это «всё зависает, хотя блока нет».
void main() {
  group('Что считается настоящим IPv6', () {
    test('глобальный unicast — да', () {
      for (final ip in [
        '2a00:1450:4010:c05::8a', // Google
        '2606:4700::6810:85e5', // Cloudflare
        '2620:1ec:29:1::10', // Microsoft
        '3fff:ffff::1', // верхняя граница 2000::/3
      ]) {
        expect(Ipv6Support.isGlobalIpv6(ip), isTrue, reason: ip);
      }
    });

    test('адреса, по которым никуда не уехать, — нет', () {
      for (final ip in [
        'fe80::1', // link-local
        'fd00::1', // ULA
        'fdfe:dcba:9876::1', // НАШ туннель — иначе он подтвердил бы сам себя
        '::1', // loopback
        'ff02::1', // multicast
        '2001:0:4137:9e76::1', // Teredo — адрес есть, связи нет
        '2002:c0a8:101::1', // 6to4 — то же самое
        '1999::1', // ниже 2000::/3
        '4000::1', // выше 3fff
        '192.168.1.1', // вообще не IPv6
      ]) {
        expect(Ipv6Support.isGlobalIpv6(ip), isFalse, reason: ip);
      }
    });
  });

  group('Конфиг туннеля', () {
    Map<String, dynamic> build({required bool ipv6Available}) {
      const settings = AppSettings();
      return SingboxConfigBuilder(
        options: TunOptions.fromSettings(settings,
            serverIps: const ['203.0.113.1'], ipv6Available: ipv6Available),
      ).buildMap(const SplitTunnelConfig());
    }

    List<Map<String, dynamic>> rules(Map<String, dynamic> cfg) =>
        ((cfg['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

    bool ipv6Rejected(Map<String, dynamic> cfg) => rules(cfg).any(
        (r) => r['ip_version'] == 6 && r['action'] == 'reject');

    test('IPv6 наружу есть — трафик по нему идёт как обычно', () {
      expect(ipv6Rejected(build(ipv6Available: true)), isFalse);
    });

    // ⚠️ Тонкость, на которой легко ошибиться: туннель ВСЁ РАВНО объявляет
    // IPv6-адрес и захватывает такой трафик. Не объявить его — значит выпустить
    // IPv6 мимо VPN под реальным адресом. Отказ приходит уже ВНУТРИ туннеля, и
    // именно поэтому он мгновенный: клиент сразу переходит на IPv4, а не ждёт
    // таймаута «unreachable network» на каждом двустековом сайте.
    test('IPv6 наружу нет — он захватывается и мгновенно отвергается', () {
      final cfg = build(ipv6Available: false);
      expect(ipv6Rejected(cfg), isTrue);

      final tun = (cfg['inbounds'] as List)
          .cast<Map>()
          .firstWhere((i) => i['type'] == 'tun');
      final addrs = (tun['address'] as List).cast<String>();
      expect(addrs.any((a) => a.contains(':')), isTrue,
          reason: 'адрес нужен, чтобы IPv6 не утёк мимо туннеля');
    });

    test('отказ IPv6 стоит НИЖЕ правила с адресом сервера', () {
      // Сервер может быть доступен по IPv6 — отказ выше отрезал бы само
      // подключение.
      final r = rules(build(ipv6Available: false));
      final reject = r.indexWhere(
          (x) => x['ip_version'] == 6 && x['action'] == 'reject');
      final server = r.indexWhere((x) =>
          (x['ip_cidr'] as List?)?.any((c) => '$c'.startsWith('203.0.113.1')) ==
          true);
      expect(server, lessThan(reject));
    });
  });
}
