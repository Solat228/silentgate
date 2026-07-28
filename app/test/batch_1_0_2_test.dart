import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/rotating_log.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/singbox/singbox_outbound_factory.dart';
import 'package:silentgate/core/singbox/singbox_proxy_config_builder.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/core/update/app_update_defaults.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/engine/windows/singbox_stats.dart';
import 'package:silentgate/engine/windows/xray_stats.dart';

void main() {
  List<Map<String, dynamic>> rules(Map<String, dynamic> cfg) =>
      ((cfg['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> dnsRules(Map<String, dynamic> cfg) =>
      (((cfg['dns'] as Map?)?['rules'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  // Набор правил, одинаковый для всех режимов, — чтобы разница в конфиге
  // объяснялась ТОЛЬКО режимом.
  const split = SplitTunnelConfig(
    apps: [
      AppRule(r'C:\direct.exe', byName: true, action: AppAction.direct),
      AppRule(r'C:\tunnel.exe', byName: true, action: AppAction.tunnel),
      AppRule(r'C:\blocked.exe', byName: true, action: AppAction.block),
    ],
    sites: [
      SiteRule('direct.example', action: AppAction.direct),
      SiteRule('tunnel.example', action: AppAction.tunnel),
      SiteRule('blocked.example', action: AppAction.block),
    ],
  );

  SplitTunnelConfig withMode(SplitMode m) => SplitTunnelConfig(
        mode: m,
        apps: split.apps,
        sites: split.sites,
      );

  Map<String, dynamic> build(SplitMode mode, {bool noRealIp = false}) =>
      SingboxConfigBuilder(
        options: TunOptions(noRealIp: noRealIp, serverIps: const ['203.0.113.9']),
      ).buildMap(withMode(mode));

  // ──────────────────────────────────────────────────────────────────────────
  // «Всё через VPN»: интерфейс прячет списки и обещает, что весь трафик идёт в
  // туннель, — а правила при этом попадали в конфиг и действовали. Сохранённое
  // «Прямо» прорезало дыру, о которой пользователь не мог узнать: правил не
  // видно. После 1.0.1, где «Прямо» снова значит «прямо», цена этого выросла.
  group('SplitMode.all: пользовательские правила НЕ применяются', () {
    test('в маршрутах нет ни одного правила пользователя', () {
      final r = rules(build(SplitMode.all));

      final userDomains = r.where((x) => x.containsKey('domain_suffix'));
      expect(userDomains, isEmpty,
          reason: 'доменных правил в режиме «всё через VPN» быть не должно');

      // process_name остаётся ровно один — инфраструктурная защита от петли.
      final byProcess =
          r.where((x) => x.containsKey('process_name')).toList();
      expect(byProcess, hasLength(1));
      expect(
        (byProcess.single['process_name'] as List).cast<String>(),
        containsAll(<String>['xray.exe', 'sing-box.exe', 'silentgate.exe']),
      );

      expect(r.where((x) => x['action'] == 'reject'), isEmpty,
          reason: 'блок-правила тоже пользовательские');
    });

    test('DNS-зеркало пустое: иначе домен «Прямо» резолвился бы локально', () {
      final d = dnsRules(build(SplitMode.all));
      expect(d.where((x) => x.containsKey('domain_suffix')), isEmpty);
      // Правило-заглушка про direct-outbound остаётся: его убирать не просили.
      expect(d, isNotEmpty);
    });

    test('инфраструктура на месте: IP сервера и петля по-прежнему direct', () {
      final r = rules(build(SplitMode.all));
      expect(
        r.any((x) =>
            (x['ip_cidr'] as List?)?.any((c) => '$c'.startsWith('203.0.113.9')) ==
                true &&
            x['outbound'] == 'direct'),
        isTrue,
      );
      expect((build(SplitMode.all)['route'] as Map)['final'], 'proxy');
    });

    test('noRealIp ничего не возвращает: правил нет вообще', () {
      final r = rules(build(SplitMode.all, noRealIp: true));
      expect(r.where((x) => x.containsKey('domain_suffix')), isEmpty);
      expect(r.where((x) => x.containsKey('process_path_regex')), isEmpty);
    });

    test('в двух других режимах правила НА МЕСТЕ (страж от перегиба)', () {
      for (final mode in [SplitMode.onlySelected, SplitMode.exceptSelected]) {
        final r = rules(build(mode));
        expect(r.any((x) => (x['domain_suffix'] as List?)?.contains('direct.example') == true),
            isTrue,
            reason: 'режим $mode обязан применять правила сайтов');
        expect(r.any((x) => (x['process_name'] as List?)?.contains('tunnel.exe') == true),
            isTrue,
            reason: 'режим $mode обязан применять правила приложений');
        expect(r.any((x) => x['action'] == 'reject'), isTrue,
            reason: 'режим $mode обязан применять блок');
        expect(dnsRules(build(mode)).any((x) => x.containsKey('domain_suffix')),
            isTrue,
            reason: 'режим $mode обязан зеркалить домены в DNS');
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // У пользователя singbox.log дорос до 758 МБ, а «Написать в поддержку» читало
  // его целиком в память. Обе беды лечит один класс — теперь общий для TUN-ядра
  // и прокси-ядра.
  group('RotatingLog', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sg_rotlog_');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    String p(String name) => '${tmp.path}${Platform.pathSeparator}$name';

    test('пишет строки и отдаёт их хвостом', () async {
      final log = RotatingLog(p('a.log'));
      await log.open();
      for (var i = 1; i <= 5; i++) {
        await log.write('строка $i');
      }
      await log.close();

      final tail = await RotatingLog.tail(p('a.log'), lines: 3);
      expect(tail.split('\n'), ['строка 3', 'строка 4', 'строка 5']);
    });

    test('перерастание порога начинает файл заново, запись продолжается',
        () async {
      final log = RotatingLog(p('b.log'), maxBytes: 200);
      await log.open();
      for (var i = 0; i < 60; i++) {
        await log.write('x' * 20); // ~1260 байт суммарно при пороге 200
      }
      await log.close();

      final size = await File(p('b.log')).length();
      expect(size, lessThan(600),
          reason: 'файл обязан усекаться на лету, а не расти всю сессию');
      final tail = await RotatingLog.tail(p('b.log'), lines: 1);
      expect(tail.trim(), isNotEmpty, reason: 'после ротации запись не теряется');
    });

    test('слишком большой файл усекается уже при открытии', () async {
      await File(p('c.log')).writeAsString('старьё\n' * 500);
      final log = RotatingLog(p('c.log'), maxBytes: 100);
      await log.open();
      await log.write('свежая строка');
      await log.close();

      final text = await File(p('c.log')).readAsString();
      expect(text.contains('старьё'), isFalse);
      expect(text.contains('свежая строка'), isTrue);
    });

    test('хвост читается С КОНЦА и не падает на битой UTF-8-границе', () async {
      // Кириллица в UTF-8 двухбайтовая: срез по tailBytes попадёт в середину.
      final f = File(p('d.log'));
      await f.writeAsString(List.generate(200, (i) => 'привет мир $i').join('\n'));
      final tail = await RotatingLog.tail(p('d.log'), lines: 2, tailBytes: 101);
      expect(tail, isNotEmpty);
      expect(() => tail.length, returnsNormally);
    });

    test('несуществующий файл — пустая строка, а не исключение', () async {
      expect(await RotatingLog.tail(p('нет.log')), '');
    });

    test('без open() запись молча игнорируется (лог не роняет туннель)',
        () async {
      final log = RotatingLog(p('e.log'));
      await log.write('в никуда');
      expect(await File(p('e.log')).exists(), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Прокси-ядру с доменным именем приходится резолвить его в рантайме. В
  // TUN-режиме этот запрос уходит от svchost.exe, попадает под hijack-dns (оно
  // выше защиты от петли) и по dns.final возвращается в ЭТО ЖЕ ядро, которое
  // ответа и ждёт. С подставленным IP резолвить нечего — петля невозможна.
  group('Подстановка отрезолвленного IP в sing-box-outbound', () {
    VpnServer hy2({String? sni, String address = 'node.example.com'}) =>
        VpnServer(
          remark: 'узел',
          rawLink: 'hysteria2://pass@$address:443',
          protocol: 'hysteria2',
          address: address,
          port: 443,
          id: 'pass',
          sni: sni,
          alpn: 'h3',
          network: 'quic',
          security: 'tls',
        );

    test('server становится IP, а SNI остаётся доменом', () {
      final out = SingboxOutboundFactory.build(hy2(), resolvedIp: '198.51.100.7');
      expect(out['server'], '198.51.100.7');
      expect((out['tls'] as Map)['server_name'], 'node.example.com',
          reason: 'без домена в server_name сертификат не проверится, '
              'а ядро отвергнет конфиг целиком');
    });

    test('явный SNI сильнее подстановки', () {
      final out = SingboxOutboundFactory.build(hy2(sni: 'sni.example.net'),
          resolvedIp: '198.51.100.7');
      expect((out['tls'] as Map)['server_name'], 'sni.example.net');
    });

    test('без resolvedIp конфиг прежний бит-в-бит', () {
      expect(SingboxOutboundFactory.build(hy2()),
          SingboxOutboundFactory.build(hy2(), resolvedIp: null));
      expect(SingboxOutboundFactory.build(hy2())['server'], 'node.example.com');
    });

    test('адрес уже IP: server_name из него НЕ делаем', () {
      final out = SingboxOutboundFactory.build(hy2(address: '198.51.100.7'),
          resolvedIp: '198.51.100.7');
      expect(out['server'], '198.51.100.7');
      expect((out['tls'] as Map).containsKey('server_name'), isFalse,
          reason: 'IP в SNI — гарантированный отказ проверки сертификата');
    });

    test('порт-хоппинг переживает подстановку', () {
      final s = VpnServer(
        remark: 'хоппинг',
        rawLink: 'hysteria2://pass@hop.example.com:443?mport=1000-2000',
        protocol: 'hysteria2',
        address: 'hop.example.com',
        port: 443,
        id: 'pass',
        security: 'tls',
        hopPorts: '1000-2000',
      );
      final out = SingboxOutboundFactory.build(s, resolvedIp: '198.51.100.8');
      expect(out['server'], '198.51.100.8');
      expect(out['server_ports'], isNotNull);
      expect(out.containsKey('server_port'), isFalse,
          reason: 'sing-box требует ЛИБО server_port, ЛИБО server_ports');
    });

    test('ws-транспорт: Host остаётся доменом', () {
      final s = VpnServer(
        remark: 'ws-узел',
        rawLink: 'vless://uuid@cdn.example.com:443?type=ws',
        protocol: 'vless',
        address: 'cdn.example.com',
        port: 443,
        id: 'uuid',
        network: 'ws',
        security: 'tls',
        path: '/ws',
      );
      final out = SingboxOutboundFactory.build(s, resolvedIp: '198.51.100.9');
      expect(out['server'], '198.51.100.9');
      final headers = ((out['transport'] as Map)['headers'] as Map?);
      expect(headers?['Host'], 'cdn.example.com',
          reason: 'без Host CDN вернёт 404 вместо апгрейда соединения');
    });

    // Дамп для проверки НАСТОЯЩИМ ядром:
    //   engine/windows/bin/sing-box.exe check -c build/split-configs/hy2_*.json
    // Ровно здесь проходит граница «починили» / «сломали»: при IP в `server` и
    // пустом server_name ядро отвергает конфиг целиком, и пользователь увидел
    // бы «Ядро завершилось при запуске» вместо работающего hysteria2.
    test('конфиг прокси-ядра с подставленным IP выгружается для sing-box check',
        () {
      final dir = Directory('build/split-configs')..createSync(recursive: true);
      for (final entry in {
        'hy2_resolved': {'node.example.com': '198.51.100.7'},
        'hy2_plain': <String, String>{},
      }.entries) {
        final json = const SingboxProxyConfigBuilder(apiSecret: 'testsecret')
            .buildJson([hy2()], resolvedIps: entry.value);
        File('${dir.path}/${entry.key}.json').writeAsStringSync(json);
        expect(json, contains('hysteria2'));
      }
      final resolved = jsonDecode(
              File('${dir.path}/hy2_resolved.json').readAsStringSync())
          as Map<String, dynamic>;
      final out = (resolved['outbounds'] as List).first as Map<String, dynamic>;
      expect(out['server'], '198.51.100.7');
      expect((out['tls'] as Map)['server_name'], 'node.example.com');
    });

    test('выбор адреса детерминирован: IPv4 предпочтительнее', () {
      final picked = VpnEngineBase.pickOneIpPerHost({
        'a.example.com': ['2001:db8::1', '198.51.100.10'],
        'b.example.com': ['2001:db8::2'],
      });
      expect(picked['a.example.com'], '198.51.100.10');
      expect(picked['b.example.com'], '2001:db8::2');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Неудачный опрос возвращал НОЛЬ, и движок принимал его за настоящий отсчёт:
  // счётчик «падал», следующая удачная выборка давала фальшивый всплеск
  // скорости, а AppState трактовал падение как перезапуск ядра и удваивал
  // трафик «за сессию». Теперь неудача — это null, и такт пропускается.
  group('Сбой опроса счётчиков — null, а не ноль', () {
    test('Clash API недоступен → null', () async {
      // Порт заведомо закрыт: соединение будет отвергнуто сразу.
      final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = free.port;
      await free.close();

      final stats = SingboxStats(apiPort: port, secret: 'x');
      expect(await stats.query(), isNull);
    });

    test('Clash API ответил не-JSON → null', () async {
      final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      srv.listen((r) {
        r.response
          ..statusCode = 200
          ..write('не json');
        r.response.close();
      });
      addTearDown(() => srv.close(force: true));

      expect(await SingboxStats(apiPort: srv.port).query(), isNull);
    });

    test('Clash API вернул 500 → null', () async {
      final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      srv.listen((r) {
        r.response.statusCode = 500;
        r.response.close();
      });
      addTearDown(() => srv.close(force: true));

      expect(await SingboxStats(apiPort: srv.port).query(), isNull);
    });

    test('исправный ответ по-прежнему разбирается', () async {
      final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      srv.listen((r) {
        r.response
          ..statusCode = 200
          ..write('{"uploadTotal": 111, "downloadTotal": 222}');
        r.response.close();
      });
      addTearDown(() => srv.close(force: true));

      final snap = await SingboxStats(apiPort: srv.port).query();
      expect(snap, isNotNull);
      expect(snap!.uplink, 111);
      expect(snap.downlink, 222);
    });

    test('Xray: ядра нет → null, а не нули', () async {
      final stats = const XrayStats(executable: 'xray-которого-нет.exe');
      expect(await stats.query(), isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Импорт app_update тянул app_log → app_paths → path_provider → flutter →
  // dart:ui, и `dart run tool/emit_*.dart` не запускался вовсе: валидировать
  // конфиги настоящим ядром было нечем.
  group('Адрес обновлений живёт в файле без импортов', () {
    test('AppSettings берёт то же значение, что и AppUpdate', () {
      expect(const AppSettings().appUpdateUrl, kDefaultAppUpdateEndpoint);
      expect(AppUpdate.defaultEndpoint, kDefaultAppUpdateEndpoint);
    });

    test('файл констант не обзавёлся импортами', () async {
      final src =
          await File('lib/core/update/app_update_defaults.dart').readAsString();
      expect(RegExp(r'^\s*import ', multiLine: true).hasMatch(src), isFalse,
          reason: 'любой импорт здесь снова сломает консольные тулы');
    });
  });
}
