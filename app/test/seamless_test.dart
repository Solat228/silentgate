import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/api_ports.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/tunnel_health.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/engine/windows/tun/tun_router.dart';
import 'package:silentgate/engine/windows/windows_engine.dart';

/// ТРИ ПЕРЕКЛЮЧАТЕЛЯ БЕСШОВНОСТИ: ЧТО ОНИ РЕАЛЬНО ДЕЛАЮТ.
///
/// Наблюдение владельца: при VPN на роутере приложения не замечают
/// переподключения, при клиентском — рвутся звонки и загрузки. У роутера не
/// меняются ни адрес, ни таблица маршрутов: пакеты просто теряются, и TCP их
/// переотправляет. У нас же рвалось три вещи — гасились ядра, снимался и заново
/// поднимался TUN (а это моргание маршрута по умолчанию для ВСЕЙ машины) и
/// менялся внешний IP.
///
/// ⚠️ Чего эти тесты НЕ утверждают: живое TCP-соединение смену внешнего IP не
/// переживёт — удалённая сторона видит другой адрес, и звонок через сервер A не
/// продолжится через сервер B. Проверяется ровно одно: у машины не мигает сеть
/// там, где мигать нечему.
///
/// У каждого флага есть ветка «выключен → поведение ПРЕЖНЕЕ»: это путь отката,
/// и он обязан быть проверен наравне с новым поведением.

// ── Общее ───────────────────────────────────────────────────────────────────

VpnServer _serverAt(String address, String name) => VpnServer(
      protocol: 'vless',
      remark: name,
      // Адрес литеральный: резолв не имеет права ходить в сеть из теста.
      address: address,
      port: 443,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'vless://x@$address:443#$name',
    );

final _a = _serverAt('203.0.113.10', 'a');
final _b = _serverAt('198.51.100.7', 'b');

AppSettings _settings({
  bool seamlessServerSwitch = true,
  bool seamlessNetworkChange = true,
  bool seamlessKeepTun = true,
  bool killSwitch = false,
  bool autoReconnect = true,
}) =>
    AppSettings.defaults.copyWith(
      captureMode: CaptureMode.tun,
      autoReconnect: autoReconnect,
      killSwitch: killSwitch,
      seamlessServerSwitch: seamlessServerSwitch,
      seamlessNetworkChange: seamlessNetworkChange,
      seamlessKeepTun: seamlessKeepTun,
      splitTunnel: const SplitTunnelConfig(mode: SplitMode.all),
      // Сторож зависания и запасной DNS-форвардер к бесшовности отношения не
      // имеют, а таймер и открытый сокет прогону только мешают.
      tunWatchdogSeconds: 0,
      tunnelDnsForAll: false,
    );

/// Проба канала, которая отвечает заранее заданным ответом.
///
/// ⚠️ Настоящая ходит по трём внешним мишеням до 8 с на каждую — прогнать на
/// ней ветку «канал жив» нельзя ни за какое разумное время, да и сети в тесте
/// быть не должно.
class _FakeHealth extends TunnelHealth {
  _FakeHealth(this.alive) : super(proxyPort: 1);
  final bool alive;
  int probes = 0;

  @override
  Future<bool> probeOnce() async {
    probes++;
    return alive;
  }
}

class _FakeEngine extends VpnEngineBase {
  /// Подменяет ответ платформы «туннель сейчас поднят» — своего TUN у фейка нет.
  bool liveCaptureKeptForTest = false;

  @override
  bool get liveCaptureKept => liveCaptureKeptForTest;

  int startCalls = 0;
  final List<bool> keepCaptureLog = [];

  /// Чем отвечает сквозная проба канала.
  bool channelAlive = true;
  int probeCalls = 0;

  @override
  Future<void> startSession() async {
    startCalls++;
    final gen = newGeneration();
    if (isStale(gen)) return;
    markConnected();
    setStatus(VpnConnectionState.connected);
  }

  @override
  TunnelHealth createHealthProbe({
    required int proxyPort,
    required String proxyUser,
    required String proxyPassword,
  }) {
    probeCalls++;
    return _FakeHealth(channelAlive);
  }

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {
    keepCaptureLog.add(keepCapture);
  }

  @override
  Future<void> platformCleanup() async {}
}

