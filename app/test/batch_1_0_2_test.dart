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
import 'package:silentgate/core/xray/private_networks.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/core/update/app_update_defaults.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/state/probe_controller.dart';
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

    // ⚠️ Именно так лог и пишется: LineSplitter отдаёт строки чанка синхронно
    // подряд, а onLine зовёт write() без await. Раньше каждая строка пачки
    // запускала СВОЮ ротацию — файл усекался повторно, стирая только что
    // записанное, порядок переворачивался, а прежние IOSink терялись
    // незакрытыми. Терялась ровно та FATAL-строка, ради которой лог заводили.
    test('пачка записей без await: строки не теряются и не переставляются',
        () async {
      final log = RotatingLog(p('burst.log'), maxBytes: 100);
      await log.open();
      final futures = <Future<void>>[];
      for (var i = 0; i < 30; i++) {
        futures.add(log.write('LINE$i'));
      }
      await Future.wait(futures);
      await log.close();

      final lines = (await File(p('burst.log')).readAsString())
          .split('\n')
          .where((l) => l.startsWith('LINE'))
          .toList();
      expect(lines, isNotEmpty);
      // Порядок сохранён: номера строго возрастают.
      final nums = lines.map((l) => int.parse(l.substring(4))).toList();
      expect(nums, orderedEquals(List.of(nums)..sort()));
      // И последняя запись пачки на месте — она и есть самая ценная.
      expect(lines.last, 'LINE29');
    });

    test('close() во время ротации не переоткрывает файл', () async {
      final log = RotatingLog(p('closerace.log'), maxBytes: 50);
      await log.open();
      for (var i = 0; i < 20; i++) {
        log.write('x' * 30); // не ждём — ротация в полёте
      }
      await log.close();
      expect(log.isOpen, isFalse);

      final sizeAfter = await File(p('closerace.log')).length();
      await log.write('ПОСЛЕ CLOSE');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await File(p('closerace.log')).length(), sizeAfter,
          reason: 'после close() в файл не должно попадать ничего');
    });

    test('порог считается в БАЙТАХ: кириллица не проходит мимо лимита',
        () async {
      final log = RotatingLog(p('cyr.log'), maxBytes: 400);
      await log.open();
      for (var i = 0; i < 40; i++) {
        await log.write('строка с кириллицей номер $i');
      }
      await log.close();
      // 40 строк по ~50 байт = ~2000 Б. При счёте по символам порог сработал
      // бы вдвое позже и файл вырос бы соответственно.
      expect(await File(p('cyr.log')).length(), lessThan(900));
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
  // Живой тест в VM: сайт «Туннель» открывался, «Блок» блокировался, а «Прямо»
  // не открывался ВООБЩЕ — `lookup ipinfo.io: i/o timeout` → `name error`.
  // Причина: dns-local = address:'local' = системный резолвер Windows, чей
  // запрос уходит в TUN и попадает под hijack-dns, возвращаясь к dns-local.
  group('DNS для «Прямо» не закольцовывается на себя', () {
    Map<String, dynamic> cfg({String? upstream, bool hijack = true}) =>
        SingboxConfigBuilder(
          options: TunOptions(
            serverIps: const ['203.0.113.9'],
            directDnsUpstream: upstream,
            dnsHijack: hijack,
          ),
        ).buildMap(const SplitTunnelConfig(
          mode: SplitMode.exceptSelected,
          sites: [SiteRule('direct.example', action: AppAction.direct)],
        ));

    List<Map<String, dynamic>> servers(Map<String, dynamic> c) =>
        ((c['dns'] as Map)['servers'] as List).cast<Map<String, dynamic>>();

    test('явный апстрим попадает в dns-local', () {
      final local =
          servers(cfg(upstream: '192.0.2.53')).firstWhere((s) => s['tag'] == 'dns-local');
      expect(local['address'], 'udp://192.0.2.53');
      expect(local['detour'], 'direct');
    });

    test('без апстрима поведение прежнее', () {
      final local = servers(cfg()).firstWhere((s) => s['tag'] == 'dns-local');
      expect(local['address'], 'local');
    });

    test('loop-protection стоит ВЫШЕ перехвата DNS', () {
      final r = rules(cfg(upstream: '192.0.2.53'));
      final hijack = r.indexWhere((x) => x['action'] == 'hijack-dns');
      final byIp = r.indexWhere((x) => x.containsKey('ip_cidr'));
      final byProc = r.indexWhere((x) => x.containsKey('process_name'));

      expect(hijack, greaterThanOrEqualTo(0));
      expect(byIp, greaterThanOrEqualTo(0));
      expect(byProc, greaterThanOrEqualTo(0));
      expect(byIp, lessThan(hijack),
          reason: 'иначе DNS прокси-ядра уходит в туннель и ядро ждёт само себя');
      expect(byProc, lessThan(hijack),
          reason: 'иначе резолвер для «Прямо» снова попадает под перехват');
    });

    test('при выключенном перехвате правил hijack-dns нет вовсе', () {
      expect(rules(cfg(hijack: false)).any((x) => x['action'] == 'hijack-dns'),
          isFalse);
    });

    // Автоподбор стека/MTU — ДЕФОЛТ, и он пересоздаёт опции на каждой
    // комбинации. Поле, забытое в copyWith, молча исчезает у большинства.
    test('copyWith не теряет ни одного поля', () {
      const orig = TunOptions(
        serverIps: ['203.0.113.9'],
        directDnsUpstream: '192.0.2.53',
        platformTun: true,
        selfPackage: 'lol.silentgate.test',
        noRealIp: true,
      );
      final copy = orig.copyWith(stack: orig.stack, mtu: orig.mtu);
      expect(copy.directDnsUpstream, orig.directDnsUpstream);
      expect(copy.platformTun, orig.platformTun);
      expect(copy.selfPackage, orig.selfPackage);
      expect(copy.noRealIp, orig.noRealIp);
      // Самый надёжный страж: конфиг из копии совпадает с конфигом оригинала.
      const split = SplitTunnelConfig(mode: SplitMode.exceptSelected);
      expect(SingboxConfigBuilder(options: copy).buildJson(split),
          SingboxConfigBuilder(options: orig).buildJson(split));
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
  group('Адрес обновлений: свой на каждую платформу', () {
    test('пусто в настройках = платформенный адрес по умолчанию', () {
      // ⚠️ Умолчание — ПУСТАЯ строка, а не константа. Раньше сюда при первом
      // сохранении писался жёсткий адрес, и значение ЗАМОРАЖИВАЛОСЬ: смена
      // адреса в новой версии не доходила до уже установленных копий.
      expect(const AppSettings().appUpdateUrl, '');
      expect(const AppSettings().effectiveAppUpdateUrl, kDefaultAppUpdateEndpoint);
      expect(AppUpdate.defaultEndpoint, kDefaultAppUpdateEndpoint);
    });

    test('правка пользователя сильнее платформенного умолчания', () {
      const s = AppSettings(appUpdateUrl: 'https://example.com/v');
      expect(s.effectiveAppUpdateUrl, 'https://example.com/v');
    });

    test('прежний жёсткий адрес забывается при загрузке', () async {
      // Иначе Android продолжал бы спрашивать Windows-эндпоинт и предлагать
      // скачать .exe, который на телефон не поставить.
      final j = const AppSettings().toJson()
        ..['appUpdateUrl'] = 'https://silentgate.lol/api/app-version';
      expect(AppSettings.fromJson(j).appUpdateUrl, '');
    });

    test('файл адресов не тянет ничего, кроме dart:io', () async {
      final src =
          await File('lib/core/update/app_update_defaults.dart').readAsString();
      final imports = RegExp(r'^\s*import\s+.*$', multiLine: true)
          .allMatches(src)
          .map((m) => m.group(0)!.trim())
          .toList();
      // `dart:io` безопасен; любой пакетный импорт снова притащит dart:ui и
      // сломает консольные генераторы конфигов.
      expect(imports.where((i) => i.contains('package:')), isEmpty,
          reason: 'пакетный импорт здесь ломает `dart run tool/emit_*`');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Ссылка `geoip:private` заставляла Xray грузить geoip.dat (18,9 МБ), иначе
  // ядро не стартовало вовсе. А ссылались мы РОВНО на неё одну — то есть 19 МБ
  // поставки существовали ради фиксированного списка подсетей. Со списком
  // гео-файлы нужны только панельным профилям «Авто».
  group('Приватные подсети списком вместо geoip:private', () {
    test('в конфиге Xray не осталось ссылок на geo-категории', () {
      final json = XrayConfigBuilder().buildJson(const VpnServer(
        protocol: 'vless',
        remark: 'узел',
        address: 'example.com',
        port: 443,
        id: '11111111-2222-3333-4444-555555555555',
        security: 'tls',
        rawLink: 'vless://fixture',
      ));
      expect(json.contains('geoip:'), isFalse);
      expect(json.contains('geosite:'), isFalse);
      expect(json.contains('10.0.0.0/8'), isTrue);
    });

    test('список покрывает то, ради чего он и нужен', () {
      // RFC 1918 целиком, CGNAT, loopback, link-local — иначе трафик к роутеру
      // и к соседям по сети уйдёт в туннель.
      for (final net in ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16',
                         '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16']) {
        expect(kPrivateNetworks, contains(net));
      }
      for (final net in ['fc00::/7', 'fe80::/10', '::1/128']) {
        expect(kPrivateNetworks, contains(net));
      }
    });

    test('нет масок, которые отвергает маршрутизатор Xray', () {
      // ::ffff:0:0/96 и 64:ff9b::/96 ядро разбирает как IPv4 и падает на
      // «invalid network mask for router: 96» — проверено xray run -test.
      expect(kPrivateNetworks.any((n) => n.startsWith('::ffff:')), isFalse);
      expect(kPrivateNetworks.any((n) => n.startsWith('64:ff9b:')), isFalse);
    });
  });

  // ⚠️ На Android hysteria2 и профили «Авто» не пингуются ВООБЩЕ: TCP-адреса у
  // них нет (QUIC / балансировщик), а вторая фаза требует харнесса, который там
  // не поднять. Через живой туннель проверять можно — но ЧЕСТНО только текущий
  // сервер: остальным такая проба показала бы чужой канал.
  group('Пинг по живому каналу там, где харнесса нет', () {
    VpnServer srv(String tag) => VpnServer(
          protocol: 'hysteria2',
          remark: tag,
          address: '$tag.example',
          port: 443,
          id: 'pass',
          security: 'tls',
          rawLink: 'hysteria2://pass@$tag.example:443',
        );

    test('хуки отдают порт и ключ активного сервера', () {
      final active = srv('a');
      final c = ProbeController(
        harnessFactory: () => throw StateError('харнесс не должен подниматься'),
        liveProxyPort: () => 10809,
        activeServerKey: () => active.key,
      );
      expect(c.liveProxyPort!(), 10809);
      expect(c.activeServerKey!(), active.key);
    });

    test('без подключения порт нулевой — проверять нечем', () {
      final c = ProbeController(
        harnessFactory: () => throw StateError('харнесс не должен подниматься'),
        liveProxyPort: () => 0,
        activeServerKey: () => null,
      );
      expect(c.liveProxyPort!(), 0);
      expect(c.activeServerKey!(), isNull);
    });
  });

  // Пункт 5 ревью: интерфейс не должен обещать больше, чем проверено.
  group('Честность пинга', () {
    test('«не проверен» имеет подпись во всех локалях', () async {
      // Раньше чип просто не рисовался, и «ещё не мерили» выглядело так же,
      // как «померили и всё плохо».
      for (final code in const ['ru', 'en', 'es', 'de', 'fr', 'pt', 'tr',
        'ar', 'fa', 'zh']) {
        final src = await File('lib/l10n/app_$code.arb').readAsString();
        expect(src.contains('pingUntestedHint'), isTrue,
            reason: 'локаль $code без подписи «не проверен»');
      }
    });

    test('hysteria2 не уезжает в Xray-харнесс', () async {
      // libXray — это Xray, hysteria2 он не поднимет; попытка замера пометила
      // бы рабочий сервер мёртвым.
      final src = await File('lib/engine/android/probe_harness_android.dart')
          .readAsString();
      expect(src.contains("protocol == 'hysteria2'"), isTrue);
    });
  });

  // Правка настроек при живом соединении применяется только после
  // переподключения: конфиг собирается один раз, в момент подъёма. У владельца
  // из-за этого удалённое правило продолжало действовать, а он думал, что
  // правило не работает.
  group('Настройки, требующие переподключения', () {
    test('правка правил раздельного туннелирования — требует', () {
      const a = AppSettings();
      final b = a.copyWith(
        splitTunnel: const SplitTunnelConfig(
          sites: [SiteRule('example.com', action: AppAction.block)],
        ),
      );
      expect(a.requiresReconnect(b), isTrue);
    });

    test('DNS всех приложений через VPN — требует', () {
      const a = AppSettings();
      expect(a.requiresReconnect(a.copyWith(tunnelDnsForAll: false)), isTrue);
    });

    for (final e in <String, AppSettings Function(AppSettings)>{
      'режим захвата': (s) => s.copyWith(captureMode: CaptureMode.tun),
      'MTU': (s) => s.copyWith(tunMtu: 1400),
      'перехват DNS': (s) => s.copyWith(dnsHijack: false),
      'не выходить под реальным IP': (s) => s.copyWith(noRealIp: true),
    }.entries) {
      test('${e.key} — требует', () {
        const a = AppSettings();
        expect(a.requiresReconnect(e.value(a)), isTrue);
      });
    }

    test('настройки интерфейса переподключения НЕ требуют', () {
      const a = AppSettings();
      // Тема и язык на конфиг ядра не влияют — дёргать пользователя незачем.
      expect(a.requiresReconnect(a.copyWith(languageCode: 'en')), isFalse);
    });
  });

  // Отчёт поддержки отдавал ПУСТОЙ раздел [app.log] при живом файле в 239 КБ:
  // строгий readAsString() падал на одном байте 0x82 в середине. Диагноз по
  // такому отчёту поставить нельзя, а выглядит он как «логов нет».
  group('Чтение логов переживает битые байты', () {
    test('хвост читается, даже если в файле не-UTF8', () async {
      final tmp = await Directory.systemTemp.createTemp('sg_badlog_');
      addTearDown(() async {
        try { await tmp.delete(recursive: true); } catch (_) {}
      });
      final f = File('${tmp.path}${Platform.pathSeparator}bad.log');
      // Ровно тот случай: валидные строки, посреди — байт из другой кодировки.
      const lf = 10; // перевод строки байтом — без escape-последовательностей
      await f.writeAsBytes([
        ...utf8.encode('строка один'),
        lf,
        0x82, // байт из другой кодировки — на нём падал строгий разбор
        lf,
        ...utf8.encode('строка два'),
        lf,
      ]);

      final tail = await RotatingLog.tail(f.path, lines: 10);
      expect(tail, contains('строка два'),
          reason: 'битый байт не должен обнулять весь лог');
    });
  });

  // Заглушка вместо «соединение сброшено»: пользователь должен понимать, что
  // сайт закрыт ЕГО ЖЕ правилом, а не сломался интернет.
  group('Страница-заглушка при блокировке', () {
    const blocked = SplitTunnelConfig(
      mode: SplitMode.exceptSelected,
      sites: [SiteRule('ads.example', action: AppAction.block)],
    );

    Map<String, dynamic> build({int port = 0}) => SingboxConfigBuilder(
          options: TunOptions(blockPagePort: port, serverIps: const ['203.0.113.1']),
        ).buildMap(blocked);

    test('http уводится на локальную страницу, https отвергается', () {
      final r = rules(build(port: 18080));
      final page = r.firstWhere((x) =>
          x['override_port'] == 18080 &&
          (x['domain_suffix'] as List?)?.contains('ads.example') == true);
      expect(page['port'], [80], reason: 'подменять https нечем — только 80');
      expect(page['override_address'], '127.0.0.1');
      // Обычный блок остаётся: 443 и всё прочее по-прежнему режется.
      expect(r.any((x) => x['action'] == 'reject'), isTrue);
      // Заглушка ВЫШЕ блока ДОМЕНА, иначе reject сработает первым.
      // Сравниваем именно с доменным блоком: выше него теперь стоит запрет
      // QUIC (UDP:443), который к порту 80 отношения не имеет.
      final domainBlock = r.indexWhere(
          (x) => x['action'] == 'reject' && x.containsKey('domain_suffix'));
      expect(domainBlock, greaterThanOrEqualTo(0));
      expect(r.indexOf(page), lessThan(domainBlock));
    });

    test('домен резолвится, когда заглушка включена', () {
      // Иначе браузер споткнётся на DNS и показывать будет нечего.
      final d = dnsRules(build(port: 18080));
      expect(d.any((x) => x['action'] == 'reject'), isFalse);
    });

    test('без заглушки поведение прежнее: домен не резолвится', () {
      final d = dnsRules(build());
      expect(d.any((x) => x['action'] == 'reject'), isTrue);
      expect(rules(build()).any((x) => x.containsKey('override_port')), isFalse);
    });
  });
}
