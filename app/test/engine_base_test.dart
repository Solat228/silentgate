import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/engine/vpn_engine.dart';

/// Мозг подключения (сессия, поколения, автовосстановление, выбор конфига)
/// переехал в платформо-независимый [VpnEngineBase] — и стал наконец
/// тестируемым: раньше он был намертво сцеплен с запуском xray.exe.
///
/// Тесты закрепляют поведение, оплаченное живыми прогонами: гварды поколений
/// против «туннель поднялся после Отключить», удержание захвата при kill switch,
/// grace-период на смену сети, переход на запасной сервер через тот же
/// `configFor` (иначе профиль панели теряет свой balancer).
class _FakeEngine extends VpnEngineBase {
  int startCalls = 0;
  int teardownCalls = 0;
  int cleanupCalls = 0;
  final List<bool> keepCaptureLog = [];

  /// Имитируем успешный подъём: как настоящий движок, помечаем подключение.
  bool succeedOnStart = true;

  @override
  Future<void> startSession() async {
    startCalls++;
    final gen = newGeneration();
    if (!succeedOnStart) return;
    if (isStale(gen)) return;
    markConnected();
    setStatus(VpnConnectionState.connected);
  }

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {
    teardownCalls++;
    keepCaptureLog.add(keepCapture);
  }

  @override
  Future<void> platformCleanup() async => cleanupCalls++;
}

VpnServer _server(String name, {String? panelConfig, String? jsonOverride}) =>
    VpnServer(
      protocol: 'vless',
      remark: name,
      address: '$name.example.com',
      port: 443,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'vless://x@$name.example.com:443#$name',
      rawPanelConfig: panelConfig,
      rawJsonOverride: jsonOverride,
    );

AppSettings _settings({
  bool autoReconnect = true,
  bool killSwitch = false,
  bool noRealIp = false,
  // Захват между попытками удерживает не только kill switch, но и «не мигать
  // сетью» (`seamlessKeepTun`, включён по умолчанию). Тестам про kill switch
  // нужен ИМЕННО kill switch, поэтому здесь второй держатель по умолчанию снят
  // — иначе они мерили бы сумму двух настроек и молчали бы, сломайся любая.
  bool seamlessKeepTun = false,
  SplitMode mode = SplitMode.all,
}) =>
    AppSettings.defaults.copyWith(
      autoReconnect: autoReconnect,
      killSwitch: killSwitch,
      noRealIp: noRealIp,
      seamlessKeepTun: seamlessKeepTun,
      splitTunnel: SplitTunnelConfig(mode: mode),
    );

