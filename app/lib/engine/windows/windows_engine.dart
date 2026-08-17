import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'adapter_dns_windows.dart';
import '../../core/platform/app_env.dart';
import '../../core/platform/app_log.dart';
import '../../core/platform/ipv6_support.dart';
import '../../core/platform/app_paths.dart';
import '../../core/net/api_ports.dart';
import '../../core/platform/port_check.dart';
import '../../core/models/traffic_stats.dart';
import '../../core/models/vpn_server.dart';
import '../../core/models/vpn_status.dart';
import '../../core/models/engine_notice.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/split_tunnel.dart';
import '../../core/singbox/singbox_config_builder.dart';
import '../../core/singbox/exit_outbounds.dart';
import '../../core/singbox/exit_router_config_builder.dart';
import '../../core/xray/xray_config_builder.dart' show XrayPorts;
import '../engine_base.dart';
import '../vpn_engine.dart';
import 'singbox_process.dart';
import 'singbox_stats.dart';
import '../../core/net/dns_fallback_server.dart';
import 'system_proxy.dart';
import 'tun/singbox_router_windows.dart';
import 'tun/tun_router.dart';
import 'xray_paths.dart';
import 'xray_process.dart';
import 'xray_stats.dart';

/// Реализация движка для Windows: запускает xray.exe / sing-box.exe и включает
/// захват трафика (системный прокси или TUN).
///
/// Платформо-независимая половина — сессия, поколения, автовосстановление,
/// выбор конфига и ядра — живёт в [VpnEngineBase].
class WindowsEngine extends VpnEngineBase {
  XrayProcess? _process;

  /// Локальный DNS-форвардер с запасным резолвером (см. _startFallbackDns).
  DnsFallbackServer? _fallbackDns;

  /// Только для теста: ЧЕЙ форвардер сейчас в поле. Нужен именно экземпляр —
  /// «устаревший запуск снёс форвардер живой сессии» отличается от исправного
  /// поведения ровно тем, тот же это объект или уже другой.
  @visibleForTesting
  DnsFallbackServer? get fallbackDns => _fallbackDns;

  /// Второе прокси-ядро: sing-box для протоколов, которых нет в Xray (hysteria2).
  /// Одновременно с [_process] не работает — какое ядро поднимать, решает
  /// [VpnServer.core]. TUN-инстанс sing-box считается отдельно (`_tunRouter`).
  SingboxProcess? _singbox;

  /// Третье, отдельное ядро: маршрутизатор выходов режима «Только прокси»
  /// (задача 3b). Крошечный sing-box БЕЗ tun-инбаунда и без прав
  /// администратора — поднимает порты серверов API там, где TUN-инстанс
  /// (`_tunRouter`) физически не запускается (он живёт только при
  /// `captureMode == CaptureMode.tun`).
  SingboxProcess? _exitRouter;
  Timer? _statsTimer;

  /// Сторож зависшего TUN-ядра. См. [AppSettings.tunWatchdogSeconds].
  Timer? _tunWatchdog;

  /// Когда TUN-ядро в последний раз ответило по своему API. `null` — оно ещё
  /// НИ РАЗУ не отвечало, и сторож в этом случае молчит: см. [_startTunWatchdog].
  DateTime? _tunLastAlive;
  StreamSubscription<int>? _exitWatch;
  final TunRouter _tunRouter;
  bool _tunActive = false;

  /// Конфиг ПОДНЯТОГО туннеля — чтобы не пересоздавать его, когда новый запуск
  /// получил бы ровно такой же. `null` — туннеля нет или его конфиг неизвестен.
  ///
  /// ⚠️ ИМЕННО СТРОКА КОНФИГА, А НЕ НАБОР ПОЛЕЙ. Поведение туннеля определяет
  /// конфиг целиком, и сравнение готовых строк не умеет «забыть поле» — а
  /// перечень полей руками в этом проекте уже терял `ipv6Upstream` и
  /// `platformTun` (см. `test/tun_options_carry_test.dart`).
  String? _liveTunConfig;

  /// Список адресов «мимо туннеля», С КОТОРЫМ ПОДНЯТ живой туннель.
  ///
  /// ⚠️ ЗАЧЕМ ХРАНИТЬ ЕГО ОТДЕЛЬНО. Сверка «тот же ли конфиг» точная, побайтная,
  /// и любое расхождение уводит в пересоздание. А список адресов РАСТЁТ сам по
  /// себе: имена серверов резолвятся не все и не сразу (живой прогон 18.08.2026:
  /// в кэше 10 имён из 15), кэш пополняется между подключениями, у имени с
  /// несколькими A-записями состав ответа «дышит». Из-за этого конфиг отличался
  /// от того, с которым туннель поднимался, и переиспользование не включалось
  /// НИ РАЗУ — при том что и мягкое отключение, и порты были уже починены.
  ///
  /// Решение: пока туннель жив, строим конфиг с ЕГО списком, а не с заново
  /// пересобранным. Условие безопасности проверяется явно — см. [_bypassForReuse].
  List<String>? _liveBypassIps;

  /// Секрет Clash API, С КОТОРЫМ ПОДНЯТ живой туннель.
  ///
  /// ⚠️ ЭТО И БЫЛА ГЛАВНАЯ ПРИЧИНА, ПО КОТОРОЙ ТУННЕЛЬ ПЕРЕСОЗДАВАЛСЯ ВСЕГДА.
  /// `prepareLocalProxyAuth` выдаёт новый секрет на КАЖДОЕ подключение
  /// (`singboxApiSecret = _newApiSecret()`), а он уезжает в конфиг туннеля.
  /// Значит побайтная сверка «тот же ли конфиг» не могла совпасть НИ РАЗУ —
  /// сколько ни чини всё остальное. Три живых прогона подряд показывали
  /// «TUN автоподбор» после каждой смены сервера именно поэтому.
  ///
  /// ⚠️ И ВТОРОЕ СЛЕДСТВИЕ, БОЛЕЕ КОВАРНОЕ. Живой туннель продолжает слушать
  /// свой API со СТАРЫМ секретом. Переиспользовать туннель, оставив в поле
  /// новый секрет, значит получить 401 на каждом опросе — то есть сторож
  /// зависания и уведомления о блокировках молча перестали бы работать, а
  /// сторож ещё и решил бы, что ядро не отвечает.
  String? _liveTunApiSecret;
  bool _proxySet = false; // чистим системный прокси только если ставили его сами

  /// Поколение запуска, которое ВЛАДЕЕТ поднятым туннелем и прописанным прокси.
  ///
  /// ⚠️ БЕЗ ЭТОГО «УСТАРЕЛ» ЧИТАЛОСЬ КАК «МОЖНО ВСЁ СНОСИТЬ». Поколение
  /// меняется не только от «Отключить»: его увеличивает и КАЖДЫЙ новый запуск
  /// (повтор после обрыва, подключение сразу после отключения). Пока
  /// `isStale(gen)` был единственным признаком, устаревший запуск, вернувшийся
  /// из долгого ожидания (автоподбор стека идёт до двух минут), гасил
  /// `_tunRouter` и ядро ИЗ ПОЛЕЙ — то есть туннель и процесс уже НОВОЙ сессии,
  /// а флаг `_tunActive` при этом обнулял, и штатная уборка этот туннель больше
  /// не находила. Снаружи: «Подключено» при мёртвом ядре либо адаптер, который
  /// никто не снимет.
  int _tunOwnerGen = 0;
  int _proxyOwnerGen = 0;

  /// ⚠️ ТОТ ЖЕ КЛАСС, ЧТО У ТУННЕЛЯ И ПРОКСИ, — И ОН БЫЛ ЗАКРЫТ НЕ ВЕЗДЕ.
  ///
  /// Запасной DNS-форвардер поднимается ВНУТРИ подготовки туннеля
  /// ([raiseTun]), то есть после нескольких await'ов — резолва серверов и
  /// опроса DNS адаптера (до 2 с на адрес). К этому моменту запуск мог
  /// устареть, а `_startFallbackDns` первой же строкой гасил ТО, ЧТО ЛЕЖИТ В
  /// ПОЛЕ: форвардер уже НОВОЙ, живой сессии. Дальше он поднимал свой и
  /// записывал его в то же поле, после чего уходил по `aborted()` — и свой
  /// оставлял слушать порт навсегда. Итог у живой сессии: `dns.final` указывает
  /// на порт, которого больше нет, то есть DNS всех приложений при включённом
  /// «весь DNS через туннель» перестаёт резолвиться, и само это не чинится.
  int _fallbackDnsOwnerGen = 0;

  /// Идёт ли сейчас опрос счётчиков (Timer.periodic async-колбэки не сериализует).
  bool _polling = false;

  XrayTrafficSnapshot _lastSnapshot = XrayTrafficSnapshot.zero;
  DateTime _lastSampleTime = DateTime.now();

  /// [tunRouter] и [recoverSystemProxy] существуют РАДИ ТЕСТА и в приложении
  /// не задаются. Про второй отдельно: маркер «прокси ставили мы» лежит в
  /// системном `%TEMP%`, а не в каталоге данных приложения, поэтому изоляция
  /// теста через `AppPaths.overrideRoot` его НЕ покрывает — создание движка в
  /// тесте сняло бы рабочий системный прокси у живого приложения владельца.
  WindowsEngine({
    super.ports,
    TunRouter? tunRouter,
    bool recoverSystemProxy = true,
  }) : _tunRouter = tunRouter ?? SingboxRouterWindows() {
    // Восстановление после аварийного выхода прошлого запуска.
    if (recoverSystemProxy) SystemProxy.recoverIfDirty();
  }

  /// ⚠️ СМЕШАННЫЙ РЕЖИМ — ТОЖЕ СИСТЕМНЫЙ ПРОКСИ. При `alsoSetSystemProxy`
  /// прокси прописывается ДОПОЛНИТЕЛЬНО к туннелю, и в локальный порт снова
  /// смотрит WinINET, который креденшелов не передаёт.
  ///
  /// ⚠️ А `proxyOnly` — НЕ системный прокси, хотя туннеля там тоже нет. В порт
  /// смотрит не WinINET, а конкретная программа, умеющая передать логин и
  /// пароль. Верни здесь `true` — и порт откроется без пароля именно в том
  /// режиме, который заведён ради стороннего кода.
  /// Туннель этого приложения сейчас поднят — значит при бесшовной смене
  /// сервера он останется жить, и его креды менять нельзя.
  @override
  bool get liveCaptureKept => _tunActive;