/// Подключённый движок, у которого grace-период смены сети уже позади.
///
/// Без сдвига момента подключения ветка «смена сети» недостижима вовсе:
/// первые [VpnEngineBase.networkGrace] секунд событие игнорируется как
/// подъём собственного туннеля.
Future<_FakeEngine> _connected(AppSettings s) async {
  final e = _FakeEngine();
  await e.connectWith(
      '{}', ConnectionOptions(settings: s), [_a]);
  e.debugSetConnectedAt(
      DateTime.now().subtract(VpnEngineBase.networkGrace * 2));
  return e;
}

/// TUN-роутер, который ничего не поднимает, но помнит обращения.
class _FakeTunRouter implements TunRouter {
  _FakeTunRouter(this.log);
  final List<String> log;
  int starts = 0;
  int stops = 0;

  @override
  Future<void> start(SplitTunnelConfig split,
      {required int xraySocksPort,
      required TunOptions options,
      void Function(String message)? onProgress,
      bool Function()? abort,
      List<Map<String, dynamic>> exitOutbounds = const [],
      String xraySocksUser = '',
      String xraySocksPassword = '',
      List<String> apiExitServerKeys = const [],
      List<String> apiOnlyExitKeys = const [],
      String apiToken = ''}) async {
    starts++;
    log.add('start');
  }

  @override
  Future<void> stop() async {
    stops++;
    log.add('stop');
  }
}

