import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/xray/geodata_fallback.dart';
import 'package:silentgate/engine/android/probe_harness_android.dart';
import 'package:silentgate/state/probe_controller.dart';

/// Панельный профиль «Авто …» на Android: пинг обязан пробовать НЕСКОЛЬКО
/// узлов профиля, а не один.
///
/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА 17.09.2026 (телефон, 1.10.0): «не пингует авто локации».
/// В журнале — «Проба через прокси 95 (общий 80, свой конфиг 15)» → «рабочих
/// 72 из 95», и так в двух прогонах подряд. Пятнадцать — это ровно число
/// профилей «Авто»; ни один не прошёл ни разу.
///
/// ЧТО БЫЛО. На Windows тот же дефект закрыли 19.08.2026: харнесс мерил ОДИН
/// узел балансировщика (тег `proxy`), и если мёртв именно он — профиль числился
/// мёртвым всегда. Починка (`_bestOverridePort`) пробует четыре узла с разбегом
/// и берёт лучший — но она живёт за гейтом `proxyPortFor(i) > 0`, а на Android
/// порт наружу не отдаётся (`proxyPortFor` = 0): замер делает `LibXray.ping`
/// по адресу `base + 0`, то есть снова через первый узел. Конфиг при этом
/// честно содержал четыре инбаунда — три из них не спрашивал никто.
///
/// ЧТО ДОЛЖНО БЫТЬ. Каждому узлу-кандидату — свой конфиг с ОДНИМ инбаундом на
/// своём порту (`ping` поднимает экземпляр ядра на весь файл: четыре
/// параллельных запуска одного файла дрались бы за одни и те же порты), замер
/// идёт по всем параллельно, профиль жив, если ответил хоть один.
///
/// Нативный канал подменён: «ядро» отвечает по НОМЕРУ ПОРТА в адресе прокси —
/// так видно, какой именно узел спрашивали.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  const probeChannel = MethodChannel('lol.silentgate/probe');
  final nativeCalls = <MethodCall>[];

  /// Что «ответило ядро» на каждом порту. Нет записи — `null` (узел мёртв).
  var delayByPort = <int, int>{};

  int portOf(MethodCall c) =>
      Uri.parse('${(c.arguments as Map)['proxy']}').port;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_android_auto_ping_');
    AppPaths.overrideRoot(tmp);
    nativeCalls.clear();
    delayByPort = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(probeChannel, (call) async {
      nativeCalls.add(call);
      return delayByPort[portOf(call)];
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

  final base = const HarnessPorts().base;

  List<File> probeFiles() => tmp
      .listSync()
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last.startsWith('probe_'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  group('Харнесс Android: профиль «Авто» меряется по нескольким узлам', () {
    test('⚠️ ГЛАВНОЕ: мёртв узел `proxy` — профиль всё равно жив', () async {
      // Первый узел молчит (как у владельца: `proxy` в его же результатах
      // пинга числится failed), третий отвечает.
      delayByPort = {base + 2: 120};
      final handle = await ProbeHarnessAndroid()
          .start([const HarnessEntry(key: 'a', server: _auto)]);
      try {
        expect(await handle.delayMs(0), 120,
            reason: 'ЗДЕСЬ БЫЛ ДЕФЕКТ: спрашивали только первый узел, и '
                'профиль числился мёртвым, пока мёртв именно он');
        // Спросили ВСЕ три узла, а не один.
        expect(nativeCalls.map(portOf).toSet(), {base, base + 1, base + 2},
            reason: 'замер обязан пройти по каждому кандидату');
      } finally {
        await handle.stop();
      }
    });

    test('у каждого кандидата свой файл с ОДНИМ инбаундом и своим портом',
        () async {
      // `LibXray.ping` поднимает экземпляр ядра на ВЕСЬ файл. Один файл с
      // четырьмя инбаундами, запущенный четыре раза параллельно, — это четыре
      // экземпляра, бьющихся за одни и те же четыре порта: три из четырёх
      // не поднялись бы, и «n/a» плавало бы по тому, кто успел первым.
      final handle = await ProbeHarnessAndroid()
          .start([const HarnessEntry(key: 'a', server: _auto)]);
      try {
        final files = probeFiles();
        expect(files, hasLength(3), reason: 'по файлу на узел-кандидат');
        final ports = <int>{};
        final tags = <String>{};
        for (final f in files) {
          final cfg = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
          final inbounds = (cfg['inbounds'] as List).cast<Map>();
          expect(inbounds, hasLength(1),
              reason: 'в ${f.path} больше одного инбаунда — параллельные '
                  'экземпляры подерутся за порты');
          ports.add(inbounds.single['port'] as int);
          // Пароль — на каждом: loopback на Android не изолирован (1.4.2).
          expect((inbounds.single['settings'] as Map)['accounts'], isNotNull);
          final rules = (cfg['routing'] as Map)['rules'] as List;
          expect(rules, hasLength(1));
          expect((rules.single as Map)['inboundTag'], [inbounds.single['tag']]);
          tags.add('${(rules.single as Map)['outboundTag']}');
          // Балансировщик и наблюдатель в харнесс не попадают (урок 1.4.3).
          expect((cfg['routing'] as Map).containsKey('balancers'), isFalse);
          expect(cfg.containsKey('burstObservatory'), isFalse);
        }
        expect(ports, {base, base + 1, base + 2},
            reason: 'порты подряд от базового и без повторов');
        expect(tags, {'proxy', 'proxy-2', 'proxy-3'},
            reason: 'каждый файл ведёт на СВОЙ узел — иначе перебор пустой');
      } finally {
        await handle.stop();
      }
      expect(probeFiles(), isEmpty,
          reason: 'stop() обязан убрать ВСЕ файлы кандидатов: в каждом пароль');
    });

    test('берётся лучший из ответивших', () async {
      delayByPort = {base: 300, base + 1: 80, base + 2: 150};
      final handle = await ProbeHarnessAndroid()
          .start([const HarnessEntry(key: 'a', server: _auto)]);
      try {
        expect(await handle.delayMs(0), 80);
      } finally {
        await handle.stop();
      }
    });

    test('не ответил никто — честный null', () async {
      final handle = await ProbeHarnessAndroid()
          .start([const HarnessEntry(key: 'a', server: _auto)]);
      try {
        expect(await handle.delayMs(0), isNull);
        expect(nativeCalls, hasLength(3), reason: 'все три спросили');
      } finally {
        await handle.stop();
      }
    });

    test('соседи профиля в пачке не садятся на его порты', () async {
      // Профиль занимает столько портов, сколько у него кандидатов; следующая
      // запись обязана начаться ПОСЛЕ них, иначе её инбаунд бьётся за порт с
      // третьим узлом профиля.
      delayByPort = {base + 3: 42};
      final handle = await ProbeHarnessAndroid().start(const [
        HarnessEntry(key: 'a', server: _auto),
        HarnessEntry(key: 'b', server: _plain),
      ]);
      try {
        expect(await handle.delayMs(1), 42);
        expect(portOf(nativeCalls.single), base + 3);
      } finally {
        await handle.stop();
      }
    });

    test('обычный сервер по-прежнему один файл и один вызов', () async {
      delayByPort = {base: 42};
      final handle = await ProbeHarnessAndroid()
          .start([const HarnessEntry(key: 'b', server: _plain)]);
      try {
        expect(await handle.delayMs(0), 42);
        expect(nativeCalls, hasLength(1));
        expect(probeFiles(), hasLength(1));
      } finally {
        await handle.stop();
      }
    });
  });

  group('Харнесс Android: гео-ссылки в конфиге замера', () {
    test('⚠️ `geosite:` из dns панели в конфиг замера не попадает', () async {
      // Боевой путь на Android чистит гео-ссылки (`stripGeodata`) либо
      // прописывает каталог баз в `env` — харнесс не делал ни того, ни
      // другого. Правила маршрутизации он заменяет своими, а вот `dns`
      // профиля оставлял как есть: `geosite:` там означает, что ядро замера
      // ищет `geosite.dat` в `/system/bin`, не находит и не стартует —
      // профиль «мёртв» без единого запроса. На Windows тот же конфиг
      // работает: базы лежат рядом с xray.exe.
      final handle = await ProbeHarnessAndroid()
          .start([const HarnessEntry(key: 'g', server: _autoWithGeoDns)]);
      try {
        for (final f in probeFiles()) {
          final json = f.readAsStringSync();
          expect(needsGeodata(json), isFalse,
              reason: 'в ${f.path} остались ссылки на гео-базы — ядро замера '
                  'их не откроет и не поднимется');
        }
      } finally {
        await handle.stop();
      }
    });
  });

  group('Сквозной путь пинга', () {
    test('⚠️ профиль с мёртвым первым узлом получает вердикт «рабочий»',
        () async {
      // Ровно сценарий владельца, через настоящий ProbeController и настоящий
      // ProbeHarnessAndroid — подменён только нативный замер.
      delayByPort = {base + 1: 95};
      final ctrl = ProbeController(harnessFactory: ProbeHarnessAndroid.new);
      await ctrl.pingAll(
          [_auto], const AppSettings(pingTimeoutMs: 700, pingConcurrency: 4));
      final r = ctrl.resultFor(_auto);
      expect(r.verification, PingVerification.passed,
          reason: 'профиль жив по второму узлу, а числился мёртвым');
      expect(r.proxyRttMs, 95);
      expect(r.outcome, PingOutcome.ok);
    });
  });
}

// ── Данные (TEST-NET, учётные данные выдуманные) ─────────────────────────────

const _plain = VpnServer(
  protocol: 'vless',
  remark: 'plain',
  address: '203.0.113.10',
  port: 443,
  id: '11111111-2222-3333-4444-555555555555',
  rawLink: 'vless://11111111-2222-3333-4444-555555555555@203.0.113.10:443'
      '?type=tcp&security=none#plain',
);

/// Урезанный профиль Remnawave «Авто»: три узла под балансировщиком
/// `leastPing` с `fallbackTag: direct`.
const _auto = VpnServer(
  protocol: 'vless',
  remark: 'Авто (YouTube)',
  address: '',
  port: 0,
  id: '',
  rawLink: 'panel://Авто (YouTube)',
  rawPanelConfig: _autoProfile,
);

const _autoWithGeoDns = VpnServer(
  protocol: 'vless',
  remark: 'Авто (RU)',
  address: '',
  port: 0,
  id: '',
  rawLink: 'panel://Авто (RU)',
  rawPanelConfig: _autoProfileGeoDns,
);

const _autoProfile = '''
{"dns":{"servers":["1.1.1.1"]},
 "inbounds":[{"tag":"socks","port":10808,"listen":"127.0.0.1","protocol":"socks",
   "settings":{"udp":true,"auth":"noauth"}}],
 "outbounds":[
   {"tag":"proxy","protocol":"vless","settings":{"vnext":[{"address":"203.0.113.1",
     "port":443,"users":[{"id":"11111111-2222-3333-4444-555555555555","encryption":"none"}]}]}},
   {"tag":"proxy-2","protocol":"vless","settings":{"vnext":[{"address":"203.0.113.2",
     "port":443,"users":[{"id":"11111111-2222-3333-4444-555555555555","encryption":"none"}]}]}},
   {"tag":"proxy-3","protocol":"vless","settings":{"vnext":[{"address":"203.0.113.3",
     "port":443,"users":[{"id":"11111111-2222-3333-4444-555555555555","encryption":"none"}]}]}},
   {"tag":"direct","protocol":"freedom"},{"tag":"block","protocol":"blackhole"}],
 "routing":{"domainStrategy":"IPIfNonMatch",
   "rules":[
     {"type":"field","ip":["geoip:ru","geoip:private"],"outboundTag":"direct"},
     {"type":"field","network":"tcp,udp","balancerTag":"yt_auto"}],
   "balancers":[{"tag":"yt_auto","selector":["proxy"],
     "strategy":{"type":"leastPing"},"fallbackTag":"direct"}]},
 "burstObservatory":{"subjectSelector":["proxy"],
   "pingConfig":{"destination":"https://www.youtube.com/generate_204",
     "interval":"120s","sampling":3,"timeout":"5s"}},
 "remarks":"Авто (YouTube)"}
''';

/// Тот же профиль, но с российским DNS панели: `geosite:` в `dns.servers`.
const _autoProfileGeoDns = '''
{"dns":{"servers":[
   {"address":"77.88.8.8","domains":["geosite:category-ru","geosite:yandex"]},
   "1.1.1.1"]},
 "outbounds":[
   {"tag":"proxy","protocol":"vless","settings":{"vnext":[{"address":"203.0.113.1",
     "port":443,"users":[{"id":"11111111-2222-3333-4444-555555555555","encryption":"none"}]}]}},
   {"tag":"proxy-2","protocol":"vless","settings":{"vnext":[{"address":"203.0.113.2",
     "port":443,"users":[{"id":"11111111-2222-3333-4444-555555555555","encryption":"none"}]}]}},
   {"tag":"direct","protocol":"freedom"}],
 "routing":{"rules":[{"type":"field","network":"tcp,udp","balancerTag":"b"}],
   "balancers":[{"tag":"b","selector":["proxy"],"fallbackTag":"direct"}]},
 "remarks":"Авто (RU)"}
''';