  @override
  bool systemProxyModeFor(ConnectionOptions options) =>
      options.captureMode == CaptureMode.systemProxy ||
      options.settings.alsoSetSystemProxy;

  /// Порты API реально нужны ТОЛЬКО когда тумблер включён, задан токен И
  /// способ захвата вообще создаёт эти инбаунды — см. `ApiPorts.exitPortsActive`,
  /// единый источник гейта для `PortCheck` (ниже в `startSession`), сборки
  /// TUN-конфига (`_tunRouter.start`) и маршрутизатора выходов.
  ///
  /// ⚠️ РЕЖИМ ЗАХВАТА — ЧАСТЬ ГЕЙТА, А НЕ ПОДРОБНОСТЬ. Без него в режиме
  /// системного прокси (умолчание!) `PortCheck` проверял порты 10820…10859 и
  /// 10819, которых конфиг в этом режиме не создаёт: сторонняя программа на
  /// любом из них давала «Конфликт портов» и полный отказ подключения на
  /// ровном месте.
  bool _apiExitsActive(AppSettings s) => ApiPorts.exitPortsActive(s);

  /// Порты, которые обязаны быть свободны ПЕРЕД стартом ядра.
  ///
  /// ⚠️ ВЫНЕСЕНО ИЗ [startSession] РАДИ ТЕСТА, А НЕ РАДИ КРАСОТЫ. На
  /// `startSession` не было ни одного теста — там живой процесс ядра, реальные
  /// сокеты и права, — и ровно поэтому дефект «проверяем порты, которых в этом
  /// режиме не будет» дожил до финального ревью. Список портов — чистая
  /// функция настроек, и в таком виде он проверяем без единого сокета.
  ///
  /// [ports] — порты ядра сессии (socks/http/api Xray). Они нужны ВСЕГДА, при
  /// любом режиме захвата. Порты API добавляются только когда инбаунды под них
  /// реально будут созданы (см. [_apiExitsActive] / `ApiPorts.exitPortsActive`).
  /// Порты, которые обязаны быть свободны перед подъёмом.
  ///
  /// [tunnelStaysUp] — живой туннель этого же приложения остаётся на месте
  /// (бесшовная смена сервера). ⚠️ ТОГДА ПОРТЫ ВЫХОДОВ ПРОВЕРЯТЬ НЕЛЬЗЯ, И ЭТО
  /// НЕ ПОСЛАБЛЕНИЕ, А УСЛОВИЕ ЗАДАЧИ. Порт «Прямо» (10819) и порты серверов
  /// поднимает САМ ТУННЕЛЬНЫЙ sing-box, тот самый, который мы намеренно
  /// оставляем жить. Сохранили туннель — сохранили и его порты; требовать их
  /// свободы значит требовать, чтобы туннель умер, то есть отменять всю затею.
  ///
  /// Найдено живым прогоном в VM 18.08.2026: туннель ВПЕРВЫЕ сохранился (в
  /// журнале нет ни строки «TUN автоподбор»), и тут же подключение упало с
  /// «Порт 10819 ещё занят нашим ядром (sing-box.exe) от прошлой сессии».
  ///
  /// ⚠️ Порты прокси-ядра (socks/http/api) проверяются ВСЕГДА: их держит ядро,
  /// которое как раз гасится и поднимается заново, и вот там конфликт реален.
  static List<int> corePortsFor(AppSettings s, XrayPorts ports,
      {bool tunnelStaysUp = false}) {
    final active = ApiPorts.exitPortsActive(s) && !tunnelStaysUp;
    final keys = active ? s.apiExitServerKeys : const <String>[];
    return [
      ports.socks,
      ports.http,
      ports.api,
      for (final k in ApiPorts.withinRange(keys)) ApiPorts.forServer(keys, k)!,
      // Порт «Прямо» поднимается по тому же гейту, что и порты серверов, и НЕ
      // зависит от их числа — см. `buildApiDirectInbound`/`buildApiExitInbounds`
      // (`core/net/api_ports.dart`) и `_startExitRouter`.
      if (active) ApiPorts.direct,
    ];
  }