void main() {
  // ── 1. Смена сервера не пересоздаёт туннель ───────────────────────────────
  //
  // Конфиг TUN запекал адрес ВЫБРАННОГО сервера в правило «мимо туннеля»,
  // поэтому смена сервера меняла конфиг — а значит требовала stop→start всего
  // туннеля. Если адреса всех кандидатов лежат в правиле заранее, конфиг
  // перестаёт зависеть от выбора.
  group('Смена сервера: конфиг TUN', () {
    late Directory tmp;

    setUp(() {
      // Резолв читает кэш адресов с диска — в боевой %APPDATA% тесту нельзя.
      tmp = Directory.systemTemp.createTempSync('sg_seamless_cfg_');
      AppPaths.overrideRoot(tmp);
    });

    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// Конфиг туннеля так, как его собрал бы `raiseTun`: тот же вход
    /// (`tunnelBypassIps` по серверам сессии) и тот же построитель.
    ///
    /// Движок передаётся снаружи, потому что часть проверок — про ПАМЯТЬ одного
    /// и того же движка между двумя подъёмами.
    Future<String> tunCfgOf(
        _FakeEngine e, List<VpnServer> sessionServers, AppSettings s) async {
      final ips = await e.tunnelBypassIps(
          await e.resolveServerHosts(sessionServers), s);
      return SingboxConfigBuilder(
        options: TunOptions.fromSettings(s, serverIps: ips),
      ).buildJson(s.splitTunnel);
    }

    /// Готовый конфиг туннеля для сессии с сервером [selected] при тех же
    /// кандидатах. Сравнивается именно он — целиком, а не перечень полей:
    /// решение «не перезапускать» строится ровно на побайтовом совпадении.
    Future<String> configFor(VpnServer selected, AppSettings s) async {
      final e = _FakeEngine()..fallbackServers = [_a, _b];
      return tunCfgOf(e, [selected], s);
    }

    test('⚠️ конфиг ПОБАЙТНО тот же при смене выбранного сервера', () async {
      final s = _settings();
      expect(await configFor(_a, s), await configFor(_b, s),
          reason: 'на побайтовом совпадении и держится решение «туннель не '
              'пересоздавать» — разойдись хоть один байт, и маршрут по '
              'умолчанию снова замигает');
    });

    test('выключенный флаг оставляет прежний конфиг — свой на каждый сервер',
        () async {
      final s = _settings(seamlessServerSwitch: false);
      expect(await configFor(_a, s), isNot(await configFor(_b, s)),
          reason: 'путь отката: конфиг снова зависит от выбранного сервера');
    });

    test('адреса кандидатов реально попали в правило «мимо туннеля»', () async {
      // Без этого «конфиги совпали» означало бы всего лишь, что из правила
      // выпали ОБА адреса, — то есть защиту от петли сняли.
      final cfg = await configFor(_a, _settings());
      expect(cfg, contains('203.0.113.10/32'));
      expect(cfg, contains('198.51.100.7/32'));
    });

    test('⚠️ переход на ЗАПАСНОЙ сервер конфиг не меняет', () async {
      // Единственный путь, на котором переиспользование живого туннеля сегодня
      // вообще достижимо (ручная смена сервера идёт через `disconnect()`, а он
      // туннель снимает). И ровно на нём набор адресов УМЕНЬШАЛСЯ: движок
      // берёт следующего запасного через `_fallbacks.removeAt(0)` и кладёт в
      // сессию только его одного — значит и сервер, с которого ушли, и
      // вычеркнутые кандидаты из расчёта пропадали.
      final s = _settings();
      final e = _FakeEngine()..fallbackServers = [_a, _b];

      // Первый подъём: сессия — сервер A, в запасе оба кандидата.
      final before = await tunCfgOf(e, [_a], s);

      // Попытки на A исчерпаны, движок дошёл до конца цепочки: сессия — B,
      // запас пуст (обоих уже вычеркнули).
      e.fallbackServers = const [];
      final after = await tunCfgOf(e, [_b], s);

      expect(after, before,
          reason: 'иначе туннель пересоздаётся именно там, где переключатель '
              'обещает обратное: на переходе между серверами');
    });

    test('⚠️ СМЕНА СОСТАВА подписки обнуляет накопленные адреса', () async {
      // Правило «мимо туннеля» выпускает трафик к этим адресам МИМО VPN.
      // Сервер УДАЛЁННОЙ подписки, оставшийся в нём навсегда, — это тихая дыра,
      // а не мелкая неточность.
      //
      // ⚠️ Раньше чистка стояла на КАЖДОЙ команде подключения — и ломала ровно
      // то, ради чего писалась бесшовность: смена сервера пересобирала список с
      // нуля, а резолв в жизни неполон (на стенде из 15 серверов в кэше
      // оказывалось 2), поэтому набор адресов «дышал» и туннель пересоздавался
      // всегда. Опасность снимает смена СОСТАВА кандидатов, а не факт нажатия.
      final s = _settings();
      final e = _FakeEngine()..bypassCandidates = [_a];
      await e.tunnelBypassIps(await e.resolveServerHosts([_a]), s);

      // Подписку сменили: состав кандидатов другой.
      e.bypassCandidates = [_b];
      final ips = await e.tunnelBypassIps(await e.resolveServerHosts([_b]), s);
      expect(ips, ['198.51.100.7'],
          reason: 'адрес чужой подписки (203.0.113.10) обязан уйти');
    });

    test('⚠️ смена ВЫБРАННОГО сервера накопленное НЕ обнуляет', () async {
      // Это и есть условие переиспользования туннеля: состав тот же, значит и
      // конфиг обязан получиться тот же — даже если очередной резолв вернул
      // меньше адресов, чем прошлый.
      final s = _settings();
      final e = _FakeEngine()..bypassCandidates = [_a, _b];
      final first = await e.tunnelBypassIps(await e.resolveServerHosts([_a]), s);

      await e.connectWith('{}', ConnectionOptions(settings: s), [_b]);
      e.bypassCandidates = [_a, _b]; // тот же состав — как при смене сервера
      final second = await e.tunnelBypassIps(await e.resolveServerHosts([_b]), s);

      expect(second, first,
          reason: 'ЗДЕСЬ ЛОМАЛАСЬ БЕСШОВНОСТЬ: список пересобирался с нуля и '
              'конфиг менялся на ровном месте');
    });

    test('⚠️ РУЧНОЙ ВЫБОР: список не зависит от того, кто выбран сейчас', () async {
      // ⚠️ ЗДЕСЬ ЖИЛ ДЕФЕКТ, КОТОРЫЙ ПОЙМАЛ ТОЛЬКО ЖИВОЙ ПРОГОН (VM, 17.08.2026).
      // Механизм «не пересоздавать туннель» был написан и проходил тесты, а в
      // бою не включался НИ РАЗУ: в журнале при каждой смене сервера снова шёл
      // «TUN автоподбор», строки «Туннель не пересоздаю» не было вовсе.
      //
      // Причина: `fallbackServers` в ручном режиме НАМЕРЕННО пуст (подменять
      // выбор человека нельзя), поэтому правило обхода знало ровно один адрес —
      // выбранного сервера. Сменил сервер — сменился и список, а значит и
      // конфиг, и сверка честно уходила в пересоздание. То есть пункт не
      // работал в самом частом режиме.
      //
      // Лечение — отдельное понятие `bypassCandidates`: «чьи адреса обязаны
      // идти мимо туннеля» ≠ «на кого можно переключиться при сбое».
      final s = _settings();
      final e = _FakeEngine()
        ..fallbackServers = const []
        ..bypassCandidates = [_a, _b];

      final onA = await e.tunnelBypassIps(await e.resolveServerHosts([_a]), s);
      await e.connectWith('{}', ConnectionOptions(settings: s), [_b]);
      e.bypassCandidates = [_a, _b];
      final onB = await e.tunnelBypassIps(await e.resolveServerHosts([_b]), s);

      expect(onA, onB,
          reason: 'состав адресов обязан совпадать при любом выбранном '
              'сервере — иначе конфиг меняется и туннель пересоздаётся');
      expect(onA, ['198.51.100.7', '203.0.113.10']);
    });

    test('выключенный флаг возвращает ПРЕЖНИЙ узкий список', () async {
      // Путь отката: без бесшовности правило содержит ровно серверы сессии, как
      // и было до всей этой работы.
      final s = _settings(seamlessServerSwitch: false);
      final e = _FakeEngine()..bypassCandidates = [_a, _b];
      final ips = await e.tunnelBypassIps(await e.resolveServerHosts([_a]), s);
      expect(ips, ['203.0.113.10']);
    });

    test('порядок адресов не «дышит»: список отсортирован', () async {
      // Порядок приходит от резолва и от порядка серверов в подписке (а тот
      // меняется от закрепления). Без сортировки туннель пересоздавался бы на
      // ровном месте — при том же самом содержимом правила.
      final e = _FakeEngine()..fallbackServers = [_b, _a];
      final ips =
          await e.tunnelBypassIps(await e.resolveServerHosts([_b]), _settings());
      expect(ips, ['198.51.100.7', '203.0.113.10']);
    });
  });

  group('Смена сервера: живой туннель', () {
    late Directory tmp;
    late List<String> log;
    late _FakeTunRouter router;
    late WindowsEngine engine;

    /// Отвечает ли туннельное ядро по своему API (см. `tunAliveForTest`).
    late bool tunAlive;

    setUp(() {
      tunAlive = true;
      tmp = Directory.systemTemp.createTempSync('sg_seamless_tun_');
      AppPaths.overrideRoot(tmp);
      log = [];
      router = _FakeTunRouter(log);
      // ⚠️ recoverSystemProxy: false — маркер «прокси ставили мы» лежит в
      // системном %TEMP% мимо AppPaths, и без этого тест снял бы системный
      // прокси у РАБОТАЮЩЕГО приложения владельца.
      engine = WindowsEngine(tunRouter: router, recoverSystemProxy: false);
      engine.adapterDnsForTest = () => const ['192.168.1.1'];
      engine.dnsReachableForTest = (_) async => true;
      // Туннеля в тесте нет, отвечать по API некому — подменяем сам вопрос.
      engine.tunAliveForTest = () async => tunAlive;
    });

    tearDown(() async {
      await engine.dispose();
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<bool> raise(AppSettings s, int gen) => engine.raiseTun(
          options: ConnectionOptions(settings: s),
          servers: [_a],
          apiKeys: const [],
          aborted: () => false,
          gen: gen,
        );

    test('⚠️ повторный подъём с тем же конфигом туннель не трогает', () async {
      final s = _settings();
      expect(await raise(s, 1), isTrue);
      log.clear();

      expect(await raise(s, 2), isTrue);

      expect(log, isEmpty,
          reason: 'снять и поднять TUN — значит на секунду убрать маршрут по '
              'умолчанию: рвётся и то, что шло мимо VPN');
      expect(router.starts, 1);
      expect(engine.tunActive, isTrue);
    });

    test('⚠️ СМЕНА СЕРВЕРА: растущий кэш адресов туннель не пересоздаёт',
        () async {
      // ⚠️ ЗДЕСЬ ЖИЛ ПОСЛЕДНИЙ СЛОЙ #30, И ПОЙМАЛ ЕГО ТОЛЬКО ЖИВОЙ ПРОГОН.
      // Мягкое отключение и порты были уже починены, а строки «Туннель не
      // пересоздаю» в журнале не появлялось НИ РАЗУ. Причина: список адресов
      // «мимо туннеля» РАСТЁТ сам по себе — имена резолвятся не все и не сразу
      // (в прогоне 18.08.2026 в кэше оказалось 10 имён из 15), кэш пополняется
      // между подключениями. Сверка конфига побайтная, поэтому любой лишний
      // адрес уводил в пересоздание.
      //
      // Теперь, пока туннель жив, конфиг строится с ЕГО списком адресов.
      final s = _settings();
      expect(await raise(s, 1), isTrue);
      log.clear();

      // Имитируем пополнение кэша: у движка появился ещё один известный сервер.
      engine.bypassCandidates = [_a, _b];

      expect(await raise(s, 2), isTrue);
      expect(log, isEmpty,
          reason: 'ЗДЕСЬ ТУННЕЛЬ ПЕРЕСОЗДАВАЛСЯ: список адресов вырос, конфиг '
              'перестал совпадать, и маршрут по умолчанию мигал на каждой '
              'смене сервера');
      expect(router.starts, 1);
    });

    test('⚠️ адрес нового сервера не покрыт — туннель ОБЯЗАН пересоздаться',
        () async {
      // Условие безопасности: правило `ip_cidr → direct` не даёт трафику
      // прокси-ядра к своему серверу зайти обратно в туннель. Отдать живой
      // список, в котором нового сервера нет, значило бы завести петлю —
      // экономия на пересоздании тут недопустима.
      final s = _settings();
      expect(await raise(s, 1), isTrue);
      log.clear();

      final ok = await engine.raiseTun(
        options: ConnectionOptions(settings: s),
        servers: [_b], // другой сервер, его адреса в живом правиле нет
        apiKeys: const [],
        aborted: () => false,
        gen: 2,
      );
      expect(ok, isTrue);
      expect(log, ['stop', 'start'],
          reason: 'петля важнее плавности: непокрытый адрес = пересоздание');
    });

    test('выключенный флаг пересоздаёт туннель, как раньше', () async {
      final s = _settings(seamlessServerSwitch: false);
      expect(await raise(s, 1), isTrue);
      log.clear();

      expect(await raise(s, 2), isTrue);

      expect(log, ['stop', 'start'], reason: 'путь отката');
    });

    test('изменившийся конфиг туннель пересоздаёт даже при включённом флаге',
        () async {
      expect(await raise(_settings(), 1), isTrue);
      log.clear();

      // Меняем то, что уезжает в конфиг туннеля (список «в туннель только эти
      // подсети»), — держать старый туннель здесь означало бы молча не
      // применить настройку.
      final other = _settings()
          .copyWith(tunRouteOnlyCidrs: const ['104.16.0.0/12']);
      expect(await raise(other, 2), isTrue);

      expect(log, ['stop', 'start']);
    });

    test('⚠️ молчащий туннель НЕ выдаётся за живой, а пересоздаётся', () async {
      // Хелпер упал — Windows убрала адаптер сама и нам не сказала: флаг
      // `_tunActive` остался поднятым. Переиспользовать его вслепую значило бы
      // показать «Подключено» машине без единого маршрута.
      final s = _settings();
      expect(await raise(s, 1), isTrue);
      log.clear();
      tunAlive = false;

      expect(await raise(s, 2), isTrue);

      expect(log, ['stop', 'start']);
    });

    test('после снятия туннеля память о конфиге не воскрешает несуществующий',
        () async {
      final s = _settings();
      expect(await raise(s, 1), isTrue);
      // Полное отключение: туннеля больше нет.
      await engine.teardownCore();
      expect(engine.tunActive, isFalse);
      log.clear();

      expect(await raise(s, 2), isTrue);

      expect(log, ['start'],
          reason: 'иначе приложение показало бы «Подключено» без единого '
              'маршрута — туннель считался бы поднятым, потому что совпал '
              'конфиг ПРОШЛОГО');
    });
  });

  // ── 2. Смена сети не рвёт живой канал ─────────────────────────────────────
  //
  // У hysteria2 транспорт QUIC, а он умеет миграцию соединения при смене
  // адреса: Wi-Fi→LTE переживает САМ. Перезапуск ядра по событию NetworkWatcher
  // убивал именно эту возможность.
  group('Смена сети', () {
    test('⚠️ живой канал переподключением не трогаем', () async {
      final e = await _connected(_settings());
      e.channelAlive = true;

      await e.onNetworkChanged();

      expect(e.keepCaptureLog, isEmpty,
          reason: 'ядро не гасили — значит и все живые сессии целы');
      expect(e.startCalls, 1, reason: 'ни одной новой попытки подключения');
    });

    test('мёртвый канал переподключается, как раньше', () async {
      final e = await _connected(_settings());
      e.channelAlive = false;

      await e.onNetworkChanged();

      expect(e.keepCaptureLog, hasLength(1),
          reason: 'проба не прошла — возвращаемся к прежнему поведению');
      e.dropPendingRetry();
    });

    test('выключенный флаг переподключается БЕЗ пробы', () async {
      final e = await _connected(_settings(seamlessNetworkChange: false));
      // Канал заведомо жив — и это ничего не меняет: путь отката спрашивать
      // никого не должен.
      e.channelAlive = true;

      await e.onNetworkChanged();

      expect(e.probeCalls, 0);
      expect(e.keepCaptureLog, hasLength(1));
      e.dropPendingRetry();
    });

    test('grace-период по-прежнему главнее пробы', () async {
      // Первая линия защиты от вечного цикла: подъём собственного туннеля сам
      // выглядит как «смена сети». Спрашивать пробу там незачем.
      final e = _FakeEngine();
      await e.connectWith(
          '{}', ConnectionOptions(settings: _settings()), [_a]);

      await e.onNetworkChanged();

      expect(e.probeCalls, 0);
      expect(e.keepCaptureLog, isEmpty);
    });
  });

  // ── 3. TUN не мигает между попытками ──────────────────────────────────────
  group('Удержание туннеля между попытками', () {
    test('⚠️ захват удерживается и без kill switch', () async {
      final e = _FakeEngine();
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings(killSwitch: false)), [_a]);

      expect(await e.scheduleRetry('обрыв'), isTrue);

      expect(e.keepCaptureLog, [true],
          reason: 'снятый и заново поднятый TUN дёргает маршрут по умолчанию — '
              'это заметнее самого разрыва');
      e.dropPendingRetry();
    });

    test('выключенный флаг снимает захват между попытками, как раньше',
        () async {
      final e = _FakeEngine();
      await e.connectWith(
          '{}',
          ConnectionOptions(
              settings: _settings(seamlessKeepTun: false, killSwitch: false)),
          [_a]);

      expect(await e.scheduleRetry('обрыв'), isTrue);

      expect(e.keepCaptureLog, [false], reason: 'путь отката');
      e.dropPendingRetry();
    });

    test('⚠️ ЭТО НЕ KILL SWITCH: попытки кончаются и блокировку не обещают',
        () async {
      // Разные обещания. Kill switch держит трафик до вмешательства человека и
      // ГОВОРИТ об этом («трафик заблокирован»). «Не мигать сетью» всего лишь
      // не пересоздаёт интерфейс между попытками: когда попытки кончатся,
      // вызывающий сходит в cleanup() и захват снимется.
      final e = _FakeEngine();
      await e.connectWith('{}',
          ConnectionOptions(settings: _settings(killSwitch: false)), [_a]);

      var scheduled = 0;
      for (var i = 0; i < VpnEngineBase.maxAttempts + 3; i++) {
        if (await e.scheduleRetry('обрыв')) scheduled++;
        e.dropPendingRetry();
      }

      expect(scheduled, VpnEngineBase.maxAttempts,
          reason: 'бесконечные попытки — обещание kill switch, а не этого '
              'переключателя');
      expect(e.status.blocking, isFalse,
          reason: 'плашка «трафик заблокирован» обещает защиту, которую '
              'пользователь здесь не включал');
    });

    test('kill switch продолжает удерживать захват сам по себе', () async {
      // Страж на случай, если удержание однажды «оптимизируют» до одного флага.
      final e = _FakeEngine();
      await e.connectWith(
          '{}',
          ConnectionOptions(
              settings: _settings(killSwitch: true, seamlessKeepTun: false)),
          [_a]);

      expect(await e.scheduleRetry('обрыв'), isTrue);

      expect(e.keepCaptureLog, [true]);
      e.dropPendingRetry();
    });
  });
  group('Порты переиспользуемого туннеля (BACKLOG #30)', () {
    // ⚠️ ПОЙМАНО ЖИВЫМ ПРОГОНОМ 18.08.2026, юнит-тесты этого не видели.
    // Мягкое отключение впервые сохранило туннель (в журнале нет ни строки
    // «TUN автоподбор») — и тут же подключение упало: «Порт 10819 ещё занят
    // нашим ядром (sing-box.exe) от прошлой сессии». Порт «Прямо» и порты
    // выходов поднимает ТОТ ЖЕ туннельный sing-box, который мы намеренно
    // оставляем жить. Требовать их свободы значит требовать смерти туннеля.
    const ports = XrayPorts(socks: 10808, http: 10809, api: 10085);

    AppSettings withExits() => AppSettings(
          captureMode: CaptureMode.tun,
          apiEnabled: true,
          apiToken: 'x' * 16,
          apiExitServerKeys: ['k1'],
        );

    test('⚠️ ГЛАВНОЕ: туннель остаётся — его порты не проверяем', () {
      final checked = WindowsEngine.corePortsFor(withExits(), ports,
          tunnelStaysUp: true);
      expect(checked, isNot(contains(ApiPorts.direct)),
          reason: 'ЗДЕСЬ ПАДАЛА СМЕНА СЕРВЕРА: 10819 держит сам туннель, '
              'который никуда не уходит');
    });

    test('туннель пересоздаётся — порты обязаны быть свободны', () {
      final checked = WindowsEngine.corePortsFor(withExits(), ports,
          tunnelStaysUp: false);
      expect(checked, contains(ApiPorts.direct),
          reason: 'иначе новый туннель молча не поднимет порт «Прямо»');
    });

    test('порты прокси-ядра проверяются ВСЕГДА', () {
      // Их держит ядро, которое как раз гасится и поднимается заново — вот там
      // конфликт настоящий, и пропускать его нельзя.
      for (final stays in [true, false]) {
        final checked = WindowsEngine.corePortsFor(withExits(), ports,
            tunnelStaysUp: stays);
        expect(checked, containsAll([10808, 10809, 10085]),
            reason: 'tunnelStaysUp=$stays');
      }
    });
  });

  group('Креды живого захвата (последний слой #30)', () {
    // ⚠️ ЭТО НАШЛОСЬ ТОЛЬКО ТОГДА, КОГДА ДВИЖОК САМ НАЗВАЛ ПОЛЕ.
    // Четыре гипотезы подряд были мимо; сверка конфигов на стенде выдала
    // `config.outbounds[0].password`. Пароль локального прокси выдаётся заново
    // на КАЖДОЕ подключение и уезжает в конфиг ТУННЕЛЯ (тот ходит в прокси-ядро
    // с этими кредами) — поэтому побайтная сверка не совпадала никогда.
    //
    // ⚠️ И почему нельзя чинить это при сборке конфига туннеля: креды выдаются
    // ДО сборки конфига прокси-ядра. Оставить туннелю старый пароль, а ядро
    // поднять с новым — 407 на каждом запросе: туннель жив, «Подключено»
    // горит, трафик не идёт (ровно этот отказ уже был в 1.3.0).

    test('⚠️ ГЛАВНОЕ: живой захват — пароль НЕ перевыдаётся', () {
      final e = _FakeEngine()..liveCaptureKeptForTest = false;
      e.applyLocalProxyAuth(_settings(), systemProxyMode: false);
      final first = e.localInboundPassword;
      expect(first, isNotEmpty);

      e.liveCaptureKeptForTest = true;
      e.applyLocalProxyAuth(_settings(), systemProxyMode: false);
      expect(e.localInboundPassword, first,
          reason: 'ЗДЕСЬ ЛОМАЛОСЬ ВСЁ: новый пароль менял конфиг туннеля, и '
              'переиспользование не включалось ни разу');
    });

    test('захвата нет — пароль выдаётся заново, как раньше', () {
      final e = _FakeEngine()..liveCaptureKeptForTest = false;
      e.applyLocalProxyAuth(_settings(), systemProxyMode: false);
      final first = e.localInboundPassword;
      e.applyLocalProxyAuth(_settings(), systemProxyMode: false);
      expect(e.localInboundPassword, isNot(first),
          reason: 'секрет на сессию — прежнее и правильное поведение');
    });

    test('выключенная бесшовность пароль тоже перевыдаёт (путь отката)', () {
      final e = _FakeEngine()..liveCaptureKeptForTest = true;
      e.applyLocalProxyAuth(_settings(), systemProxyMode: false);
      final first = e.localInboundPassword;
      e.applyLocalProxyAuth(_settings(seamlessServerSwitch: false),
          systemProxyMode: false);
      expect(e.localInboundPassword, isNot(first));
    });
  });

}