void main() {
  group('VpnEngineBase: поколения', () {
    test('isStale ловит устаревший запуск', () {
      final e = _FakeEngine();
      final gen = e.newGeneration();
      expect(e.isStale(gen), isFalse);

      e.newGeneration(); // как будто пошёл ретрай или отмена
      expect(e.isStale(gen), isTrue,
          reason: 'запуск, стартовавший раньше, обязан узнать, что устарел — '
              'иначе туннель поднимется уже после «Отключить»');
    });

    test('cleanup увеличивает поколение — поэтому «была ли отмена» '
        'проверяется ДО него', () async {
      final e = _FakeEngine();
      final gen = e.newGeneration();

      await e.cleanup();

      expect(e.isStale(gen), isTrue);
      expect(e.cleanupCalls, 1);
    });
  });

  group('VpnEngineBase: подключение', () {
    test('повторный connect во время подключения молча игнорируется', () async {
      final e = _FakeEngine()..succeedOnStart = false;
      await e.connectWith('{}', const ConnectionOptions(), [_server('a')]);
      e.setStatus(VpnConnectionState.connecting);

      await e.connectWith('{}', const ConnectionOptions(), [_server('b')]);

      expect(e.startCalls, 1, reason: 'очереди подключений нет — UI на это '
          'рассчитывает');
    });

    test('connectBalancer с пустым списком ничего не делает', () async {
      final e = _FakeEngine();
      await e.connectBalancer([]);
      expect(e.startCalls, 0);
    });

    test('disconnect гасит захват даже из состояния «отключено»', () async {
      // Kill switch мог оставить захват после неудачного восстановления.
      final e = _FakeEngine();
      await e.disconnect();
      expect(e.cleanupCalls, 1);
    });

    test('disconnect отменяет автовосстановление и чистит сессию', () async {
      final e = _FakeEngine();
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings()), [_server('a')]);

      await e.disconnect();

      expect(e.userStopped, isTrue);
      expect(e.session, isNull);
      expect(e.status.state, VpnConnectionState.disconnected);
    });
  });

  group('VpnEngineBase: автовосстановление', () {
    test('не планируется без сессии', () async {
      expect(await _FakeEngine().scheduleRetry('тест'), isFalse);
    });

    test('не планируется при выключенном autoReconnect', () async {
      final e = _FakeEngine();
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings(autoReconnect: false)),
          [_server('a')]);

      expect(await e.scheduleRetry('тест'), isFalse);
    });

    test('не планируется после disconnect пользователем', () async {
      final e = _FakeEngine();
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings()), [_server('a')]);
      await e.disconnect();

      expect(await e.scheduleRetry('тест'), isFalse);
    });

    test('kill switch удерживает захват между попытками', () async {
      final e = _FakeEngine();
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings(killSwitch: true)),
          [_server('a')]);

      expect(await e.scheduleRetry('обрыв'), isTrue);

      expect(e.keepCaptureLog, [true],
          reason: 'иначе на время паузы трафик пойдёт мимо VPN');
    });

    test('без kill switch и без «не мигать сетью» захват снимается между '
        'попытками', () async {
      final e = _FakeEngine();
      await e.connectWith('{}',
          ConnectionOptions(
              settings: _settings(killSwitch: false, seamlessKeepTun: false)),
          [_server('a')]);

      await e.scheduleRetry('обрыв');

      expect(e.keepCaptureLog, [false]);
    });

    // Один обрыв приходит НЕСКОЛЬКИМИ событиями: при hysteria2 в TUN-режиме
    // одновременно умирают процесс туннеля и процесс прокси-ядра, у каждого
    // свой onCoreDied. Раньше каждое событие жгло отдельную попытку — все 8
    // отрабатывали в одну миллисекунду, backoff не выдерживался, и первый же
    // случайный сбой навсегда исчерпывал лимит.
    test('повторные события одного обрыва не жгут попытки', () async {
      final e = _FakeEngine()..succeedOnStart = false;
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings()), [_server('a')]);
      final afterConnect = e.startCalls;

      for (var i = 0; i < 5; i++) {
        expect(await e.scheduleRetry('обрыв'), isTrue);
      }
      // Пока запланированная попытка не отработала, новых не появляется.
      expect(e.startCalls, afterConnect,
          reason: 'запланирована ровно одна попытка, а не пять');
      // И израсходована ровно одна попытка из лимита.
      expect(e.attemptsUsed, 1);
    });

    // `WindowsEngine` держал СВОЁ поле `_attempt`, которое никто не увеличивал,
    // поэтому «Переподключение (попытка N)…» и «Соединение восстановлено
    // (попытка N)» всегда показывали ноль. Счётчик теперь один — в базе.
    test('attempt виден наследнику и растёт вместе со счётчиком базы', () async {
      final e = _FakeEngine()..succeedOnStart = false;
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings()), [_server('a')]);
      expect(e.attempt, 0, reason: 'обычное подключение — не попытка');

      expect(await e.scheduleRetry('обрыв'), isTrue);
      expect(e.attempt, 1);
      expect(e.attempt, e.attemptsUsed, reason: 'счётчик обязан быть один');

      e.dropPendingRetry();
      expect(await e.scheduleRetry('обрыв'), isTrue);
      expect(e.attempt, 2);

      e.markConnected();
      expect(e.attempt, 0, reason: 'успех обнуляет отсчёт');
    });

    test('попытки исчерпываются на maxAttempts', () async {
      final e = _FakeEngine()..succeedOnStart = false;
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings()), [_server('a')]);

      var scheduled = 0;
      for (var i = 0; i < VpnEngineBase.maxAttempts + 3; i++) {
        if (await e.scheduleRetry('обрыв')) scheduled++;
        // Ждём отработки таймера: без этого все вызовы схлопнутся в один обрыв.
        e.dropPendingRetry();
      }

      expect(scheduled, VpnEngineBase.maxAttempts);
    });

    // «Отключить» во время долгого teardownCore не должно воскрешать статус:
    // раньше scheduleRetry дописывал connecting и ставил таймер уже ПОСЛЕ
    // отключения — пользователь навсегда оставался в «Подключение…», а повторный
    // connectWith отсекался гвардом «уже подключаемся».
    test('отключение во время гашения ядра отменяет попытку', () async {
      final e = _FakeEngine()..succeedOnStart = false;
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings()), [_server('a')]);
      await e.disconnect();
      expect(await e.scheduleRetry('обрыв'), isFalse,
          reason: 'после «Отключить» попытки не планируются');
    });

    test('backoff — 800мс/3с/8с/20с, дальше держится на 20с', () {
      // Значения важны: первая пауза короткая, потому что при kill switch
      // трафик всё это время заблокирован.
      expect(VpnEngineBase.backoff.map((d) => d.inMilliseconds).toList(),
          [800, 3000, 8000, 20000]);
    });
  });

  group('VpnEngineBase: смена сети', () {
    test('игнорируется в grace-период после подключения', () async {
      // Первая линия защиты от вечного цикла: подъём собственного туннеля
      // сам выглядит как «смена сети».
      final e = _FakeEngine();
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings()), [_server('a')]);
      expect(e.status.state, VpnConnectionState.connected);

      await e.onNetworkChanged();

      expect(e.teardownCalls, 0, reason: 'сразу после подключения смена сети — '
          'это почти всегда наш же туннель');
    });

    test('игнорируется, когда не подключены', () async {
      final e = _FakeEngine()..succeedOnStart = false;
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings()), [_server('a')]);

      await e.onNetworkChanged();

      expect(e.teardownCalls, 0);
    });
  });

  group('VpnEngineBase: выбор конфига и ядра', () {
    test('hysteria2 идёт на sing-box', () {
      final e = _FakeEngine();
      final hy = VpnServer(
        protocol: 'hysteria2',
        remark: 'hy',
        address: 'hy.example.com',
        port: 443,
        id: 'pass',
        rawLink: 'hysteria2://pass@hy.example.com:443#hy',
      );

      expect(e.configFor(hy, const ConnectionOptions()).core, ProxyCore.singbox);
    });

    test('панельный профиль применяется целиком, ядро — Xray', () {
      final e = _FakeEngine();
      const panel = '{"outbounds":[{"tag":"proxy","protocol":"vless"}],'
          '"routing":{"balancers":[{"tag":"b"}]}}';

      final cfg = e.configFor(
          _server('p', panelConfig: panel), const ConnectionOptions());

      expect(cfg.core, ProxyCore.xray);
      expect(cfg.json, contains('balancers'),
          reason: 'иначе теряется весь автовыбор панели');
    });

    test('правка пользователя приоритетнее панельного профиля', () {
      final e = _FakeEngine();
      const panel = '{"outbounds":[{"tag":"proxy","protocol":"vless"}],'
          '"routing":{"balancers":[{"tag":"panel-balancer"}]}}';
      const override = '{"outbounds":[{"tag":"proxy","protocol":"vless",'
          '"settings":{"marker":"user-override"}}]}';

      final cfg = e.configFor(
          _server('p', panelConfig: panel, jsonOverride: override),
          const ConnectionOptions());

      expect(cfg.json, contains('user-override'));
      expect(cfg.json, isNot(contains('panel-balancer')));
    });

    test('hysteria2 с Xray-JSON: правка игнорируется, ядро остаётся sing-box',
        () {
      // Xray такого протокола не знает и просто не стартует.
      final e = _FakeEngine();
      final hy = VpnServer(
        protocol: 'hysteria2',
        remark: 'hy',
        address: 'hy.example.com',
        port: 443,
        id: 'pass',
        rawLink: 'hysteria2://pass@hy.example.com:443#hy',
        rawJsonOverride: '{"outbounds":[{"protocol":"vless"}]}',
      );

      expect(e.configFor(hy, const ConnectionOptions()).core, ProxyCore.singbox);
    });

    test('секрет Clash API — 32 hex и новый на КАЖДУЮ СЕССИЮ', () {
      // ⚠️ ВЫДАЁТСЯ НА СЕССИЮ, А НЕ ПРИ СБОРКЕ КОНФИГА sing-box. Пока
      // присваивание жило внутри `buildSingboxJson`, секрет появлялся только
      // когда прокси-ядром работает sing-box (hysteria2). При обычном
      // VLESS/Reality — то есть почти всегда — он оставался пустым, и
      // ТУННЕЛЬНЫЙ sing-box поднимал Clash API без пароля: список посещённых
      // доменов и адресов читала любая открытая веб-страница.
      final e = _FakeEngine();

      e.prepareLocalProxyAuth(const ConnectionOptions());
      final first = e.singboxApiSecret;
      e.prepareLocalProxyAuth(const ConnectionOptions());
      final second = e.singboxApiSecret;

      expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(second, isNot(first));
    });

    test('секрет есть и без hysteria2 — обычный сервер тоже закрывает API', () {
      final e = _FakeEngine();
      e.prepareLocalProxyAuth(const ConnectionOptions());
      // Конфиг sing-box при этом не собирался вовсе — и это главное: раньше
      // ровно на этом пути секрет и оставался пустым.
      expect(e.singboxApiSecret, isNotEmpty);
    });
  });

  group('VpnEngineBase: запасные серверы', () {
    test('переход на запасной пересобирает конфиг через configFor', () async {
      // Это и есть смысл: у запасного может быть свой профиль панели, и
      // сборка «из полей» его потеряла бы.
      const panel = '{"outbounds":[{"tag":"proxy","protocol":"vless"}],'
          '"routing":{"balancers":[{"tag":"fallback-balancer"}]}}';
      final e = _FakeEngine();
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings()), [_server('a')]);
      e.fallbackServers = [_server('b', panelConfig: panel)];

      // Доводим до последней попытки, после которой берётся запасной. Между
      // обрывами снимаем ожидающую попытку: подряд идущие вызовы считаются
      // ОДНИМ обрывом и попыток не расходуют.
      for (var i = 0; i < VpnEngineBase.maxAttempts - 1; i++) {
        await e.scheduleRetry('обрыв');
        e.dropPendingRetry();
      }
      await e.scheduleRetry('обрыв');

      expect(e.session, isNotNull);
      expect(e.session!.configJson, contains('fallback-balancer'));
    });

    test('disconnect очищает список запасных', () async {
      final e = _FakeEngine();
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings()), [_server('a')]);
      e.fallbackServers = [_server('b')];

      await e.disconnect();
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings()), [_server('a')]);
      for (var i = 0; i < VpnEngineBase.maxAttempts; i++) {
        await e.scheduleRetry('обрыв');
      }

      // Сервер сессии не подменился запасным из прошлой сессии.
      expect(e.session!.servers.single.remark, 'a');
    });
  });

  // ── Реестр маскировки адресов ──────────────────────────────────────────────
  //
  // ⚠️ ЗАКРЫТАЯ ДВЕРЬ БЕЗ СТРАЖА ОТКРЫВАЕТСЯ ОБРАТНО МОЛЧА. Реестр
  // [SensitiveAddresses] наполняется из ПОДПИСКИ (`AppState._rebuild`), а там
  // лежит ИМЯ узла. В журнал же уезжает АДРЕС, полученный из этого имени: своей
  // строкой «беру прошлый адрес» и каждой строкой `dial tcp <адрес>:443` в логе
  // ядра, который целиком вкладывается в отчёт поддержки. Две регистрации в
  // `engine_base` (в момент резолва и при чтении кэша с диска) — единственное,
  // что связывает имя с адресом, и снять их можно было без единого красного
  // теста.
  //
  // Каждый тест ниже сначала показывает, ЧТО ПИСАЛ БЫ ЖУРНАЛ без регистрации
  // (та же строка через `scrubSecrets` до вызова — адрес виден целиком), и
  // только потом проверяет, что после вызова он замаскирован. Поэтому тест не
  // может позеленеть на пустом месте: «до» — это буквально поведение с
  // открытой дверью.
  group('VpnEngineBase: адрес сервера попадает в реестр маскировки', () {
    // Литерал в скобках — единственный способ получить УСПЕШНЫЙ резолв без
    // сети: `InternetAddress.tryParse` скобок не понимает (значит код идёт в
    // ветку `lookup`, ту самую, где стоит регистрация), а системный резолвер
    // отдаёт литерал обратно, не спрашивая DNS. Диапазон `2001:db8::/32` —
    // документационный (RFC 3849), реального узла за ним нет.
    const bracketHost = '[2001:db8::77]';
    const resolvedIp = '2001:db8::77';

    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_engine_resolve_');
      AppPaths.overrideRoot(tmp);
      // Реестр — глобальная статика процесса: адреса соседнего теста иначе
      // маскировали бы строки этого.
      SensitiveAddresses.forgetAllForTest();
    });

    tearDown(() async {
      // ⚠️ СНАЧАЛА даём догореть фоновой записи кэша (`_saveResolveCache`
      // уходит в `unawaited`), и только ПОТОМ снимаем подмену каталога:
      // незавершённая цепочка резолвит путь заново и получает настоящий
      // %APPDATA% — ровно так 14.08.2026 тестом переписали боевой
      // `subscriptions.json` владельца.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      // Запись кэша идёт на диск, а не в микрозадачу, поэтому одних тактов
      // цикла событий ей мало. Если и этого не хватит, ничего страшного не
      // случится: путь резолвится ДО записи, а `_saveResolveCache` глушит
      // собственные исключения — но и настоящий каталог данных ей уже не
      // отдадут (предохранитель `AppPaths`).
      await Future<void>.delayed(const Duration(milliseconds: 20));
      SensitiveAddresses.forgetAllForTest();
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('⚠️ отрезолвленный адрес маскируется в журнале', () async {
      expect(InternetAddress.tryParse(bracketHost), isNull,
          reason: 'предпосылка теста: скобки не разбираются как литерал, '
              'иначе `resolveServerHosts` вернёт адрес мимо ветки резолва');

      // Так выглядела бы строка лога ядра БЕЗ регистрации — то есть ровно то,
      // что уезжало в отчёт поддержки до закрытия двери.
      String coreLine() =>
          scrubSecrets('dial tcp $bracketHost:443: i/o timeout');
      expect(coreLine(), contains(resolvedIp),
          reason: 'до резолва реестр адреса не знает — это и есть дефект');

      final e = _FakeEngine();
      final hosts = await e.resolveServerHosts([_serverAt(bracketHost)]);
      expect(hosts[bracketHost], [resolvedIp],
          reason: 'предпосылка теста: резолв обязан удаться без сети');

      final line = coreLine();
      expect(line, isNot(contains(resolvedIp)),
          reason: 'адрес из резолва — тот же секрет, что и имя узла');
      expect(line, contains('адрес №'),
          reason: 'место узла обязано остаться видимым, иначе лог не разобрать');
      expect(line, contains(':443'), reason: 'порт не секрет и нужен для разбора');
    });

    test('⚠️ адрес из КЭША маскируется — кэш переживает перезапуск, реестр нет',
        () async {
      // Сценарий, ради которого кэш и заведён: DNS заблокирован системным
      // always-on, резолв провалился, берём прошлый адрес — и пишем об этом в
      // журнал. Реестр к этому моменту знает только ИМЯ узла из подписки.
      const cachedHost = 'ru7.node.example';
      const cachedIp = '198.51.100.7';
      File('${tmp.path}${Platform.pathSeparator}resolved_hosts.json')
          .writeAsStringSync(jsonEncode({
        cachedHost: [cachedIp]
      }));

      // Дословно строка `engine_base.resolveServerHosts` из ветки провала.
      String fallbackLine() => scrubSecrets(
          'Не удалось отрезолвить $cachedHost (таймаут), беру прошлый адрес '
          '($cachedIp) — это и спасает старт при системном always-on');
      expect(fallbackLine(), contains(cachedIp),
          reason: 'до чтения кэша реестр адреса не знает — это и есть дефект');

      final e = _FakeEngine();
      // Кэш поднимается с диска первым делом ЛЮБОГО резолва.
      await e.resolveServerHosts([_serverAt(bracketHost)]);

      final line = fallbackLine();
      expect(line, isNot(contains(cachedIp)),
          reason: 'иначе адрес утёк бы ровно в том случае, ради которого кэш '
              'и заведён');
      expect(line, contains('адрес №'));
    });
  });
}

/// Сервер с заданным АДРЕСОМ (в отличие от [_server], который выводит адрес из
/// имени): тестам резолва важен именно он.
VpnServer _serverAt(String address) => VpnServer(
      protocol: 'vless',
      remark: 'узел',
      address: address,
      port: 443,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'vless://x@$address:443#узел',
    );