  /// Один запуск текущей сессии (первичный или повторный при восстановлении).
  @override
  Future<void> startSession() async {
    final session = this.session;
    if (session == null) return;
    final configJson = session.configJson;
    final options = session.options;
    final servers = session.servers;

    // Метка этого запуска: пока мы ждём (подъём ядра, автоподбор TUN — до минут),
    // пользователь мог нажать «Отключить». Тогда поколение сменится, и всё, что
    // мы успели поднять после этого, нужно немедленно погасить, иначе туннель
    // остаётся жить при выключенном на вид VPN.
    final gen = newGeneration();
    bool aborted() => isStale(gen);

    // message: null затирал бы уже выставленное базой «Пробую другой сервер: …»
    // — она ставит его прямо перед этим вызовом, и подпись жила меньше секунды.
    setStatus(
      VpnConnectionState.connecting,
      message: attempt > 0
          ? 'Переподключение (попытка $attempt)…'
          : (status.state == VpnConnectionState.connecting
              ? status.message
              : null),
    );

    final singboxCore = session.core == ProxyCore.singbox;
    final location = XrayPaths.locate();
    final singboxExe = singboxCore ? SingboxProcess.locate() : null;
    if (singboxCore && singboxExe == null) {
      // _cleanup обязателен: при kill switch захват трафика мог остаться с
      // прошлой попытки, и без него интернет остался бы заблокированным.
      await cleanup();
      setStatus(
        VpnConnectionState.error,
        message: 'Для Hysteria2 нужен sing-box.exe рядом с xray.exe.\n'
            'Запустите tools/fetch-singbox.ps1',
      );
      return;
    }
    if (!singboxCore && location == null) {
      await cleanup();
      setStatus(
        VpnConnectionState.error,
        message: 'Не найден xray.exe. Запустите tools/fetch-xray.ps1',
      );
      return;
    }

    // Порты проверяем ДО запуска: если их занял другой VPN-клиент, ядро просто
    // упадёт, и раньше пользователь видел бесполезное «Ядро завершилось при запуске».
    //
    // ⚠️ НО СНАЧАЛА ЖДЁМ СВОЁ ЖЕ ЯДРО. Быстрое «Отключить → Подключить» — гонка
    // с самим собой: прежний xray.exe уже получил kill, а слушающий сокет
    // Windows освобождает не мгновенно. Раньше мы в этот момент либо падали с
    // «код 1», либо объявляли собственный остаток чужим VPN-клиентом и
    // предлагали «закройте Happ» — при том что никакого Happ у пользователя не
    // запущено. Ожидание короткое и только пока порт реально занят.
    // Креды локальных прокси здесь УЖЕ выданы — базой, до сборки конфига
    // (`prepareLocalProxyAuth`). Повторять вызов нельзя: он выдал бы новый
    // пароль, а конфиг ядра остался бы с прежним.
    // ⚠️ Новые порты проверяются НАРАВНЕ с портами ядра. Иначе занятый порт
    // сервера дал бы отказ подъёма без единого внятного слова: «Bad state»
    // вместо имени программы, которая порт держит.
    //
    // Гейт — `_apiExitsActive`, ТОТ ЖЕ, что решает, создавать ли инбаунды: при
    // пустом токене (или в режиме системного прокси) их не будет ни одного, и
    // проверять порты, которых не возникнет, — значит рисковать ложным отказом
    // подключения на чужом порту.
    final apiKeys = _apiExitsActive(options.settings)
        ? options.settings.apiExitServerKeys
        : const <String>[];
    // Живой туннель остаётся на месте только при включённой бесшовности — тогда
    // его порты не наши к освобождению. Иначе он будет снят и порты вернутся.
    final corePorts = corePortsFor(options.settings, ports,
        tunnelStaysUp: _tunActive && options.settings.seamlessServerSwitch);
    var conflict = await PortCheck.findConflict(corePorts);
    // ⚠️ ЖДЁМ И ТОГДА, КОГДА ВЛАДЕЛЬЦА ОПОЗНАТЬ НЕ УДАЛОСЬ.
    //
    // Найдено живым прогоном в VM 17.08.2026, на смене сервера: подключение
    // падало с «Порт 10819 уже занят другой программой, определить её не
    // удалось» — при том что никакой другой программы не было. Держал порт наш
    // же маршрутизатор выходов от ПРЕДЫДУЩЕЙ сессии: процесс уже получил `kill`
    // и успел умереть, а слушающий сокет Windows отпускает не мгновенно. Мёртвый
    // процесс по PID не находится — `holder` выходил `null`, `heldByOwnCore`
    // давал `false`, ожидание не включалось, и человек получал отказ вместо
    // паузы в полсекунды.
    //
    // Порт из НАШЕГО диапазона с неопознанным владельцем — почти всегда наш
    // собственный остаток: чужая программа, занявшая его всерьёз, никуда не
    // денется и после ожидания, и сообщение об отказе придёт ровно то же, лишь
    // на несколько секунд позже. Ошибиться в эту сторону дёшево, в обратную —
    // отказ подключения на ровном месте.
    if (conflict != null) {
      AppLog.i(conflict.heldByOwnCore
          ? 'Порт ${conflict.port} ещё держит наше ядро '
              '(${conflict.holder}) — жду освобождения'
          : 'Порт ${conflict.port} занят, владелец не определён — жду: на смене '
              'сервера так выглядит наш же процесс, чей сокет ещё не отпущен');
      await PortCheck.waitFree(corePorts);
      if (aborted()) return;
      conflict = await PortCheck.findConflict(corePorts);
    }
    // ⚠️ Проверка отмены — ДО разбора конфликта. Порты проверяются с двумя
    // await'ами (`findConflict`, `waitFree`), и за это время запуск мог
    // устареть; тогда «Конфликт портов» и общая уборка достались бы уже НОВОЙ
    // сессии, у которой с портами всё в порядке.
    if (aborted()) return;
    if (conflict != null) {
      final message = conflict.fallbackMessage;
      AppLog.e('Конфликт портов: ${message.split("\n").first}');
      await cleanup();
      setStatus(VpnConnectionState.error, message: message);
      return;
    }

    // Процессы, поднятые ИМЕННО ЭТИМ запуском. Гасить при отмене нужно их, а
    // не то, что лежит в полях: поля к тому моменту могут принадлежать новой
    // сессии (см. [_stopOwnProcesses]).
    final mine = <Object?>[];
    try {
      final configPath =
          await _writeConfigJson(configJson, singbox: singboxCore);

      // Одно из двух ядер: Xray или (для hysteria2) sing-box.
      String Function() tailOf;
      bool Function() alive;
      Future<int>? exited;
      if (singboxCore) {
        final process = SingboxProcess();
        // Пишем вывод в файл: у прокси-ядра (hysteria2) диагностики не было
        // вообще — «конфиг валиден, процесс жив, трафика нет» не оставляло
        // ни байта, по которому можно понять причину.
        await process.start(
          executable: singboxExe!,
          configPath: configPath,
          logPath: SingboxProcess.logPathFor(await AppPaths.supportDir()),
        );
        _singbox = process;
        mine.add(process);
        tailOf = () => process.tail;
        alive = () => process.isRunning;
        exited = process.exitCode;
      } else {
        final process = XrayProcess();
        await process.start(
          executable: location!.executable,
          configPath: configPath,
          assetDir: location.assetDir,
          // ⚠️ Вывод Xray В ФАЙЛ — не «на всякий случай». Без него падение
          // ядра выглядело в журнале как «остановилось (код 1)» и ничего
          // больше, хотя сам Xray причину печатает внятно («порт занят»,
          // «конфиг отвергнут»). У sing-box такой файл был давно, у Xray —
          // нет, и разбор жалобы «весь интернет лёг» упирался в пустоту.
          logPath: XrayProcess.logPathFor(await AppPaths.supportDir()),
        );
        _process = process;
        mine.add(process);
        tailOf = () => process.tail;
        alive = () => process.isRunning;
        exited = process.exitCode;
      }

      // Следим за неожиданным падением ядра. Хвост вывода передаём вместе с
      // кодом: код сам по себе ничего не объясняет.
      _exitWatch = exited?.asStream().listen((code) {
        if (status.isConnected || status.state == VpnConnectionState.connecting) {
          onCoreDied(code, tail: tailOf());
        }
      });

      // Небольшая пауза на инициализацию ядра.
      await Future.delayed(const Duration(milliseconds: 500));
      if (!alive()) {
        // Показываем реальную причину из вывода ядра, а не голое «завершилось».
        final tail = tailOf().trim();
        AppLog.e('Ядро не стартовало. Вывод:\n$tail');
        throw StateError(tail.isEmpty
            ? 'Ядро завершилось при запуске (вывод пуст)'
            : 'Ядро завершилось при запуске:\n$tail');
      }

      if (aborted()) {
        await _stopOwnProcesses(mine);
        return;
      }

      if (options.captureMode == CaptureMode.tun) {
        if (!await raiseTun(
          options: options,
          servers: servers,
          apiKeys: apiKeys,
          aborted: aborted,
          gen: gen,
        )) {
          await _stopOwnProcesses(mine);
          return;
        }
      }

      // Маршрутизатор выходов «Только прокси» (задача 3b): второе ядро
      // (`_tunRouter`) в этом режиме не поднимается вовсе (см. блок выше,
      // условие `captureMode == CaptureMode.tun`), а значит порты серверов
      // из ApiPorts физически негде слушать. Здесь — третий, отдельный
      // sing-box, БЕЗ tun-инбаунда и без прав администратора.
      if (options.captureMode == CaptureMode.proxyOnly &&
          _apiExitsActive(options.settings)) {
        mine.add(await _startExitRouter(options, aborted));
      }

      // ⚠️ СИСТЕМНЫЙ ПРОКСИ СТАВИТСЯ И ВМЕСТО ТУННЕЛЯ, И ВМЕСТЕ С НИМ.
      //
      // Вместе — это «смешанный» режим (у Happ он так и подписан, Mixed):
      // прокси-aware приложения идут коротким путём прямо в http-инбаунд,
      // минуя пользовательский стек туннеля, и отдают ядру ИМЯ ДОМЕНА, а не
      // голый IP.
      //
      // ⚠️ ЦЕНА, КОТОРУЮ ОБЯЗАН ЗНАТЬ ПОЛЬЗОВАТЕЛЬ: у такого соединения нет
      // процесса-владельца — для ядра это локальное подключение с петли.
      // Значит правила ПО ПРИЛОЖЕНИЯМ для прокси-aware программ в смешанном
      // режиме не срабатывают вовсе (правила по сайтам работают, и даже лучше:
      // имя приходит без сниффинга). Интерфейс говорит об этом прямо — молча
      // отдавать неработающие правила мы уже пробовали восемь раз.
      // ⚠️ `proxyOnly` не ставит НИ системный прокси, НИ туннель. Прежнее
      // условие `!= CaptureMode.tun` считало бы его системным прокси и прописало
      // бы адрес в реестр — то есть увело бы туда весь трафик машины, ровно
      // против смысла режима.
      final wantProxy = options.captureMode == CaptureMode.systemProxy ||
          options.settings.alsoSetSystemProxy;
      if (wantProxy) {
        await SystemProxy.set('127.0.0.1:${ports.http}');
        _proxySet = true;
        _proxyOwnerGen = gen;
        if (options.captureMode == CaptureMode.tun) {
          AppLog.i('Смешанный режим: туннель + системный прокси на '
              '127.0.0.1:${ports.http}');
        }
      }

      // #4 — пользователь мог нажать «Отключить», пока поднимались ядро и
      // прокси/туннель. Без этой проверки в режиме системного прокси прокси
      // оставался прописанным, а статус вставал в «Подключено» уже ПОСЛЕ отмены.
      if (aborted()) {
        await _abandonRun(gen, mine);
        return;
      }

      _lastSnapshot = XrayTrafficSnapshot.zero;
      _lastSampleTime = DateTime.now();
      _startStatsPolling(
          singboxCore ? null : location!.executable, singbox: singboxCore);

      // Читаем ДО markConnected(): он и обнуляет счётчик попыток.
      if (attempt > 0) {
        AppLog.i('Соединение восстановлено (попытка $attempt)');
        // Говорим вслух ТОЛЬКО когда перед этим были неудачи: обычное
        // подключение по кнопке в сообщении не нуждается.
        emitNotice(EngineNoticeKind.recovered, 'Соединение восстановлено',
            detail: 'Потребовалось попыток: $attempt');
      }
      markConnected(); // сбрасывает счётчик попыток и запускает grace смены сети
      setStatus(VpnConnectionState.connected);
      // ⚠️ СТРОГО ПОСЛЕ «Подключено», а не рядом с подъёмом туннеля.
      //
      // Условие отмены у наблюдения — `aborted() || !status.isConnected`.
      // Пока вызов стоял выше (рядом со сторожем зависания), статус был ещё
      // `connecting`, и наблюдение глушило себя на ПЕРВОЙ же пробе. Внешне это
      // выглядело как «сторож не работает»: в журнале ни строчки, а живой
      // прогон в VM с отключённым адаптером не дал ничего за три минуты.
      // На Android вызов изначально стоял после статуса — потому там и
      // сработало. Расхождение платформ на ровном месте.
      // ⚠️ В ОБОИХ РЕЖИМАХ ЗАХВАТА, а не только в TUN. Умолчание на Windows —
      // системный прокси (`AppSettings.captureMode`), и с условием
      // `== CaptureMode.tun` на свежей установке сквозной проверки не было
      // ВООБЩЕ: сервер отваливался, ядро исправно отвечало по своему API,
      // приложение показывало «Подключено», и весь трафик машины уходил в
      // мёртвый прокси без единой строчки в журнале. Ровно тот инцидент, ради
      // которого подсистема и написана — только в режиме по умолчанию.
      // Проба ходит в 127.0.0.1:$httpProxyPort, то есть в тот же порт, что и
      // системный прокси; кредов в этом режиме не ставится, 407 невозможен.
      startHealthWatch(aborted);
    } on TunStartException catch (e) {
      // Честная причина из лога sing-box вместо ложного «Подключено».
      AppLog.e('TUN не поднялся: $e');
      // #6 — если пользователь сам отменил (aborted), НЕ затираем его
      // «Отключено» статусом «Ошибка». Проверяем ДО уборки (она ++_generation).
      if (aborted()) {
        // ⚠️ ОБЩАЯ УБОРКА ЗДЕСЬ ЗАПРЕЩЕНА: поколение могло смениться не
        // отменой, а НОВЫМ запуском — `cleanup()` снял бы его туннель, ядро и
        // прокси. Сворачиваем только своё.
        await _abandonRun(gen, mine);
        return;
      }
      await cleanup();
      setStatus(VpnConnectionState.error, message: e.toString());
    } catch (e) {
      AppLog.e('Подключение не удалось: $e');
      if (aborted()) {
        await _abandonRun(gen, mine);
        return;
      }
      // Сеть могла быть ещё не готова (например, сразу после пробуждения) —
      // это как раз случай для повторной попытки.
      if (await scheduleRetry('не удалось подключиться: $e')) return;
      await cleanup();
      setStatus(VpnConnectionState.error,
          message: 'Не удалось подключиться: $e');
    }
  }

