import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/singbox/singbox_harness_config_builder.dart';
import 'package:silentgate/core/singbox/singbox_proxy_config_builder.dart';
import 'package:silentgate/core/xray/harness_config_builder.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';
import 'package:silentgate/engine/android/probe_harness_android.dart';

/// Локальные порты ядра закрыты паролем НА ВСЕХ ПУТЯХ.
///
/// ⚠️ ЧТО ЗДЕСЬ СТЕРЕЖЁТСЯ И ПОЧЕМУ ЭТО НЕ ПРИДИРКА. Порт 10808/10809 на
/// 127.0.0.1 — это полноценный вход в VPN пользователя: выходной IP, квота
/// подписки и обход его же правил, включая приложения с действием «Блок».
/// Настройка «Пароль на локальный прокси» включена по умолчанию и обещает,
/// что порт закрыт.
///
/// Обещание держалось не везде. Пароль выдавался и уходил ТУННЕЛЮ, а
/// построитель конфига Xray умел только `auth: noauth` — по этому пути идут
/// ВСЕ обычные серверы подписки и режим «Авто (лучший сервер)», то есть
/// подавляющее большинство подключений. Прокси-ядро sing-box (hysteria2) не
/// умело кредов вовсе. Снаружи всё выглядело исправным: подключение проходит,
/// тумблер включён, — а порт открыт любому процессу машины.
///
/// ⚠️ И ТОТ ЖЕ УРОК ПОВТОРИЛСЯ. В 1.3.0 закрыли ДВА пути сборки конфига из
/// ЧЕТЫРЁХ, а этот файл проверял ровно те же два. Про ХАРНЕСС — отдельный
/// экземпляр ядра, который поднимается на время пинга и подбора, — забыли, и
/// его порт 21000+/21500+ оставался открытым входом в туннель весь прогон.
/// Нашлось только ревью, спустя две версии.
///
/// Поэтому ниже проверяются ВСЕ ЧЕТЫРЕ построителя. Появится пятый — добавить
/// его сюда, а не надеяться, что «этот путь не такой».
///
/// ⚠️ И ТРЕТИЙ РАЗ ТОТ ЖЕ УРОК — ПОЭТОМУ ЗДЕСЬ ПРОВЕРЯЮТСЯ ЕЩЁ И МЕСТА ВЫЗОВА.
/// В 1.4.1 харнесс закрыли паролем, но выдавал его только Windows: андроидный
/// путь звал построитель БЕЗ `withAuth`, и на 127.0.0.1:21000 всё время
/// прогона висел открытый вход в туннель кандидата (loopback на Android между
/// приложениями не изолирован — хватает разрешения INTERNET). Все тесты
/// построителей при этом были зелёными: построитель умеет креды, ему их просто
/// не передали. Дефект живёт в ВЫЗОВЕ, и ловить его надо там — см. группу
/// «Боевые пути поднимают харнесс с кредами».
void main() {
  // Мок канала `lol.silentgate/probe` требует биндингов.
  TestWidgetsFlutterBinding.ensureInitialized();

  const vless = VpnServer(
    protocol: 'vless',
    remark: 'srv',
    address: 'example.com',
    port: 443,
    id: '00000000-0000-0000-0000-000000000000',
    rawLink: 'vless://00000000-0000-0000-0000-000000000000@example.com:443#srv',
  );
  const hy2 = VpnServer(
    protocol: 'hysteria2',
    remark: 'hy',
    address: 'hy.example.com',
    port: 443,
    id: 'pass',
    rawLink: 'hysteria2://pass@hy.example.com:443#hy',
  );

  Map<String, dynamic> inboundByTag(Map<String, dynamic> cfg, String tag) =>
      (cfg['inbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((i) => i['tag'] == tag);

  group('Xray: обычный сервер', () {
    test('с кредами socks требует пароль', () {
      final cfg = const XrayConfigBuilder()
          .withAuth('sg', 'secret')
          .buildMap(vless);
      final socks = inboundByTag(cfg, 'socks')['settings'] as Map;
      expect(socks['auth'], 'password');
      expect(socks['accounts'], [
        {'user': 'sg', 'pass': 'secret'}
      ]);
    });

    test('с кредами http требует пароль', () {
      final cfg = const XrayConfigBuilder()
          .withAuth('sg', 'secret')
          .buildMap(vless);
      final http = inboundByTag(cfg, 'http')['settings'] as Map;
      expect(http['accounts'], [
        {'user': 'sg', 'pass': 'secret'}
      ]);
    });

    test('БЕЗ кредов остаётся noauth — это режим системного прокси', () {
      // Не забыть и обратное: в режиме системного прокси пароль ставить
      // НЕЛЬЗЯ. WinINET креденшелов не передаёт, и весь интернет получил бы
      // 407 — то есть «защита» уронила бы связь целиком.
      final cfg = const XrayConfigBuilder().buildMap(vless);
      final socks = inboundByTag(cfg, 'socks')['settings'] as Map;
      expect(socks['auth'], 'noauth');
      expect(socks.containsKey('accounts'), isFalse);
      expect((inboundByTag(cfg, 'http')['settings'] as Map).isEmpty, isTrue);
    });

    test('пустой пароль при заданном логине паролем не считается', () {
      // Полумера опаснее отсутствия: инбаунд с `auth: password` и пустым
      // паролем пускал бы кого угодно, а в интерфейсе стояло бы «закрыт».
      final cfg =
          const XrayConfigBuilder().withAuth('sg', '').buildMap(vless);
      expect((inboundByTag(cfg, 'socks')['settings'] as Map)['auth'], 'noauth');
    });
  });

  group('Xray: «Авто (лучший сервер)»', () {
    test('балансировщик тоже закрывает оба инбаунда', () {
      // Отдельный путь сборки (`buildBalancerMap`), и он про креды не знал.
      final cfg = const XrayConfigBuilder()
          .withAuth('sg', 'secret')
          .buildBalancerMap([vless, vless]);
      expect((inboundByTag(cfg, 'socks')['settings'] as Map)['auth'],
          'password');
      expect((inboundByTag(cfg, 'http')['settings'] as Map)['accounts'], [
        {'user': 'sg', 'pass': 'secret'}
      ]);
    });
  });

  group('sing-box: прокси-ядро hysteria2', () {
    test('оба mixed-инбаунда требуют пароль', () {
      final cfg = const SingboxProxyConfigBuilder(
              user: 'sg', password: 'secret')
          .buildMap([hy2]);
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(ins, isNotEmpty);
      for (final i in ins) {
        expect(i['users'], [
          {'username': 'sg', 'password': 'secret'}
        ], reason: 'инбаунд ${i['tag']} остался без пароля');
      }
    });

    test('без кредов инбаунды открыты — режим системного прокси', () {
      final cfg = const SingboxProxyConfigBuilder().buildMap([hy2]);
      for (final i in (cfg['inbounds'] as List).cast<Map<String, dynamic>>()) {
        expect(i.containsKey('users'), isFalse);
      }
    });
  });

  group('Конфиг остаётся валидным JSON', () {
    test('Xray с кредами сериализуется', () {
      final json = const XrayConfigBuilder()
          .withAuth('sg', 'secret')
          .buildJson(vless);
      expect(() => jsonDecode(json), returnsNormally);
    });

    test('sing-box с кредами сериализуется', () {
      final json = const SingboxProxyConfigBuilder(
              user: 'sg', password: 'secret')
          .buildJson([hy2]);
      expect(() => jsonDecode(json), returnsNormally);
    });
  });

  // ── Харнесс: третий и четвёртый пути сборки конфига ───────────────────────
  //
  // Инбаунд харнесса живёт недолго — только пока идёт прогон пинга или подбора.
  // Но всё это время он ведёт В ТУННЕЛЬ кандидата, а «недолго» на машине с
  // чужим процессом ничем не лучше «всегда».
  const entry = HarnessEntry(key: 'k', server: vless);
  // Второй обычный сервер — чтобы проверить набор инбаундов, а не один.
  // ⚠️ hysteria2 сюда класть НЕЛЬЗЯ: Xray этого протокола не знает и падает на
  // сборке outbound'а. Разложение по ядрам делает MixedProbeHarness.
  const entry2 = HarnessEntry(key: 'k2', server: vless);
  const hy2Entry = HarnessEntry(key: 'k2', server: hy2);

  group('Харнесс Xray', () {
    test('с кредами каждый инбаунд требует пароль', () {
      final cfg = const HarnessConfigBuilder()
          .withAuth('sg', 'secret')
          .buildMap([entry, entry2]);
      final inbounds = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(inbounds, isNotEmpty);
      for (final i in inbounds) {
        final accounts = (i['settings'] as Map)['accounts'];
        expect(accounts, isNotNull,
            reason: 'открытый инбаунд харнесса = вход в туннель без пароля');
        expect((accounts as List).first, {'user': 'sg', 'pass': 'secret'});
      }
    });

    test('без кредов инбаунд открыт — так было до 1.4.1', () {
      final cfg = const HarnessConfigBuilder().buildMap([entry]);
      final i = (cfg['inbounds'] as List).first as Map<String, dynamic>;
      expect((i['settings'] as Map).containsKey('accounts'), isFalse);
    });

    test('с кредами сериализуется', () {
      final json =
          const HarnessConfigBuilder().withAuth('sg', 'secret').buildJson([entry]);
      expect(() => jsonDecode(json), returnsNormally);
    });

    test('withPortBase сдвигает порт и НЕ теряет креды', () {
      // Копия строится новым конструктором, и потерять в ней логин с паролем —
      // одна забытая пара аргументов. Снаружи это выглядело бы как обычный
      // сдвиг порта, а инбаунд оказался бы открыт.
      final b =
          const HarnessConfigBuilder().withAuth('sg', 'secret').withPortBase(31000);
      expect(b.portFor(0), 31000);
      expect(b.portFor(2), 31002);
      final inbound = (b.buildMap([entry])['inbounds'] as List).first as Map;
      expect(inbound['port'], 31000);
      expect((inbound['settings'] as Map)['accounts'], [
        {'user': 'sg', 'pass': 'secret'}
      ]);
    });
  });

  // ── Вторая ветка сборки: профиль панели «Авто» и ручная правка JSON ────────
  //
  // ⚠️ ПОЧЕМУ ЭТО ОТДЕЛЬНАЯ ГРУППА. `buildMap` при ОДНОМ кандидате с полным
  // конфигом уходит в `_tryOverrideMap`, и инбаунд там собирается СВОИМ кодом.
  // Тесты выше её не задевают вовсе: они кладут обычный vless и идут штатной
  // веткой. По этой же ветке идут профили «Авто …» — а они есть в каждой
  // подписке владельца, то есть «редкий случай» тут как раз самый частый.
  group('Харнесс Xray: полный конфиг (профиль «Авто», правка JSON)', () {
    // Панельный профиль-автовыбор в миниатюре: свои инбаунды (их построитель
    // обязан выбросить), балансировщик и burstObservatory — по ним же тест
    // убеждается, что попал именно в эту ветку, а не в штатную.
    const panelRaw = '''
{
  "inbounds": [
    {"tag":"socks","listen":"127.0.0.1","port":10808,"protocol":"socks",
     "settings":{"auth":"noauth"}}
  ],
  "outbounds": [
    {"tag":"proxy-1","protocol":"vless","settings":{}},
    {"tag":"direct","protocol":"freedom"}
  ],
  "routing": {
    "balancers":[{"tag":"bal","selector":["proxy"]}],
    "rules":[{"type":"field","network":"tcp,udp","balancerTag":"bal"}]
  },
  "burstObservatory": {"subjectSelector":["proxy"]}
}
''';
    const panelServer = VpnServer(
      protocol: 'vless',
      remark: 'Авто (YouTube)',
      address: '',
      port: 0,
      id: '',
      rawLink: 'panel://Авто (YouTube)',
      rawPanelConfig: panelRaw,
    );
    const panelEntry = HarnessEntry(key: 'panel', server: panelServer);

    Map<String, dynamic> onlyInbound(Map<String, dynamic> cfg) {
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      // Инбаунды исходного конфига обязаны быть ВЫБРОШЕНЫ целиком: socks:10808
      // из панельного конфига — тоже вход в туннель, и закрывать его паролем
      // харнесса бессмысленно, он там просто не нужен.
      expect(ins, hasLength(1), reason: 'инбаунды панели не заменены: $ins');
      return ins.first;
    }

    test('профиль панели «Авто»: инбаунд закрыт паролем', () {
      final cfg = const HarnessConfigBuilder()
          .withAuth('sg', 'secret')
          .buildMap([panelEntry]);
      // Доказательство, что ветка та самая: штатная сборка балансировщик и
      // burstObservatory не сохраняет — она их не знает вовсе.
      expect(cfg['burstObservatory'], isNotNull,
          reason: 'ушли в штатную ветку — тест проверяет не тот код');
      expect((cfg['routing'] as Map)['balancers'], isNotNull);

      final settings = onlyInbound(cfg)['settings'] as Map;
      expect(settings['accounts'], [
        {'user': 'sg', 'pass': 'secret'}
      ], reason: 'открытый инбаунд профиля «Авто» = вход в туннель без пароля');
    });

    test('ручная правка JSON: инбаунд закрыт паролем', () {
      // Тот же код, но источник другой (`rawJsonOverride` важнее
      // `rawPanelConfig`), и приходит он от пользователя.
      const edited = VpnServer(
        protocol: 'vless',
        remark: 'свой JSON',
        address: 'example.com',
        port: 443,
        id: '00000000-0000-0000-0000-000000000000',
        rawLink: 'json://custom',
        rawJsonOverride: panelRaw,
      );
      final cfg = const HarnessConfigBuilder()
          .withAuth('sg', 'secret')
          .buildMap([const HarnessEntry(key: 'j', server: edited)]);
      expect((onlyInbound(cfg)['settings'] as Map)['accounts'], [
        {'user': 'sg', 'pass': 'secret'}
      ]);
    });

    test('без кредов инбаунд открыт — так было до 1.4.1', () {
      // Обратная половина: без неё тест выше был бы зелёным и на построителе,
      // который лепит `accounts` независимо от того, дали ему пароль или нет.
      final cfg = const HarnessConfigBuilder().buildMap([panelEntry]);
      expect((onlyInbound(cfg)['settings'] as Map).containsKey('accounts'),
          isFalse);
    });
  });

  group('Харнесс sing-box', () {
    test('с кредами каждый инбаунд требует пароль', () {
      final cfg = const SingboxHarnessConfigBuilder()
          .withAuth('sg', 'secret')
          .buildMap([hy2Entry]);
      final inbounds = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(inbounds, isNotEmpty);
      for (final i in inbounds) {
        // ⚠️ У sing-box поле называется `users`, а не `accounts`, и ключи
        // внутри другие: построители решают одну задачу, но не взаимозаменяемы.
        final users = i['users'];
        expect(users, isNotNull);
        expect((users as List).first,
            {'username': 'sg', 'password': 'secret'});
      }
    });

    test('без кредов инбаунд открыт — так было до 1.4.1', () {
      final cfg = const SingboxHarnessConfigBuilder().buildMap([hy2Entry]);
      final i = (cfg['inbounds'] as List).first as Map<String, dynamic>;
      expect(i.containsKey('users'), isFalse);
    });

    test('с кредами сериализуется', () {
      final json = const SingboxHarnessConfigBuilder()
          .withAuth('sg', 'secret')
          .buildJson([hy2Entry]);
      expect(() => jsonDecode(json), returnsNormally);
    });
  });

  // ── Места вызова: боевой путь обязан ВЫДАТЬ креды построителю ─────────────
  //
  // Всё, что выше, — про построители, и оно было зелёным ровно тогда, когда
  // Android поднимал открытый инбаунд. Ниже проверяется то, что построители
  // проверить не могут в принципе: кто и как их зовёт.
  group('Боевые пути поднимают харнесс с кредами', () {
    late Directory tmp;
    const probeChannel = MethodChannel('lol.silentgate/probe');
    final nativeCalls = <MethodCall>[];

    setUp(() {
      // Изолированный корень данных: `start()` пишет конфиги на диск, и в
      // боевой `%APPDATA%\SilentGate` тесту лезть нельзя.
      tmp = Directory.systemTemp.createTempSync('sg_harness_auth_');
      AppPaths.overrideRoot(tmp);
      nativeCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(probeChannel, (call) async {
        nativeCalls.add(call);
        return 42; // мс: нативная сторона отдаёт готовую задержку
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(probeChannel, null);
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('Android: конфиг, УЖЕ ЗАПИСАННЫЙ на диск, закрыт паролем', () async {
      // Смотрим не на построитель, а на файл, который боевой `start()` отдаёт
      // ядру: именно из него libXray поднимает инбаунд. До 1.4.2 в этом файле
      // `settings` был пустым объектом — прокси в туннель без пароля.
      final handle = await ProbeHarnessAndroid().start([entry]);
      final file = File('${tmp.path}${Platform.pathSeparator}probe_0.json');
      expect(file.existsSync(), isTrue, reason: 'конфиг кандидата не записан');

      final cfg = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final inbounds = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(inbounds, isNotEmpty);
      for (final i in inbounds) {
        final accounts = (i['settings'] as Map)['accounts'];
        expect(accounts, isNotNull,
            reason: 'инбаунд харнесса Android поднят БЕЗ пароля: на loopback '
                'Android к нему подключится любое приложение с INTERNET');
        final account = (accounts as List).first as Map;
        expect(account['user'], harnessProxyUser);
        expect('${account['pass']}'.length, greaterThanOrEqualTo(16),
            reason: 'пароль короче секрета прогона — похоже на заглушку');
      }

      await handle.stop();
      expect(file.existsSync(), isFalse, reason: 'конфиг остался на диске');
    });

    test('Android: тот же пароль доезжает до нативного замера', () async {
      // ⚠️ ВТОРАЯ ПОЛОВИНА ДЕФЕКТА, и она страшнее первой: закрыть инбаунд и
      // не предъявить пароль потребителю — это 407 на КАЖДОМ сервере и
      // молчаливое «вся подписка мертва». Потребитель здесь нативный, порт
      // наружу не отдаётся, поэтому креды едут в самом адресе прокси.
      final handle = await ProbeHarnessAndroid().start([entry]);
      expect(await handle.delayMs(0), 42);

      final args = nativeCalls.single.arguments as Map;
      final proxy = Uri.parse('${args['proxy']}');
      expect(proxy.scheme, 'http');
      expect(proxy.host, '127.0.0.1');
      expect(proxy.port, const HarnessPorts().base);
      expect(handle.proxyPassword, isNotEmpty);
      expect(proxy.userInfo, '${handle.proxyUser}:${handle.proxyPassword}',
          reason: 'замер пойдёт в закрытый инбаунд без пароля → 407 везде');

      // И это ТОТ ЖЕ пароль, что лёг в конфиг: два независимых секрета дали бы
      // ровно тот же 407, только искать его пришлось бы дольше.
      final cfg = jsonDecode(
              File('${tmp.path}${Platform.pathSeparator}probe_0.json')
                  .readAsStringSync())
          as Map<String, dynamic>;
      final account = ((((cfg['inbounds'] as List).first
          as Map)['settings'] as Map)['accounts'] as List).first as Map;
      expect(Uri.decodeComponent(proxy.userInfo.split(':').last),
          account['pass']);

      await handle.stop();
    });

    test('Android: конфиг профиля «Авто» на диске тоже закрыт паролем', () async {
      // Боевой путь ВТОРОЙ ветки сборки: у профиля панели конфиг собирается
      // `_tryOverrideMap`, отдельным от обычных серверов кодом, и на диск
      // ложится он же. Проверять только обычный vless (как делали первые два
      // теста этой группы) — значит не проверить ровно те серверы, которые
      // есть в каждой подписке владельца.
      const panelRaw = '{"outbounds":[{"tag":"proxy","protocol":"vless",'
          '"settings":{}}],"burstObservatory":{"subjectSelector":["proxy"]}}';
      const panel = HarnessEntry(
        key: 'panel',
        server: VpnServer(
          protocol: 'vless',
          remark: 'Авто (YouTube)',
          address: '',
          port: 0,
          id: '',
          rawLink: 'panel://Авто (YouTube)',
          rawPanelConfig: panelRaw,
        ),
      );
      final handle = await ProbeHarnessAndroid().start([panel]);
      final cfg = jsonDecode(
              File('${tmp.path}${Platform.pathSeparator}probe_0.json')
                  .readAsStringSync())
          as Map<String, dynamic>;
      expect(cfg['burstObservatory'], isNotNull,
          reason: 'кандидат ушёл в штатную ветку — проверяется не тот код');
      final inbound = (cfg['inbounds'] as List).first as Map;
      expect((inbound['settings'] as Map)['accounts'], isNotNull,
          reason: 'инбаунд профиля «Авто» поднят БЕЗ пароля');

      // И замер обязан предъявить креды туда же, иначе 407 у всех «Авто».
      expect(await handle.delayMs(0), 42);
      final proxy = Uri.parse('${(nativeCalls.single.arguments as Map)['proxy']}');
      expect(proxy.userInfo, '${handle.proxyUser}:${handle.proxyPassword}');
      await handle.stop();
    });

    int portOnDisk(Directory root, int i) {
      final cfg = jsonDecode(
              File('${root.path}${Platform.pathSeparator}probe_$i.json')
                  .readAsStringSync())
          as Map<String, dynamic>;
      return ((cfg['inbounds'] as List).first as Map)['port'] as int;
    }

    test('Android: у каждого кандидата СВОЙ порт', () async {
      // ⚠️ ДЕФЕКТ СТАРЫЙ, НЕ ИЗ ЭТОЙ ПРАВКИ, И ОН ОБЪЯСНЯЕТ ПЛАВАЮЩИЕ «n/a».
      // Конфиг на Android — свой у каждого кандидата, и внутри своего конфига
      // кандидат всегда под индексом 0, поэтому все просили один и тот же
      // 21000. А `ProbeController` гоняет замеры пачкой (Pool до 8 сразу):
      // второй бинд на занятый порт не проходит, `ping` отдаёт пустоту, и
      // живой сервер красится в «n/a» — по тому, кто успел первым.
      final handle = await ProbeHarnessAndroid().start([entry, entry2]);
      final base = const HarnessPorts().base;
      expect(portOnDisk(tmp, 0), base);
      expect(portOnDisk(tmp, 1), base + 1,
          reason: 'два кандидата на одном порту — параллельные замеры дерутся');

      // Адрес замера обязан идти за портом СВОЕГО кандидата, иначе при
      // раздельных портах он стучался бы в чужой инбаунд (то есть в чужой
      // туннель) или в никуда.
      expect(await handle.delayMs(1), 42);
      expect(
          Uri.parse('${(nativeCalls.single.arguments as Map)['proxy']}').port,
          base + 1);
      await handle.stop();
    });

    test('Android: пропущенный hysteria2 не сдвигает порты соседей', () async {
      // Кандидату hysteria2 конфиг не пишется вовсе (Xray его не знает), но
      // индекс он занимает: раздача портов обязана считать по индексу
      // кандидата, а не по числу записанных файлов — иначе адрес замера и порт
      // в конфиге разъедутся у всех, кто стоит ниже hysteria2 в списке.
      final handle = await ProbeHarnessAndroid().start([hy2Entry, entry]);
      final base = const HarnessPorts().base;
      expect(
          File('${tmp.path}${Platform.pathSeparator}probe_0.json').existsSync(),
          isFalse,
          reason: 'для hysteria2 собран конфиг Xray, который его не поднимет');
      expect(portOnDisk(tmp, 1), base + 1);
      expect(await handle.delayMs(0), isNull);
      expect(await handle.delayMs(1), 42);
      expect(
          Uri.parse('${(nativeCalls.single.arguments as Map)['proxy']}').port,
          base + 1);
      await handle.stop();
    });

    test('Android: порт и пароль, заданные тестом, доезжают до конфига',
        () async {
      // ⚠️ ЧЕСТНО: параметры `ports:`/`secret:` боевой путь НЕ передаёт —
      // `createProbeHarness()` зовёт конструктор без аргументов. Живут они
      // ради вот таких проверок: со случайным портом и случайным паролём
      // сверять нечего. Этот тест — единственное, что делает их не мёртвыми,
      // поэтому удалять его вместе с ними или не удалять — решать вместе.
      final handle = await ProbeHarnessAndroid(
        ports: const HarnessPorts(base: 31000),
        secret: 'test-secret-0123456789',
      ).start([entry, entry2]);
      expect(portOnDisk(tmp, 0), 31000);
      expect(portOnDisk(tmp, 1), 31001);
      expect(handle.proxyPassword, 'test-secret-0123456789');
      expect(await handle.delayMs(1), 42);
      expect('${(nativeCalls.single.arguments as Map)['proxy']}',
          'http://$harnessProxyUser:test-secret-0123456789@127.0.0.1:31001');
      await handle.stop();
    });

    test('⚠️ Android: сбой записи не оставляет конфиг с паролем на диске',
        () async {
      // Ломаем запись ВТОРОГО кандидата: на месте `probe_1.json` заранее лежит
      // каталог, и `writeAsString` туда падает. Первый конфиг к этому моменту
      // уже записан — и прибрать его некому: исключение уходит наверх ДО
      // появления хендла, поэтому `finally` вызывающего зовёт `stop()` на
      // `null`. В боевом прогоне это полсотни файлов из ста пяти, и в каждом —
      // пароль харнесса и учётные данные сервера.
      Directory('${tmp.path}${Platform.pathSeparator}probe_1.json')
          .createSync();

      await expectLater(
        ProbeHarnessAndroid().start([entry, entry2]),
        throwsA(isA<FileSystemException>()),
        reason: 'сбой записи обязан дойти до вызывающего, а не молчать',
      );
      expect(
          File('${tmp.path}${Platform.pathSeparator}probe_0.json').existsSync(),
          isFalse,
          reason: 'конфиг уже записанного кандидата остался на диске — а в нём '
              'пароль инбаунда прогона');
    });

    test('Android: пароль свой на каждый прогон', () {
      // Общий на все прогоны секрет утёк бы один раз и навсегда; сессионный —
      // живёт только пока идёт замер.
      expect(ProbeHarnessAndroid().builder.password,
          isNot(ProbeHarnessAndroid().builder.password));
    });

    /// Что не так с `withAuth` в хвосте оператора, создающего построитель;
    /// `null` — всё в порядке.
    ///
    /// ⚠️ ПРОВЕРЯТЬ НАЛИЧИЕ ПОДСТРОКИ `withAuth(` МАЛО, И ЭТО НЕ ПРИДИРКА.
    /// Построитель считает креды заданными, только если НЕПУСТЫ оба поля
    /// (`_hasAuth = user.isNotEmpty && password.isNotEmpty`): вызов
    /// `withAuth(harnessProxyUser, '')` собирает инбаунд БЕЗ `accounts` —
    /// такой же открытый вход в туннель, как и полное отсутствие вызова. Страж,
    /// искавший подстроку, пропускал его молча, а выглядела бы дыра закрытой:
    /// слово `withAuth` в коде стоит.
    ///
    /// ⚠️ ОДНА ФУНКЦИЯ НА ОБА ТЕСТА НИЖЕ — по живому `lib/` и по заведомым
    /// образцам. Вторая копия разбора зеленела бы на образцах ровно тогда,
    /// когда первая пропускает дыру: тот же класс дефекта, что «два разбора
    /// одной строки» в `single_instance`.
    String? authProblem(String stmtTail) {
      const call = 'withAuth(';
      final at = stmtTail.indexOf(call);
      if (at == -1) return 'без withAuth';

      // Аргументы ВЕРХНЕГО УРОВНЯ: делением по запятым их не получить —
      // `withAuth(user, secret ?? make(a, b))` распался бы на три.
      final args = <String>[];
      final buf = StringBuffer();
      var depth = 0;
      String? quote;
      for (var i = at + call.length; i < stmtTail.length; i++) {
        final ch = stmtTail[i];
        if (quote != null) {
          buf.write(ch);
          if (ch == r'\') {
            if (++i < stmtTail.length) buf.write(stmtTail[i]);
          } else if (ch == quote) {
            quote = null;
          }
          continue;
        }
        if (ch == "'" || ch == '"') {
          quote = ch;
        } else if (ch == '(' || ch == '[' || ch == '{') {
          depth++;
        } else if (ch == ']' || ch == '}') {
          depth--;
        } else if (ch == ')') {
          if (depth == 0) break;
          depth--;
        } else if (ch == ',' && depth == 0) {
          args.add(buf.toString());
          buf.clear();
          continue;
        }
        buf.write(ch);
      }
      args.add(buf.toString());
      if (args.length < 2) return 'withAuth не с двумя аргументами';

      bool isEmptyLiteral(String arg) {
        final v = arg.replaceFirst(RegExp(r'^\s*\w+\s*:'), '').trim();
        return v == "''" || v == '""' || v == "r''" || v == 'r""';
      }

      if (args.any(isEmptyLiteral)) {
        return 'withAuth с пустым аргументом '
            '(${args.map((a) => a.trim()).join(', ')})';
      }
      return null;
    }

    test('ни один путь в lib/ не строит харнесс без НЕПУСТОГО пароля', () {
      // Страж на будущее: следующая платформа (iOS) скопирует ближайший
      // платформенный харнесс, и забытый `withAuth` обязан краснеть сразу, а
      // не через две версии, как на Android.
      const builderDefs = [
        'lib/core/xray/harness_config_builder.dart',
        'lib/core/singbox/singbox_harness_config_builder.dart',
      ];
      final ctor = RegExp(r'\b(?:Singbox)?HarnessConfigBuilder\s*\(');
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final rel = f.path.replaceAll(r'\', '/');
        // Файлы самих построителей: там конструктор объявляется, и внутри него
        // же живёт `withAuth` — требовать от них вызова себя бессмысленно.
        if (builderDefs.any(rel.endsWith)) continue;
        final src = f.readAsStringSync();
        for (final m in ctor.allMatches(src)) {
          // Хвост ОПЕРАТОРА, а не строки: конструктор часто разбит переносами,
          // а `.withAuth(...)` стоит после закрывающей скобки.
          final semi = src.indexOf(';', m.end);
          final stmt = src.substring(m.end, semi == -1 ? src.length : semi);
          final problem = authProblem(stmt);
          if (problem == null) continue;
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('$rel:$line — $problem');
        }
      }
      expect(offenders, isEmpty,
          reason: 'харнесс поднят без пароля — это открытый вход в туннель '
              'кандидата на всё время прогона: $offenders');
    });

    test('страж ловит пустой пароль — проверено на образцах', () {
      // ⚠️ Страж выше читает `lib/`, и пока там всё в порядке, он зелёный при
      // ЛЮБОЙ своей логике, включая сломанную. Здесь ТА ЖЕ функция гоняется по
      // заведомым образцам: «страж перестал ловить» видно сразу, а не в тот
      // день, когда кто-то напишет `withAuth('sg', '')`.
      expect(authProblem(').withAuth(harnessProxyUser, secret ?? newSecret());'),
          isNull);
      expect(authProblem(").withAuth(harnessProxyUser, '')"), isNotNull,
          reason: 'пустой пароль = инбаунд без accounts, страж обязан краснеть');
      expect(authProblem(").withAuth('', 'secret')"), isNotNull,
          reason: 'пустой логин закрывает инбаунд ровно так же — никак');
      expect(authProblem(').withAuth(user)'), isNotNull);
      expect(authProblem(');'), isNotNull, reason: 'вызова нет вовсе');
      // Запятая внутри вложенного вызова и внутри строки аргументы не делит —
      // иначе разбор объявил бы нарушением совершенно исправный код.
      expect(authProblem(""").withAuth(u, pick(['a', 'b'], ','))"""), isNull);
    });
  });
}
