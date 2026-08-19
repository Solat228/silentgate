import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/xray/harness_config_builder.dart';
import 'package:silentgate/engine/android/probe_harness_android.dart';

/// Проба панельного профиля «Авто …» — жалоба владельца 1.4.3: «на телефоне и
/// ПК плохо пингуются серверы со своим раздельным туннелированием, в то время
/// как на Happ всё прекрасно».
///
/// ЧТО БЫЛО. Харнесс поднимал конфиг профиля целиком и вёл пробу на его
/// `balancerTag`. Балансировщик Remnawave стоит на `leastPing`, а задержки ему
/// даёт `burstObservatory` — наблюдатель, который стартует ВМЕСТЕ С ЯДРОМ и
/// обходит все узлы профиля (у владельца их десятки) внешней пробой. Харнесс
/// живёт один замер: порт слушает через доли секунды, проба уходит с таймаутом
/// 3 с. Наблюдений к этому моменту нет, `leastPing` не выбирает ничего, и Xray
/// уводит соединение в `fallbackTag` — а он в панельных профилях `direct`.
/// То есть либо мерился ПРЯМОЙ канал пользователя (цифра есть, к серверу
/// отношения не имеет), либо, без fallbackTag, соединение отвергалось и живой
/// профиль показывал «n/a». Плюс наблюдатель всё это время долбил сотнями
/// TLS-сессий ровно в те секунды, когда мы меряем задержку.
///
/// ЧТО ДОЛЖНО БЫТЬ. Проба идёт до КОНКРЕТНОГО узла профиля — того самого, чей
/// адрес показан в строке, — а балансировщик с наблюдателем в харнесс не
/// попадают вовсе.
///
/// Ни один сервер здесь не поднимается: проверяется только конфиг.
void main() {
  // ── Конфиг харнесса ────────────────────────────────────────────────────────

  test('панельный профиль: проба идёт на узел, а не на балансировщик', () {
    final map = _harnessFor(_autoProfile);

    final rules = (map['routing'] as Map)['rules'] as List;

    // ⚠️ ПРАВИЛ ТЕПЕРЬ НЕСКОЛЬКО — по одному на кандидата (19.08.2026).
    // Профиль «Авто …» это БАЛАНСИРОВЩИК над десятками узлов, и мерить ровно
    // один (как делали с 1.4.3) — значит объявлять профиль мёртвым всякий раз,
    // когда мёртв именно этот узел. На данных владельца так и вышло: «рабочих
    // 83 из 101» при 83 обычных серверах и 18 профилях, то есть НИ ОДИН
    // профиль не прошёл ни разу.
    expect(rules.length, greaterThan(1),
        reason: 'один кандидат — это ставка на узел, который может быть мёртв');
    for (var i = 0; i < rules.length; i++) {
      expect(rules[i]['inboundTag'], ['in-$i'],
          reason: 'каждому кандидату свой инбаунд: порты идут подряд от базового');
      // ⚠️ ГЛАВНОЕ, И ЭТО УРОК 1.4.3. Раньше здесь стоял `balancerTag: yt_auto`.
      expect(rules[i].containsKey('balancerTag'), isFalse,
          reason: 'у балансировщика в харнессе нет данных наблюдателя — '
              'выбрать он не может и уходит в fallbackTag');
      // Выход не может оказаться служебным. `fallbackTag` профиля — `direct`,
      // и именно туда уходила проба; такая цифра — про прямой канал
      // пользователя, а не про сервер.
      expect(rules[i]['outboundTag'], isNot('direct'));
      expect(rules[i]['outboundTag'], isNot('block'));
    }
    // Узел, чей адрес показан в строке сервера, остаётся первым: привычная
    // цифра должна остаться привычной.
    expect(rules[0]['outboundTag'], 'proxy');
    // Кандидаты РАЗНЫЕ — иначе перебор не даёт ничего.
    final tags = [for (final r in rules) r['outboundTag']];
    expect(tags.toSet().length, tags.length);
  });

  test('балансировщик и наблюдатель в харнесс не попадают', () {
    final map = _harnessFor(_autoProfile);

    expect((map['routing'] as Map).containsKey('balancers'), isFalse);
    // ⚠️ Отдельная причина, а не следствие: наблюдатель шлёт пробу через
    // КАЖДЫЙ узел профиля по `sampling` раз, и делает это ровно в те секунды,
    // когда мы меряем. Цифра получалась про эту бурю, а трафик — из подписки.
    expect(map.containsKey('burstObservatory'), isFalse);
    expect(map.containsKey('observatory'), isFalse);

    // Узлы профиля остаются: их выкидывать нельзя — `dialerProxy`/`sockopt`
    // умеют ссылаться на соседний outbound, и обрыв такой цепочки уронил бы
    // конфиг целиком.
    final outs = (map['outbounds'] as List).cast<Map>();
    expect(outs.map((o) => o['tag']),
        containsAll(<String>['proxy', 'proxy-2', 'proxy-3', 'direct', 'block']));
  });

  test('domainStrategy форсируется в AsIs, а не наследуется из профиля', () {
    // В профиле стоит IPIfNonMatch: он заставляет ядро резолвить имя мишени
    // локально, и резолв попадает в измеряемую задержку.
    expect(jsonDecode(_autoProfile)['routing']['domainStrategy'],
        'IPIfNonMatch');
    final map = _harnessFor(_autoProfile);
    expect((map['routing'] as Map)['domainStrategy'], 'AsIs');
  });

  test('инбаунд харнесса профиля закрыт паролем', () {
    // Регресс 1.4.2: ветка полного конфига собирает инбаунд СВОИМ кодом, и
    // забыть в ней креды означало бы открытый вход в туннель ровно у тех
    // серверов, которые есть в каждой подписке.
    final map = _harnessFor(_autoProfile, user: 'sg', password: 'secret42');
    final inbounds = (map['inbounds'] as List).cast<Map>();
    expect(inbounds, isNotEmpty);
    // ⚠️ ПАРОЛЬ НА КАЖДОМ, А НЕ НА ПЕРВОМ. Инбаундов теперь несколько (по
    // одному на кандидата профиля), и открытый вход хотя бы в один означает
    // ровно ту дыру, ради которой пароль и заводили: чужой процесс на той же
    // машине получает туннель целиком.
    for (final inb in inbounds) {
      final accounts = (inb['settings'] as Map)['accounts'] as List;
      expect(accounts.single, {'user': 'sg', 'pass': 'secret42'},
          reason: 'инбаунд ${inb['tag']} открыт');
    }
  });

  // ── Выбор узла ─────────────────────────────────────────────────────────────

  test('узел выбирается из selector балансировщика, а не из всего списка', () {
    // Балансируется только часть узлов (`selector: ["fr-"]`), а тег `proxy`
    // в балансировку не входит: мерить его значило бы мерить узел, которым
    // профиль не пользуется.
    const cfg = '''
{"outbounds":[
   {"tag":"proxy","protocol":"vless","settings":{"vnext":[]}},
   {"tag":"fr-1","protocol":"vless","settings":{"vnext":[]}},
   {"tag":"fr-2","protocol":"vless","settings":{"vnext":[]}},
   {"tag":"direct","protocol":"freedom"}],
 "routing":{"balancers":[{"tag":"b","selector":["fr-"],
     "strategy":{"type":"leastPing"}}],
   "rules":[{"type":"field","network":"tcp,udp","balancerTag":"b"}]}}
''';
    final rules = (_harnessFor(cfg)['routing'] as Map)['rules'] as List;
    expect(rules[0]['outboundTag'], 'fr-1');
  });

  test('selector не совпал ни с чем — мерим первый прокси, а не отказываемся',
      () {
    const cfg = '''
{"outbounds":[
   {"tag":"nl-1","protocol":"trojan","settings":{}},
   {"tag":"direct","protocol":"freedom"}],
 "routing":{"balancers":[{"tag":"b","selector":["net-takogo"]}],
   "rules":[{"type":"field","balancerTag":"b"}]}}
''';
    final rules = (_harnessFor(cfg)['routing'] as Map)['rules'] as List;
    expect(rules[0]['outboundTag'], 'nl-1');
  });

  test('служебные outbound\'ы выходом не становятся', () {
    // Порядок в конфиге специально «неудобный»: freedom стоит первым.
    const cfg = '''
{"outbounds":[
   {"tag":"direct","protocol":"freedom"},
   {"tag":"block","protocol":"blackhole"},
   {"tag":"dns-out","protocol":"dns"},
   {"tag":"vless-1","protocol":"vless","settings":{"vnext":[]}}],
 "routing":{"rules":[]}}
''';
    final rules = (_harnessFor(cfg)['routing'] as Map)['rules'] as List;
    expect(rules[0]['outboundTag'], 'vless-1',
        reason: 'проба через freedom мерила бы прямой канал пользователя');
  });

  test('probeExitTag: разбор без сборки всего конфига', () {
    final cfg = jsonDecode(_autoProfile) as Map<String, dynamic>;
    final routing = (cfg['routing'] as Map).cast<String, dynamic>();
    expect(
        HarnessConfigBuilder.probeExitTag(routing, cfg['outbounds'] as List),
        'proxy');

    // Совсем без outbound'ов с тегом мерить нечего — честный null, а не
    // выдуманный тег (правило с висячим тегом Xray уводит трафик молча).
    expect(HarnessConfigBuilder.probeExitTag({}, [const {}]), isNull);
  });

  // ── Android идёт тем же путём ──────────────────────────────────────────────

  group('Android', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_panel_probe_');
      AppPaths.overrideRoot(tmp);
    });

    tearDown(() async {
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('конфиг замера на телефоне — без балансировщика и наблюдателя',
        () async {
      // Жалоба владельца про ОБЕ платформы, и лечится она в одном месте:
      // конфиг замера на Android собирает тот же построитель. Тест ходит по
      // настоящему `ProbeHarnessAndroid.start` (нативный канал он не трогает —
      // только пишет файлы), чтобы проверялся боевой путь, а не копия рядом.
      final harness = ProbeHarnessAndroid();
      final server = ShareLinkParser.tryParse(_realityLink)!
          .copyWith(rawPanelConfig: _autoProfile);
      final handle =
          await harness.start([HarnessEntry(key: 'auto', server: server)]);
      try {
        final f = File('${tmp.path}${Platform.pathSeparator}probe_0.json');
        expect(f.existsSync(), isTrue, reason: 'конфиг замера не записан');
        final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

        final rules = (map['routing'] as Map)['rules'] as List;
        expect(rules[0]['outboundTag'], 'proxy');
        expect(rules[0].containsKey('balancerTag'), isFalse);
        expect(map.containsKey('burstObservatory'), isFalse);
        // Пароль инбаунда на месте — на Android loopback между приложениями
        // не изолирован (1.4.2).
        final accounts = ((map['inbounds'] as List).first
            as Map)['settings']['accounts'] as List;
        expect((accounts.single as Map)['user'], harnessProxyUser);
      } finally {
        await handle.stop();
      }
    });
  });
}