  /// Поднять туннель текущей сессии. `false` — запуск устарел и туннеля нет:
  /// вызывающий обязан свернуться, не трогая чужого.
  ///
  /// ⚠️ ВЫНЕСЕНО ИЗ [startSession] РАДИ ТЕСТА, а не ради красоты — как и
  /// [corePortsFor]. На `startSession` теста нет и быть не может (живое ядро,
  /// реальные сокеты, права администратора), а здесь проверяется ровно то, что
  /// решает судьбу kill switch: ПОРЯДОК «подготовка → снятие старого → подъём
  /// нового».
  ///
  /// ⚠️ ⚠️ ГЛАВНОЕ ЗДЕСЬ — ЧТО ПОДГОТОВКА ИДЁТ ДО СНЯТИЯ СТАРОГО ТУННЕЛЯ.
  ///
  /// Между попытками восстановления kill switch НЕ снимает захват: туннель
  /// стоит, ядра нет, соединения честно падают — в этом весь его смысл. А
  /// начало каждой попытки первым же делом снимало этот туннель и только потом
  /// шло резолвить серверы, опрашивать DNS адаптера (до 2 с на адрес), искать
  /// IPv6 и поднимать запасной форвардер. Всё это время — секунды, а на
  /// сломанной сети (то есть ровно тогда, когда идут попытки) и десятки секунд
  /// — трафик машины шёл НАПРЯМУЮ под реальным IP, без единого признака в
  /// интерфейсе: статус показывал «Переподключение… трафик заблокирован».
  /// Обещание «не выпущу мимо VPN» нарушалось именно там, где его дают.
  ///
  /// Снятие старого туннеля отменить нельзя (элевейтнутый хелпер продолжил бы
  /// работать по СТАРОМУ конфигу — со старым IP сервера в правиле «мимо
  /// туннеля», то есть с риском петли и мёртвой сети), но окно без захвата
  /// сжимается до «снял → поднимаю».
  /// Чем ЖЕЛАЕМЫЙ конфиг туннеля отличается от конфига живого — списком путей
  /// к полям, БЕЗ значений.
  ///
  /// ⚠️ ЗАЧЕМ ЭТО В БОЕВОМ КОДЕ, А НЕ В ОТЛАДКЕ. Переиспользование туннеля не
  /// включалось четыре прогона подряд, и каждый раз причиной оказывалось
  /// очередное поле, которое незаметно меняется от подключения к подключению
  /// (список адресов, секрет Clash API…). Гадать по одному полю дороже, чем
  /// один раз посмотреть: сверка побайтная, и любое новое поле такого рода
  /// молча вернёт нас к пересозданию туннеля. Пусть отвечает журнал.
  ///
  /// ⚠️ ТОЛЬКО ИМЕНА ПОЛЕЙ, НИКОГДА ЗНАЧЕНИЯ. В конфиге лежат адреса серверов и
  /// секрет Clash API; путь `route.rules[3].ip_cidr` разбор объясняет, а список
  /// адресов в журнале — это утечка, за которую в этом проекте уже платили.
  static List<String> tunConfigDiff(String liveJson, String wantJson) {
    final out = <String>[];
    void walk(Object? a, Object? b, String path) {
      if (out.length >= 12) return; // журнал не резиновый
      if (a is Map && b is Map) {
        for (final k in {...a.keys, ...b.keys}) {
          if (!a.containsKey(k)) {
            out.add('$path.$k (появилось)');
          } else if (!b.containsKey(k)) {
            out.add('$path.$k (исчезло)');
          } else {
            walk(a[k], b[k], '$path.$k');
          }
        }
        return;
      }
      if (a is List && b is List) {
        if (a.length != b.length) {
          out.add('$path (было ${a.length}, стало ${b.length})');
          return;
        }
        for (var i = 0; i < a.length; i++) {
          walk(a[i], b[i], '$path[$i]');
        }
        return;
      }
      if (a.toString() != b.toString()) out.add(path);
    }

    try {
      walk(jsonDecode(liveJson), jsonDecode(wantJson), 'config');
    } catch (e) {
      return ['(конфиг не разобрать: $e)'];
    }
    return out;
  }

  /// Адреса «мимо туннеля» для сборки конфига.
  ///
  /// Пока живого туннеля нет — обычный расчёт. Если туннель жив и включена
  /// бесшовность, отдаём список, С КОТОРЫМ ОН ПОДНЯТ, — но только если он
  /// ПОКРЫВАЕТ адреса серверов текущей сессии.
  ///
  /// ⚠️ УСЛОВИЕ ПОКРЫТИЯ — НЕ ФОРМАЛЬНОСТЬ. Правило `ip_cidr → direct` для
  /// адресов серверов существует, чтобы трафик прокси-ядра к своему серверу не
  /// заходил обратно в туннель. Отдать живой список, в котором нового сервера
  /// нет, значило бы завести петлю: ядро пошло бы к серверу через туннель,
  /// который сам же и обслуживает. Правило по имени процесса — второй эшелон, и
  /// полагаться на него одного здесь нельзя.
  ///
  /// Не покрывает — возвращаем свежий список; конфиг тогда отличается, и
  /// туннель честно пересоздаётся, как раньше.
  Future<List<String>> _bypassForReuse(
      List<VpnServer> servers, AppSettings s) async {
    final sessionHosts = await resolveServerHosts(servers);
    final fresh = await tunnelBypassIps(sessionHosts, s);
    final live = _liveBypassIps;
    if (!_tunActive || !s.seamlessServerSwitch || live == null) return fresh;

    final needed = sessionHosts.values.expand((e) => e).toSet();
    if (needed.isNotEmpty && live.toSet().containsAll(needed)) {
      return live;
    }
    AppLog.i('Адреса нового сервера не покрыты правилом живого туннеля — '
        'туннель придётся пересоздать');
    return fresh;
  }

