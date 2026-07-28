// Регрессы на баги, найденные adversarial-ревью батча (16 подтверждённых).
// Каждый тест воспроизводит конкретный сценарий из аудита.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/net/site_favicon.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/xray/override_normalizer.dart';
import 'package:silentgate/core/xray/panel_direct_reroute.dart';
import 'package:silentgate/data/settings_storage.dart';

void main() {
  group('Реврайт direct→VPN: закрытые утечки (#1/#2)', () {
    Map decode(String s) => jsonDecode(s) as Map;
    List<Map> rulesOf(String s) =>
        ((decode(s)['routing'] as Map)['rules'] as List).cast<Map>();

    test('#1 смешанное правило ip:[geoip:ru, geoip:private] РАЗБИВАЕТСЯ', () {
      const panel = '''{
        "outbounds":[{"protocol":"vless","tag":"srv1"}],
        "routing":{
          "balancers":[{"tag":"bal","selector":["srv"]}],
          "rules":[
            {"type":"field","ip":["geoip:ru","geoip:private"],"outboundTag":"direct"},
            {"type":"field","network":"tcp,udp","balancerTag":"bal"}
          ]
        }
      }''';
      final rs = rulesOf(rerouteDirectThroughVpn(panel));
      // Приватная часть осталась direct.
      expect(
          rs.any((r) =>
              (r['ip'] as List?)?.contains('geoip:private') == true &&
              (r['ip'] as List).contains('geoip:ru') == false &&
              r['outboundTag'] == 'direct'),
          isTrue,
          reason: 'geoip:private должен остаться direct отдельным правилом');
      // Публичная часть (geoip:ru) уведена в VPN (balancerTag, без direct).
      expect(
          rs.any((r) =>
              (r['ip'] as List?)?.contains('geoip:ru') == true &&
              (r['ip'] as List).contains('geoip:private') == false &&
              r['balancerTag'] == 'bal' &&
              r['outboundTag'] == null),
          isTrue,
          reason: 'geoip:ru должен уйти на балансер (VPN)');
    });

    test('#2 непокрытый трафик уходит в VPN (catch-all), а не на freedom-дефолт',
        () {
      // Override, где ПЕРВЫЙ outbound — freedom (дефолтный маршрут Xray).
      const override = '''{
        "outbounds":[
          {"protocol":"freedom","tag":"direct"},
          {"protocol":"vless","tag":"srv1"}
        ],
        "routing":{"rules":[
          {"type":"field","domain":["example.com"],"outboundTag":"srv1"}
        ]}
      }''';
      final rs = rulesOf(rerouteDirectThroughVpn(override));
      // Последним правилом — безусловный увод всего в прокси (srv1).
      final last = rs.last;
      expect(last['outboundTag'], 'srv1');
      expect(last['ip'], isNull);
      expect(last['domain'], isNull);
      // И сверху — страховка LAN → direct. Проверяем СМЫСЛ, а не написание:
      // с отказом от гео-файлов `geoip:private` заменён явным списком подсетей.
      expect(rs.first['outboundTag'], 'direct');
      expect((rs.first['ip'] as List), contains('192.168.0.0/16'));
      expect((rs.first['ip'] as List), contains('10.0.0.0/8'));
    });

    test('домен-правило direct уводится в VPN, приватный домен — остаётся', () {
      const cfg = '''{
        "outbounds":[{"protocol":"vless","tag":"srv1"},{"protocol":"freedom","tag":"direct"}],
        "routing":{"rules":[
          {"type":"field","domain":["geosite:category-ru"],"outboundTag":"direct"},
          {"type":"field","domain":["geosite:private"],"outboundTag":"direct"}
        ]}
      }''';
      final rs = rulesOf(rerouteDirectThroughVpn(cfg));
      expect(
          rs.any((r) =>
              (r['domain'] as List?)?.contains('geosite:category-ru') == true &&
              r['outboundTag'] == 'srv1'),
          isTrue);
      expect(
          rs.any((r) =>
              (r['domain'] as List?)?.contains('geosite:private') == true &&
              r['outboundTag'] == 'direct'),
          isTrue);
    });

    test('идемпотентность: повторный проход не плодит страховку и catch-all', () {
      const panel = '''{
        "outbounds":[{"protocol":"vless","tag":"srv1"},{"protocol":"freedom","tag":"direct"}],
        "routing":{"balancers":[{"tag":"bal"}],"rules":[
          {"type":"field","domain":["geosite:category-ru"],"outboundTag":"direct"}
        ]}
      }''';
      final once = rerouteDirectThroughVpn(panel);
      final twice = rerouteDirectThroughVpn(once);
      final r1 = rulesOf(once), r2 = rulesOf(twice);
      expect(r2.length, r1.length, reason: 'повтор не должен добавлять правила');
      // Ровно одна страховка private→direct и один catch-all на балансер.
      expect(
          r2
              .where((r) =>
                  r['outboundTag'] == 'direct' &&
                  (r['ip'] as List?)?.contains('192.168.0.0/16') == true)
              .length,
          1,
          reason: 'страховка LAN должна остаться ровно одна');
      expect(r2.where((r) => r['balancerTag'] == 'bal' && r['ip'] == null && r['domain'] == null).length, 1);
    });
  });

  group('ensureXrayStats: коллизия порта и StatsService (#4)', () {
    test('порт api занят ЧУЖИМ inbound → конфиг не трогаем (не роняем старт)', () {
      const cfg = '''{
        "inbounds":[{"tag":"other","protocol":"http","port":10085}],
        "outbounds":[{"protocol":"vless","tag":"proxy"}]
      }''';
      final out = ensureXrayStats(cfg, apiPort: 10085);
      final ins = ((jsonDecode(out) as Map)['inbounds'] as List).cast<Map>();
      // Второго inbound на 10085 не появилось.
      expect(ins.where((i) => '${i['port']}' == '10085').length, 1);
      expect(ins.any((i) => i['tag'] == 'api'), isFalse);
    });

    test('существующий api без StatsService — сервис дописывается', () {
      const cfg = '''{
        "inbounds":[{"tag":"api","protocol":"dokodemo-door","port":10085}],
        "api":{"tag":"api","services":["HandlerService"]},
        "outbounds":[{"protocol":"vless","tag":"proxy"}]
      }''';
      final out = jsonDecode(ensureXrayStats(cfg, apiPort: 10085)) as Map;
      final services = ((out['api'] as Map)['services'] as List);
      expect(services, containsAll(['HandlerService', 'StatsService']));
    });

    test('идемпотентность: повтор не дублирует inbound/rule', () {
      const cfg = '''{
        "inbounds":[{"tag":"socks","protocol":"socks","port":10808}],
        "outbounds":[{"protocol":"vless","tag":"proxy"}]
      }''';
      final once = ensureXrayStats(cfg, apiPort: 10085);
      final twice = ensureXrayStats(once, apiPort: 10085);
      final o = jsonDecode(twice) as Map;
      final ins = (o['inbounds'] as List).cast<Map>();
      expect(ins.where((i) => i['tag'] == 'api').length, 1);
      final rs = ((o['routing'] as Map)['rules'] as List).cast<Map>();
      expect(rs.where((r) => r['outboundTag'] == 'api').length, 1);
    });
  });

  group('sing-box: БЛОК выше bypassLan/excludeCidr (#3)', () {
    List<Map> rules(Map<String, dynamic> cfg) =>
        ((cfg['route'] as Map)['rules'] as List).cast<Map>();

    test('reject-правило сайта стоит РАНЬШЕ excludeCidr и bypassLan', () {
      final cfg = const SingboxConfigBuilder(
        options: TunOptions(bypassLan: true, excludeCidrs: ['104.16.0.0/13']),
      ).buildMap(const SplitTunnelConfig(
        // Не `all`: там пользовательских правил в конфиге нет по определению
        // («исключений нет»), и проверять порядок было бы не на чем. База у
        // exceptSelected та же — proxy.
        mode: SplitMode.exceptSelected,
        sites: [SiteRule('trackers.example', action: AppAction.block)],
      ));
      final rs = rules(cfg);
      final block = rs.indexWhere((r) =>
          r['action'] == 'reject' &&
          (r['domain_suffix'] as List?)?.contains('trackers.example') == true);
      final excl = rs.indexWhere((r) =>
          (r['ip_cidr'] as List?)?.contains('104.16.0.0/13') == true);
      final lan = rs.indexWhere((r) => r['ip_is_private'] == true);
      expect(block, greaterThanOrEqualTo(0));
      expect(excl, greaterThan(block), reason: 'блок должен идти раньше excludeCidr');
      expect(lan, greaterThan(block), reason: 'блок должен идти раньше bypassLan');
    });
  });

  group('rootDomain: 3-буквенный gTLD не считается ccTLD (#13)', () {
    test('X.go.com сводится к go.com (com — gTLD, не ccTLD)', () {
      expect(SiteFaviconService.rootDomain('mail.go.com'), 'go.com');
    });
    test('настоящий two-level (co.uk) сохраняется', () {
      expect(SiteFaviconService.rootDomain('www.shop.example.co.uk'),
          'example.co.uk');
    });
  });

  group('Настройки: битый файл не сбрасывает всё молча', () {
    test('BOM в начале файла НЕ ломает разбор (главный триггер)', () {
      // PowerShell `>`, Out-File, Set-Content -Encoding utf8 пишут UTF-8 с BOM.
      // Раньше это роняло jsonDecode → все настройки уезжали в дефолт.
      const json = '{"captureMode":"tun","killSwitch":true,"tunMtu":1400}';
      final s = SettingsStorage.parseContent('﻿$json');
      expect(s, isNotNull);
      expect(s!.captureMode, CaptureMode.tun);
      expect(s.killSwitch, isTrue);
      expect(s.tunMtu, 1400);
    });

    test('пустой файл — это не порча, а «настроек ещё нет» → дефолты', () {
      expect(SettingsStorage.parseContent('')?.captureMode,
          CaptureMode.systemProxy);
      expect(SettingsStorage.parseContent('   \n ')?.killSwitch, isFalse);
    });

    test('битый JSON и неверный ТИП значения дают null (а не тихий дефолт)', () {
      expect(SettingsStorage.parseContent('{не json'), isNull);
      // Строка вместо числа — реальный случай при правке файла скриптом.
      expect(SettingsStorage.parseContent('{"tunMtu":"1400"}'), isNull);
    });

    test('нормальный файл читается как прежде', () {
      final s = SettingsStorage.parseContent('{"captureMode":"tun"}');
      expect(s?.captureMode, CaptureMode.tun);
    });
  });

  group('Автоподбор TUN: отмена ≠ неудача (#16)', () {
    final t0 = DateTime(2026, 1, 1, 12);
    VpnStatus tuning() => const VpnStatus(VpnConnectionState.connecting,
        message: 'system, MTU 1500', phase: VpnPhase.tunAutotune);

    test('отмена (disconnected) в ходе подбора — без тоста-итога', () {
      var s = const TunAutotuneTracking().next(tuning(), t0);
      s = s.next(const VpnStatus(VpnConnectionState.disconnected), t0);
      expect(s.running, isFalse);
      expect(s.finishedAt, isNull,
          reason: 'отмена не должна показывать «не удалось»');
    });

    test('error в ходе подбора — это неудача (тост есть)', () {
      var s = const TunAutotuneTracking().next(tuning(), t0);
      s = s.next(const VpnStatus(VpnConnectionState.error), t0);
      expect(s.finishedAt, isNotNull);
      expect(s.succeeded, isFalse);
    });
  });
}