// ── Данные ───────────────────────────────────────────────────────────────────

const _realityLink =
    'vless://11111111-2222-3333-4444-555555555555@example.com:443'
    '?type=tcp&security=reality&pbk=K&sni=a.com&sid=ab&encryption=none#AUTO';

/// Урезанная копия реального профиля Remnawave «Авто»: балансировщик
/// `leastPing` с `fallbackTag: direct`, `burstObservatory` с внешней пробой и
/// три узла. Ровно эта форма и давала «плохо пингуется».
const _autoProfile = '''
{"dns":{"servers":["1.1.1.1"]},
 "inbounds":[{"tag":"socks","port":10808,"listen":"127.0.0.1","protocol":"socks",
   "settings":{"udp":true,"auth":"noauth"}}],
 "outbounds":[
   {"tag":"proxy","protocol":"vless","settings":{"vnext":[{"address":"a.example.com",
     "port":443,"users":[{"id":"11111111-2222-3333-4444-555555555555",
     "encryption":"none","flow":"xtls-rprx-vision"}]}]},
    "streamSettings":{"network":"tcp","security":"reality",
      "realitySettings":{"serverName":"st.ozone.ru","publicKey":"KEY","shortId":"ab"}}},
   {"tag":"proxy-2","protocol":"vless","settings":{"vnext":[{"address":"b.example.com",
     "port":443,"users":[{"id":"11111111-2222-3333-4444-555555555555",
     "encryption":"none"}]}]},
    "streamSettings":{"network":"tcp","security":"reality",
      "realitySettings":{"serverName":"st.ozone.ru","publicKey":"KEY","shortId":"ab"}}},
   {"tag":"proxy-3","protocol":"vless","settings":{"vnext":[{"address":"c.example.com",
     "port":443,"users":[{"id":"11111111-2222-3333-4444-555555555555",
     "encryption":"none"}]}]},
    "streamSettings":{"network":"tcp","security":"reality",
      "realitySettings":{"serverName":"st.ozone.ru","publicKey":"KEY","shortId":"ab"}}},
   {"tag":"direct","protocol":"freedom"},{"tag":"block","protocol":"blackhole"}],
 "routing":{"domainStrategy":"IPIfNonMatch",
   "rules":[
     {"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"block"},
     {"type":"field","ip":["geoip:ru","geoip:private"],"outboundTag":"direct"},
     {"type":"field","network":"tcp,udp","balancerTag":"yt_auto"}],
   "balancers":[{"tag":"yt_auto","selector":["proxy"],
     "strategy":{"type":"leastPing","settings":{"maxRTT":"15s"}},
     "fallbackTag":"direct"}]},
 "burstObservatory":{"subjectSelector":["proxy"],
   "pingConfig":{"destination":"https://www.youtube.com/generate_204",
     "interval":"120s","sampling":3,"timeout":"5s"}},
 "remarks":"🎬 Авто (YouTube)"}
''';

Map<String, dynamic> _harnessFor(String panelConfig,
    {String user = '', String password = ''}) {
  final server =
      ShareLinkParser.tryParse(_realityLink)!.copyWith(rawPanelConfig: panelConfig);
  final builder = const HarnessConfigBuilder().withAuth(user, password);
  return builder.buildMap([HarnessEntry(key: 'auto', server: server)]);
}