  @visibleForTesting
  Future<bool> raiseTun({
    required ConnectionOptions options,
    required List<VpnServer> servers,
    required List<String> apiKeys,
    required bool Function() aborted,
    required int gen,
  }) async {
    // Серверы, назначенные отдельным правилам. Собираются ТЕМ ЖЕ кодом,
    // что на Android, — иначе платформы разъедутся на первом же правиле.
    //
    // ⚠️ Резолвим ДО подъёма туннеля и вместе с серверами сессии: домен,
    // отданный ядру как есть, спрашивался бы уже из-под туннеля и замкнулся
    // сам на себя. На живом тесте это не всплыло только потому, что оба
    // сервера были заданы адресами, — не считать это проверкой.
    final exitHosts = await resolveServerHosts([
      ...servers,
      ...options.exitServers.values,
    ]);
    final exitsBuilt = ExitOutbounds.build(
      servers: options.exitServers,
      resolvedIps: VpnEngineBase.pickOneIpPerHost(exitHosts),
    );
    for (final e in exitsBuilt.skipped.entries) {
      AppLog.i('Сервер правила не поднят: ${e.value} — '
          'эти правила пойдут основным туннелем');
    }
    if (exitsBuilt.outbounds.isNotEmpty) {
      AppLog.i('Мульти-VPN: дополнительных серверов '
          '${exitsBuilt.outbounds.length}');
    }
    // ⚠️ ПЕРЕИСПОЛЬЗУЕМ ТУННЕЛЬ — ЗНАЧИТ ЖИВЁМ С ЕГО СЕКРЕТОМ.
    // Возвращаем поле к значению живого туннеля ДО сборки конфига: иначе и
    // сверка не совпадёт, и сторож пойдёт стучаться с чужим паролем.
    final liveSecret = _liveTunApiSecret;
    if (_tunActive && options.settings.seamlessServerSwitch && liveSecret != null) {
      singboxApiSecret = liveSecret;
    }
    final tunOptions = TunOptions.fromSettings(
      options.settings,
      // ⚠️ НЕ ТОЛЬКО СЕРВЕР СЕССИИ. При включённой бесшовности сюда идут и
      // запасные серверы — тогда конфиг перестаёт зависеть от того, кто из них
      // выбран, и переход на запасной не требует пересоздавать туннель (см.
      // `VpnEngineBase.tunnelBypassIps` и сверку конфига ниже). Выключенный
      // флаг отдаёт РОВНО прежний список.
      serverIps: await _bypassForReuse(servers, options.settings),
      // Имена ВСЕЙ инфраструктуры — резолвим только напрямую.
      serverDomains: knownServerDomains,
      // Резолвер для «Прямо». Спрашивается ДО подъёма НОВОГО туннеля: после
      // него системный резолвер указывает на сам туннель, и «Прямо»
      // резолвилось бы через VPN. Прежний туннель (тот, что держит kill
      // switch) при этом ещё стоит — потому у ответа и есть память о прошлом
      // рабочем адресе, см. `_systemDnsServer`.
      directDnsUpstream: await _systemDnsServer(),
      // Запасной резолвер под общий DNS — только когда пользователь
      // просил вести DNS через туннель. Без этой галочки прямой трафик и
      // так резолвится локально, и лишнее звено не нужно.
      fallbackDnsPort: await _startFallbackDns(options.settings, gen, aborted),
      ipv6Available: await _ipv6Reality(),
      // API туннельного экземпляра — ТОЛЬКО для сторожа зависания.
      //
      // ⚠️ Порт новый, поэтому сверен с обоими ядрами: Xray держит
      // 10808/10809/10085, sing-box-прокси — те же 10808/10809 плюс
      // 10085 под Clash API, на Android туннель занимает 10812. 10813
      // свободен. Урок 10085 и 10809 повторять не будем.
      clashApiPort: _tunApiPort,
      clashApiSecret: singboxApiSecret,
    );
    // Подготовка была долгой — сверяемся с отменой ДО того, как тронем захват.
    // ⚠️ И убираем СВОЙ форвардер: он уже поднят (строкой выше, внутри сборки
    // опций) и слушает порт, а конфиг с этим портом никуда не поедет.
    if (aborted()) {
      await _releaseOwnFallbackDns(gen);
      return false;
    }

    // ⚠️ ЖИВОЙ ТУННЕЛЬ С ТЕМ ЖЕ КОНФИГОМ ПЕРЕСОЗДАВАТЬ НЕ НУЖНО.
    //
    // Снять TUN и поднять его заново — значит на секунду убрать маршрут по
    // умолчанию: рвутся не только соединения через VPN, но и всё, что шло мимо
    // него. Пользователь замечает это сильнее самого разрыва — у VPN на
    // роутере такого нет вовсе, там при переподключении не меняются ни адрес,
    // ни таблица маршрутов.
    //
    // Решение принимается по ГОТОВОМУ КОНФИГУ, а не по перечню полей: конфиг —
    // единственное, что определяет поведение туннеля, и сравнение строк не
    // умеет «забыть поле». Собирается он тем же `SingboxConfigBuilder` и из тех
    // же аргументов, что уходят в `_tunRouter.start` ниже.
    //
    // ⚠️ ЧЕГО ЭТО НЕ ОБЕЩАЕТ: живое TCP-соединение не переживёт смену внешнего
    // IP — удалённая сторона видит другой адрес. Речь только о том, чтобы у
    // машины не мигала сеть.
    //
    // ⚠️ Автоподбор стека/MTU конфиг подменяет уже внутри роутера, поэтому
    // сверяем ИСХОДНЫЕ опции — тем же способом на обеих сторонах сравнения. Раз
    // они не изменились, живой туннель работает на подобранной комбинации, а
    // подбирать заново нечего.
    final wantConfig = _tunConfigPreview(
      split: options.split,
      options: tunOptions,
      exitOutbounds: exitsBuilt.outbounds,
      apiKeys: apiKeys,
      apiOnlyKeys: options.apiOnlyExitKeys.toList(),
      apiToken: _apiExitsActive(options.settings) ? options.settings.apiToken : '',
    );
    final live = _liveTunConfig;
    if (_tunActive &&
        options.settings.seamlessServerSwitch &&
        live != null &&
        live != wantConfig) {
      final diff = tunConfigDiff(live, wantConfig);
      AppLog.i('Туннель придётся пересоздать — конфиг отличается: '
          '${diff.isEmpty ? "(различий не найдено, отличаются пробелы/порядок)" : diff.join(", ")}');
    }
    if (_tunActive &&
        options.settings.seamlessServerSwitch &&
        _liveTunConfig == wantConfig) {
      // ⚠️ «ФЛАГ ПОДНЯТ» — ЭТО НЕ «ТУННЕЛЬ ЖИВ», И РАЗНИЦА ЗДЕСЬ РЕШАЮЩАЯ.
      //
      // При падении элевейтнутого хелпера Windows убирает адаптер сама, а нам
      // не сообщает: `_tunActive` остаётся true. Прежний код в этом случае
      // делал stop → start и туннель поднимался заново; переиспользование
      // вслепую оставило бы машину БЕЗ маршрутов при статусе «Подключено» —
      // ровно тот класс отказов, ради которого написан сторож зависания.
      // Спрашиваем то же, что и он: отвечает ли туннельное ядро по своему API.
      // Не ответило — молча возвращаемся к пересозданию, то есть к прежнему
      // поведению.
      if (await (tunAliveForTest?.call() ?? _tunApiAlive())) {
        // Туннель остаётся тот же, но ведёт его теперь ЭТОТ запуск: иначе
        // устаревшее поколение сняло бы его, вернувшись из своего ожидания.
        _tunOwnerGen = gen;
        AppLog.i('Туннель не пересоздаю: конфиг тот же и ядро отвечает — '
            'перезапускается только прокси-ядро, маршрут по умолчанию не мигает');
        _startTunWatchdog(options.settings, aborted);
        startBlockNotice(
            settings: options.settings,
            apiPort: _tunApiPort,
            secret: singboxApiSecret);
        return true;
      }
      AppLog.w('Туннель с тем же конфигом не отвечает по своему API — '
          'пересоздаю его, а не выдаю мёртвый за живой');
    }

    // Вот теперь — и только теперь — снимаем старый туннель, вплотную к
    // подъёму нового (см. заголовок метода).
    if (_tunActive) {
      await _tunRouter.stop();
      _tunActive = false;
      _liveTunConfig = null;
      _liveBypassIps = null;
      _liveTunApiSecret = null;
      _liveBypassIps = null;
      _liveTunApiSecret = null;
      await Future.delayed(const Duration(milliseconds: 600));
    }
    // TUN: sing-box поднимает туннель и заворачивает прокси-трафик в SOCKS Xray.
    // start() бросит TunStartException, если туннель реально не поднялся.
    _tunActive = true; // чтобы уборка погасила недоподнятый туннель
    _tunOwnerGen = gen;
    await _tunRouter.start(
      options.split,
      exitOutbounds: exitsBuilt.outbounds,
      xraySocksPort: ports.socks,
      xraySocksUser: localInboundUser,
      xraySocksPassword: localInboundPassword,
      // ⚠️ Тот же гейт (`_apiExitsActive`/`apiKeys`), что и у `corePorts`
      // выше: конфиг обязан создавать РОВНО те инбаунды, чьи порты уже
      // проверены — иначе PortCheck и построитель конфига разъедутся.
      apiExitServerKeys: apiKeys,
      // ⚠️ Кому outbound собран ТОЛЬКО ради порта. Тег у него в конфиге
      // есть, но правила раздельного туннелирования его не видят — иначе
      // правило «через активный сервер» завело бы второе соединение к
      // тому же узлу (см. `SingboxConfigBuilder.apiOnlyExitKeys`).
      apiOnlyExitKeys: options.apiOnlyExitKeys.toList(),
      apiToken: _apiExitsActive(options.settings) ? options.settings.apiToken : '',
      options: tunOptions,
      // Автоподбор стека/MTU может занять время — показываем, что происходит
      // (#8: отдельная фаза → прогресс-тост, не только строка статуса).
      onProgress: (m) => setStatus(VpnConnectionState.connecting,
          message: m, phase: VpnPhase.tunAutotune),
      // #5 — прекратить перебор, если пользователь отключился за время подбора.
      abort: aborted,
    );
    // ⚠️ ЗАПОМИНАЕМ КОНФИГ ТОЛЬКО ПОСЛЕ УСПЕШНОГО ПОДЪЁМА. Поставь мы отметку
    // раньше (рядом с `_tunActive = true`), и после отказа `start` следующая
    // попытка с тем же конфигом «переиспользовала» бы туннель, которого нет:
    // приложение показало бы «Подключено» без единого маршрута.
    _liveTunConfig = wantConfig;
    _liveBypassIps = tunOptions.serverIps;
    _liveTunApiSecret = singboxApiSecret;
    // Подбор стека/MTU идёт до двух минут — за это время пользователь мог
    // отключиться. Туннель, поднятый уже «после отмены», гасим сразу — но
    // ТОЛЬКО свой (за две минуты успевает начаться и новый запуск).
    if (aborted()) {
      await _releaseOwnTun(gen);
      await _releaseOwnFallbackDns(gen);
      return false;
    }
    // Сторож вооружается ТОЛЬКО когда туннель уже стоит: во время
    // автоподбора стека и MTU ядро законно молчит до двух минут.
    _startTunWatchdog(options.settings, aborted);
    // Наблюдение за блокировками — ТОЛЬКО после подъёма туннеля: раньше
    // Clash API ещё не слушает, и опрос уходил бы в пустоту.
    startBlockNotice(
        settings: options.settings,
        apiPort: _tunApiPort,
        secret: singboxApiSecret);
    return true;
  }

  /// Поднят ли сейчас туннель (для теста: устаревший запуск не имеет права
  /// снимать чужой).
  @visibleForTesting
  bool get tunActive => _tunActive;

  /// Конфиг, который получит туннель при этих аргументах.
  ///
  /// ⚠️ ОДИН ИСТОЧНИК С ТЕМ, ЧТО СОБИРАЕТ РОУТЕР. `SingboxRouterWindows`
  /// строит файл этим же `SingboxConfigBuilder` и из этих же аргументов —
  /// других входов у него нет. Поэтому сверка живого туннеля с будущим
  /// отвечает на настоящий вопрос («изменится ли конфиг»), а не на его
  /// пересказ. Появится у `TunRouter.start` НОВЫЙ аргумент — он обязан
  /// появиться и здесь, иначе сверка перестанет замечать его изменение и
  /// туннель останется жить со старым конфигом.
  String _tunConfigPreview({
    required SplitTunnelConfig split,
    required TunOptions options,
    required List<Map<String, dynamic>> exitOutbounds,
    required List<String> apiKeys,
    required List<String> apiOnlyKeys,
    required String apiToken,
  }) =>
      SingboxConfigBuilder(
        xraySocksPort: ports.socks,
        xraySocksUser: localInboundUser,
        xraySocksPassword: localInboundPassword,
        options: options,
        exitOutbounds: exitOutbounds,
        apiExitServerKeys: apiKeys,
        apiOnlyExitKeys: apiOnlyKeys,
        apiToken: apiToken,
      ).buildJson(split);

  /// Свернуть УСТАРЕВШИЙ запуск: погасить то, что подняли МЫ, и не трогать
  /// ничего чужого. Общая уборка ([cleanup]) здесь запрещена — она гасит то,
  /// что лежит в полях сейчас, а там уже может стоять новая сессия.
  Future<void> _abandonRun(int gen, List<Object?> mine) async {
    await _releaseOwnTun(gen);
    await _releaseOwnProxy(gen);
    // Форвардер — такой же ресурс запуска, как туннель и прокси: он слушает
    // UDP-порт на петле и без своего конфига никому не нужен.
    await _releaseOwnFallbackDns(gen);
    await _stopOwnProcesses(mine);
  }

  /// Снять туннель, если он всё ещё принадлежит запуску [gen].
  Future<void> _releaseOwnTun(int gen) async {
    if (!_tunActive) return;
    if (_tunOwnerGen != gen) {
      AppLog.i('Устаревший запуск туннель не трогает: им уже владеет другой '
          '(поколение $_tunOwnerGen)');
      return;
    }
    // Сторож зависания и наблюдение за блокировками привязаны к ЭТОМУ туннелю
    // — уходят вместе с ним, иначе остались бы опрашивать пустой Clash API.
    // Свои они по тому же признаку: пока `_tunOwnerGen` наш, никакой другой
    // запуск до подъёма (и до вооружения своих) ещё не дошёл.
    _tunWatchdog?.cancel();
    _tunWatchdog = null;
    stopBlockNotice();
    await _tunRouter.stop();
    _tunActive = false;
    // Туннеля нет — значит и «конфиг поднятого туннеля» больше не правда.
    // Забудь это, и следующий запуск с тем же конфигом решил бы, что
    // пересоздавать нечего, и оставил бы машину без маршрутов.
    _liveTunConfig = null;
      _liveBypassIps = null;
      _liveTunApiSecret = null;
  }

  /// Снять системный прокси, если его прописал запуск [gen].
  Future<void> _releaseOwnProxy(int gen) async {
    if (!_proxySet || _proxyOwnerGen != gen) return;
    await SystemProxy.clear();
    _proxySet = false;
  }

