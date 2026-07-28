import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/rotating_log.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/core/update/app_update_defaults.dart';

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
