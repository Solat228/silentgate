import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/net/dns_fallback_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/engine/windows/tun/tun_router.dart';
import 'package:silentgate/engine/windows/windows_engine.dart';

/// ДВЕ ЗАЩИТЫ WINDOWS-ДВИЖКА, КОТОРЫЕ ДО СИХ ПОР НЕ СТЕРЁГ НИКТО.
///
/// Обе написаны верно и обе снимались бы молча: ревьюер убрал разом гейт
/// устаревшего запуска в `_startFallbackDns`, проверку владельца в
/// `_releaseOwnFallbackDns` и оба места забывания `_lastDirectDns` — и весь
/// набор тестов остался зелёным. Пока это так, следующий агент снимет их так же
/// молча, как снимали до сих пор.
///
/// ## 1. Форвардер принадлежит ЗАПУСКУ, а не полю
///
/// Запасной DNS-форвардер поднимается ВНУТРИ подготовки туннеля ([raiseTun]) —
/// то есть после нескольких await'ов: резолва серверов и UDP-опроса DNS
/// адаптера (до 2 с на адрес). За это время запуск успевает устареть, а поле
/// `_fallbackDns` — принадлежать уже НОВОЙ, живой сессии. Устаревший запуск,
/// который «просто прибирает за собой» по содержимому поля, гасит чужой
/// форвардер, а свой оставляет слушать порт навсегда. У живой сессии при этом
/// `dns.final` указывает на порт, которого больше нет: при включённом «весь DNS
/// через туннель» имена перестают резолвиться у ВСЕХ приложений, и само это не
/// чинится.
///
/// ## 2. Память о резолвере «Прямо» живёт ровно одну сеть
///
/// `_lastDirectDns` заведён намеренно: определение резолвера идёт, пока старый
/// туннель ещё держит трафик (иначе kill switch выпускал бы его на всё время
/// подготовки), и под этим туннелем UDP-проба может не пройти. Но резолвер
/// привязан к сети целиком — `192.168.1.1` дома, `10.0.0.1` в офисе, адрес
/// оператора в мобильной. А самый частый путь сюда — ПЕРЕПОДКЛЮЧЕНИЕ ПО СМЕНЕ
/// СЕТИ, где проба вполне может не пройти (адаптер только поднялся). Отдать там
/// домашний адрес значит прописать ядру резолвер, которого в этой сети нет: он
/// не ответит никогда, и каждый домен с правилом «Прямо» перестанет
/// открываться. `null` честно откатывает на системный резолвер.
///
/// Проверяется всё это через `raiseTun` — единственную точку, где логика
/// подъёма отделена от живого ядра, реальных сокетов и прав администратора.
/// `startSession` целиком в тесте не поднять, и это осознанная граница.

/// TUN-роутер, который ничего не поднимает, но умеет «зависнуть» в подъёме —
/// как настоящий автоподбор стека и MTU (до двух минут).
class _FakeTunRouter implements TunRouter {
  int starts = 0;
  int stops = 0;
  bool up = false;

  /// Опции ПОСЛЕДНЕГО подъёма — то, что реально уехало бы ядру.
  TunOptions? lastOptions;

  /// Вызывается внутри `start`, до его завершения.
  Future<void> Function(int call)? onStart;

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
    lastOptions = options;
    await onStart?.call(starts);
    up = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    up = false;
  }
}