  /// Погасить процессы, поднятые ИМЕННО ЭТИМ запуском.
  ///
  /// ⚠️ Не [_stopCoreProcesses]: тот гасит то, что лежит в полях СЕЙЧАС. У
  /// устаревшего запуска в полях уже ядро НОВОЙ сессии, и общий гаситель убивал
  /// бы его — «Подключено» при мёртвом ядре, само не чинится.
  Future<void> _stopOwnProcesses(List<Object?> mine) async {
    for (final p in mine) {
      if (p == null) continue;
      // Поле обнуляем только если оно указывает на НАС.
      if (identical(_process, p)) _process = null;
      if (identical(_singbox, p)) _singbox = null;
      if (identical(_exitRouter, p)) _exitRouter = null;
      if (p is XrayProcess) {
        await p.stop();
        p.dispose();
      } else if (p is SingboxProcess) {
        await p.stop();
        p.dispose();
      }
    }
  }

  /// Маршрутизатор выходов режима «Только прокси» (задача 3b): отдельный
  /// крошечный sing-box, БЕЗ tun-инбаунда и без прав администратора (тот же
  /// класс `SingboxProcess`, что для hysteria2-прокси), который даёт каждому
  /// выбранному серверу свой локальный порт, плюс порт «Прямо» (задача 3c) —
  /// мимо VPN, для сравнения «через/без VPN» одним и тем же скриптом.
  ///
  /// ⚠️ СБОЙ ЗДЕСЬ НЕ ВАЛИТ ПОДКЛЮЧЕНИЕ ЦЕЛИКОМ. Основной канал (порт ядра
  /// сессии) уже поднят и работает — порты API поверх него надстройка, а не
  /// требование. Но осиротевший процесс всё равно обязан быть погашен: иначе
  /// следующий подъём упрётся в занятый порт (см. `_stopCoreProcesses`,
  /// который гасит и его тоже).
  ///
  /// Возвращает поднятый процесс (или `null`) — вызывающий кладёт его в список
  /// «моё», чтобы при отмене погасить именно его, а не то, что успела положить
  /// в поле новая сессия.
  Future<SingboxProcess?> _startExitRouter(
      ConnectionOptions options, bool Function() aborted) async {
    final routerExe = SingboxProcess.locate();
    if (routerExe == null) {
      AppLog.w('sing-box.exe не найден — порты API для серверов не поднимутся');
      return null;
    }
    try {
      // Резолвим ЗАРАНЕЕ, как и у обычных дополнительных серверов (TUN-ветка
      // выше): домен, отданный ядру как есть, — не проблема здесь (петли нет,
      // адаптера, забирающего трафик машины, тоже нет), но собственный
      // резолвер маршрутизатора может не подняться раньше, чем нужно.
      final exitHosts =
          await resolveServerHosts(options.exitServers.values.toList());
      final exitsBuilt = ExitOutbounds.build(
        servers: options.exitServers,
        resolvedIps: VpnEngineBase.pickOneIpPerHost(exitHosts),
      );
      for (final e in exitsBuilt.skipped.entries) {
        AppLog.i('Сервер API-порта не поднят: ${e.value}');
      }
      // ⚠️ БОЛЬШЕ НЕ `if (exitsBuilt.outbounds.isEmpty) return;`. Порт «Прямо»
      // (`ApiPorts.direct`) не нуждается ни в одном из этих outbound-ов — он
      // ведёт во встроенный `direct` — а вызывающий уже проверил `_apiExitsActive`,
      // значит токен непуст и этот порт будет создан ВСЕГДА. Ранний выход по
      // пустому `exitsBuilt.outbounds` молча гасил бы именно его — единственный
      // порт, который в режиме «Только прокси» пользователь мог хотеть, даже
      // не выбрав НИ ОДНОГО сервера под отдельный порт.
      if (aborted()) return null;

      final builder = ExitRouterConfigBuilder(
        serverKeys: options.settings.apiExitServerKeys,
        token: options.settings.apiToken,
        exitOutbounds: exitsBuilt.outbounds,
        // Галочка задачи 3b: правила раздельного туннелирования на этих
        // портах — только если пользователь явно включил её.
        applyRules: options.settings.applyRulesInProxyOnly,
        split: options.split,
      );
      final configPath = await _writeConfigJson(builder.buildJson(),
          name: 'exit_router.json');

      final process = SingboxProcess();
      await process.start(
        executable: routerExe,
        configPath: configPath,
        // Отдельное имя лога: маршрутизатор может жить ОДНОВРЕМЕННО с этим же
        // классом, поднятым под hysteria2-прокси (`_singbox`) — общий файл
        // смешал бы два потока диагностики в один.
        logPath: SingboxProcess.logPathFor(await AppPaths.supportDir(),
            name: 'singbox_exit_router.log'),
      );
      // С этой точки процесс ЗАПУЩЕН и обязан быть погашен при ЛЮБОМ выходе
      // из метода — иначе он осиротеет, будет держать порты серверов, и
      // следующий подъём упрётся в конфликт. `_attached` = процесс успешно
      // передан в `_exitRouter`, где его погасит `_stopCoreProcesses`; если
      // нет — гасим сами в finally (сегодня между start() и присваиванием
      // ничего не бросает, но инвариант не должен держаться на этом факте).
      var attached = false;
      try {
        await Future.delayed(const Duration(milliseconds: 300));
        if (aborted() || !process.isRunning) {
          if (!aborted()) {
            AppLog.w(
                'Маршрутизатор выходов API не поднялся:\n${process.tail}');
          }
          return null;
        }
        _exitRouter = process;
        attached = true;
        // Порт «Прямо» поднят всегда (вызывающий уже проверил
        // `_apiExitsActive` — токен непуст), серверные порты — по числу
        // собравшихся выходов.
        AppLog.i('Маршрутизатор выходов API: серверных портов '
            '${exitsBuilt.outbounds.length}, порт «Прямо» поднят');
        return process;
      } finally {
        if (!attached) {
          await process.stop();
        }
      }
    } catch (e) {
      AppLog.w('Маршрутизатор выходов API не поднялся: $e');
      return null;
    }
  }

  /// Погасить ядро (и, если [keepCapture] == false, снять захват трафика).
  ///
  /// При включённом kill switch между попытками восстановления захват НЕ снимается:
  /// системный прокси остаётся прописанным на мёртвый порт, TUN продолжает держать
  /// маршрут — приложения получают ошибку соединения вместо утечки мимо VPN.
  @override
  Future<void> teardownCore({bool keepCapture = false}) async {
    _statsTimer?.cancel();
    _statsTimer = null;
    _tunWatchdog?.cancel();
    _tunWatchdog = null;
    stopHealthWatch();
    await _exitWatch?.cancel();
    _exitWatch = null;
    await _stopCoreProcesses();

    // ⚠️ Форвардер гасим ВМЕСТЕ С ЯДРОМ, даже при keepCapture. Он ходит через
    // локальный SOCKS ядра, и без ядра его «основной» путь ведёт в никуда: он
    // ждал бы таймаут на каждом запросе и только замедлял бы переподключение.
    // Заново поднимется при следующем старте сессии, с новым портом.
    await _stopFallbackDns();

    if (keepCapture) return;

    if (_tunActive) {
      await _tunRouter.stop();
      _tunActive = false;
      _liveTunConfig = null;
      _liveBypassIps = null;
      _liveTunApiSecret = null;
      _liveBypassIps = null;
      _liveTunApiSecret = null;
    }
    // Не сбрасываем чужой прокси (например, корпоративный): чистим только свой.
    if (_proxySet) {
      await SystemProxy.clear();
      _proxySet = false;
    }
  }

  /// Платформенная часть полной остановки. Счётчик поколений и таймер повтора
  /// живут в базе — [VpnEngineBase.cleanup] увеличивает поколение ДО вызова
  /// этого метода, поэтому проверки «была ли отмена» делаются раньше.
  @override
  Future<void> platformCleanup() async {
    _polling = false;
    // Полная остановка: следующее подключение начнётся без нашего туннеля, и
    // проба резолвера пройдёт честно. Память о прошлом ответе тут только вредна
    // — см. [_lastDirectDns].
    _lastDirectDns = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    _tunWatchdog?.cancel();
    _tunWatchdog = null;
    stopHealthWatch();
    await _exitWatch?.cancel();
    _exitWatch = null;
    // ⚠️ ФОРВАРДЕР ГАСИТСЯ И ЗДЕСЬ, А НЕ ТОЛЬКО В [teardownCore]. `cleanup()` в
    // базе зовёт ТОЛЬКО этот метод — значит после обычного «Отключить» (и после
    // провала подъёма, где стоит `await cleanup()`) форвардер оставался слушать
    // UDP-порт на петле при выключенном VPN, а его «основной» путь вёл в
    // мёртвый SOCKS ядра: каждый запрос уходил в запас, то есть к резолверу
    // провайдера. Комментарий в Android-движке утверждал, что «Windows гасит
    // всё это в своём platformCleanup с самого начала», — неправдой это было
    // ровно про эту строку.
    await _stopFallbackDns();
    if (_tunActive) {
      await _tunRouter.stop();
      _tunActive = false;
    }
    // Полная остановка: туннеля больше нет ни при каком исходе, и память о его
    // конфиге обязана уйти вместе с ним (см. [_liveTunConfig]).
    _liveTunConfig = null;
      _liveBypassIps = null;
      _liveTunApiSecret = null;
    // Не сбрасываем чужой прокси (например, корпоративный): чистим только свой.
    if (_proxySet) {
      await SystemProxy.clear();
      _proxySet = false;
    }
    await _stopCoreProcesses();
  }

  /// Гасим все прокси-ядра: основное (Xray/sing-box, зависит от протокола
  /// сессии) и маршрутизатор выходов «Только прокси» (задача 3b), если он
  /// поднимался. Осиротевший процесс держит порты, и следующий подъём
  /// упёрся бы в конфликт — поэтому гасим его здесь БЕЗУСЛОВНО, тем же
  /// путём, что и остальные ядра (`teardownCore`/`platformCleanup` зовут
  /// этот метод и при обычном отключении, и при сбое подъёма).
  Future<void> _stopCoreProcesses() async {
    await _process?.stop();
    _process?.dispose();
    _process = null;
    await _singbox?.stop();
    _singbox?.dispose();
    _singbox = null;
    await _exitRouter?.stop();
    _exitRouter?.dispose();
    _exitRouter = null;
  }

  /// Порт Clash API туннельного sing-box. Только петля, только для сторожа.
  static int get _tunApiPort => 10813 + AppEnv.portOffset;

  /// Сторож ЗАВИСШЕГО туннельного ядра.
  ///
  /// ⚠️ ЗАЧЕМ ОН ВООБЩЕ НУЖЕН — разница между «упало» и «зависло».
  ///
  /// Если sing-box ПАДАЕТ, Windows убирает за ним сама: WFP-сессия открыта
  /// динамической, адаптер заведён через `SwDeviceCreate`, поэтому фильтры,
  /// маршруты и сам адаптер снимаются вместе с процессом и сеть возвращается.
  /// Если же процесс ЗАВИС, не снимается ничего: адаптер с метрикой 0 и
  /// маршрутом `0.0.0.0/0` остаётся на месте и глотает весь трафик машины —
  /// включая помеченный «Прямо», которому туннель не нужен вовсе. Снаружи это
  /// «интернет пропал совсем», и само оно не чинится никогда.
  ///
  /// ⚠️ СТОРОЖ ВООРУЖАЕТСЯ ТОЛЬКО ПОСЛЕ ПЕРВОГО УСПЕШНОГО ОТВЕТА.
  ///
  /// Иначе он превращается в убийцу подключения: не смог подняться API (занят
  /// порт, старая сборка ядра, что угодно) — и сторож честно решает, что ядро
  /// зависло, гасит туннель, тот поднимается заново, API снова не отвечает.
  /// Вечный цикл переподключений, причём ровно у тех, у кого что-то не так с
  /// окружением. Поэтому `_tunLastAlive == null` означает «сторож ещё не
  /// вооружён», и в этом состоянии он не делает НИЧЕГО.
  ///
  /// Честная граница: это детектор зависшего ПРОЦЕССА, а не всякого затыка.
  /// HTTP-сервер API живёт в своей горутине, поэтому остановка обработки
  /// пакетов в стеке при живом API сторожем не ловится.
  void _startTunWatchdog(AppSettings settings, bool Function() aborted) {
    _tunWatchdog?.cancel();
    _tunLastAlive = null;
    final limit = settings.tunWatchdogSeconds;
    if (limit <= 0) return; // выключено пользователем

    final startedAt = DateTime.now();
    _tunWatchdog = Timer.periodic(const Duration(seconds: 5), (t) async {
      // Поколение сменилось — сессия уже другая, нам тут делать нечего.
      // Без этой проверки сторож прошлой сессии убивал бы туннель следующей.
      if (aborted() || !_tunActive) {
        t.cancel();
        return;
      }
      if (await _tunApiAlive()) {
        if (_tunLastAlive == null) {
          AppLog.i('Сторож туннеля вооружён: ядро отвечает по своему API');
        }
        _tunLastAlive = DateTime.now();
        return;
      }
      final since = _tunLastAlive;
      if (since == null) {
        // Ни одного ответа так и не было. Через минуту сдаёмся и говорим об
        // этом вслух: молчащий сторож хуже отсутствующего — на него надеются.
        if (DateTime.now().difference(startedAt).inSeconds > 60) {
          AppLog.w('Сторож туннеля НЕ вооружён: ядро ни разу не ответило по '
              'API на порту $_tunApiPort. Зависание отслеживаться не будет.');
          t.cancel();
        }
        return;
      }
      final silent = DateTime.now().difference(since).inSeconds;
      if (silent < limit) return;

      t.cancel();
      AppLog.e('Туннельное ядро не отвечает $silent с — считаю его зависшим. '
          'Снимаю туннель, чтобы система вернула сеть.');
      // Гасим ЖЁСТКО и вместе с захватом: смысл всей затеи в том, чтобы исчез
      // адаптер, иначе трафик так и останется в чёрной дыре. Kill switch здесь
      // не спорит — он защищает от утечки, а утекать при зависшем туннеле
      // нечему: наружу и так ничего не проходит.
      await teardownCore();
      if (!await scheduleRetry('туннельное ядро зависло')) {
        setStatus(VpnConnectionState.error,
            message: 'Туннельное ядро зависло, туннель снят');
      }
    });
  }