void main() {
  late Directory tmp;
  late _FakeTunRouter router;
  late WindowsEngine engine;

  /// Что сейчас «видно» на адаптерах и отвечает ли оно. Хуки подменяют РОВНО
  /// два внешних шага — список адресов (Windows API) и UDP-пробу; разбор,
  /// включая память о прошлом рабочем резолвере, остаётся настоящим кодом.
  late List<String> adapterDns;
  late bool dnsAnswers;

  /// Чем задержать ПЕРВЫЙ вопрос «отвечает ли резолвер»: это и есть тот долгий
  /// await (до 2 с на адрес), за который запуск успевает устареть.
  Completer<void>? holdFirstProbe;
  Completer<void>? firstProbeReached;

  final servers = [
    const VpnServer(
      protocol: 'vless',
      remark: 'a',
      // Адрес литеральный: резолв не должен ходить в сеть.
      address: '203.0.113.10',
      port: 443,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'vless://x@203.0.113.10:443#a',
    ),
  ];

  ConnectionOptions optionsWith({required bool fallbackDns}) => ConnectionOptions(
        settings: AppSettings.defaults.copyWith(
          captureMode: CaptureMode.tun,
          // Сторож зависания к делу не относится, а таймер прогону мешает.
          tunWatchdogSeconds: 0,
          // Форвардер поднимается ТОЛЬКО при этой галочке.
          tunnelDnsForAll: fallbackDns,
          splitTunnel: const SplitTunnelConfig(mode: SplitMode.all),
        ),
      );

  Future<bool> raise({required int gen, required bool Function() aborted, bool fallbackDns = false}) =>
      engine.raiseTun(
        options: optionsWith(fallbackDns: fallbackDns),
        servers: servers,
        apiKeys: const [],
        aborted: aborted,
        gen: gen,
      );

  setUp(() {
    // Изолированный каталог данных: резолв читает кэш адресов с диска, а журнал
    // пишется файлом — в боевой %APPDATA%\SilentGate тесту лезть нельзя.
    tmp = Directory.systemTemp.createTempSync('sg_win_guards_');
    AppPaths.overrideRoot(tmp);
    router = _FakeTunRouter();
    // ⚠️ recoverSystemProxy: false — маркер «прокси ставили мы» лежит в
    // системном %TEMP% мимо AppPaths, и без этого создание движка в тесте сняло
    // бы системный прокси у РАБОТАЮЩЕГО приложения владельца.
    engine = WindowsEngine(tunRouter: router, recoverSystemProxy: false);
    adapterDns = ['192.168.1.1'];
    dnsAnswers = true;
    holdFirstProbe = null;
    firstProbeReached = null;
    engine.adapterDnsForTest = () => List<String>.from(adapterDns);
    engine.dnsReachableForTest = (ip) async {
      final hold = holdFirstProbe;
      if (hold != null) {
        holdFirstProbe = null;
        firstProbeReached?.complete();
        await hold.future;
      }
      return dnsAnswers;
    };
  });

  tearDown(() async {
    await engine.dispose();
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Запасной DNS-форвардер: чей он', () {
    test('устаревший запуск не гасит и не подменяет форвардер живой сессии',
        () async {
      // Запуск №1 уходит в опрос DNS адаптера и застревает там — ровно тот
      // длинный await, за который пользователь успевает отключиться и
      // подключиться снова.
      final reached = firstProbeReached = Completer<void>();
      final release = Completer<void>();
      holdFirstProbe = release;

      var staleFirst = false;
      final first = raise(gen: 1, aborted: () => staleFirst, fallbackDns: true);
      await reached.future;
      expect(engine.fallbackDns, isNull, reason: 'до пробы поднимать нечего');

      // Новый запуск: он живой, он поднял СВОЙ форвардер и теперь им владеет.
      staleFirst = true;
      expect(await raise(gen: 2, aborted: () => false, fallbackDns: true), isTrue);
      final DnsFallbackServer? live = engine.fallbackDns;
      expect(live, isNotNull, reason: 'живая сессия форвардер не подняла — '
          'дальше проверять нечего');
      expect(live!.isRunning, isTrue);
      final livePort = live.port;
      expect(livePort, greaterThan(0));

      // И только теперь запуск №1 возвращается из пробы и доходит до
      // запасного DNS, будучи уже устаревшим.
      release.complete();
      expect(await first, isFalse);

      expect(engine.fallbackDns, same(live),
          reason: 'устаревший запуск подменил форвардер живой сессии: '
              'её dns.final смотрит на порт, которого больше нет');
      expect(live.isRunning, isTrue,
          reason: 'форвардер живой сессии погашен чужим запуском — при '
              '«весь DNS через туннель» имена перестанут резолвиться у всех '
              'приложений, и само это не починится');
      expect(live.port, livePort);
    });

    test('устаревший запуск, вернувшийся из подъёма, не гасит чужой форвардер',
        () async {
      // Запуск №1 успевает поднять свой форвардер и застревает в подъёме
      // туннеля (автоподбор стека идёт до двух минут).
      final reached = Completer<void>();
      final release = Completer<void>();
      DnsFallbackServer? ownOfFirst;
      router.onStart = (call) async {
        if (call != 1) return;
        ownOfFirst = engine.fallbackDns;
        reached.complete();
        await release.future;
      };

      var staleFirst = false;
      final first = raise(gen: 1, aborted: () => staleFirst, fallbackDns: true);
      await reached.future;
      expect(ownOfFirst, isNotNull);

      // Новый запуск: он законно снимает осиротевший форвардер из поля и
      // ставит туда свой — поле теперь принадлежит ЕМУ.
      staleFirst = true;
      expect(await raise(gen: 2, aborted: () => false, fallbackDns: true), isTrue);
      final live = engine.fallbackDns;
      expect(live, isNotNull);
      expect(live, isNot(same(ownOfFirst)));
      expect(live!.isRunning, isTrue);

      // Запуск №1 возвращается из подъёма и сворачивается.
      release.complete();
      expect(await first, isFalse);

      expect(engine.fallbackDns, same(live),
          reason: 'устаревший запуск снял форвардер живой сессии');
      expect(live.isRunning, isTrue,
          reason: 'форвардер живой сессии погашен по содержимому поля, а не '
              'по владельцу');
    });

    test('свой форвардер устаревший запуск за собой гасит', () async {
      // Противовес двум предыдущим: «никогда никого не трогать» — не решение.
      // Форвардер слушает UDP-порт на петле, и брошенный никем не снимается.
      final reached = Completer<void>();
      final release = Completer<void>();
      DnsFallbackServer? own;
      router.onStart = (call) async {
        own = engine.fallbackDns;
        reached.complete();
        await release.future;
      };

      var stale = false;
      final run = raise(gen: 1, aborted: () => stale, fallbackDns: true);
      await reached.future;
      expect(own, isNotNull);
      expect(own!.isRunning, isTrue);

      // Пользователь отключился, пока шёл подбор стека. Чужого здесь нет —
      // всё, что поднято, поднял этот запуск.
      stale = true;
      release.complete();
      expect(await run, isFalse);

      expect(own!.isRunning, isFalse,
          reason: 'брошенный форвардер остался слушать UDP-порт при '
              'выключенном VPN, а его туннельный путь ведёт в мёртвое ядро — '
              'каждый запрос уходил бы к резолверу провайдера');
      expect(engine.fallbackDns, isNull);
    });
  });

  group('Резолвер «Прямо»: память живёт ровно одну сеть', () {
    test('в пределах одной сети прошлый рабочий резолвер подставляется',
        () async {
      // Противовес: память заведена не зря, и «просто убрать её» — не починка.
      expect(await raise(gen: 1, aborted: () => false), isTrue);
      expect(router.lastOptions!.directDnsUpstream, '192.168.1.1');
      expect(engine.lastDirectDns, '192.168.1.1');

      // Повторная попытка: старый туннель ещё держит трафик (kill switch), и
      // UDP-проба из-под него не проходит. Сеть при этом та же.
      dnsAnswers = false;
      expect(await raise(gen: 2, aborted: () => false), isTrue);
      expect(router.lastOptions!.directDnsUpstream, '192.168.1.1',
          reason: 'без памяти домены «Прямо» на каждом переподключении '
              'оставались бы вообще без резолвера');
    });

    test('смена сети стирает память: чужой резолвер в конфиг не уезжает',
        () async {
      expect(await raise(gen: 1, aborted: () => false), isTrue);
      expect(engine.lastDirectDns, '192.168.1.1');

      // Wi-Fi → мобильная сеть. Именно отсюда чаще всего и приходит
      // переподключение.
      await engine.onNetworkChanged();

      // Новая сеть: адаптер только поднялся, его резолвер ещё молчит.
      adapterDns = ['10.0.0.1'];
      dnsAnswers = false;
      expect(await raise(gen: 2, aborted: () => false), isTrue);

      // ⚠️ Сначала — то, что реально уехало бы ЯДРУ: проверять внутреннее поле
      // раньше конфига значит рапортовать о поломке, не показав вреда.
      expect(router.lastOptions!.directDnsUpstream, isNot('192.168.1.1'),
          reason: 'ядру прописан домашний резолвер, которого в этой сети НЕТ: '
              'он не ответит никогда, и КАЖДЫЙ домен с правилом «Прямо» '
              'перестанет открываться');
      expect(router.lastOptions!.directDnsUpstream, isNull,
          reason: '«не знаю» честно откатывает на системный резолвер — это '
              'прежнее поведение, и оно понятное');
      expect(engine.lastDirectDns, isNull,
          reason: 'резолвер прошлой сети пережил смену сети');
    });

    test('полная остановка стирает память', () async {
      expect(await raise(gen: 1, aborted: () => false), isTrue);
      expect(engine.lastDirectDns, '192.168.1.1');

      // Кнопка «Отключить»: следующее подключение начнётся без нашего туннеля,
      // и проба пройдёт честно — память тут только вредна.
      await engine.cleanup();

      // Между отключением и следующим подключением ноутбук переехал в другую
      // сеть — сигнала о смене сети при выключенном VPN никто не шлёт.
      adapterDns = ['10.0.0.1'];
      dnsAnswers = false;
      expect(await raise(gen: 2, aborted: () => false), isTrue);
      expect(router.lastOptions!.directDnsUpstream, isNull,
          reason: 'резолвер прошлой сети пережил полную остановку движка и '
              'уехал в конфиг ядра уже в другой сети');
      expect(engine.lastDirectDns, isNull);
    });
  });
}