  /// Отвечает ли туннельное ядро по своему API. Короткий таймаут: сторож
  /// спрашивает раз в 5 с, и висеть на ответе ему нельзя.
  Future<bool> _tunApiAlive() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 700);
    try {
      final req =
          await client.getUrl(Uri.parse('http://127.0.0.1:$_tunApiPort/version'));
      if (singboxApiSecret.isNotEmpty) {
        req.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $singboxApiSecret');
      }
      final resp = await req.close().timeout(const Duration(milliseconds: 1500));
      await resp.drain<void>();
      // 401 тоже означает «живо»: ядро ответило, просто пароль не понравился.
      // Считать это зависанием — значит убивать рабочий туннель из-за своей же
      // ошибки в передаче секрета.
      return resp.statusCode == 200 || resp.statusCode == 401;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Счётчики трафика: у Xray — `api statsquery`, у sing-box — Clash API.
  void _startStatsPolling(String? executable, {bool singbox = false}) {
    final xrayStats = singbox
        ? null
        : XrayStats(executable: executable!, apiPort: ports.api);
    final singboxStats = singbox ? SingboxStats(apiPort: ports.api, secret: singboxApiSecret) : null;
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      // Timer.periodic не сериализует async-колбэки: опрос Xray идёт через
      // Process.run и на нагруженной машине легко перекрывает секунду, а два
      // такта разом дают неверную разницу по времени.
      if (_polling) return;
      _polling = true;
      try {
      final snap =
          await (singboxStats?.query() ?? xrayStats!.query());
      // Опрос не удался — такт ПРОПУСКАЕМ целиком. Раньше сюда приезжал ноль,
      // и он затирал базу: скорость на следующем удачном опросе взлетала до
      // «всего трафика за секунду», а счётчик сессии удваивался.
      if (snap == null) return;
      final now = DateTime.now();
      final dt = now.difference(_lastSampleTime).inMilliseconds / 1000.0;
      final upSpeed = dt > 0 ? ((snap.uplink - _lastSnapshot.uplink) / dt).round() : 0;
      final downSpeed =
          dt > 0 ? ((snap.downlink - _lastSnapshot.downlink) / dt).round() : 0;
      _lastSnapshot = snap;
      _lastSampleTime = now;

      emitStats(TrafficStats(
        uplinkBytes: snap.uplink,
        downlinkBytes: snap.downlink,
        uplinkSpeed: upSpeed < 0 ? 0 : upSpeed,
        downlinkSpeed: downSpeed < 0 ? 0 : downSpeed,
      ));
      } finally {
        _polling = false;
      }
    });
  }

  /// Конфиги ядер лежат рядом, но в разных файлах: TUN-инстанс sing-box пишет
  /// свой (`singbox_config.json`), поэтому прокси-конфиг — `singbox_proxy.json`.
  /// DNS-сервер физического адаптера — резолвер для доменов «Прямо».
  ///
  /// Нужен явным адресом: транспорт `local` в sing-box на Windows означает
  /// системный резолвер, а тот под поднятым TUN закольцовывается сам на себя,
  /// и домен «Прямо» не резолвится вовсе (подтверждено живым тестом).
  ///
  /// Берём ПЕРВЫЙ адрес не-туннельного адаптера. Свой туннель узнаём по
  /// собственным адресам (172.19.0.x / fdfe:dcba:9876::), а не по имени: имя
  /// адаптера на Windows приходит не то — на этом уже обжигались в 0.8.3.
  /// Не нашли — `null`, поведение остаётся прежним.
  /// Реальность IPv6: есть ли он наружу.
  ///
  /// Логируем РЕШЕНИЕ, а не только факт: молчаливое урезание возможностей —
  /// худший вид поведения. Пользователь включил IPv6 в настройках, а получил
  /// туннель без него: он должен видеть, почему.
  Future<bool> _ipv6Reality() async {
    final has = await Ipv6Support.hasGlobalIpv6();
    if (!has) {
      AppLog.i('IPv6 наружу не найден — в туннеле он выключен, иначе '
          'двустековые сайты упирались бы в «unreachable network»');
    }
    return has;
  }

  /// Отвечает ли DNS-сервер. Проверяем ДО подъёма туннеля — потом поздно.
  ///
  /// Обычный запрос A-записи по UDP: если за отведённое время ответа нет,
  /// резолвер считаем непригодным. Секунды хватает — это адрес из локальной
  /// сети или адрес провайдера, дальше идти не нужно.
  Future<bool> _dnsReachable(String ip) async {
    final hook = dnsReachableForTest;
    if (hook != null) return hook(ip);
    RawDatagramSocket? sock;
    try {
      final addr = InternetAddress.tryParse(ip);
      if (addr == null) return false;
      sock = await RawDatagramSocket.bind(
          addr.type == InternetAddressType.IPv6
              ? InternetAddress.anyIPv6
              : InternetAddress.anyIPv4,
          0);
      // Минимальный запрос: A-запись для example.com.
      final query = <int>[
        0x12, 0x34, // id
        0x01, 0x00, // стандартный запрос, рекурсия
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        7, ...'example'.codeUnits, 3, ...'com'.codeUnits, 0,
        0x00, 0x01, 0x00, 0x01,
      ];
      sock.send(query, addr, 53);
      final got = Completer<bool>();
      sock.listen((e) {
        if (e == RawSocketEvent.read && !got.isCompleted) {
          final d = sock?.receive();
          if (d != null && d.data.length > 2) got.complete(true);
        }
      });
      return await got.future
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
    } catch (_) {
      return false;
    } finally {
      sock?.close();
    }
  }

  /// Поднять локальный DNS-форвардер с запасным резолвером и вернуть его порт.
  /// 0 — форвардер не нужен или не поднялся.
  ///
  /// ⚠️ Нужен ТОЛЬКО при «DNS всех приложений через туннель». Без этой галочки
  /// прямой трафик резолвится локально и так, и лишнее звено в пути DNS было бы
  /// чистым риском без выгоды.
  ///
  /// Сбой подъёма НЕ фатален: без форвардера `dns.final` останется прежним
  /// (`dns-proxy`), то есть вернётся поведение до этой правки. Диагностика не
  /// имеет права мешать подключению.
  Future<int> _startFallbackDns(
      AppSettings s, int gen, bool Function() aborted) async {
    // ⚠️ ГЕЙТ ДО ПЕРВОГО ДЕЙСТВИЯ, А НЕ ПОСЛЕ. Ниже стоит `_stopFallbackDns()`,
    // и он снимает форвардер ИЗ ПОЛЯ — а там уже может стоять форвардер живой
    // сессии (см. [_fallbackDnsOwnerGen]). Устаревший запуск обязан уйти,
    // ничего не тронув и ничего не подняв: поднятое им никто бы не погасил.
    //
    // Предикат — ТОТ ЖЕ `aborted`, которым сверяется весь остальной [raiseTun].
    // Свой (`isStale(gen)`) означал бы два независимых ответа на один вопрос, а
    // чем это кончается, в проекте уже записано отдельным уроком.
    if (aborted()) {
      AppLog.i('Запасной DNS не поднимаю: запуск устарел, форвардер живой '
          'сессии не трогаю');
      return 0;
    }
    await _stopFallbackDns();
    if (s.captureMode != CaptureMode.tun || !s.tunnelDnsForAll) return 0;
    final local = await _systemDnsServer();
    if (local == null || local.isEmpty) {
      AppLog.w('Запасной DNS не поднят: локальный резолвер не определён');
      return 0;
    }
    final upstream = _dnsUpstreamFor(s);
    // ⚠️ ФОРВАРДЕР УМЕЕТ ТОЛЬКО ЛИТЕРАЛЬНЫЙ IPv4. Рукопожатие SOCKS требует
    // адрес байтами; на домене или IPv6 оно молча возвращает false, и КАЖДЫЙ
    // запрос уходит в запас — то есть весь DNS к провайдеру, при внешне
    // исправной работе. Лучше честно не поднимать форвардер: тогда работает
    // прежнее поведение, и оно хотя бы понятное.
    final ip = InternetAddress.tryParse(upstream);
    if (ip == null || ip.type != InternetAddressType.IPv4) {
      AppLog.w('Запасной DNS не поднят: резолвер «$upstream» не литеральный '
          'IPv4-адрес. DNS работает как раньше — целиком через туннель.');
      return 0;
    }
    try {
      final srv = DnsFallbackServer(
        socksPort: ports.socks,
        // Те же креды, что у инбаунда: без них рукопожатие SOCKS отвергается,
        // и форвардер молча уходил бы в запас на КАЖДОМ запросе — то есть
        // весь DNS к провайдеру при внешне исправной работе.
        socksUser: localInboundUser,
        socksPassword: localInboundPassword,
        tunnelDns: upstream,
        localDns: local,
      );
      await srv.start();
      _fallbackDns = srv;
      _fallbackDnsOwnerGen = gen;
      return srv.port;
    } catch (e) {
      AppLog.w('Запасной DNS не поднялся: $e');
      return 0;
    }
  }

  /// Снять форвардер, если его поднял запуск [gen]. Чужой не трогаем — ровно
  /// как с туннелем и системным прокси.
  Future<void> _releaseOwnFallbackDns(int gen) async {
    if (_fallbackDns == null || _fallbackDnsOwnerGen != gen) return;
    await _stopFallbackDns();
  }

  Future<void> _stopFallbackDns() async {
    final srv = _fallbackDns;
    _fallbackDns = null;
    if (srv == null) return;
    if (srv.queryCount > 0) {
      AppLog.i('Запасной DNS: запросов ${srv.queryCount}, '
          'туннель промолчал ${srv.fallbackCount}, '
          'ушло к провайдеру ${srv.fallbackAnsweredCount}');
    }
    await srv.stop();
  }

  /// Тот же апстрим, что построитель кладёт в `dns-proxy`, и разобранный ТЕМ
  /// ЖЕ кодом — иначе строки расходятся и форвардер спрашивает не тот адрес.
  static String _dnsUpstreamFor(AppSettings s) =>
      SingboxConfigBuilder.dnsHostOf(
          s.dnsMode == DnsMode.custom ? s.dnsCustomServer : '1.1.1.1');

  /// Последний резолвер, который РЕАЛЬНО ответил, — В ПРЕДЕЛАХ ОДНОЙ СЕТИ.
  ///
  /// ⚠️ Нужен из-за порядка в [raiseTun]: определение идёт, пока старый туннель
  /// ещё держит трафик (иначе kill switch выпускал бы его на всё время
  /// подготовки). Под этим туннелем UDP-проба может не пройти — и тогда без
  /// памяти о прошлом ответе домены «Прямо» на каждом переподключении
  /// оставались бы без резолвера. То же соображение, что у кэша адресов
  /// серверов в базе.
  ///
  /// ⚠️ ⚠️ НО ЖИТЬ ДОЛЬШЕ СЕТИ ЭТА ПАМЯТЬ НЕ ИМЕЕТ ПРАВА, И ЭТО НЕ ПРИДИРКА.
  /// Кэш адресов серверов от сети не зависит: узел подписки в любой сети тот
  /// же. Резолвер — наоборот, привязан к сети целиком: `192.168.1.1` дома,
  /// `10.0.0.1` в офисе, адрес оператора в мобильной. А самый частый путь сюда
  /// — ПЕРЕПОДКЛЮЧЕНИЕ ПО СМЕНЕ СЕТИ, где новая проба вполне может не пройти
  /// (адаптер только поднялся). Отдать в этом случае домашний адрес значит
  /// прописать ядру резолвер, которого в этой сети НЕТ: он не ответит никогда,
  /// и КАЖДЫЙ домен с правилом «Прямо» перестанет открываться — тогда как
  /// `null` честно откатывает на прежнее поведение (системный резолвер).
  /// Худший ответ, чем «не знаю».
  ///
  /// Поэтому память живёт ровно от смены сети до смены сети и стирается ещё и
  /// при полной остановке ([platformCleanup]): следующее подключение по кнопке
  /// идёт уже без туннеля, и пробе ничто не мешает.
  String? _lastDirectDns;

  /// Смена сети: прежний резолвер к новой сети отношения не имеет.
  @override
  Future<void> onNetworkChanged() async {
    _lastDirectDns = null;
    await super.onNetworkChanged();
  }

  /// Только для теста: чем сейчас движок помнит резолвер «Прямо».
  @visibleForTesting
  String? get lastDirectDns => _lastDirectDns;

  /// Чем в тесте подменяется определение резолвера для «Прямо».
  ///
  /// ⚠️ ПОДМЕНЯЮТСЯ РОВНО ДВА ВНЕШНИХ ШАГА — список адресов у адаптеров
  /// (Windows API) и UDP-проба «а он вообще отвечает» (до 2 с на адрес). Разбор
  /// остаётся ТЕМ ЖЕ кодом, включая память о прошлом рабочем резолвере: прежний
  /// хук подменял метод целиком, и тест, который «проверяет» откат на память,
  /// на самом деле проверял бы заглушку — ни одной строки этой логики не
  /// исполнив.
  @visibleForTesting
  List<String> Function()? adapterDnsForTest;
  @visibleForTesting
  Future<bool> Function(String ip)? dnsReachableForTest;

  /// Чем в тесте подменяется вопрос «отвечает ли туннельное ядро по API».
  ///
  /// Настоящий ответ приходит по HTTP с 127.0.0.1, а в тесте туннеля нет вовсе
  /// — без подмены ветка «конфиг тот же, туннель переиспользуем» недостижима.
  @visibleForTesting
  Future<bool> Function()? tunAliveForTest;

  Future<String?> _systemDnsServer() async {
    try {
      // ⚠️ БЕЗ PowerShell. Прежний `Get-DnsClientServerAddress` — командлет того
      // же семейства CIM, что и изгнанный отсюда `Get-NetAdapter`: на машине
      // владельца он упирался в пятисекундный таймаут, и домены «Прямо»
      // переставали резолвиться молча. Живой тест в VM это подтвердил.
      final list = (adapterDnsForTest?.call() ?? AdapterDnsWindows.servers())
          // Адреса самого туннеля и заглушки резолвером быть не могут.
          .where((e) => !e.startsWith('172.19.0.'))
          .where((e) => !e.startsWith('fdfe:dcba:9876'))
          .where((e) => e != '0.0.0.0' && e != '127.0.0.1' && e != '::1')
          .toList();

      // ⚠️ Мало НАЙТИ адрес — надо убедиться, что он отвечает.
      //
      // Система охотно отдаёт DNS виртуальных адаптеров (Hyper-V, WSL, Docker).
      // В тестовой VM первым шёл 172.19.128.1 с адаптера Hyper-V: адрес есть,
      // порт 53 закрыт наглухо. Взяв его, мы получали резолвер, который не
      // отвечает никогда, и КАЖДЫЙ домен с правилом «Прямо» переставал
      // открываться — притом что настройка выглядела рабочей.
      for (final ip in list) {
        if (await _dnsReachable(ip)) {
          AppLog.i('Резолвер для «Прямо»: $ip');
          _lastDirectDns = ip;
          return ip;
        }
        AppLog.w('DNS $ip не отвечает — пробую следующий');
      }
      if (list.isEmpty) {
        AppLog.w('DNS физического адаптера не найден — домены «Прямо» '
            'будут резолвиться ${_directDnsFallbackNote()}');
        return _lastDirectDns;
      }
      AppLog.w('Ни один DNS адаптера не ответил — «Прямо» пойдёт '
          '${_directDnsFallbackNote()}');
      return _lastDirectDns;
    } catch (e) {
      AppLog.w('Не удалось определить DNS адаптера: $e');
      return _lastDirectDns;
    }
  }

  String _directDnsFallbackNote() => _lastDirectDns == null
      ? 'системным резолвером, и домены могут не открыться'
      : 'через прошлый рабочий резолвер $_lastDirectDns';

  /// [name] переопределяет имя файла (нужно маршрутизатору выходов задачи 3b —
  /// он пишет СВОЙ конфиг, а не тот, что уходит основному ядру).
  Future<String> _writeConfigJson(String json,
      {bool singbox = false, String? name}) async {
    final dir = await AppPaths.supportDir();
    final fileName = name ?? (singbox ? 'singbox_proxy.json' : 'xray_config.json');
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(json);
    return file.path;
  }

}
